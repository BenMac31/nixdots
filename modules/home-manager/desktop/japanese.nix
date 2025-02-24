{ config, lib, pkgs, inputs, ... }:
{
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
  # xdg.dataFile."fonts" = {
  #   enable = true;
  #   source = config.lib.file.mkOutOfStoreSymlink "/run/current-system/sw/share/X11/fonts";
  # };
  # xdg.configFile."fcitx5/conf/classic-ui.config".text = ''
  #   Theme = Gruvbox-Dark
  #   '';
}
