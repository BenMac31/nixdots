{ config, lib, pkgs, inputs, ... }:

let
  upkgs = pkgs.unstable;
in
{
  imports =
    [
      ../../modules/nixos
      ./hardware-configuration.nix
      ./agent-throttle.nix
      ./remote-builds.nix
      ./nix-store-hygiene.nix
    ];
  networking.hostName = "nixWorks";
  custom.flakeAttr = "nixWorks";
  custom.tailscale.enable = true;
  head = {
    enable = true;
    gaming = true;
  };
  programs = {
    hyprland.enable = true;
    nix-ld.enable = true;
    nix-ld.libraries = with pkgs; [

      # Add any missing dynamic libraries for unpackaged programs

      # here, NOT in environment.systemPackages

    ];
    kdeconnect.enable = true;
    noisetorch.enable = true;
  };

  fonts.packages = with pkgs; [
    nerd-fonts.fira-code
    nerd-fonts.droid-sans-mono
    nerd-fonts.jetbrains-mono
    noto-fonts-cjk-sans
    source-han-sans
    source-han-mono
    source-han-serif
    source-han-sans-vf-ttf
    source-han-sans-vf-otf

  ];

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [ intel-media-driver ];
  };
  environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD";

  time.timeZone = lib.mkDefault "America/New_York";
  services = {
    displayManager.defaultSession = "hyprland";
    flatpak.enable = true;
    mullvad-vpn.enable = true;

    printing.enable = true;
    fwupd.enable = true;
    fprintd.enable = true;
    thermald.enable = true;

    xserver.enable = true;
    desktopManager.gnome.enable = true;
    logind = {
      lidSwitch = "hibernate";
      lidSwitchExternalPower = "hibernate";
    };
    # UPower's stock policy acts at 2% with a hybrid sleep. The Framework EC
    # cuts power before 2% under load, so the box died instead of sleeping.
    # Action at 5% leaves time to write a multi-GB image; UPower requires
    # low > critical > action.
    #
    # criticalPowerAction alone does not get you a hibernate: upower deems
    # Hibernate "risky" and silently substitutes HybridSleep unless the flag
    # below is set. That substitution killed the box on 2026-09-08 — hybrid
    # sleep wrote the image and then kept drawing power in S3, the EC cut out
    # 28s in, and the next boot found no signature (PM: Image not found, -22).
    # A real hibernate powers off as soon as the image is down.
    upower = {
      enable = true;
      allowRiskyCriticalPowerAction = true;
      percentageLow = 20;
      percentageCritical = 10;
      percentageAction = 5;
      criticalPowerAction = "Hibernate";
    };
  };
  environment.systemPackages = with pkgs; [
    android-tools
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
  boot.initrd.systemd.enable = true;

  home-manager = {
    users."greencheetah" = import ./home.nix;
  };
  services.openssh = {
    enable = true;
    ports = [ 22 ];
    settings = {
      PasswordAuthentication = true;
      UseDns = true;
      X11Forwarding = false;
      PermitRootLogin = "prohibit-password"; # "yes", "without-password", "prohibit-password", "forced-commands-only", "no"
    };
  };

  nix.package = pkgs.lix;

  system.stateVersion = "23.11"; # DO NOT CHANGE
  services.udev.extraRules = ''
  SUBSYSTEM=="usb", ATTR{idVendor}=="0483", MODE="0666"
'';
  networking.extraHosts = ''
  127.0.0.1 host.docker.internal
'';
}
