{ config, lib, pkgs, osConfig, ... }:
let
  cfg = config.services.diskWatch;
  watch = pkgs.writeShellScript "disk-watch" ''
    export PATH=${lib.makeBinPath [ pkgs.util-linux pkgs.systemd pkgs.libnotify ]}
    exec ${pkgs.python3}/bin/python3 ${./disk-watch.py} "$@"
  '';
in
{
  options.services.diskWatch.enable = lib.mkEnableOption
    "independent disk checks, cleanup and alerts before Btrfs fills";

  config = lib.mkIf cfg.enable {
    # Recovery can install these units before a Home Manager activation.
    xdg.configFile = lib.genAttrs [
      "systemd/user/disk-watch.service"
      "systemd/user/disk-watch.timer"
      "systemd/user/disk-watch-gc.service"
    ] (_: { force = true; });

    systemd.user.services.disk-watch = {
      Unit.Description = "Check disk headroom independently of slow cleanup";
      Service = {
        Type = "oneshot";
        ExecStart = watch;
        Slice = "background.slice";
        TimeoutStartSec = "25s";
      };
    };
    systemd.user.timers.disk-watch = {
      Unit.Description = "Check disk headroom every 30 seconds";
      Timer = {
        OnBootSec = "15s";
        OnUnitInactiveSec = "30s";
        AccuracySec = "1s";
      };
      Install.WantedBy = [ "timers.target" ];
    };
    systemd.user.services.disk-watch-gc = {
      Unit.Description = "Reclaim unrooted Nix store paths under disk pressure";
      Service = {
        Type = "oneshot";
        ExecStart = "${osConfig.nix.package}/bin/nix-store --gc --max-freed 107374182400";
        Slice = "background.slice";
        Nice = 10;
        IOSchedulingClass = "best-effort";
        IOSchedulingPriority = 6;
        TimeoutStartSec = "45min";
      };
    };
  };
}
