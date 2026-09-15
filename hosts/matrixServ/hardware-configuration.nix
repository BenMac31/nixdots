# Azure VM (Gen2/UEFI). This subscription has no cheap Gen1-compatible VM
# sizes available, so the image is built for UEFI boot instead of using
# nixpkgs' Gen1-only azure-image.nix. system.build.azureImage below mirrors
# that module's approach but with an EFI partition table and a manually
# fixed-format VHD conversion: make-disk-image.nix's built-in "vpc" format
# writes a dynamic VHD (unusable for Azure's disk-upload API, which requires
# fixed), and even a manual fixed conversion needs the virtual disk size
# padded so that (size + 512-byte footer) lands on a 1MiB boundary -- Azure
# rejects anything else during `az disk create --upload-size-bytes`.
{ config, lib, pkgs, modulesPath, ... }:
{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.growPartition = true;

  boot.initrd.availableKernelModules = [
    "hv_vmbus"
    "hv_storvsc"
    "hv_netvsc"
    "hv_utils"
    "sd_mod"
  ];
  boot.kernelParams = [ "console=ttyS0" ];

  networking.usePredictableInterfaceNames = false;

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
    autoResize = true;
  };
  fileSystems."/boot" = {
    device = "/dev/disk/by-label/ESP";
    fsType = "vfat";
  };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  system.build.azureImage = import (modulesPath + "/../lib/make-disk-image.nix") {
    inherit config lib pkgs;
    name = "azure-image";
    partitionTableType = "efi";
    format = "raw";
    postVM = ''
      set -euo pipefail
      current_size=$(stat -c '%s' "$diskImage")
      remainder=$(( current_size % 1048576 ))
      if [ "$remainder" -eq 0 ]; then
        pad=0
      else
        pad=$(( 1048576 - remainder ))
      fi
      new_size=$(( current_size + pad ))
      ${pkgs.qemu-utils}/bin/qemu-img resize -f raw "$diskImage" "$new_size"
      ${pkgs.qemu-utils}/bin/qemu-img convert -f raw -o subformat=fixed,force_size -O vpc "$diskImage" "$out/disk.vhd"
      rm "$diskImage"
    '';
  };
}
