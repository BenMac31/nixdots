{ config, lib, pkgs, inputs, ... }:

let
  upkgs = pkgs.unstable;
in
{
  imports =
    [
      ../../modules/nixos
      ./hardware-configuration.nix
    ];
  networking.hostName = "nixBlade";
  head = {
    enable = true;
    gaming = true;
  };
  programs = {
    hyprland.enable = true;
    adb.enable = true;
    nix-ld.enable = true;
    nix-ld.libraries = with pkgs; [

      # Add any missing dynamic libraries for unpackaged programs

      # here, NOT in environment.systemPackages

    ];
    kdeconnect.enable = true;
    noisetorch.enable = true;
  };

  time.timeZone = "America/New_York";
  services = {
    flatpak.enable = true;
    mullvad-vpn.enable = true;

    printing.enable = true;
    fwupd.enable = true;
    fprintd.enable = true;
    thermald.enable = true;

    xserver = {
      enable = true;
      desktopManager.gnome.enable = true;
    };
  };
  environment.systemPackages = with pkgs; [
    libusb1
    powertop
    numworks-udev-rules
  ];

  users.users.greencheetah = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = [ "adbusers" "docker" "wheel" "uinput" "input" "video" ]; # Enable ‘sudo’ for the user.
  };
  boot.extraModulePackages = with config.boot.kernelPackages; [
    v4l2loopback
  ];

  home-manager = {
    users."greencheetah" = import ./home.nix;
  };

  nix.package = pkgs.lix;

  system.stateVersion = "23.11"; # DO NOT CHANGE
}
