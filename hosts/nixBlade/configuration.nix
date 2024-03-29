{ config, lib, pkgs, inputs, ... }:

let
upkgs = pkgs.unstable;
in
{
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [
    "nvidia-x11"
      "nvidia-settings"
      "nvidia-persistenced"
      "cudatoolkit"
      "cudatoolkit-11.8.0"
      "cudatoolkit-12.2.2"
    ];
  imports =
    [
    ./hardware-configuration.nix
      ../../modules/nixos/gnome.nix
      ../../modules/nixos/japanese.nix
      ../../modules/nixos/nvidia.nix
      ../../modules/nixos/onTheGo.nix
      ../../modules/nixos/laptop.nix
      ../../modules/nixos/plymouth.nix
    ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "nixBlade";
  networking.networkmanager.enable = true;  # Easiest to use and most distros use this by default.

    services = {
      flatpak = {
        enable = true;
      };
      ratbagd.enable = true;
      automatic-timezoned.enable = true;
      printing.enable = true;
      mullvad-vpn.enable = true;
      udev.extraRules = # Numworks Udev
        ''
        SUBSYSTEM=="usb", ATTR{idVendor}=="0483", ATTR{idProduct}=="a291", TAG+="uaccess"
        SUBSYSTEM=="usb", ATTR{idVendor}=="0483", ATTR{idProduct}=="df11", TAG+="uaccess"
        '';
    };
  time.timeZone = "America/New_York";


  sound.enable = true;
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  environment.systemPackages = with pkgs; [ #
    vim
    pciutils
    htop
    wget
    home-manager
    pinentry
    lshw
    lsof
    powertop
    git
    nix-index
    openrazer-daemon
  ];

  system.stateVersion = "23.11"; # DO NOT CHANGE

    nix.settings.experimental-features = [ "nix-command" "flakes" ];
  programs.zsh.enable = true;

  users.users.greencheetah = {
    isNormalUser = true;
    shell= pkgs.zsh;
    extraGroups = [ "docker" "openrazer" "wheel" "uinput" "input" "video" ]; # Enable ‘sudo’ for the user.
  };
  programs.gnupg.agent = {                                                      
    enable = true;
  };
  hardware.uinput.enable = true;
  hardware.openrazer.enable = true;
  programs.hyprland.enable = true;
  virtualisation.docker = {
    enable = lib.mkDefault true;
    enableNvidia = true;
  };
  programs.gamemode.enable = true;
  fileSystems."/home/greencheetah/Desktop" = {
    device = "/home/greencheetah/.local/share/applications";
    options = [ "bind" ];
  };
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };
  programs.nix-ld.enable = true;
}
