{ config, lib, pkgs, ... }:
let
  cfg = config.desktop.verdigris;
  # The shell's colours, so apps match it, plus what the shell does not draw:
  # popovers, text on the accent, and the editor theme's syntax hues.
  c = config.programs.graphide-shell.palette // {
    dim = "#52616b"; light = "#dae1e6"; white = "#ffffff";
    popover = "#0d1720"; onAccent = "#04120f";
    orange = "#f78c6c"; green = "#c3e88d"; blue = "#8aaeff"; purple = "#c792ea";
  };
  gtkCss = with c; ''
    @define-color window_bg_color ${page};
    @define-color window_fg_color ${text};
    @define-color view_bg_color ${sunken};
    @define-color view_fg_color ${text};
    @define-color headerbar_bg_color ${raised};
    @define-color headerbar_fg_color ${text};
    @define-color sidebar_bg_color ${raised};
    @define-color sidebar_fg_color ${text};
    @define-color card_bg_color ${raised};
    @define-color card_fg_color ${text};
    @define-color popover_bg_color ${popover};
    @define-color popover_fg_color ${text};
    @define-color dialog_bg_color ${popover};
    @define-color dialog_fg_color ${text};
    @define-color accent_bg_color ${accent};
    @define-color accent_fg_color ${onAccent};
    @define-color accent_color ${bright};
    @define-color theme_bg_color ${page};
    @define-color theme_fg_color ${text};
    @define-color theme_base_color ${sunken};
    @define-color theme_text_color ${text};
    @define-color theme_selected_bg_color ${accent};
    @define-color theme_selected_fg_color ${onAccent};
    @define-color borders rgba(255,255,255,0.08);
    @define-color error_color ${error};
    @define-color warning_color ${warning};
    @define-color success_color ${good};
  '';
  # Qt palette roles in QPalette order (Qt5 and Qt6 share the first 21).
  qtColors = lib.concatStringsSep ", " (with c; [
    text raised secondary secondary sunken muted
    text white text sunken page sunken
    accent onAccent bright accentSoft raised "#000000"
    popover text muted accent
  ]);
in {
  options.desktop.verdigris.enable = lib.mkEnableOption "Graphide's Verdigris Ink application theme";
  config = lib.mkMerge [
    { desktop.verdigris.enable = lib.mkDefault config.desktop.enable; }
    (lib.mkIf cfg.enable {
      colorScheme = {
        slug = "verdigris-ink";
        name = "Verdigris Ink";
        author = "Graphide";
        palette = lib.mapAttrs (_: lib.removePrefix "#") (with c; {
          base00 = page; base01 = raised; base02 = secondary; base03 = dim;
          base04 = muted; base05 = text; base06 = light; base07 = white;
          base08 = error; base09 = orange; base0A = warning; base0B = green;
          base0C = accent; base0D = blue; base0E = purple; base0F = accentSoft;
        });
      };
      gtk = {
        theme = { package = pkgs.adw-gtk3; name = "adw-gtk3-dark"; };
        iconTheme = { package = pkgs.papirus-icon-theme; name = "Papirus-Dark"; };
        font = { name = "Inter"; size = 10; package = pkgs.inter; };
        gtk3.extraCss = gtkCss;
        gtk4.extraCss = gtkCss;
        gtk3.extraConfig.gtk-application-prefer-dark-theme = true;
      };
      qt = {
        platformTheme.name = "qtct";
        style.name = "Fusion";
        qt5ctSettings = {
          Appearance = { color_scheme_path = "${config.xdg.configHome}/qt5ct/colors/verdigris.conf"; custom_palette = true; icon_theme = "Papirus-Dark"; style = "Fusion"; };
          # QSettings treats unquoted commas as a list, not a font description.
          Fonts = { fixed = ''"JetBrains Mono,10,-1,5,50,0,0,0,0,0"''; general = ''"Inter,10,-1,5,50,0,0,0,0,0"''; };
          # Preserve the existing Qt interaction preferences; only appearance changes.
          Interface = {
            activate_item_on_single_click = 1; buttonbox_layout = 0;
            cursor_flash_time = 1000; dialog_buttons_have_icons = 1;
            double_click_interval = 400; keyboard_scheme = 2;
            menus_have_icons = true; show_shortcuts_in_context_menus = true;
            toolbutton_style = 4; underline_shortcut = 1; wheel_scroll_lines = 3;
          };
          Troubleshooting.force_raster_widgets = 1;
        };
        qt6ctSettings = config.qt.qt5ctSettings;
      };
      xdg.configFile."qt5ct/colors/verdigris.conf".text = ''
        [ColorScheme]
        active_colors=${qtColors}
        inactive_colors=${qtColors}
        disabled_colors=${qtColors}
      '';
      dconf.settings."org/gnome/desktop/interface".color-scheme = "prefer-dark";
      # Manage just the theme file, not the directory containing IME profiles
      # and dictionaries which fcitx writes at runtime.
      xdg.configFile.fcitx5 = lib.mkIf (config.desktop.japanese.enable && config.desktop.japanese.input.enable) {
        recursive = true;
      };
      i18n.inputMethod.fcitx5 = lib.mkIf (config.desktop.japanese.enable && config.desktop.japanese.input.enable) {
        settings.addons.classicui.globalSection.Theme = "verdigris-ink";
        themes.verdigris-ink.theme = {
          Metadata = { Name = "Verdigris Ink"; Author = "Graphide"; Version = "1"; };
          InputPanel = {
            Font = "Inter 12"; NormalColor = c.text;
            HighlightCandidateColor = c.onAccent; HighlightColor = c.accent;
            HighlightBackgroundColor = c.secondary; Spacing = 4;
          };
          "InputPanel/Background" = { Color = c.page; BorderColor = c.secondary; BorderWidth = 1; };
          "InputPanel/Highlight".Color = c.accent;
          "InputPanel/TextMargin" = { Left = 10; Right = 10; Top = 6; Bottom = 6; };
          Menu = { Font = "Inter 11"; NormalColor = c.text; HighlightCandidateColor = c.onAccent; };
          "Menu/Background" = { Color = c.page; BorderColor = c.secondary; BorderWidth = 1; };
          "Menu/Highlight".Color = c.accent;
          "Menu/Separator".Color = c.secondary;
          "Menu/TextMargin" = { Left = 10; Right = 10; Top = 6; Bottom = 6; };
        };
      };
      programs.librewolf.profiles.default.userChrome = lib.mkAfter (with c; ''
        :root {
          --lwt-accent-color: ${page} !important;
          --lwt-text-color: ${text} !important;
          --toolbar-bgcolor: ${raised} !important;
          --toolbar-color: ${text} !important;
          --toolbar-field-background-color: ${sunken} !important;
          --toolbar-field-color: ${text} !important;
          --sidebar-background-color: ${page} !important;
          --sidebar-text-color: ${text} !important;
          --tab-selected-bgcolor: ${secondary} !important;
          --focus-outline-color: ${accent} !important;
          --color-accent-primary: ${accent} !important;
        }
      '');
    })
  ];
}
