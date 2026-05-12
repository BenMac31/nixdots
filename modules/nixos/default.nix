{ config, lib, pkgs, inputs, ... }:

let
  upkgs = pkgs.unstable;
in
{
  imports =
    [
      inputs.home-manager.nixosModules.default
      ./head
      ./serv
    ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.networkmanager.enable = true;

  services = {
    # automatic-timezoned.enable = true; # Re-Enable once https://github.com/NixOS/nixpkgs/issues/321121 closes
    printing = {
      drivers = [
        pkgs.gutenprint
      ];
    };
    # avahi = {
    #   # Networking stuff
    #   enable = true;
    #   nssmdns4 = true;
    # };
  };

  i18n.supportedLocales = [ "all" ]; # Support all languages

  security.rtkit.enable = true;
  environment.systemPackages = with pkgs; [
    neovim
    pciutils
    htop
    wget
    home-manager
    pinentry-curses
    git
    git-crypt
    unzip
    ripgrep
    fzf
  ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  programs = {
    gnupg.agent.enable = true;
    zsh.enable = true;
  };
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };
  home-manager = {
    # also pass inputs to home-manager modules
    extraSpecialArgs = { inherit inputs; inherit pkgs; };
  };
  networking.firewall = rec {
    enable = lib.mkDefault false;
    allowedTCPPortRanges = [
      { from = 22; to = 22; }
      { from = 1714; to = 1764; }
    ];
    allowedUDPPortRanges = allowedTCPPortRanges;
  };
  fonts.fontDir.enable = true;
}
