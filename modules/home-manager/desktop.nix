{ config, lib, pkgs, iputs, ... }:
{
  imports = [
    ./firefox.nix
    ./gnome.nix
    ./hyprland.nix
    ./foot.nix
    ./kitty.nix
    ./mpv.nix
    ./gaming.nix
    ./japanese.nix
    ./zathura.nix
    ./rice.nix
    ./comms.nix
    ./sync.nix
    ./office.nix
    ./media.nix
  ];
  comms.enable = lib.mkDefault true;
  office.enable = lib.mkDefault true;
  media.enable = lib.mkDefault true;
  home.packages = with pkgs; [
    brave
    brightnessctl
    pkgs.bitwarden
    pkgs.pavucontrol
    pkgs.helvum
    pkgs.wl-clipboard
  ];
  services.flatpak.packages = [
    "com.github.tchx84.Flatseal"
  ];
}
