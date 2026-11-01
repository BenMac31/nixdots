{ lib, config, pkgs, inputs, ... }:
{
  options = {
    ai.claude = {
      enable = lib.mkEnableOption "Enable Claude Code";
      package = lib.mkOption {
        type = lib.types.package;
        default = inputs.claude-code.packages.${pkgs.stdenv.hostPlatform.system}.default;
        defaultText = lib.literalExpression "inputs.claude-code.packages.\${pkgs.stdenv.hostPlatform.system}.default";
        description = "Claude Code package from github:sadjow/claude-code-nix.";
      };
      effort = lib.mkOption {
        type = lib.types.nullOr (lib.types.enum [ "low" "medium" "high" "xhigh" ]);
        default = "high";
        description = "Effort every new session starts at. The account wrapper passes it as --settings; a per-model default /effort saves to the profile settings.json still wins for that model, and account handoffs copy it to the new profile.";
      };
      bypassPermissions = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Start every session in bypassPermissions mode, the settings form of --dangerously-skip-permissions, passed through the account wrapper's --settings so subcommands parse unchanged.";
      };
      autoCompactWindow = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.positive;
        default = 400000;
        description = "Context size in tokens at which a session compacts. Every request re-sends the whole context, so this caps the cost of a long session. Activation writes it into ~/.claude/settings.json, which each Graphide account profile copies at launch; null leaves the file alone.";
      };
    };
  };

  config = lib.mkIf config.ai.claude.enable {
    programs.claude-code = {
      enable = true;
      inherit (config.ai.claude) package;
    };

    # Merged into the file rather than managed: Claude, grug and Orca all
    # rewrite settings.json, so a store link would break them.
    home.activation.claudeAutoCompactWindow = lib.mkIf (config.ai.claude.autoCompactWindow != null)
      (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.diffutils pkgs.jq ]}:$PATH
        settings="$HOME/.claude/settings.json"
        if [ -z "''${DRY_RUN:-}" ]; then
          mkdir -p "$HOME/.claude"
          [ -s "$settings" ] || echo '{}' >"$settings"
          tmp=$(mktemp "$settings.XXXXXX")
          if jq --argjson w ${toString config.ai.claude.autoCompactWindow} '.autoCompactWindow = $w' "$settings" >"$tmp"; then
            if cmp -s "$tmp" "$settings"; then rm -f "$tmp"; else mv "$tmp" "$settings"; fi
          else
            rm -f "$tmp"
            warnEcho "could not set autoCompactWindow in $settings"
          fi
        fi
      '');
  };
}
