{ config, lib, pkgs, inputs, osConfig, ... }:

{
  imports = [
    ../../modules/home-manager
  ];
  programs.home-manager.enable = true;
  home.username = "carol";
  home.homeDirectory = "/home/carol";

  home.stateVersion = "23.11"; # Do not change
}
