{ config, lib, pkgs, inputs, ... }:
let
  # The monolith's source tree drawn as a sea chart, redrawn with each bump.
  # 3840x2400 covers a 4K screen without upscaling.
  chart = pkgs.runCommand "approaches-to-the-monolith.png" {
    nativeBuildInputs = [ (pkgs.python3.withPackages (ps: with ps; [ numpy scipy pillow pycairo scikit-image ])) ];
    palette = builtins.toJSON config.programs.graphide-shell.palette;
    passAsFile = [ "palette" ];
  } ''
    python3 ${./monolith-chart.py} --out "$out" --width 3840 --height 2400 \
      --src ${inputs.graphide-tools} \
      --rev ${builtins.substring 0 10 (inputs.graphide-tools.rev or "unknown")} \
      --palette "$palettePath" \
      --font ${pkgs.eb-garamond}/share/fonts/opentype/EBGaramond12-Italic.otf \
      --font ${pkgs.eb-garamond}/share/fonts/opentype/EBGaramond12-Regular.otf \
      --font ${pkgs.eb-garamond}/share/fonts/opentype/EBGaramondSC12-Regular.otf
  '';
in
{
  imports = [ inputs.graphide-tools.homeManagerModules.quickshell ];
  config = lib.mkIf config.programs.graphide-shell.enable {
    programs.graphide-shell = {
      widgetMonitor = "eDP-1";
      terminalPackage = pkgs.kitty;
      pomodoro = pkgs.waybar-pomodoro;
      rbwPinentry = true;
      todoCommand = [ "nvim" "${config.home.homeDirectory}/Projects/graphide/docs/TODO.md" ];
      commitsRepo = "${config.home.homeDirectory}/Projects/graphide/graphide";
      hyprland = { layerRules = true; decoration = true; };
      # No panel opens from pointer position, by choice. Keep it that way.
      hoverReveal = false;
      launcherSideCards = false;
      wallpaper = chart;
      reminders = [ { text = "Show BF"; } ];
    };
    # Bridge must keep running after `connect.py proton` pairs it, or IMAP sync
    # dies the moment that CLI session exits.
    services.protonmail-bridge.enable = true;
  };
}
