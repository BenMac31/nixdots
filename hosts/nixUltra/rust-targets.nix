{ config, lib, pkgs, ... }:
{
  options.services.rustTargetSubvolumes.enable = lib.mkEnableOption
    "exclude Cargo target directories from home snapshots";

  config = lib.mkIf config.services.rustTargetSubvolumes.enable {
    systemd.services.rust-target-subvolumes = {
      description = "Keep Rust build outputs outside home snapshots";
      after = [ "local-fs.target" ];
      path = [ pkgs.btrfs-progs pkgs.coreutils ];
      serviceConfig = {
        Type = "oneshot";
        User = "greencheetah";
        Group = "users";
        Nice = 10;
        IOSchedulingClass = "idle";
        TimeoutStartSec = "20min";
      };
      script = ''
        exec ${pkgs.python3}/bin/python3 ${./rust-target-subvolumes.py}
      '';
    };

    systemd.timers.rust-target-subvolumes = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitInactiveSec = "5min";
      };
    };
  };
}
