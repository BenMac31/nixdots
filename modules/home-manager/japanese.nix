{ config, lib, pkgs, inputs, ... }:
{
  home.packages = [ #
    pkgs.noto-fonts-cjk
  ];
  i18n.inputMethod = {
    enabled = "fcitx5";
    fcitx5.addons = with pkgs; [
      fcitx5-mozc
      fcitx5-gtk
    ];
  };
  xdg.dataFile."fcitx5/themes".source = inputs.fcitx5-gruvbox;
  # xdg.configFile."fcitx5/conf/classic-ui.config".text = ''
  #   Theme = Gruvbox-Dark
  #   '';
}
