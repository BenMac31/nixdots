{ config, lib, pkgs, inputs, ... }:
{
  imports = [
    ./gnome.nix
    ./hyprland.nix
    ./xdg.nix
  ];
}
