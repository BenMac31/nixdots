{ config, lib, pkgs, ... }:
let
  cfg = config.services.diskGuard;
  gib = n: toString (n * 1024 * 1024 * 1024);
  str = lib.escapeShellArg;

  # btrfs metadata grows only into unallocated space, so a disk with 150 GiB
  # "free" in df can still abort a transaction and go read-only. This reads
  # the allocator from sysfs every couple of minutes and escalates while
  # deletes still work: balance, prune, freeze the agents, drop the ballast.
  guard = pkgs.writeShellApplication {
    name = "disk-guard";
    runtimeInputs = [
      pkgs.btrfs-progs
      pkgs.coreutils
      pkgs.e2fsprogs
      pkgs.findutils
      pkgs.gawk
      pkgs.libnotify
      pkgs.snapper
      pkgs.util-linux
      config.nix.package
      config.systemd.package
    ];
    text = ''
      mount=${str cfg.mountPoint}
      user=${str cfg.user}
      slice=${str cfg.slice}
      target=${gib cfg.targetGiB}
      tight=${gib cfg.tightGiB}
      critical=${gib cfg.criticalGiB}
      meta_pct=${toString cfg.metadataCriticalPercent}
      meta_critical=${gib cfg.metadataCriticalGiB}
      free_tight=${gib cfg.trueFreeTightGiB}
      free_ok_pct=${toString cfg.trueFreeOkPercent}
      ballast_dir=${str (if cfg.ballast.dir == null then "" else cfg.ballast.dir)}
      ballast_size=${gib cfg.ballast.sizeGiB}
      snapper_config=${str (if cfg.snapper.config == null then "" else cfg.snapper.config)}
      snapper_keep=${toString cfg.snapper.keep}
      purge_dirs=(${lib.escapeShellArgs cfg.purge.dirs})
      purge_age=${toString cfg.purge.minAgeMinutes}
      nix_gc=${if cfg.nixGc then "1" else "0"}
      rundir=/run/disk-guard

      uuid=$(findmnt -no UUID -M "$mount" || true)
      fs=/sys/fs/btrfs/$uuid
      if [ -z "$uuid" ] || [ ! -d "$fs" ]; then
        echo "$mount is not a mounted btrfs filesystem" >&2
        exit 1
      fi
      uid=$(id -u "$user")
      cg=/sys/fs/cgroup/user.slice/user-$uid.slice/user@$uid.service/$slice
      ballast_file=$ballast_dir/ballast

      read_metrics() {
        local f dt du ddisk mt mu ratio
        size=0
        alloc=0
        for f in "$fs"/devices/*/size; do size=$((size + $(<"$f") * 512)); done
        for f in "$fs"/allocation/{data,metadata,system}/disk_total; do alloc=$((alloc + $(<"$f"))); done
        unalloc=$((size - alloc))
        dt=$(<"$fs/allocation/data/total_bytes")
        du=$(<"$fs/allocation/data/bytes_used")
        ddisk=$(<"$fs/allocation/data/disk_total")
        mt=$(<"$fs/allocation/metadata/total_bytes")
        mu=$(<"$fs/allocation/metadata/bytes_used")
        ratio=1
        if [ "$dt" -gt 0 ] && [ "$ddisk" -ge "$dt" ]; then ratio=$((ddisk / dt)); fi
        free=$((dt - du + unalloc / ratio))
        metapct=0
        if [ "$mt" -gt 0 ]; then metapct=$((mu * 100 / mt)); fi
        ro=0
        case ,$(findmnt -no OPTIONS -M "$mount"), in *,ro,*) ro=1 ;; esac
      }

      # 0 OK, 1 LOW, 2 TIGHT, 3 CRITICAL, 4 READ-ONLY
      classify() {
        if [ "$ro" = 1 ]; then
          echo 4
        elif [ "$unalloc" -lt "$critical" ] || { [ "$metapct" -ge "$meta_pct" ] && [ "$unalloc" -lt "$meta_critical" ]; }; then
          echo 3
        elif [ "$unalloc" -lt "$tight" ] || [ "$free" -lt "$free_tight" ]; then
          echo 2
        elif [ "$unalloc" -lt "$target" ] || [ $((free * 100)) -lt $((size * free_ok_pct)) ]; then
          echo 1
        else
          echo 0
        fi
      }

      name() {
        case $1 in
          0) echo OK ;;
          1) echo LOW ;;
          2) echo TIGHT ;;
          3) echo CRITICAL ;;
          *) echo READ-ONLY ;;
        esac
      }

      gibs() { awk -v b="$1" 'BEGIN { printf "%.1f GiB", b / 1073741824 }'; }
      bool() { if "$@"; then echo true; else echo false; fi; }

      frozen() { [ -r "$cg/cgroup.freeze" ] && [ "$(<"$cg/cgroup.freeze")" = 1 ]; }
      ballast_present() { [ -n "$ballast_dir" ] && [ -e "$ballast_file" ]; }

      user_ctl() {
        if [ "$(id -u)" = "$uid" ]; then
          systemctl --user "$@"
        else
          runuser -u "$user" -- env XDG_RUNTIME_DIR="/run/user/$uid" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" systemctl --user "$@"
        fi
      }

      # systemctl keeps the manager's view in step; the cgroup file is the
      # fallback when the user manager does not answer.
      freeze() {
        if [ ! -d "$cg" ]; then
          echo "no $slice to freeze"
          return 0
        fi
        frozen || user_ctl freeze "$slice" || true
        frozen || echo 1 >"$cg/cgroup.freeze"
        echo "froze $slice"
      }

      thaw() {
        [ -d "$cg" ] || return 0
        user_ctl thaw "$slice" || true
        if frozen; then echo 0 >"$cg/cgroup.freeze"; fi
      }

      notify() {
        local bus=/run/user/$uid/bus
        [ -S "$bus" ] || return 0
        runuser -u "$user" -- env DBUS_SESSION_BUS_ADDRESS="unix:path=$bus" \
          notify-send -a disk-guard -u "$1" "$2" "$3" || true
      }

      busy() { [ -r "$fs/exclusive_operation" ] && [ "$(<"$fs/exclusive_operation")" != none ]; }

      balance_to() {
        local want=$1 u
        shift
        for u in "$@"; do
          read_metrics
          [ "$unalloc" -lt "$want" ] || return 0
          if busy; then
            echo "a balance or device operation is already running; not balancing"
            return 0
          fi
          btrfs balance start -dusage="$u" "$mount" || true
        done
        read_metrics
      }

      prune_snapshots() {
        local old
        [ -n "$snapper_config" ] && [ -e "/etc/snapper/configs/$snapper_config" ] || return 0
        snapper -c "$snapper_config" cleanup timeline || true
        mapfile -t old < <(snapper -c "$snapper_config" --csvout list --columns number,cleanup \
          | awk -F, '$2 == "timeline" { print $1 }' | sort -n | head -n -"$snapper_keep")
        if [ "''${#old[@]}" -gt 0 ]; then
          echo "deleting timeline snapshots ''${old[*]}"
          snapper -c "$snapper_config" delete --sync "''${old[@]}" || true
        fi
      }

      nix_collect() {
        local stamp=$rundir/nix-gc
        [ "$nix_gc" = 1 ] || return 0
        if [ -e "$stamp" ] && [ $(($(date +%s) - $(stat -c %Y "$stamp"))) -lt 3600 ]; then return 0; fi
        touch "$stamp"
        nix-store --gc || true
      }

      purge() {
        local d
        for d in "''${purge_dirs[@]}"; do
          [ -d "$d" ] || continue
          find "$d" -xdev -mindepth 1 \( -type f -o -type l \) -mmin +"$purge_age" -delete || true
          find "$d" -xdev -mindepth 1 -depth -type d -empty -mmin +"$purge_age" -delete || true
        done
      }

      make_ballast() {
        [ -n "$ballast_dir" ] && [ -d "$ballast_dir" ] && [ ! -e "$ballast_file" ] || return 0
        if [ "$(stat -c %i "$ballast_dir")" != 256 ] || [ "$(findmnt -no UUID -T "$ballast_dir")" != "$uuid" ]; then
          echo "$ballast_dir is not a subvolume on $mount; no ballast"
          return 0
        fi
        [ "$unalloc" -ge $((target + ballast_size)) ] || return 0
        [ $((free - ballast_size)) -ge "$free_tight" ] || return 0
        [ $(((free - ballast_size) * 100)) -ge $((size * free_ok_pct)) ] || return 0
        rm -f "$ballast_file.new"
        touch "$ballast_file.new"
        chattr +C "$ballast_file.new"
        if fallocate -l "$ballast_size" "$ballast_file.new"; then
          mv "$ballast_file.new" "$ballast_file"
          echo "created ballast $(gibs "$ballast_size")"
        else
          rm -f "$ballast_file.new"
        fi
      }

      drop_ballast() {
        [ -n "$ballast_dir" ] || return 0
        if [ -e "$ballast_file" ] || [ -e "$ballast_file.new" ]; then
          rm -f "$ballast_file" "$ballast_file.new"
          btrfs filesystem sync "$mount" || true
          echo "deleted ballast"
        fi
      }

      critical_actions() {
        freeze
        drop_ballast
        if ! busy; then btrfs balance start -dusage=0 "$mount" || true; fi
        read_metrics
      }

      tight_actions() {
        prune_snapshots
        nix_collect
        purge
        balance_to "$target" 0 5 10 20 30 40 50
      }

      write_state() {
        mkdir -p "$rundir"
        printf '{"state":"%s","unallocated_bytes":%d,"metadata_used_percent":%d,"true_free_bytes":%d,"ballast":%s,"frozen":%s,"updated":%d}\n' \
          "$(name "$1")" "$unalloc" "$metapct" "$free" "$(bool ballast_present)" "$(bool frozen)" "$(date +%s)" \
          >"$rundir/state.json.tmp"
        mv "$rundir/state.json.tmp" "$rundir/state.json"
      }

      report() {
        local state=$1 level=$2 last was_frozen now_frozen=0
        if frozen; then
          now_frozen=1
          if [ "$level" -lt 3 ]; then level=3; fi
        fi
        write_state "$state"
        last=$(cat "$rundir/notified" 2>/dev/null || echo 0)
        was_frozen=$(cat "$rundir/frozen" 2>/dev/null || echo 0)
        echo "$now_frozen" >"$rundir/frozen"
        echo "state $(name "$state"), unallocated $(gibs "$unalloc"), metadata $metapct%, true free $(gibs "$free")"
        if [ "$level" -gt "$last" ] || { [ "$now_frozen" = 1 ] && [ "$was_frozen" = 0 ]; }; then
          echo "$level" >"$rundir/notified"
          case $level in
            1) notify normal "Disk headroom low" \
                 "Unallocated $(gibs "$unalloc"). Balancing to hand data chunks back." ;;
            2) notify critical "Disk space tight" \
                 "Unallocated $(gibs "$unalloc"), true free $(gibs "$free"). Pruned timeline snapshots, collected Nix garbage, purged scratch tmp." ;;
            3) notify critical "Disk nearly full: agents frozen" \
                 "Unallocated $(gibs "$unalloc"), metadata $metapct%. $slice is frozen and the ballast is gone. Free space, then run: disk-guard thaw" ;;
            4) notify critical "Disk is READ-ONLY" \
                 "btrfs forced $mount read-only. From a root shell: swapfile-release, then btrfs-ram-rescue." ;;
          esac
        elif [ "$state" = 0 ] && [ "$now_frozen" = 0 ] && [ "$last" -gt 0 ]; then
          echo 0 >"$rundir/notified"
          if [ "$last" -ge 2 ]; then notify normal "Disk space recovered" "Unallocated $(gibs "$unalloc")."; fi
        fi
      }

      run() {
        local s worst
        if [ "$(id -u)" != 0 ]; then
          echo "disk-guard run needs root" >&2
          exit 1
        fi
        mkdir -p "$rundir"
        exec 9>"$rundir/lock"
        if ! flock -n 9; then
          echo "disk-guard is already running"
          return 0
        fi
        read_metrics
        s=$(classify)
        if [ "$s" = 4 ]; then
          report 4 4
          return 0
        fi
        worst=$s
        if [ "$worst" -gt 1 ]; then worst=1; fi
        if [ "$s" -ge 3 ]; then critical_actions; fi
        if [ "$s" -ge 1 ]; then
          balance_to "$target" 0 5 10 20 30 40 50
          s=$(classify)
          if [ "$s" -gt "$worst" ]; then worst=$s; fi
        fi
        if [ "$s" -ge 2 ]; then
          tight_actions
          s=$(classify)
        fi
        if [ "$s" -ge 3 ]; then
          critical_actions
          s=$(classify)
        fi
        if [ "$s" = 0 ] && ! frozen; then
          make_ballast
          read_metrics
        fi
        report "$s" "$worst"
      }

      status() {
        local s
        read_metrics
        s=$(classify)
        echo "state         $(name "$s")"
        echo "unallocated   $(gibs "$unalloc") (target $(gibs "$target"))"
        echo "metadata      $metapct% used"
        echo "true free     $(gibs "$free") ($((free * 100 / size))% of $(gibs "$size"))"
        if [ -n "$ballast_dir" ]; then
          if ballast_present; then echo "ballast       present ($ballast_file)"; else echo "ballast       absent"; fi
        fi
        if frozen; then echo "$slice  FROZEN (disk-guard thaw)"; else echo "$slice  running"; fi
        if [ -r "$rundir/state.json" ]; then
          echo "last run      $(date -d "@$(awk -F'"updated":' '{ print $2 + 0 }' "$rundir/state.json")")"
        fi
      }

      case ''${1:-status} in
        status) status ;;
        run) run ;;
        thaw)
          thaw
          if frozen; then
            echo "$slice is still frozen" >&2
            exit 1
          fi
          echo "$slice thawed"
          ;;
        *)
          echo "usage: disk-guard [status|run|thaw]" >&2
          exit 2
          ;;
      esac
    '';
  };
in
{
  options.services.diskGuard = {
    enable = lib.mkEnableOption "the btrfs unallocated-space watchdog";
    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = guard;
      description = "The disk-guard command.";
    };
    mountPoint = lib.mkOption {
      type = lib.types.str;
      default = "/";
    };
    user = lib.mkOption {
      type = lib.types.str;
      default = "greencheetah";
      description = "Whose desktop gets notifications and whose user slice is frozen.";
    };
    slice = lib.mkOption {
      type = lib.types.str;
      default = "agents.slice";
    };
    interval = lib.mkOption {
      type = lib.types.str;
      default = "2min";
    };
    targetGiB = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 64;
      description = "Below this much unallocated space: LOW, balance.";
    };
    tightGiB = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 32;
      description = "Still below this after balancing: TIGHT, prune and collect.";
    };
    criticalGiB = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 16;
      description = "Below this: CRITICAL, freeze the slice and drop the ballast.";
    };
    metadataCriticalPercent = lib.mkOption {
      type = lib.types.ints.between 1 100;
      default = 90;
    };
    metadataCriticalGiB = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 8;
      description = "Metadata at metadataCriticalPercent with less unallocated than this is CRITICAL.";
    };
    trueFreeTightGiB = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 150;
      description = "Data space actually free (inside data chunks plus unallocated) below this is TIGHT.";
    };
    trueFreeOkPercent = lib.mkOption {
      type = lib.types.ints.between 0 100;
      default = 10;
    };
    ballast = {
      dir = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "/ballast";
        description = "A btrfs subvolume on the guarded filesystem; no ballast unless it exists.";
      };
      sizeGiB = lib.mkOption {
        type = lib.types.ints.unsigned;
        default = 32;
      };
    };
    snapper = {
      config = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "home";
      };
      keep = lib.mkOption {
        type = lib.types.ints.unsigned;
        default = 2;
        description = "Timeline snapshots TIGHT never deletes.";
      };
    };
    purge = {
      dirs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "/scratch/tmp" ];
        description = "Scratch directories whose old files TIGHT deletes.";
      };
      minAgeMinutes = lib.mkOption {
        type = lib.types.ints.positive;
        default = 1440;
      };
    };
    nixGc = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Delete unrooted store paths in TIGHT, at most hourly.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ guard ];

    systemd.services.disk-guard = {
      description = "Keep unallocated btrfs space for metadata";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${guard}/bin/disk-guard run";
        # Must keep up with agents.slice (IOWeight 30), so not the idle class.
        Nice = 5;
        IOSchedulingClass = "best-effort";
        IOSchedulingPriority = 4;
        IOWeight = 200;
        CPUWeight = 200;
        TimeoutStartSec = "30min";
        RuntimeDirectory = "disk-guard";
        RuntimeDirectoryPreserve = "yes";
      };
    };
    systemd.timers.disk-guard = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "1min";
        OnUnitActiveSec = cfg.interval;
      };
    };
  };
}
