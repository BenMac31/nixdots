{ config, lib, pkgs, inputs, ... }:
{
  options.desktop.japanese.enable = lib.mkEnableOption "Enable Japanese";
  config = lib.mkIf config.desktop.japanese.enable {
    home.packages = with pkgs; [
      (lib.mkIf config.media.enable mokuro)
      noto-fonts-cjk-sans
      source-han-sans
      source-han-mono
      source-han-serif
      source-han-sans-vf-ttf
      source-han-sans-vf-otf
    ];
    i18n.inputMethod = {
      enabled = "fcitx5";
      fcitx5.addons = with pkgs; [
        fcitx5-mozc
        fcitx5-gtk
      ];
    };
    xdg.dataFile."fcitx5/themes".source = inputs.fcitx5-gruvbox;
  };
}
