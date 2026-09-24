{ lib, config, pkgs, ... }:
{
  options = {
    ai.claude = {
      enable = lib.mkEnableOption "Enable Claude Code";
      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.master.unfree.claude-code;
        defaultText = lib.literalExpression "pkgs.master.unfree.claude-code";
        description = "Which claude-code build to install; unfree, so it tracks the master overlay.";
      };
      effort = lib.mkOption {
        type = lib.types.nullOr (lib.types.enum [ "low" "medium" "high" "xhigh" ]);
        default = "high";
        description = "Effort every new session starts at. The account wrapper passes it as --settings, which outranks the per-model default /effort saves to settings.json, so /effort only changes the session it runs in.";
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
