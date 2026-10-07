{ config, lib, pkgs, inputs, ... }:
{
  options.desktop.japanese = {
    enable = lib.mkEnableOption "Enable Japanese";
    input.enable = lib.mkEnableOption "Enable japanese input";
  };
  config = lib.mkIf config.desktop.japanese.enable {
    desktop.japanese.input.enable = lib.mkDefault true;
    home.packages = with pkgs;
      [
        (lib.mkIf config.media.enable mokuro)
        noto-fonts-cjk-sans
        source-han-sans
        source-han-mono
        source-han-serif
        source-han-sans-vf-ttf
        source-han-sans-vf-otf
      ];
    home.sessionVariables = lib.mkIf config.desktop.japanese.input.enable {
      QT_IM_MODULE = "fcitx";
    };
    i18n.inputMethod = lib.mkIf config.desktop.japanese.input.enable {
      enable = true;
      type = "fcitx5";
      fcitx5.addons = with pkgs; [
        fcitx5-mozc-ut
        fcitx5-gtk
        qt6Packages.fcitx5-configtool
      ];
      # Without this fcitx5 starts with keyboard-us only, and Mozc had to be
      # added by hand in the config tool on every new machine.
      fcitx5.settings.inputMethod = {
        GroupOrder."0" = "Default";
        "Groups/0" = {
          Name = "Default";
          "Default Layout" = "us";
          DefaultIM = "mozc";
        };
        "Groups/0/Items/0".Name = "keyboard-us";
        "Groups/0/Items/1".Name = "mozc";
      };
    };
    # fcitx5 rewrites profile at runtime, which would leave a plain file in
    # the way of the next switch. Recursive keeps its dictionaries writable;
    # force puts the declared profile back each time.
    xdg.configFile.fcitx5 = lib.mkIf config.desktop.japanese.input.enable {
      recursive = true;
      force = true;
    };
    xdg.dataFile = lib.mkIf (config.desktop.japanese.input.enable && !config.desktop.verdigris.enable) {
      "fcitx5/themes".source = inputs.fcitx5-gruvbox;
    };
  };
}
