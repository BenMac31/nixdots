{config, pkgs, inputs, ...}:

{
  programs.hyprland = {
    enable = true;
    enableNvidiaPatches = true;
    xwayland.enable = true;

  };
  environment.sessionVariables = {
    WLR_NO_HARDWARE_CURSORS = "1";
    # WLR_DRM_DEVICES="/dev/dri/card1:/dev/dri/card0";
    WLR_DRM_DEVICES="/dev/dri/card1";
    NIXOS_OZONE_WL = "1";
  };
}
