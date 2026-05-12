{ config, lib, pkgs, inputs, osConfig, ... }:

{
  imports = [
    ../../modules/home-manager
  ];

  # IDK, but it makes it work
  dconf.enable = lib.mkForce false;

  programs.home-manager.enable = true;
  home.username = "carol";
  home.homeDirectory = "/home/carol";

  home.stateVersion = "23.11"; # Do not change
}
