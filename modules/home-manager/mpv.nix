{config, lib, pkgs, inputs, ...}:
{
  programs.mpv = {
    enable = true;
    scripts = with pkgs.mpvScripts; [
      sponsorblock
      mpris
      thumbnail
      quality-menu
      reload
      webtorrent-mpv-hook
    ];
    config = {
      osc = "no";
      slang = "en";
      alang = "jp,en";
      profile = lib.mkDefault "high-quality";
      force-window="immediate";
    };
    scriptOpts = {
      sponsorblock = {
        categories="music_offtopic,intro,outro,interaction,selfpromo";
        skip_categories="music_offtopic,sponsor,selfpromo,outro";
      };
    };
  };
}
