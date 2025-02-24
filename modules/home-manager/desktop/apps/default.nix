{ config, lib, pkgs, iputs, osConfig, ... }:
{
  imports = [
    ./firefox.nix
    ./foot.nix
    ./kitty.nix
    ./mpv.nix
    ./zathura.nix
  ];
  home.packages = with pkgs; [
    brave
    pkgs.bitwarden
    (lib.mkIf osConfig.services.pipewire.enable pkgs.helvum)
    (lib.mkIf osConfig.services.pipewire.pulse.enable pkgs.pavucontrol)
  ];
}
