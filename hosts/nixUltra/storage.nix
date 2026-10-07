{ ... }:
# Snapshots, scrub and swap for the LUKS + btrfs disk install-nixUltra lays
# out. NixOS generations already roll the system back; these cover the data.
{
  # Hourly snapshots of /home; browse them under /home/.snapshots or roll
  # back with `snapper -c home undochange`. Nested subvolumes are not
  # snapshotted, so a churny directory can be kept out by making it one.
  services.snapper.configs.home = {
    SUBVOLUME = "/home";
    ALLOW_USERS = [ "greencheetah" ];
    TIMELINE_CREATE = true;
    TIMELINE_CLEANUP = true;
    TIMELINE_LIMIT_HOURLY = 48;
    TIMELINE_LIMIT_DAILY = 14;
    TIMELINE_LIMIT_WEEKLY = 8;
    TIMELINE_LIMIT_MONTHLY = 0;
    TIMELINE_LIMIT_YEARLY = 0;
  };
  # Snapper expects the .snapshots subvolume to exist; `v` makes one.
  systemd.tmpfiles.rules = [ "v /home/.snapshots 0750 root users -" ];

  # Every subvolume is the same filesystem, so scrubbing / covers all four.
  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = [ "/" ];
  };

  # Fills before the swapfile; hibernation skips zram and uses the swapfile.
  zramSwap.enable = true;

  # Each 7.2 kernel + initrd is ~80 MB on the 1 GB ESP.
  boot.loader.systemd-boot.configurationLimit = 20;
}
