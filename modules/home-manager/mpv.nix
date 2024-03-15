{config, pkgs, inputs, ...}:
{
  programs.mpv = {
    enable = true;
    scripts = with pkgs.mpvScripts; [
      sponsorblock
      mpris
      thumbnail
      quality-menu
      reload
    ];
    config = {
      osc = "no";
    };
    scriptOpts = {
      sponsorblock = {
        categories="music_offtopic";
        skip_categories="music_offtopic";
      };
    };
  };
}
