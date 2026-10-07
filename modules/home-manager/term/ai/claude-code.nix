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
        description = "Effort every new session starts at. The account wrapper passes it as --settings, which outranks the per-model default /effort saves to settings.json, so /effort only changes the session it runs in.";
      };
      bypassPermissions = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Start every session in bypassPermissions mode, the settings form of --dangerously-skip-permissions, passed through the account wrapper's --settings so subcommands parse unchanged.";
      };
    };
  };

  config = lib.mkIf config.ai.claude.enable {
    programs.claude-code = {
      enable = true;
      inherit (config.ai.claude) package;
    };
  };
}
