{ config, lib, pkgs, ... }:
let
  prune = pkgs.writeShellScript "build-cache-prune" ''
    export PATH=${lib.makeBinPath [ pkgs.git pkgs.findutils ]}
    exec ${pkgs.python3}/bin/python3 ${./build-cache-prune.py} \
      --proc-helper ${./worktree-prune.py} "$@"
  '';
in
{
  options.services.buildCachePrune.enable = lib.mkEnableOption
    "cleanup of idle reproducible dependencies and stopped throwaway test databases";

  config = lib.mkIf config.services.buildCachePrune.enable {
    xdg.configFile = lib.genAttrs [
      "systemd/user/build-cache-prune.service"
      "systemd/user/build-cache-prune.timer"
    ] (_: { force = true; });
    systemd.user.services.build-cache-prune = {
      Unit.Description = "Remove idle build caches while retaining source and test evidence";
      Unit.After = [ "worktree-prune.service" ];
      Service = {
        Type = "oneshot";
        ExecStart = prune;
        Slice = "background.slice";
        Nice = 15;
        IOSchedulingClass = "idle";
        TimeoutStartSec = "2h";
      };
    };
    systemd.user.timers.build-cache-prune = {
      Unit.Description = "Reclaim idle build caches hourly";
      Timer = {
        OnBootSec = "10min";
        OnUnitInactiveSec = "1h";
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
