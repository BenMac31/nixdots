{config, pkgs, inputs, ... }:

{
  i18n.inputMethod = {
    enabled = "ibus";
    ibus.engines = with pkgs.ibus-engines; [ mozc ];
  };
  # home.packages = with pkgs; [
  #   noto-fonts-cjk
  # ];
}
