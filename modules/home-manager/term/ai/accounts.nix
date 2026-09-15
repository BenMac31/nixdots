{ config, lib, inputs, pkgs, ... }:
let
  cfg = config.services.graphide-accounts;
  selectedClaude = pkgs.writeShellScriptBin "claude" ''
    export GRAPHIDE_CLAUDE_BIN=${lib.escapeShellArg (lib.getExe config.ai.claude.package)}
    exec ${cfg.package}/bin/graphide-claude "$@"
  '';
  selectedCodex = pkgs.writeShellScriptBin "codex" ''
    export GRAPHIDE_CODEX_BIN=${lib.escapeShellArg (lib.getExe pkgs.unstable.unfree.codex)}
    exec ${cfg.package}/bin/graphide-codex "$@"
  '';
  selectedAccountCommands = pkgs.symlinkJoin {
    name = "graphide-selected-account-commands";
    paths = [ selectedClaude selectedCodex ];
  };
in {
  imports = [ inputs.graphide-tools.homeManagerModules.accounts ];
  services.graphide-accounts = {
    enable = lib.mkDefault config.ai.enable;
    claudeCommand = lib.getExe config.ai.claude.package;
    # This flake's unstable package set lives under the unfree-enabled overlay.
    codexCommand = lib.getExe pkgs.unstable.unfree.codex;
    # Each poll cold-starts `codex app-server`: ~15 MB read and ~2 MB of sqlite
    # writes. 240s still refreshes inside the snapshot's 300s stale cutoff.
    interval = 240;
  };
  # High-priority executable names make selection apply to every new launch
  # through PATH, including GUI launchers and child applications. The account
  # service keeps absolute paths to the real vendor binaries, avoiding loops.
  home.packages = lib.mkIf cfg.enable [
    pkgs.unstable.unfree.codex
    (lib.hiPrio selectedAccountCommands)
  ];
}
