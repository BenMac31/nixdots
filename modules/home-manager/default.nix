{ config, lib, pkgs, inputs, osConfig, ... }:
{
  imports = [
    ./desktop
    ./term
    ./rice.nix
    inputs.nix-flatpak.homeManagerModules.nix-flatpak
  ];
  options = {
    media = {
      enable = lib.mkEnableOption "Enable media";
    };
  };
  config = {
    services.flatpak.update.onActivation = true;
  };
}
