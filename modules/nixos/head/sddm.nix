{ config, pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    sddm-sugar-dark
  ];
  services.displayManager.sddm = {
    wayland.enable = true;
    theme = "sugar-dark";
    extraPackages = [ pkgs.sddm-sugar-dark ];
  };
}
