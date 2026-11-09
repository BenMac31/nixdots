{ config, lib, pkgs, ... }:
let
  cfg = config.services.btrfsRescue;
  inherit (config.boot.kernelPackages) kernel kernelModuleMakeFlags;

  # swapoff(2) opens the swapfile O_RDWR before releasing it, which a
  # read-only btrfs refuses, and the active swapfile then pins the filesystem
  # until a reboot. This rewrites that one open to O_RDONLY for a process
  # named swapoff; nothing loads it except swapfile-release.
  swapoffRo = pkgs.stdenv.mkDerivation {
    pname = "swapoff-ro";
    version = kernel.modDirVersion;
    src = pkgs.writeText "swapoff_ro.c" ''
      #include <linux/module.h>
      #include <linux/kprobes.h>
      #include <linux/sched.h>
      #include <linux/string.h>
      #include <linux/fcntl.h>

      static int pre(struct kprobe *p, struct pt_regs *regs)
      {
          if (strcmp(current->comm, "swapoff") == 0 && (regs->si & O_ACCMODE) == O_RDWR) {
              regs->si = (regs->si & ~O_ACCMODE) | O_RDONLY;
              pr_info("swapoff_ro: opened swapfile read-only for swapoff (pid %d)\n", current->pid);
          }
          return 0;
      }

      static struct kprobe kp = { .symbol_name = "file_open_name", .pre_handler = pre };

      static int __init swapoff_ro_init(void)
      {
          int r = register_kprobe(&kp);
          pr_info("swapoff_ro: loaded, kprobe %d\n", r);
          return r;
      }
      static void __exit swapoff_ro_exit(void) { unregister_kprobe(&kp); pr_info("swapoff_ro: unloaded\n"); }
      module_init(swapoff_ro_init);
      module_exit(swapoff_ro_exit);
      MODULE_LICENSE("GPL");
      MODULE_DESCRIPTION("Open swapfiles read-only in swapoff");
    '';
    dontUnpack = true;
    hardeningDisable = [ "pic" ];
    nativeBuildInputs = kernel.moduleBuildDependencies;
    buildPhase = ''
      runHook preBuild
      mkdir mod
      cp $src mod/swapoff_ro.c
      echo 'obj-m := swapoff_ro.o' > mod/Kbuild
      make ${lib.escapeShellArgs kernelModuleMakeFlags} \
        -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build M="$PWD/mod" modules
      runHook postBuild
    '';
    installPhase = ''
      install -Dm444 mod/swapoff_ro.ko $out/lib/modules/${kernel.modDirVersion}/extra/swapoff_ro.ko
    '';
    # regs->si is the second argument only on x86_64. Re-check the
    # file_open_name call in mm/swapfile.c on a new kernel major version.
    meta.platforms = [ "x86_64-linux" ];
  };

  swapfileRelease = pkgs.writeShellApplication {
    name = "swapfile-release";
    runtimeInputs = [ pkgs.coreutils pkgs.gawk pkgs.gnugrep pkgs.kmod pkgs.util-linux ];
    text = ''
      swap=${lib.escapeShellArg cfg.swapfile}
      if [ "$(id -u)" != 0 ]; then
        echo "Run as root: sudo swapfile-release"
        exit 1
      fi
      if ! findmnt -no OPTIONS / | tr , '\n' | grep -qx ro; then
        echo "/ is read-write; use a plain: swapoff $swap"
        exit 1
      fi
      if ! awk 'NR > 1 { print $1 }' /proc/swaps | grep -qxF -- "$swap"; then
        echo "$swap is not an active swap area."
        exit 0
      fi
      insmod ${swapoffRo}/lib/modules/${kernel.modDirVersion}/extra/swapoff_ro.ko
      trap 'rmmod swapoff_ro' EXIT
      rc=0
      swapoff "$swap" || rc=$?
      swapon --show
      dmesg | grep -E 'swapoff_ro|swap' | tail -n 20 || true
      exit "$rc"
    '';
  };

  toolkit = pkgs.buildEnv {
    name = "btrfs-ram-rescue-tools";
    paths = with pkgs; [
      bashInteractive
      btrfs-progs
      coreutils
      findutils
      gawk
      gnugrep
      gnused
      kbd
      less
      procps
      util-linux
    ];
  };

  # Builds a small RAM root at /run/nextroot and soft-reboots into it, so
  # nothing holds the disk and btrfs can be mounted read-write again. The
  # running system may be read-only with nix-daemon dead, so the closure
  # comes from scanning store paths, not from the Nix database.
  ramRescue = pkgs.writeShellApplication {
    name = "btrfs-ram-rescue";
    runtimeInputs = [
      pkgs.btrfs-progs
      pkgs.coreutils
      pkgs.findutils
      pkgs.gawk
      pkgs.gnugrep
      pkgs.gnused
      pkgs.util-linux
      config.systemd.package
    ];
    bashOptions = [ "nounset" "pipefail" ];
    text = ''
      R=/run/nextroot
      swap=${lib.escapeShellArg cfg.swapfile}
      mapper=${lib.escapeShellArg cfg.luksDevice}
      snapdir=${lib.escapeShellArg cfg.snapshotDir}
      keep=${toString cfg.keepSnapshots}
      tty=${lib.escapeShellArg cfg.tty}
      headroom=${toString cfg.headroomGiB}
      clear=(${lib.escapeShellArgs cfg.clearPaths})
      if [ "$(id -u)" != 0 ]; then
        echo "Run as root: sudo btrfs-ram-rescue"
        exit 1
      fi
      tp() {
        local p=${toolkit}/bin/$1
        [ -e "$p" ] || p=/run/current-system/sw/bin/$1
        [ -e "$p" ] || return 1
        p=$(readlink -f "$p")
        case $p in /nix/store/*) echo "$p" ;; *) return 1 ;; esac
      }
      UUID=$(findmnt -no UUID /)
      if [ -z "$UUID" ] || [ ! -d "/sys/fs/btrfs/$UUID" ]; then
        echo "Could not find the btrfs UUID"
        exit 1
      fi
      if mountpoint -q "$R"; then umount -R "$R"; fi
      mkdir -p "$R"
      mount -t tmpfs -o size=${cfg.ramRootSize},mode=755 nextroot "$R" || exit 1
      mkdir -p "$R"/{bin,sbin,etc,dev,proc,sys,run,tmp,mnt,root,usr/lib,nix/store}

      TOOLS=(bash ls cat cp mv rm mkdir ln echo sleep sort head tail tr wc du df stat truncate sync env readlink tee mount umount mountpoint findmnt lsblk dmesg setsid swapoff btrfs grep sed awk find xargs less ps chvt)
      PAT='/nix/store/[0-9a-z]\{32\}-[-._+?=0-9a-zA-Z]*'
      declare -A seen
      queue=()
      for t in "''${TOOLS[@]}"; do
        p=$(tp "$t") || { echo "skip $t (not installed)"; continue; }
        queue+=("$(echo "$p" | cut -d/ -f1-4)")
      done
      echo "Working out what those tools depend on..."
      while [ ''${#queue[@]} -gt 0 ]; do
        p=''${queue[0]}
        queue=("''${queue[@]:1}")
        [ -n "''${seen[$p]:-}" ] && continue
        seen[$p]=1
        for r in $({ grep -raoh "$PAT" "$p"; find "$p" -type l -printf '%l\n'; } 2>/dev/null | grep -o "$PAT" | sort -u); do
          if [ -e "$r" ] && [ -z "''${seen[$r]:-}" ]; then queue+=("$r"); fi
        done
      done
      KB=$(du -sck "''${!seen[@]}" | tail -1 | cut -f1)
      avail=$(df -k --output=avail "$R" | tail -1)
      echo "''${#seen[@]} store paths, $((KB / 1024)) MB"
      if [ "$KB" -ge $((avail - 1024 * 1024)) ]; then
        echo "Too big for the ${cfg.ramRootSize} RAM root, stopping. Nothing changed."
        umount "$R"
        exit 1
      fi
      cp -a "''${!seen[@]}" "$R/nix/store/" || exit 1
      # Without the running systemd binary, soft-reboot runs /sbin/init below.
      SD=$(readlink -f /proc/1/exe)
      if [ -n "$SD" ] && [ -e "$R$SD" ]; then rm -f "$R$SD"; fi
      for t in "''${TOOLS[@]}"; do
        if p=$(tp "$t"); then ln -sf "$p" "$R/bin/$t"; fi
      done
      ln -sf bash "$R/bin/sh"
      cp -L /etc/os-release "$R/etc/os-release"
      cp -L /etc/os-release "$R/usr/lib/os-release"
      cp -L /etc/passwd /etc/group "$R/etc/"
      TI=""
      for d in "$R"/nix/store/*ncurses*/share/terminfo; do
        if [ -d "$d" ]; then TI=''${d#"$R"}; break; fi
      done

      {
        printf 'export PATH=/bin TERM=linux TERMINFO_DIRS=%q UUID=%q\n' "$TI" "$UUID"
        printf 'MAPPER=%q SNAPDIR=%q KEEP=%q TTY=%q HEADROOM=%q\n' "$mapper" "$snapdir" "$keep" "$tty" "$headroom"
        printf 'CLEAR=('
        for c in "''${clear[@]}"; do printf '%q ' "$c"; done
        printf ')\n'
      } >"$R/etc/fixenv"
      cat >"$R/etc/bashrc" <<'RC'
      . /etc/fixenv
      PS1='ramroot# '
      status
      RC
      cat >"$R/bin/status" <<'ST'
      #!/bin/bash
      . /etc/fixenv
      echo
      if mountpoint -q /mnt; then btrfs filesystem usage /mnt | sed -n '2,4p;/^Metadata/p'; echo "Commands: fix | status | reboot-now"
      elif [ -d /sys/fs/btrfs/$UUID ]; then echo "!!! Disk is STILL HELD by the old system. Tell QM, or run: reboot-now"
      else echo "Disk released. Type: fix    (then reboot-now when it says Done)"; fi
      ST
      cat >"$R/bin/fix" <<'FX'
      #!/bin/bash
      . /etc/fixenv
      M=/mnt
      say() { echo; echo "=== $*"; }
      unalloc() { btrfs filesystem usage -b $M | awk '/Device unallocated:/{print $3}'; }
      if ! mountpoint -q $M; then
        [ -d /sys/fs/btrfs/$UUID ] && { echo "Disk still held; can't fix from here."; exit 1; }
        say "Mounting the disk read-write"
        mount -o subvolid=5,skip_balance,noatime "$MAPPER" $M || exit 1
      fi
      say "1/4 Freeing empty data space"
      if ! { btrfs balance start -dusage=0 $M && btrfs balance start -dusage=5 $M; }; then
        echo "!!! Balance hit ENOSPC. Stop here and tell QM."; exit 1
      fi
      say "2/4 Deleting old snapshots in $SNAPDIR (keeping newest $KEEP)"
      for n in $(ls "$M/$SNAPDIR" | grep -E '^[0-9]+$' | sort -n | head -n -"$KEEP"); do
        btrfs subvolume delete "$M/$SNAPDIR/$n/snapshot" && rm -rf "$M/$SNAPDIR/$n"
      done
      btrfs subvolume sync $M
      say "3/4 Clearing: ''${CLEAR[*]:-nothing}"
      for d in "''${CLEAR[@]}"; do
        [ -n "$d" ] || continue
        du -sh "$M/$d" 2>/dev/null; rm -rf "$M/$d"
      done
      say "4/4 Freeing more data space for metadata"
      for u in 10 20 30 40 50; do
        [ "$(unalloc)" -ge $((HEADROOM*1024*1024*1024)) ] && break
        btrfs balance start -dusage=$u $M
      done
      btrfs filesystem usage $M | sed -n '2,4p;/^Metadata/p'
      echo; echo "Done. If 'Device unallocated' is tens of GiB, type: reboot-now"
      FX
      cat >"$R/bin/reboot-now" <<'RB'
      #!/bin/bash
      . /etc/fixenv
      sync; umount /mnt 2>/dev/null; sync; echo b > /proc/sysrq-trigger
      RB
      cat >"$R/sbin/init" <<'IN'
      #!/bin/bash
      . /etc/fixenv
      mountpoint -q /proc || mount -t proc proc /proc
      mountpoint -q /sys || mount -t sysfs sys /sys
      mountpoint -q /dev || mount -t devtmpfs dev /dev
      chvt "''${TTY#tty}" 2>/dev/null
      while :; do setsid -c bash --rcfile /etc/bashrc -i <>"/dev/$TTY" >&0 2>&1; sleep 1; done
      IN
      chmod +x "$R/bin/status" "$R/bin/fix" "$R/bin/reboot-now" "$R/sbin/init"

      if chroot "$R" /bin/bash -c '. /etc/fixenv; btrfs --version && findmnt --version && setsid --version && mountpoint --version' >/dev/null; then
        echo "RAM toolkit works."
      else
        echo "Toolkit test failed; NOT switching. Paste this to QM."
        exit 1
      fi

      if awk 'NR > 1 { print $1 }' /proc/swaps | grep -qxF -- "$swap"; then
        echo
        echo "First: moving what is in $swap back into RAM, so it stops holding the disk."
        if findmnt -no OPTIONS / | tr , '\n' | grep -qx ro; then
          echo "/ is read-only, so swapfile-release opens the swapfile read-only to turn it off."
          if ! ${swapfileRelease}/bin/swapfile-release; then
            echo "Could not release the swapfile; NOT switching. Paste this to QM."
            umount -R "$R"
            exit 1
          fi
        else
          echo "/ is still read-write, so a plain swapoff is enough."
          if ! swapoff "$swap"; then
            echo "swapoff failed; NOT switching. Paste this to QM."
            umount -R "$R"
            exit 1
          fi
        fi
      fi

      echo
      echo "Next: soft-reboot into the RAM toolkit."
      echo "EVERYTHING open closes (Hyprland, LibreWolf, agents). Keep QM open on your phone."
      echo "After the switch you get a text console. If the screen stays black, press Ctrl+Alt+F''${tty#tty}."
      read -rp "Type GO to continue: " a </dev/tty
      if [ "$a" != GO ]; then
        echo "Stopped. The swapfile stays off until the next boot."
        umount -R "$R"
        exit 0
      fi
      if awk 'NR > 1 { print $1 }' /proc/swaps | grep -qxF -- "$swap"; then
        echo "Swapfile still active; stopping."
        exit 1
      fi
      systemctl soft-reboot
    '';
  };
in
{
  options.services.btrfsRescue = {
    enable = lib.mkEnableOption "tools that recover a btrfs root that went read-only without a live USB";
    swapfile = lib.mkOption {
      type = lib.types.str;
      default = "/swap/swapfile";
      description = "Swapfile on the btrfs filesystem; while active it keeps the filesystem from unmounting.";
    };
    luksDevice = lib.mkOption {
      type = lib.types.str;
      default = "/dev/mapper/root";
      description = "Block device the RAM root mounts read-write.";
    };
    snapshotDir = lib.mkOption {
      type = lib.types.str;
      default = "home/.snapshots";
      description = "Snapper snapshot directory, relative to the top-level subvolume.";
    };
    keepSnapshots = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 2;
      description = "Newest snapshots `fix` keeps.";
    };
    clearPaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "root/tmp/claude-1000" ];
      description = "Directories `fix` deletes, relative to the top-level subvolume.";
    };
    tty = lib.mkOption {
      type = lib.types.str;
      default = "tty1";
      description = "Console the RAM root's shell runs on.";
    };
    ramRootSize = lib.mkOption {
      type = lib.types.str;
      default = "8G";
      description = "Size of the tmpfs holding the RAM root.";
    };
    headroomGiB = lib.mkOption {
      type = lib.types.ints.positive;
      default = 64;
      description = "Unallocated space `fix` balances towards.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isx86_64;
        message = "services.btrfsRescue: the swapoff_ro kprobe reads x86_64 registers.";
      }
      {
        # fix runs rm -rf on each, joined to the top-level mount.
        assertion = lib.all (p: p != "" && !lib.hasPrefix "/" p && !lib.hasInfix ".." p) cfg.clearPaths;
        message = "services.btrfsRescue.clearPaths must be non-empty relative paths without '..'.";
      }
    ];
    environment.systemPackages = [ swapfileRelease ramRescue ];
  };
}
