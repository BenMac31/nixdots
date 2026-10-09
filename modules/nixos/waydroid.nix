# Waydroid: Android in an LXC container on this machine's own kernel, for
# trying Android apps beside the desktop (Graphide's phone app, built from
# gred-rs/crates/phone, is the reason it is here).
#
# nixpkgs' virtualisation.waydroid does the work: the gbinder config, LXC,
# the waydroid-container service, and a trusted firewall bridge (waydroid0)
# so the Android side has network. It needs binder and binderfs, which the
# NixOS kernel has built in, and PSI, which it turns on with psi=1. It draws
# with the host GPU through Mesa, so on an AMD or Intel GPU it runs at
# native speed, Vulkan included; on NVIDIA it falls back to software.
#
# The Android images are not part of the system. After the first rebuild,
# once:
#   sudo waydroid init -s GAPPS     # or plain `waydroid init`; ~1 GB download
# Then in the Wayland session:
#   waydroid show-full-ui           # starts the session and shows Android
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
