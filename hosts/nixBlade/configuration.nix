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
    inputs.home-manager.nixosModules.default
      ./hardware-configuration.nix
      ../../modules/nixos/gnome.nix
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
      # udev.extraRules = # Numworks Udev
      #   ''
      #   SUBSYSTEM=="usb", ATTR{idVendor}=="0483", ATTR{idProduct}=="a291", TAG+="uaccess"
      #   SUBSYSTEM=="usb", ATTR{idVendor}=="0483", ATTR{idProduct}=="df11", TAG+="uaccess"
      #   SUBSYSTEM=="usb", ATTR{idVendor}=="483", ATTR{idProduct}=="a291", TAG+="uaccess"
      #   SUBSYSTEM=="usb", ATTR{idVendor}=="483", ATTR{idProduct}=="df11", TAG+="uaccess"
      #   '';
      fwupd.enable = true; # Firmware updater
    };
  time.timeZone = "America/New_York";

  i18n.supportedLocales = ["all"]; # Support all languages

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
    pkgs.noto-fonts-cjk
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
    numworks-udev-rules
  ];

  system.stateVersion = "23.11"; # DO NOT CHANGE

    nix.settings.experimental-features = [ "nix-command" "flakes" ];

  users.users.greencheetah = {
    isNormalUser = true;
    shell= pkgs.zsh;
    extraGroups = [ "docker" "openrazer" "wheel" "uinput" "input" "video" ]; # Enable ‘sudo’ for the user.
  };
  hardware.uinput.enable = true;
  hardware.openrazer.enable = true;
  virtualisation = {
    waydroid.enable = lib.mkDefault true;
    docker = {
      enable = lib.mkDefault true;
      enableNvidia = true;
    };
  };
  programs = {
    noisetorch.enable = true;
    gamemode.enable = true;
    gamescope.enable = true;
    hyprland.enable = true;
    gnupg.agent.enable = true;
    zsh.enable = true;
    kdeconnect.enable = true;
    nix-ld.enable = true;
  };
  fileSystems."/home/greencheetah/Desktop" = {
    device = "/home/greencheetah/.local/share/applications";
    options = [ "bind" ];
  };
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };
  home-manager = {
# also pass inputs to home-manager modules
    extraSpecialArgs = {inherit inputs; inherit pkgs;};
    users."greencheetah" = import ./home.nix;
  };
}
