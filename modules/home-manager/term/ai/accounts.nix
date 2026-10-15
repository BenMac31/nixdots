{ config, lib, inputs, pkgs, ... }:
let
  cfg = config.services.graphide-accounts;
  # Every agent session runs in agents.slice (hosts/nixBlade/agent-throttle.nix),
  # and these wrappers are the one launch path every terminal and GUI uses.
  # Ask the user manager first: inside a bwrap pid namespace the bus socket
  # exists but refuses connections, and systemd-run would fail the launch.
  intoAgentsSlice = ''
    if [[ $(< /proc/self/cgroup) != */agents.slice/* && -S "''${XDG_RUNTIME_DIR:-/nonexistent}/bus" ]] \
        && command -v systemd-run >/dev/null \
        && systemctl --user show-environment >/dev/null 2>&1; then
      exec systemd-run --user --scope --slice=agents.slice --quiet --collect -- "$0" "$@"
    fi
  '';
  claudeSettings = lib.optionalAttrs (config.ai.claude.effort != null) {
    effortLevel = config.ai.claude.effort;
  } // lib.optionalAttrs config.ai.claude.bypassPermissions {
    permissions.defaultMode = "bypassPermissions";
    skipDangerousModePermissionPrompt = true;
  };
  sessionSettings = lib.optionalString (claudeSettings != { })
    "--settings ${lib.escapeShellArg (builtins.toJSON claudeSettings)}";
  selectedClaude = pkgs.writeShellScriptBin "claude" ''
    ${intoAgentsSlice}
    export GRAPHIDE_CLAUDE_BIN=${lib.escapeShellArg (lib.getExe config.ai.claude.package)}
    exec ${cfg.finalPackage}/bin/graphide-claude ${sessionSettings} "$@"
  '';
  selectedCodex = pkgs.writeShellScriptBin "codex" ''
    ${intoAgentsSlice}
    export GRAPHIDE_CODEX_BIN=${lib.escapeShellArg (lib.getExe pkgs.master.unfree.codex)}
    exec ${cfg.finalPackage}/bin/graphide-codex "$@"
  '';
  # Graphide drives Codex through this adapter: point it at the account-aware
  # codex unless the caller set CODEX_PATH.
  selectedCodexAcp = pkgs.writeShellScriptBin "codex-acp" ''
    export CODEX_PATH="''${CODEX_PATH:-${lib.getExe selectedCodex}}"
    exec ${lib.getExe pkgs.unstable.unfree.codex-acp} "$@"
  '';
  selectedAccountCommands = pkgs.symlinkJoin {
    name = "graphide-selected-account-commands";
    paths = [ selectedClaude selectedCodex selectedCodexAcp ];
  };
in {
  imports = [ inputs.graphide-tools.homeManagerModules.accounts ];
  services.graphide-accounts = {
    enable = lib.mkDefault config.ai.enable;
    claudeCommand = lib.getExe config.ai.claude.package;
    codexCommand = lib.getExe pkgs.master.unfree.codex;
    # Each poll cold-starts `codex app-server`; 240s stays inside the
    # snapshot's 300s stale cutoff.
    interval = 240;
    idleInterval = 900;
    claudeUsage.enable = config.ai.claude.enable;
  };
  # These shadow the vendors' `claude` and `codex` on PATH; the account
  # service calls the vendor binaries by absolute path.
  home.packages = lib.mkIf cfg.enable [
    pkgs.master.unfree.codex
    (lib.hiPrio selectedAccountCommands)
  ];
}
