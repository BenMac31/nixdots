{ lib, pkgs, ... }:
# Snapshots, scrub and swap for the LUKS + btrfs disk install-nixUltra lays
# out. NixOS generations already roll the system back; these cover the data.
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
  # The NixOS default is daily, too slow to free space under agent churn.
  services.snapper.cleanupInterval = "1h";

  # Agent and build churn, capped at the image size (scratch.nix).
  services.scratchImage = {
    enable = lib.mkDefault true;
    binds = [ "Projects/wt" ".cache/go-build" ".cache/gred-rs" ".local/share/containers" ];
  };
  # Agents write to /scratch/tmp instead, so /tmp in RAM stays small.
  boot.tmp = {
    useTmpfs = true;
    tmpfsSize = "25%";
  };
  # Snapper expects the .snapshots subvolume to exist; `v` makes one.
  # An agent started outside the wrappers still writes /tmp/claude-1000,
  # now RAM; anything untouched for a day goes.
  systemd.tmpfiles.rules = [
    "v /home/.snapshots 0750 root users -"
    "e /tmp/claude-1000 - - - 1d"
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

  # swapfile-release and btrfs-ram-rescue, for when btrfs has gone read-only.
  services.btrfsRescue.enable = lib.mkDefault true;

  # Every subvolume is the same filesystem, so scrubbing / covers all four.
  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = [ "/" ];
  };

  # Metadata grows into unallocated space only; with none left a transaction
  # aborts and btrfs goes read-only while df still shows free space. The
  # guard keeps unallocated space and escalates long before that.
  services.diskGuard = {
    enable = lib.mkDefault true;
    # The 128 GiB /scratch image leaves about 85 GiB truly free, which is fine:
    # the metadata risk is unallocated space, not data free.
    trueFreeTightGiB = 48;
    trueFreeOkPercent = 4;
    ballast.sizeGiB = 16;
    # Agents started outside the wrappers still write here, in RAM.
    purge.dirs = [ "/scratch/tmp" "/tmp/claude-1000" ];
  };

  # Fills before the swapfile; hibernation skips zram and uses the swapfile.
  zramSwap.enable = true;

  # Each 7.2 kernel + initrd is ~80 MB on the 1 GB ESP.
  boot.loader.systemd-boot.configurationLimit = 20;
}
