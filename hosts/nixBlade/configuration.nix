{ config, lib, pkgs, inputs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
    ./hardware-configuration.nix
      inputs.home-manager.nixosModules.default
      ../../modules/nixos/gnome.nix
      ../../modules/nixos/japanese.nix
      ../../modules/nixos/nvidia.nix
      ../../modules/nixos/hyprland.nix
    ];

# Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "nixBlade";
  networking.networkmanager.enable = true;  # Easiest to use and most distros use this by default.

# Set your time zone.
# time.timeZone = "Europe/Amsterdam";
    services.localtimed.enable = true;

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

# Enable CUPS to print documents.
  services.printing.enable = true;

# Enable sound.
  sound.enable = true;
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
# If you want to use JACK applications, uncomment this
#jack.enable = true;
  };

# List packages installed in system profile. To search, run:
# $ nix search wget
  environment.systemPackages = with pkgs; [
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
      wget
      home-manager
      pinentry
      lshw
      lsof
      powertop
      git
  ];

# Some programs need SUID wrappers, can be configured further or are
# started in user sessions.
# programs.mtr.enable = true;
# programs.gnupg.agent = {
#   enable = true;
#   enableSSHSupport = true;
# };

# List services that you want to enable:

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
    extraGroups = [ "wheel" ]; # Enable ‘sudo’ for the user.
  };
  home-manager = {
# also pass inputs to home-manager modules
    extraSpecialArgs = {inherit inputs;};
    users = {
      "greencheetah" = import ./home.nix;
    };
  };
  services.flatpak.enable = true;
  programs.gnupg.agent = {                                                      
    enable = true;
  };
}
