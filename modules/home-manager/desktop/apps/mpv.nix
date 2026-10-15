{ config, lib, pkgs, inputs, ... }:
{
  config = lib.mkIf config.programs.mpv.enable {
    xdg.configFile."mpv/scripts/speed-breakpoints.lua".source =
      ./mpv-scripts/speed-breakpoints.lua;

    programs.mpv.config = {
      # Software decode cannot keep up with speed-breakpoints' big speed swings
      # (45x on 1080p h264): frames drop, A/V desyncs, and the speed looks unchanged.
      hwdec = "auto-safe";
    };
  };
}
