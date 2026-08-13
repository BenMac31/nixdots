{ config, lib, pkgs, inputs, ... }:
{
  config = lib.mkIf config.programs.mpv.enable {
    xdg.configFile."mpv/scripts/speed-breakpoints.lua".source =
      ./mpv-scripts/speed-breakpoints.lua;

    programs.mpv.config = {
      # Software-only decode can't keep up with the large speed swings
      # speed-breakpoints.lua produces (e.g. 45x+ on 1080p h264), causing
      # dropped frames and A/V desync that make applied speed changes look
      # like they didn't take effect. mpv's own desync warning suggests
      # this exact fix.
      hwdec = "auto-safe";
    };

    # programs.mpv = {
    #   scripts = with pkgs.mpvScripts; [
    #     sponsorblock
    #     mpris
    #     thumbfast
    #     # quality-menu
    #     reload
    #     mpvacious
    #     mpv-cheatsheet
    #     webtorrent-mpv-hook
    #     autocrop
    #     uosc
    #     pkgs.unfree.mpvScripts.youtube-upnext
    #   ];
    #   bindings = {
    #     "Alt+," = "cycle-values play-dir - +";
    #     "F" = "script-binding quality_menu/video_formats_toggle";
    #     "Alt+f" = "script-binding quality_menu/audio_formats_toggle";
    #   };
    #   config = {
    #     osc = false;
    #     slang = "en";
    #     osd-bar = false;
    #     border = false;
    #     alang = "jp,en";
    #     profile = lib.mkDefault "high-quality";
    #   };
    #
    #   scriptOpts = {
    #     sponsorblock = {
    #       categories = "music_offtopic,intro,outro,interaction,selfpromo";
    #       skip_categories = "music_offtopic,sponsor,selfpromo,outro";
    #     };
    #   };
    # };
    # xdg.mimeApps.defaultApplications = {
    #   "video/x-matroska" = "mpv.desktop";
    #   "video/mp4" = "mpv.desktop";
    #   "video/h264" = "mpv.desktop";
    # };
  };
}
