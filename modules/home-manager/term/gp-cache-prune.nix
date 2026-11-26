{ config, lib, pkgs, ... }:
let
  cfg = config.services.gpCachePrune;
  prune = pkgs.writeShellScript "gp-cache-prune" ''
    export PATH=${lib.makeBinPath [ pkgs.git ]}
    exec ${pkgs.python3}/bin/python3 ${./gp-cache-prune.py} \
      ${lib.concatMapStringsSep " " (p: "--cache-root ${lib.escapeShellArg p}") cfg.cacheRoots} \
      ${lib.concatMapStringsSep " " (p: "--temporary-root ${lib.escapeShellArg p}") cfg.temporaryRoots} \
      ${lib.optionalString (cfg.pressurePath != null) "--pressure-path ${lib.escapeShellArg cfg.pressurePath} --pressure-idle-hours 1"} "$@"
  '';
in
{
  options.services.gpCachePrune = {
    enable = lib.mkEnableOption "cleanup of old, unused, fully published gp registry mirrors";
    cacheRoots = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "${config.home.homeDirectory}/.cache" ];
      description = "Cache roots containing gp and gp-* namespaces.";
    };
    pressurePath = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Filesystem whose low headroom enables one-hour rather than 48-hour clone retention.";
    };
    temporaryRoots = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Shared temporary roots whose immediate children may contain dedicated gp/gp-*/gpcache namespaces.";
    };
  };

  config = lib.mkIf config.services.gpCachePrune.enable {
    xdg.configFile = lib.genAttrs [
      "systemd/user/gp-cache-prune.service"
      "systemd/user/gp-cache-prune.timer"
    ] (_: { force = true; });

    systemd.user.services.gp-cache-prune = {
      Unit.Description = "Prune old registry mirrors without unpublished work";
      Service = {
        Type = "oneshot";
        ExecStart = prune;
        Slice = "background.slice";
        Nice = 19;
        IOSchedulingClass = "idle";
        TimeoutStartSec = "15min";
      };
    };
    systemd.user.timers.gp-cache-prune = {
      Unit.Description = "Check unused registry mirrors every minute";
      Timer = {
        OnBootSec = "5min";
        OnUnitInactiveSec = "1min";
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
