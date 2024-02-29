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
      # config.boot.kernel.kernelPackages.nvidiaPackages.beta
    ];
  imports =
    [ # Include the results of the hardware scan.
    ./hardware-configuration.nix
      # inputs.home-manager.nixosModules.default
      ../../modules/nixos/gnome.nix
      ../../modules/nixos/japanese.nix
      ../../modules/nixos/nvidia.nix
      ../../modules/nixos/onTheGo.nix
      ../../modules/nixos/laptop.nix
      ../../modules/nixos/plymouth.nix
      # ../../modules/nixos/hyprland.nix
    ];

# Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "nixBlade";
  networking.networkmanager.enable = true;  # Easiest to use and most distros use this by default.

    services = {
      flatpak = {
        enable = true;
      };
      localtimed.enable = true;
      printing.enable = true;
      mullvad-vpn.enable = true;
    };
# Set your time zone.
  time.timeZone = "America/New_York";

# Configure network proxy if necessary
# networking.proxy.default = "http://user:password@proxy:port/";
# networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";
# Select internationalisation properties.
# i18n.defaultLocale = "en_US.UTF-8";
# console = {
#   font = "Lat2-Terminus16";
#   keyMap = "us";
#   useXkbConfig = true; # use xkb.options in tty.
# };

  sound.enable = true;
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
#jack.enable = true;
  };

  environment.systemPackages = with pkgs; [ #
    vim
    htop
    wget
    home-manager
    pinentry
    lshw
    lsof
    powertop
    (unstable-unfree.ollama.override {
     enableCuda = true;
     })
    git
    nix-index
    openrazer-daemon
  ];

# Some programs need SUID wrappers, can be configured further or are
# started in user sessions.
# programs.mtr.enable = true;
# programs.gnupg.agent = {
#   enable = true;
#   enableSSHSupport = true;
# };

# Open ports in the firewall.
# networking.firewall.allowedTCPPorts = [ ... ];
# networking.firewall.allowedUDPPorts = [ ... ];
# Or disable the firewall altogether.
# networking.firewall.enable = false;

  system.stateVersion = "23.11"; # DO NOT CHANGE

    nix.settings.experimental-features = [ "nix-command" "flakes" ];
  programs.zsh.enable = true;

  users.users.greencheetah = {
    isNormalUser = true;
    shell= pkgs.zsh;
    extraGroups = [ "openrazer" "wheel" "uinput" "input" "video" ]; # Enable ‘sudo’ for the user.
  };
#   home-manager = {
# # also pass inputs to home-manager modules
#     extraSpecialArgs = {inherit inputs; inherit upkgs;};
#     users."greencheetah" = import ./home.nix;
#   };
  programs.gnupg.agent = {                                                      
    enable = true;
  };
  hardware.uinput.enable = true;
  hardware.openrazer.enable = true;
  # hardware.openrazer.users = [ "greencheetah" ];
  programs.hyprland.enable = true;
}
