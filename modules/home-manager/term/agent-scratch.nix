{ config, lib, pkgs, osConfig, ... }:
let
  cfg = config.services.agentScratch;
  storage = osConfig.services.agentStorage or { enable = false; };
  runtime = pkgs.writeShellScriptBin "agent-storage" ''
    export PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.systemd pkgs.libnotify ]}:"$PATH"
    exec ${pkgs.python3}/bin/python3 ${./agent-storage.py} \
      --bulk ${lib.escapeShellArg storage.bulkPath} \
      --output ${lib.escapeShellArg storage.outputPath} \
      --task-helper ${./agent-task-storage.py} \
      --bwrap ${pkgs.bubblewrap}/bin/bwrap \
      --minimum-free-gib ${toString cfg.minimumFreeGiB} \
      --cleanup-free-gib ${toString cfg.cleanupFreeGiB} \
      --command-reserve-gib ${toString cfg.commandReserveGiB} \
      --uv ${pkgs.uv}/bin/uv \
      --output-limit-mib ${toString cfg.commandOutputMiB} \
      ${lib.optionalString cfg.cacheCleanup.enable "--cache-cleanup"} \
      ${lib.optionalString cfg.taskCleanup.enable "--task-cleanup"} "$@"
  '';
  bashInit = pkgs.writeText "agent-storage-bash-env" ''
    if [[ -n "''${BASH_EXECUTION_STRING:-}" && -z "''${AGENT_STORAGE_COMMAND:-}" ]]; then
      mapfile -d "" -t _agent_storage_argv < /proc/$$/cmdline
      exec ${runtime}/bin/agent-storage command -- ${pkgs.bash}/bin/bash \
        "''${_agent_storage_argv[@]:1}"
    fi
  '';
  command = pkgs.writeShellScriptBin "agent-scratch" ''
    export PATH=${lib.makeBinPath [
      pkgs.btrfs-progs pkgs.coreutils pkgs.e2fsprogs pkgs.findutils
      pkgs.rsync pkgs.udisks pkgs.util-linux
    ]}
    exec ${pkgs.python3}/bin/python3 ${./agent-scratch.py} \
      --size-gib ${toString cfg.sizeGiB} \
      --minimum-free-gib ${toString cfg.cleanupFreeGiB} \
      --proc-helper ${./worktree-prune.py} \
      ${lib.concatMapStringsSep " " (p: "--boundary ${lib.escapeShellArg p}") cfg.boundaryPaths} \
      ${lib.concatMapStringsSep " " (p: "--path ${lib.escapeShellArg p}") cfg.paths} "$@"
  '';
in
{
  options.services.agentScratch = {
    enable = lib.mkEnableOption "a user-owned capped agent workspace mounted through UDisks";
    sizeGiB = lib.mkOption {
      type = lib.types.ints.positive;
      default = 128;
      description = "Fixed image capacity shared by agent workspaces and caches.";
    };
    minimumFreeGiB = lib.mkOption { type = lib.types.ints.positive; default = 8; };
    cleanupFreeGiB = lib.mkOption { type = lib.types.ints.positive; default = 32; };
    commandOutputMiB = lib.mkOption { type = lib.types.ints.positive; default = 8; };
    commandReserveGiB = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 0;
      description = "Optional bulk admission estimate held until descendants finish. Zero disables accounting; long-lived agent descendants make fixed per-command estimates unsuitable for the default policy.";
    };
    taskCleanup.enable = lib.mkEnableOption "reclaim command scratch after every tracked child exits";
    cacheCleanup.enable = lib.mkEnableOption "pressure cleanup of reproducible Go and unused UV cache entries";
    migration.enable = lib.mkEnableOption "automatic migration of idle legacy worktrees into scratch";
    runtimePackage = lib.mkOption { type = lib.types.package; readOnly = true; default = runtime; };
    bashInit = lib.mkOption { type = lib.types.path; readOnly = true; default = bashInit; };
    paths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Paths relative to home eligible for explicit verified migration.";
    };
    boundaryPaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "Projects/wt" "Projects/graphide/scratch" "Projects/IvorySummit" ".cache/tmp-overflow" ".cache/gp" ];
      description = "Workspace roots whose new children go into scratch while existing inodes remain linked.";
    };
    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = command;
      description = "Workspace provisioning, mounting and migration command.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ command ] ++ lib.optional storage.enable runtime;
    home.activation.agentStorageBootstrap = lib.hm.dag.entryAfter [ "installPackages" ] ''
      # A current declarative activation supersedes the legacy-boot repair.
      if [ -f "$HOME/.local/state/agent-storage-rollout/desired.json" ]; then
        run ${pkgs.systemd}/bin/systemctl --user stop agent-storage-restore.timer agent-storage-restore.service 2>/dev/null || true
        for storage_restore_link in \
          "$HOME/.config/systemd/user/agent-storage-restore.service" \
          "$HOME/.config/systemd/user/agent-storage-restore.timer"; do
          case "$(${pkgs.coreutils}/bin/readlink "$storage_restore_link")" in
            /nix/store/*-agent-storage-bootstrap/share/agent-storage/agent-storage-restore.*)
              run rm -f "$storage_restore_link" ;;
          esac
        done
        run rm -f "$HOME/.config/systemd/user/default.target.wants/agent-storage-restore.service" \
          "$HOME/.config/systemd/user/timers.target.wants/agent-storage-restore.timer" \
          "$HOME/.local/state/agent-storage-rollout/desired.json" \
          "$HOME/.local/state/agent-storage-rollout/gcroot"
      fi
      if ${pkgs.nix}/bin/nix profile list --json 2>/dev/null \
          | ${pkgs.jq}/bin/jq -e '.elements | has("agent-storage-bootstrap")' >/dev/null; then
        run ${pkgs.nix}/bin/nix profile remove agent-storage-bootstrap
      fi
    '';
    xdg.configFile."systemd/user/agent-scratch.service".force = true;
    systemd.user.services.agent-scratch = {
      Unit = {
        Description = "Mount the bounded agent workspace without pausing sessions";
        ConditionPathExists = "%h/.local/share/agent-scratch/store/scratch.img";
        Before = [ "gp-reprove-watch.service" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${command}/bin/agent-scratch mount";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = "30s";
        Slice = "background.slice";
        TimeoutStartSec = "45s";
      };
      Install.WantedBy = [ "default.target" ];
    };
    systemd.user.services.agent-storage-cleanup = lib.mkIf storage.enable {
      Unit.Description = "Clean expired scratch cache and closed output without stopping agents";
      Service = {
        Type = "oneshot";
        ExecStart = "${runtime}/bin/agent-storage cleanup";
        Slice = "background.slice";
        TimeoutStartSec = "5min";
      };
    };
    systemd.user.services.agent-scratch-migrate = lib.mkIf (storage.enable && cfg.migration.enable) {
      Unit.Description = "Move idle agent directories into bounded scratch without losing local work";
      Service = {
        Type = "oneshot";
        ExecStartPre = "${command}/bin/agent-scratch --apply boundary";
        ExecStart = "${command}/bin/agent-scratch --children --limit 4 --apply migrate";
        Slice = "background.slice";
        Nice = 19;
        IOSchedulingClass = "idle";
        TimeoutStartSec = "30min";
        KillMode = "control-group";
      };
    };
    systemd.user.timers.agent-scratch-migrate = lib.mkIf (storage.enable && cfg.migration.enable) {
      Unit.Description = "Retry deferred agent-directory migrations hourly";
      Timer = { OnBootSec = "5min"; OnUnitInactiveSec = "1h"; };
      Install.WantedBy = [ "timers.target" ];
    };
    systemd.user.timers.agent-storage-cleanup = lib.mkIf storage.enable {
      Unit.Description = "Check bounded scratch storage every minute";
      Timer = { OnBootSec = "1min"; OnUnitInactiveSec = "1min"; };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
