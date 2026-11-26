{ config, lib, pkgs, inputs, osConfig, ... }:
{
  imports = [
    ./aichat.nix
    ./aiclip.nix
    ./claude-code.nix
    ./claude-fast.nix
    ./localrun.nix
    ./reason.nix
    ./t3code.nix
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
      reason.enable = lib.mkDefault true;
      t3code.enable = lib.mkDefault true;
    };
    home.packages = [ pkgs.unstable.unfree.cursor-cli ];
  };
}
