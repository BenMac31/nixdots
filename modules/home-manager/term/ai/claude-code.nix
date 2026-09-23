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
    };
  };

  config = lib.mkIf config.ai.claude.enable {
    programs.claude-code = {
      enable = true;
      inherit (config.ai.claude) package;
    };
  };
}
