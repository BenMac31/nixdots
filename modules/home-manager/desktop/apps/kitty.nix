{ lib, config, ... }:
{
  home.sessionVariables = lib.mkIf config.programs.kitty.enable { TERMINAL = "kitty"; };
  programs.kitty = lib.mkIf config.programs.kitty.enable {
    settings = with config.colorScheme.palette; {
      font_family = if config.desktop.verdigris.enable then "JetBrains Mono" else "FiraCodeNerdFont-Regular";
      enable_audio_bell = true;
      font_size = 10;
      color0 = "#${base00}";
      color1 = "#${base08}";
      color2 = "#${base0B}";
      color3 = "#${base0A}";
      color4 = "#${base0D}";
      color5 = "#${base0E}";
      color6 = "#${base0C}";
      color7 = "#${base05}";
      color8 = "#${base03}";
      color9 = "#${base08}";
      color10 = "#${base0B}";
      color11 = "#${base0A}";
      color12 = "#${base0D}";
      color13 = "#${base0E}";
      color14 = "#${base0C}";
      color15 = "#${base07}";
      background = "#${base00}";
      foreground = "#${base05}";
      background_opacity = if config.desktop.verdigris.enable then 0.90 else 0.8;
    };
  };
}
