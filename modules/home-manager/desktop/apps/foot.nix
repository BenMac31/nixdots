{ lib, config, ... }:
{
  programs.foot = lib.mkIf config.programs.foot.enable {
    server.enable = true;
    settings = {
      main = {
        font = if config.desktop.verdigris.enable then "JetBrains Mono:size=10" else "FiraCodeNerdFont-Regular:size=10";
        dpi-aware = true;
      };
      colors = with config.colorScheme.palette; {
        regular0 = "${base00}";
        regular1 = "${base08}";
        regular2 = "${base0B}";
        regular3 = "${base0A}";
        regular4 = "${base0D}";
        regular5 = "${base0E}";
        regular6 = "${base0C}";
        regular7 = "${base05}";
        bright0 = "${base03}";
        bright1 = "${base08}";
        bright2 = "${base0B}";
        bright3 = "${base0A}";
        bright4 = "${base0D}";
        bright5 = "${base0E}";
        bright6 = "${base0C}";
        bright7 = "${base07}";
        alpha = if config.desktop.verdigris.enable then 0.90 else 0.8;
        background = "${base00}";
        foreground = "${base05}";
        flash = "${base0A}";
        flash-alpha = 0.4;
      };
    };
  };
}
