{ config, lib, pkgs, ... }:
let
  cfg = config.services.worktreePrune;
  prune = pkgs.writeShellScript "worktree-prune" ''
    export PATH=${lib.makeBinPath [ pkgs.git pkgs.git-lfs pkgs.gnutar pkgs.zstd ]}
    exec ${pkgs.python3}/bin/python3 ${./worktree-prune.py} \
      --idle-hours ${toString cfg.idleHours} \
      --archive-dir "$HOME/.local/state/disk-watch/worktree-archives" "$@"
  '';
in
{
  options.services.worktreePrune = {
    enable = lib.mkEnableOption "retirement of idle, fully published agent worktrees";
    idleHours = lib.mkOption {
      type = lib.types.ints.positive;
      default = 6;
      description = "Minimum idle time before a clean published worktree can be retired.";
    };
  };

  config = lib.mkIf cfg.enable {
    xdg.configFile = lib.genAttrs [
      "systemd/user/worktree-prune.service"
      "systemd/user/worktree-prune.timer"
    ] (_: { force = true; });

    systemd.user.services.worktree-prune = {
      Unit.Description = "Retire idle worktrees without losing unpublished work or evidence";
      Service = {
        Type = "oneshot";
        ExecStart = prune;
        Slice = "background.slice";
        Nice = 15;
        IOSchedulingClass = "idle";
        TimeoutStartSec = "2h";
      };
    };
    systemd.user.timers.worktree-prune = {
      Unit.Description = "Retire completed worktrees every fifteen minutes";
      Timer = {
        OnBootSec = "5min";
        OnUnitInactiveSec = "15min";
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
