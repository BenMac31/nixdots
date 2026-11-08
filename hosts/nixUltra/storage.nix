{ pkgs, ... }:
# Snapshots, scrub and swap for the LUKS + btrfs disk install-nixUltra lays
# out. NixOS generations already roll the system back; these cover the data.
let
  # Metadata grows into unallocated space only. On 2026-11-07 data chunks
  # held every byte of the disk (unallocated 1 MiB since the mid-October
  # fill), metadata reached 64.5 of its 65 GiB and the laptop hung with
  # 166 GiB "free". Compacting near-empty data chunks hands space back.
  unallocatedTarget = 64 * 1024 * 1024 * 1024;
in
{
  # Hourly snapshots of /home; browse them under /home/.snapshots or roll
  # back with `snapper -c home undochange`. Nested subvolumes are not
  # snapshotted, so a churny directory can be kept out by making it one.
  # Snapshots pinned 340 GiB of data and 21 GiB of metadata on 2026-11-07.
  # With ranges, cleanup trims to the lower bound while under FREE_LIMIT
  # free; single numbers make snapper ignore free space entirely.
  services.snapper.configs.home = {
    SUBVOLUME = "/home";
    ALLOW_USERS = [ "greencheetah" ];
    TIMELINE_CREATE = true;
    TIMELINE_CLEANUP = true;
    TIMELINE_LIMIT_HOURLY = "6-12";
    TIMELINE_LIMIT_DAILY = "2-7";
    TIMELINE_LIMIT_WEEKLY = "0-2";
    TIMELINE_LIMIT_MONTHLY = 0;
    TIMELINE_LIMIT_YEARLY = 0;
    FREE_LIMIT = "0.2";
  };
  # Snapper expects the .snapshots subvolume to exist; `v` makes one.
  # Claude Code sessions keep scratchpads, podman stores and Go caches under
  # /tmp/claude-1000 on this same disk; the 10-day /tmp default let 760 GB
  # pile up in a week and fill it. Anything untouched for 3 days goes.
  systemd.tmpfiles.rules = [
    "v /home/.snapshots 0750 root users -"
    "e /tmp/claude-1000 - - - 3d"
    # The kernel relocates sparse data chunks itself once unallocated space
    # drops under ten chunks; both default off.
    "w /sys/fs/btrfs/*/allocation/data/dynamic_reclaim - - - - 1"
    "w /sys/fs/btrfs/*/allocation/data/periodic_reclaim - - - - 1"
  ];
  # gred-rs's local cargo lanes and sccache; snapshots held 1.1 TB of rebuilt
  # target dirs on 2026-10-16. Made at login if missing, as the user.
  systemd.user.tmpfiles.users.greencheetah.rules = [
    "v %C/gred-rs/target - - - -"
    "v %C/gred-rs/sccache - - - -"
    # Agent worktrees, 96% of what hourly snapshots caught on 2026-11-07.
    "v %h/Projects/wt - - - -"
    # ubuntu-vm's 32 GB disk image rewrites constantly; no CoW, no snapshots.
    "v %h/.local/share/vms - - - -"
    "h %h/.local/share/vms - - - - +C"
  ];

  # Every subvolume is the same filesystem, so scrubbing / covers all four.
  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = [ "/" ];
  };

  # Backstop for the kernel reclaim above, with more headroom: a no-op
  # unless unallocated is under the target. Chunks holding the swapfile are
  # full and skipped.
  systemd.services.btrfs-headroom = {
    description = "Keep unallocated btrfs space for metadata";
    path = [ pkgs.btrfs-progs pkgs.gawk ];
    serviceConfig = {
      Type = "oneshot";
      Nice = 19;
      IOSchedulingClass = "idle";
    };
    script = ''
      unallocated() {
        btrfs filesystem usage -b / | awk '/Device unallocated:/ { print $3 }'
      }
      for usage in 0 5 10 20 30 40 50; do
        if [ "$(unallocated)" -ge ${toString unallocatedTarget} ]; then
          exit 0
        fi
        btrfs balance start -dusage=$usage /
      done
      echo "unallocated still $(unallocated) bytes after -dusage=50" >&2
    '';
  };
  systemd.timers.btrfs-headroom = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "10min";
      OnUnitActiveSec = "1h";
    };
  };

  # Fills before the swapfile; hibernation skips zram and uses the swapfile.
  zramSwap.enable = true;

  # Each 7.2 kernel + initrd is ~80 MB on the 1 GB ESP.
  boot.loader.systemd-boot.configurationLimit = 20;
}
