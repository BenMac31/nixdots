{ config, lib, pkgs, inputs, osConfig, ... }:
{
  imports = [
    ./aichat.nix
    ./aiclip.nix
    ./claude-code.nix
    ./localrun.nix
  ];
  options = {
    ai = {
      enable = lib.mkEnableOption "Enable AI";
    };
  };
  config = lib.mkIf config.ai.enable {
    ai = {
      aichat.enable = lib.mkDefault true;
      aiclip.enable = lib.mkDefault true;
      claude.enable = lib.mkDefault true;
    };
  };
}
