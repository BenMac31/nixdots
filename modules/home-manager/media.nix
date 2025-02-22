{ lib, config, pkgs, ... }:
{
  options = {
    media = {
      enable = lib.mkEnableOption "Enable media";
    };
  };
  config = lib.mkIf config.media.enable {
    programs.mpv.enable = true;
    home.packages = with pkgs; [
      yt-dlp
      obs-studio
      audacity
      gimp
      mpc
      ncmpcpp
      inkscape
      pkgs.unfree.ytfzf
      pkgs.unfree.ffmpeg-full
      pkgs.imagemagick
    ];
    services.flatpak.packages = [
      "org.qbittorrent.qBittorrent"
    ];
  };
}
