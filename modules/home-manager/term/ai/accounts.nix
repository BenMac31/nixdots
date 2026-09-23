{ config, lib, inputs, pkgs, ... }:
let
  cfg = config.services.graphide-accounts;
  # Every agent session, and everything it spawns, runs in agents.slice
  # (hosts/nixBlade/agent-throttle.nix: low CPU/IO weight, 11G memory kill
  # line). This wrapper is the one launch path every terminal, alias and GUI
  # launcher goes through, so the slice lives here rather than in a shell
  # alias: on 2026-09-23 the alias had been shadowed, no session was in the
  # slice, and one agent's `nix eval` grew to 13 GB and swapped the desktop
  # to a standstill. The wrapper re-execs itself inside a scope once; with no
  # user bus (a bare ssh or a container) it runs unconfined.
  intoAgentsSlice = ''
    if [[ $(< /proc/self/cgroup) != */agents.slice/* && -S "''${XDG_RUNTIME_DIR:-/nonexistent}/bus" ]] \
        && command -v systemd-run >/dev/null; then
      exec systemd-run --user --scope --slice=agents.slice --quiet --collect -- "$0" "$@"
    fi
  '';
  selectedClaude = pkgs.writeShellScriptBin "claude" ''
    ${intoAgentsSlice}
    export GRAPHIDE_CLAUDE_BIN=${lib.escapeShellArg (lib.getExe config.ai.claude.package)}
    exec ${cfg.package}/bin/graphide-claude "$@"
  '';
  selectedCodex = pkgs.writeShellScriptBin "codex" ''
    ${intoAgentsSlice}
    export GRAPHIDE_CODEX_BIN=${lib.escapeShellArg (lib.getExe pkgs.master.unfree.codex)}
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
    # This flake's master package set lives under the unfree-enabled overlay.
    codexCommand = lib.getExe pkgs.master.unfree.codex;
    # Each poll cold-starts `codex app-server`: ~15 MB read and ~2 MB of sqlite
    # writes. 240s still refreshes inside the snapshot's 300s stale cutoff.
    interval = 240;
  };
  # High-priority executable names make selection apply to every new launch
  # through PATH, including GUI launchers and child applications. The account
  # service keeps absolute paths to the real vendor binaries, avoiding loops.
  home.packages = lib.mkIf cfg.enable [
    pkgs.master.unfree.codex
    (lib.hiPrio selectedAccountCommands)
  ];
}
