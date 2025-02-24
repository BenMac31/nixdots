{ config, lib, pkgs, inputs, osConfig, ... }:

{
  imports = [
    ../../modules/home-manager
  ];
  programs.home-manager.enable = true;
  home.username = "greencheetah";
  home.homeDirectory = "/home/greencheetah";
  sync.enable = true;
  gaming.enable = true;
  programming.enable = true;
  ai.enable = true;

  home.packages = [
    # pkgs.unfree.android-studio
    # pkgs.mullvad-vpn
    pkgs.nix-output-monitor
    pkgs.fractal
  ];


  programs = {
    password-store.enable = true;
    rbw.enable = true;
  };
  systemd.user.sessionVariables.SSH_AUTH_SOCK = "/run/user/1000/keyring/ssh"; # Makes ssh-agent work
  home.stateVersion = "23.11"; # Do not change
}
