{ pkgs, ... }:
let
  # Agents write about 30k files an hour into ~/Projects/graphide/scratch
  # (362 GiB, 2.4M files on 2026-11-07), and hourly /home snapshots pinned
  # all of it. Scratch itself is never idle, so each top-level folder becomes
  # its own subvolume, at the same path, once no process is inside it and
  # nothing in it changed for 30 minutes. Files are reflinked, not copied.
  # A write that lands during the swap keeps the old copy as .<name>.leftover-*.
  convert = pkgs.writeShellApplication {
    name = "scratch-subvolumes";
    runtimeInputs = [ pkgs.btrfs-progs pkgs.coreutils pkgs.findutils pkgs.gawk pkgs.gnugrep pkgs.util-linux ];
    text = ''
      scratch="$HOME/Projects/graphide/scratch"
      [ -d "$scratch" ] || exit 0
      fs=/sys/fs/btrfs/$(findmnt -no UUID -T "$scratch")
      used=$(mktemp)
      stamp=$(mktemp)
      trap 'rm -f "$used" "$stamp"' EXIT
      # The copy writes new metadata for every file; never while it is short.
      roomy() {
        local size=0 alloc=0 f
        for f in "$fs"/devices/*/size; do size=$((size + $(cat "$f") * 512)); done
        for f in "$fs"/allocation/*/disk_total; do alloc=$((alloc + $(cat "$f"))); done
        [ $((size - alloc)) -ge $((32 << 30)) ]
      }
      scan() {
        {
          find /proc/[0-9]*/cwd /proc/[0-9]*/fd/ -maxdepth 1 -type l -printf '%l\n'
          awk '$6 ~ /^\// { print $6 }' /proc/[0-9]*/maps
        } 2>/dev/null >"$used" || true
      }
      busy() { grep -qxF -- "$1" "$used" || grep -qF -- "$1/" "$used"; }
      changed() { local d=$1; shift; [ -n "$(find "$d" "$@" -print -quit 2>/dev/null)" ]; }
      scan
      for left in "$scratch"/.*.subvol; do
        if [ -e "$left" ] && ! busy "$left"; then rm -rf "$left"; fi
      done
      for d in "$scratch"/*/; do
        d=''${d%/}
        if [ -L "$d" ] || [ "$(stat -c %i "$d")" = 256 ]; then continue; fi
        if busy "$d" || changed "$d" -mmin -30; then continue; fi
        if ! roomy; then
          echo "unallocated space under 32 GiB; waiting"
          exit 0
        fi
        stage="$scratch/.''${d##*/}.subvol"
        touch "$stamp"
        btrfs subvolume create "$stage" >/dev/null
        if ! cp -a --reflink=always "$d/." "$stage/"; then
          rm -rf "$stage"
          echo "skipped $d: copy failed" >&2
          continue
        fi
        chmod --reference="$d" "$stage"
        touch --reference="$d" "$stage"
        scan
        if busy "$d" || changed "$d" -newer "$stamp"; then
          rm -rf "$stage"
          echo "deferred $d: written during the copy"
          continue
        fi
        mv -T --exchange "$stage" "$d"
        if changed "$stage" -newer "$stamp"; then
          mv -T "$stage" "$scratch/.''${d##*/}.leftover-$(date +%s)"
          echo "converted $d; a write during the swap is in the leftover dir" >&2
        else
          rm -rf "$stage"
          echo "converted $d"
        fi
      done
    '';
  };
in
{
  systemd.user.services.scratch-subvolumes = {
    Unit.Description = "Keep agent scratch folders out of /home snapshots";
    Service = {
      Type = "oneshot";
      ExecStart = "${convert}/bin/scratch-subvolumes";
      Nice = 19;
      IOSchedulingClass = "idle";
    };
  };
  systemd.user.timers.scratch-subvolumes = {
    Unit.Description = "Convert idle scratch folders to subvolumes every 15 minutes";
    Timer = {
      OnCalendar = "*:0/15";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
