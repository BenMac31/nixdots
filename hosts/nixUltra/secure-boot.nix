{ config, lib, pkgs, inputs, ... }:
# Secure Boot through lanzaboote, which signs the kernel and initrd with keys
# made on this machine. Off until those keys exist -- lanzaboote cannot sign
# without them, and install-nixUltra runs before they can be made. To turn on:
#
#   sudo sbctl create-keys
#   set boot.lanzaboote.enable = true below, rebuild, `sudo sbctl verify`
#   BIOS (F10): clear the Secure Boot keys so the firmware is in Setup Mode
#   sudo sbctl enroll-keys --microsoft    # keeps Microsoft's keys for firmware
#   reboot, BIOS: enable Secure Boot; `bootctl status` then says "enabled"
{
  imports = [ inputs.lanzaboote.nixosModules.lanzaboote ];

  environment.systemPackages = [ pkgs.sbctl ];

  boot.lanzaboote = {
    enable = false;
    pkiBundle = "/var/lib/sbctl";
  };
  boot.loader.systemd-boot.enable = lib.mkForce (!config.boot.lanzaboote.enable);
}
