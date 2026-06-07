{ config, lib, pkgs, inputs, ... }:

let
  upkgs = pkgs.unstable;
in
{
  imports =
    [
      ./hardware-configuration.nix
      ../../modules/nixos
    ];
  services.home-assistant.enable = true;
  services.mullvad-vpn.enable = true;
  serv = {
    enable = true;
    media.enable = true;
  };
  services.openssh = {
    enable = true;
    ports = [ 22 ];
    settings = {
      PasswordAuthentication = true;
      AllowUsers = [ "ghastly" ];
      UseDns = true;
      X11Forwarding = false;
    };
  };

  networking.hostName = "nixos";
  custom.flakeAttr = "phantomServ";

  time.timeZone = "America/New_York";

  users.users.ghastly = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = [ "wheel" ];
  };

  home-manager = {
    users."ghastly" = import ./home.nix;
  };
  system.stateVersion = "23.11"; # DO NOT CHANGE
}
