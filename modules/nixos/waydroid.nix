# Android in an LXC container, for Graphide's phone app (gred-rs/crates/phone).
# The Android images are not part of the system. Once:
#   sudo waydroid init -s GAPPS     # or plain `waydroid init`; ~1 GB download
# Then in the Wayland session:
#   waydroid show-full-ui
#   waydroid app install foo.apk
#   waydroid app launch dev.graphide.phone
#   adb connect "$(waydroid status | awk '/IP address/ {print $3}')"
{ config, lib, ... }:
{
  options.custom.waydroid.enable = lib.mkEnableOption "Waydroid, Android in a container";

  config = lib.mkIf config.custom.waydroid.enable {
    virtualisation.waydroid.enable = true;
  };
}
