{ config, lib, inputs, pkgs, osConfig, ... }:
let
  cfg = config.services.graphide-accounts;
  storage = osConfig.services.agentStorage or { enable = false; };
  storageCommand = "${config.services.agentScratch.runtimePackage}/bin/agent-storage";
  sessionPrefix = lib.optionalString storage.enable "${storageCommand} session -- ";
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
  # Keep temp files in the bounded workspace once its image is provisioned.
  intoScratchTmp = if storage.enable then ''
    export TMPDIR=${lib.escapeShellArg "${storage.outputPath}/tmp"}
    export BASH_ENV=${config.services.agentScratch.bashInit}
  '' else ''
    if [[ -f "$HOME/.local/share/agent-scratch/store/scratch.img" ]]; then
      if [[ ! -d "$HOME/.local/share/agent-scratch/mount/tmp/$UID" ]]; then
        systemctl --user start agent-scratch.service || exit 1
      fi
      if [[ ! -w "$HOME/.local/share/agent-scratch/mount/tmp/$UID" ]]; then
        echo "Bounded workspace unavailable; restart agent-scratch.service." >&2
        exit 1
      fi
      export TMPDIR="$HOME/.local/share/agent-scratch/mount/tmp/$UID"
    elif [[ -d /scratch/tmp/$USER && -w /scratch/tmp/$USER ]]; then
      export TMPDIR=/scratch/tmp/$USER
    else
      # Scratch is optional; agent outputs must not fall back to the small RAM /tmp.
      export TMPDIR="$HOME/.cache/tmp-overflow/tmp"
      ${pkgs.coreutils}/bin/install -d -m 0700 "$TMPDIR" || exit 1
    fi
  '';
  claudeSettings = lib.optionalAttrs config.ai.claude.bypassPermissions {
    permissions.defaultMode = "bypassPermissions";
    skipDangerousModePermissionPrompt = true;
  };
  sessionSettings = lib.optionalString (claudeSettings != { })
    "--settings ${lib.escapeShellArg (builtins.toJSON claudeSettings)}";

  # Saved modelSettings.<model>.effortLevel can beat --settings effortLevel.
  # A CLI effort sets the launch default while allowing a later caller flag.
  sessionEffort = effort: lib.optionalString (effort != null)
    "--effort ${lib.escapeShellArg effort}";
  subagentLimit = lib.optionalString (config.ai.claude.maxConcurrentSubagents != null)
    "export CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS=\"\${CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS:-${toString config.ai.claude.maxConcurrentSubagents}}\"";
  selectedClaude = pkgs.writeShellScriptBin "claude" ''
    ${intoAgentsSlice}
    ${intoScratchTmp}
    # Keep Claude's deferred MCP tool loading enabled when an account or proxy
    # wrapper supplies a non-Anthropic API base URL.
    export ENABLE_TOOL_SEARCH="''${ENABLE_TOOL_SEARCH:-true}"
    ${subagentLimit}
    export GRAPHIDE_CLAUDE_BIN=${lib.escapeShellArg (lib.getExe config.ai.claude.package)}
    exec ${sessionPrefix}${cfg.finalPackage}/bin/graphide-claude ${sessionSettings} ${sessionEffort config.ai.claude.effort} "$@"
  '';
  selectedCodex = pkgs.writeShellScriptBin "codex" ''
    ${intoAgentsSlice}
    ${intoScratchTmp}
    export GRAPHIDE_CODEX_BIN=${lib.escapeShellArg (lib.getExe pkgs.master.unfree.codex)}
    exec ${sessionPrefix}${cfg.finalPackage}/bin/graphide-codex "$@"
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
  # GUI services may launch agents without going through the shell wrappers.
  home.sessionVariables = lib.mkIf cfg.enable {
    TMPDIR = if storage.enable then "${storage.bulkPath}/tmp"
      else "${config.home.homeDirectory}/.cache/tmp-overflow/tmp";
  };
  # Existing desktop sessions have already sourced Home Manager's guarded environment.
  programs.zsh.envExtra = lib.mkIf cfg.enable ''
    ${lib.optionalString storage.enable ''
      if [[ -n "''${ZSH_EXECUTION_STRING:-}" && -z "''${AGENT_STORAGE_COMMAND:-}" ]] \
          && { [[ -n "''${AGENT_STORAGE_SESSION:-}" ]] || ${storageCommand} is-agent; }; then
        _agent_storage_argv=("''${(@0)$(</proc/$$/cmdline)}")
        _agent_storage_argv[-1]=()
        exec ${storageCommand} command -- ${pkgs.zsh}/bin/zsh \
          "''${_agent_storage_argv[@]:1}"
      fi
    ''}
    export TMPDIR="''${TMPDIR:-${if storage.enable then "${storage.bulkPath}/tmp" else "${config.home.homeDirectory}/.cache/tmp-overflow/tmp"}}"
  '';
  xdg.configFile."environment.d/30-agent-tmp.conf" = lib.mkIf cfg.enable {
    text = "TMPDIR=${if storage.enable then "${storage.bulkPath}/tmp" else "${config.home.homeDirectory}/.cache/tmp-overflow/tmp"}\n";
  };
  home.activation.agentTemporaryDirectory = lib.mkIf cfg.enable
    (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${pkgs.coreutils}/bin/install -d -m 0700 "$HOME/.cache/tmp-overflow/tmp"
    '');
}
