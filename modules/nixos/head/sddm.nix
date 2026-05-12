{ config, pkgs, lib, ... }:

{
  services.displayManager.sddm = {
    wayland.enable = true;
    theme = "sddm-astronaut-theme";
  };
  services.displayManager.autoLogin = {
    enable = true;
    user = "greencheetah";
  };
  environment.systemPackages = with pkgs; lib.mkIf config.services.displayManager.sddm.enable [
    (sddm-astronaut.override {
      themeConfig = import ./sddm/gruvbox.nix;
    })
    noto-fonts-cjk-sans
  ];
}
