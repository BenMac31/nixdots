{ config, lib, pkgs, ... }:
let
  cfg = config.desktop.verdigris;
  p = config.colorScheme.palette;
  gtkCss = ''
    @define-color window_bg_color #${p.base00};
    @define-color window_fg_color #${p.base05};
    @define-color view_bg_color #070d12;
    @define-color view_fg_color #${p.base05};
    @define-color headerbar_bg_color #${p.base01};
    @define-color headerbar_fg_color #${p.base05};
    @define-color sidebar_bg_color #${p.base01};
    @define-color sidebar_fg_color #${p.base05};
    @define-color card_bg_color #${p.base01};
    @define-color card_fg_color #${p.base05};
    @define-color popover_bg_color #0d1720;
    @define-color popover_fg_color #${p.base05};
    @define-color dialog_bg_color #0d1720;
    @define-color dialog_fg_color #${p.base05};
    @define-color accent_bg_color #${p.base0C};
    @define-color accent_fg_color #04120f;
    @define-color accent_color #6dbcb0;
    @define-color theme_bg_color #${p.base00};
    @define-color theme_fg_color #${p.base05};
    @define-color theme_base_color #070d12;
    @define-color theme_text_color #${p.base05};
    @define-color theme_selected_bg_color #${p.base0C};
    @define-color theme_selected_fg_color #04120f;
    @define-color borders rgba(255,255,255,0.08);
    @define-color error_color #${p.base08};
    @define-color warning_color #${p.base0A};
    @define-color success_color #2ea043;
  '';
  # Qt palette roles in QPalette order (Qt5 and Qt6 share the first 21).
  qtColors = lib.concatStringsSep ", " [
    "#bcc6cd" "#0f1a22" "#18242c" "#18242c" "#070d12" "#75838b"
    "#bcc6cd" "#ffffff" "#bcc6cd" "#070d12" "#0a1218" "#070d12"
    "#4fa396" "#04120f" "#6dbcb0" "#79b0a8" "#0f1a22" "#000000"
    "#0d1720" "#bcc6cd" "#75838b" "#4fa396"
  ];
in {
  options.desktop.verdigris.enable = lib.mkEnableOption "Graphide's Verdigris Ink application theme";
  config = lib.mkMerge [
    { desktop.verdigris.enable = lib.mkDefault config.desktop.enable; }
    (lib.mkIf cfg.enable {
      # Canonical neutrals/accent from Graphide's pre_design_system.md;
      # syntax hues from the bundled Verdigris Ink editor theme.
      colorScheme = {
        slug = "verdigris-ink";
        name = "Verdigris Ink";
        author = "Graphide";
        palette = {
          base00 = "0a1218"; base01 = "0f1a22"; base02 = "18242c"; base03 = "52616b";
          base04 = "75838b"; base05 = "bcc6cd"; base06 = "dae1e6"; base07 = "ffffff";
          base08 = "f85149"; base09 = "f78c6c"; base0A = "e3b341"; base0B = "c3e88d";
          base0C = "4fa396"; base0D = "8aaeff"; base0E = "c792ea"; base0F = "79b0a8";
        };
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
            Font = "Inter 12"; NormalColor = "#${p.base05}";
            HighlightCandidateColor = "#04120f"; HighlightColor = "#${p.base0C}";
            HighlightBackgroundColor = "#${p.base02}"; Spacing = 4;
          };
          "InputPanel/Background" = { Color = "#${p.base00}"; BorderColor = "#${p.base02}"; BorderWidth = 1; };
          "InputPanel/Highlight".Color = "#${p.base0C}";
          "InputPanel/TextMargin" = { Left = 10; Right = 10; Top = 6; Bottom = 6; };
          Menu = { Font = "Inter 11"; NormalColor = "#${p.base05}"; HighlightCandidateColor = "#04120f"; };
          "Menu/Background" = { Color = "#${p.base00}"; BorderColor = "#${p.base02}"; BorderWidth = 1; };
          "Menu/Highlight".Color = "#${p.base0C}";
          "Menu/Separator".Color = "#${p.base02}";
          "Menu/TextMargin" = { Left = 10; Right = 10; Top = 6; Bottom = 6; };
        };
      };
      programs.librewolf.profiles.default.userChrome = lib.mkAfter ''
        :root {
          --lwt-accent-color: #${p.base00} !important;
          --lwt-text-color: #${p.base05} !important;
          --toolbar-bgcolor: #${p.base01} !important;
          --toolbar-color: #${p.base05} !important;
          --toolbar-field-background-color: #070d12 !important;
          --toolbar-field-color: #${p.base05} !important;
          --sidebar-background-color: #${p.base00} !important;
          --sidebar-text-color: #${p.base05} !important;
          --tab-selected-bgcolor: #${p.base02} !important;
          --focus-outline-color: #${p.base0C} !important;
          --color-accent-primary: #${p.base0C} !important;
        }
      '';
    })
  ];
}
