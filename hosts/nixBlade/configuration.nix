{ config, lib, pkgs, inputs, ... }:

let
  upkgs = pkgs.unstable;
in
{
  imports =
    [
      inputs.home-manager.nixosModules.default
      ./hardware-configuration.nix
      ../../modules/nixos/gnome.nix
      ../../modules/nixos/laptop.nix
      ../../modules/nixos/plymouth.nix
    ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "nixBlade";
  networking.networkmanager.enable = true;

  time.timeZone = "America/New_York";
  services = {
    displayManager.sddm = {
      enable = true;
      wayland.enable = true;
      theme = "sugar-dark";
      extraPackages = [ pkgs.sddm-sugar-dark ];
    };
    flatpak = {
      enable = true;
    };
    ratbagd.enable = true;
    # automatic-timezoned.enable = true; # Re-Enable once https://github.com/NixOS/nixpkgs/issues/321121 closes
    printing = {
      enable = true;
      drivers = [
        pkgs.gutenprint
      ];
    };
    avahi = {
      enable = true;
      nssmdns4 = true;
      openFirewall = true;
    };
    mullvad-vpn.enable = true;
    fwupd.enable = true; # Firmware updater
    fprintd = {
      enable = true;
    };
  };

  i18n.supportedLocales = [ "all" ]; # Support all languages

  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  environment.systemPackages = with pkgs; [
    #
    vim
    noto-fonts-cjk-sans
    source-han-sans
    source-han-mono
    source-han-serif
    source-han-sans-vf-ttf
    source-han-sans-vf-otf
    elegant-sddm
    pciutils
    htop
    wget
    home-manager
    libusb1
    pinentry
    lshw
    lsof
    powertop
    git
    nix-index
    numworks-udev-rules
  ];

  system.stateVersion = "23.11"; # DO NOT CHANGE

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  users.users.greencheetah = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = [ "docker" "wheel" "uinput" "input" "video" ]; # Enable ‘sudo’ for the user.
  };
  hardware.uinput.enable = true;
  programs = {
    gamemode.enable = true;
    gamescope.enable = true;
    hyprland.enable = true;
    gnupg.agent.enable = true;
    zsh.enable = true;
    nix-ld.enable = true;
  };
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };
  home-manager = {
    # also pass inputs to home-manager modules
    extraSpecialArgs = { inherit inputs; inherit pkgs; };
    users."greencheetah" = import ./home.nix;
  };
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 5900 36149 ];
    allowedUDPPorts = [ 5900 36149 ];
    allowedTCPPortRanges = [
      { from = 1714; to = 1764; } # KDE Connect
    ];
    allowedUDPPortRanges = [
      { from = 1714; to = 1764; } # KDE Connect
    ];
  };
  services.nginx = {
    enable = true;
    additionalModules = [ pkgs.nginxModules.rtmp ];
    appendConfig = ''
        rtmp {
              server {
                      listen 1935;
                      chunk_size 4096;

                      application feed {
                              live on;
                              record off;
                      }
              }
      }
    '';
  };
   fonts.fontDir.enable = true;
#   fileSystems."/usr/share/fonts" = {
#   device = "/run/curren-system/sw/share/X11/fonts";
#   fsType = "btrfs";
# };
}
