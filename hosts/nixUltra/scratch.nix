# A fixed-size ext4 image for agent and build churn. When it fills, builds
# and agents get ENOSPC; the btrfs disk under /, /home and /nix does not.
# The image lives NOCOW and fully allocated in its own subvolume, so writes
# inside it never take new btrfs data or metadata chunks.
{ config, lib, pkgs, ... }:
let
  cfg = config.services.scratchImage;
  home = "/home/${cfg.user}";
in
{
  options.services.scratchImage = {
    enable = lib.mkEnableOption "the capped /scratch image for agent and build churn";
    user = lib.mkOption {
      type = lib.types.str;
      default = "greencheetah";
    };
    binds = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Paths under the user's home, mounted from the same name under /scratch/home.";
    };
  };

  config = lib.mkIf cfg.enable {
    fileSystems = lib.listToAttrs (map (p: lib.nameValuePair "${home}/${p}" {
      device = "/scratch/home/${p}";
      fsType = "none";
      options = [ "bind" "nofail" "x-systemd.requires-mounts-for=/scratch" "x-systemd.after=scratch-dirs.service" ];
    }) cfg.binds) // {
      "/scratch-store" = {
        device = "/dev/disk/by-label/nixultra";
        fsType = "btrfs";
        options = [ "subvol=scratch-store" "noatime" "nofail" ];
      };
      # X-fstrim.notrim and the udev rule keep discards off the loop device:
      # a discard punches holes in the image, and the cap leaks back to btrfs.
      "/scratch" = {
        device = "/scratch-store/scratch.img";
        fsType = "ext4";
        # systemd-fsck only checks block devices, not a loop image path.
        noCheck = true;
        options = [ "loop" "nofail" "noatime" "X-fstrim.notrim" "x-systemd.requires-mounts-for=/scratch-store" ];
      };
    };
    services.udev.extraRules = ''
      ACTION=="add|change", KERNEL=="loop[0-9]*", ATTR{loop/backing_file}=="/scratch-store/scratch.img", ATTR{queue/discard_max_bytes}="0"
    '';

    # Made after the mount, never on the root filesystem underneath it.
    systemd.services.scratch-dirs = {
      description = "Create the directories on /scratch";
      wantedBy = [ "scratch.mount" ];
      after = [ "scratch.mount" ];
      unitConfig.RequiresMountsFor = "/scratch";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        install -d -m 1777 /scratch/tmp
        install -d -m 0700 -o ${cfg.user} -g users /scratch/tmp/${cfg.user} /scratch/home
        ${lib.concatMapStrings (p: ''
          install -d -m 0755 -o ${cfg.user} -g users ${lib.escapeShellArg "/scratch/home/${p}"}
        '') cfg.binds}
      '';
    };
    systemd.tmpfiles.rules = [ "e /scratch/tmp/${cfg.user} - - - 3d" ];
  };
}
