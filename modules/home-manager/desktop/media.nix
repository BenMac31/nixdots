{ lib, config, pkgs, ... }:
{
  config = lib.mkIf (config.media.enable && config.desktop.enable) {
    home.packages = with pkgs; [
      obs-studio
      audacity
      gimp
      ncmpcpp
      inkscape
      sxiv
    ];
    services.flatpak.packages = [
      "org.qbittorrent.qBittorrent"
    ];
  };
}
