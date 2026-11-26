{ lib, config, pkgs, inputs, ... }:
{
  options = {
    ai.claude = {
      enable = lib.mkEnableOption "Enable Claude Code";
      agentTeams.enable = lib.mkEnableOption "Claude Code experimental agent teams";
      package = lib.mkOption {
        type = lib.types.package;
        default = inputs.claude-code.packages.${pkgs.stdenv.hostPlatform.system}.default;
        defaultText = lib.literalExpression "inputs.claude-code.packages.\${pkgs.stdenv.hostPlatform.system}.default";
        description = "Claude Code package from github:sadjow/claude-code-nix.";
      };
      effort = lib.mkOption {
        type = lib.types.nullOr (lib.types.enum [ "low" "medium" "high" "xhigh" ]);
        default = "high";
        description = "Effort every new session starts at. The account wrapper passes it as --effort, overriding saved per-model defaults. An explicit --effort from the caller or /effort during the session can change it; null leaves the default to Claude Code.";
      };
      bypassPermissions = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Start every session in bypassPermissions mode, the settings form of --dangerously-skip-permissions, passed through the account wrapper's --settings so subcommands parse unchanged.";
      };
      autoCompactWindow = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.positive;
        default = 300000;
        description = "Context size in tokens at which a session compacts. Every request re-sends the whole context, so this caps the cost of a long session. Activation writes it into ~/.claude/settings.json, which each Graphide account profile copies at launch; null leaves the file alone.";
      };
      maxConcurrentSubagents = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.positive;
        default = 40;
        description = "Subagents one session may run at once. The account wrapper exports it as CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS unless the caller set it; null leaves Claude Code's default of 20.";
      };
    };
  };

  config = lib.mkIf config.ai.claude.enable {
    ai.claude.agentTeams.enable = lib.mkDefault true;

    programs.claude-code = {
      enable = true;
      inherit (config.ai.claude) package;
    };

    # Merged into the file rather than managed: Claude, grug and Orca all
    # rewrite settings.json, so a store link would break them.
    home.activation.claudeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.diffutils pkgs.jq ]}:$PATH
      settings="$HOME/.claude/settings.json"
      if [ -z "''${DRY_RUN:-}" ]; then
        mkdir -p "$HOME/.claude"
        [ -s "$settings" ] || echo '{}' >"$settings"
        tmp=$(mktemp "$settings.XXXXXX")
        if jq --arg teams ${if config.ai.claude.agentTeams.enable then "1" else "0"} \
          --argjson w ${builtins.toJSON config.ai.claude.autoCompactWindow} \
          '.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = $teams | if $w == null then . else .autoCompactWindow = $w end' \
          "$settings" >"$tmp"; then
          if cmp -s "$tmp" "$settings"; then rm -f "$tmp"; else mv "$tmp" "$settings"; fi
        else
          rm -f "$tmp"
          warnEcho "could not update Claude Code settings in $settings"
        fi
      fi
    '';
  };
}
