{ config, lib, pkgs, inputs, osConfig, ... }:
{
  imports = [
    ./apps
    ./env
    ./gaming.nix
    ./japanese.nix
    ./comms.nix
    ./sync.nix
    ./office.nix
    ./media.nix
  ];
  options = {
    desktop = {
      enable = lib.mkEnableOption "Enable desktop";
    };
  };
  config = {
    desktop.enable = true;
    comms.enable = lib.mkDefault true;
    office.enable = lib.mkDefault true;
    media.enable = lib.mkDefault true;
    services.flatpak.packages = [
      "com.github.tchx84.Flatseal"
    ];
    home.packages = with pkgs; [
      brightnessctl
      pkgs.wl-clipboard
    ];
  };
}
