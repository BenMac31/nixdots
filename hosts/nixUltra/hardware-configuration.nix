# HP ZBook Ultra G1a (Ryzen AI Max PRO 390, Radeon 8050S, 64 GB).
#
# Written by hand rather than by nixos-generate-config: the disk is laid out
# by install-nixUltra (hosts/nixUltra/installer.nix), which names everything,
# so this file mounts by label and needs no UUIDs from the machine.
{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [ (modulesPath + "/installer/scan/not-detected.nix")
    ];

  boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "thunderbolt" "usb_storage" "usbhid" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-amd" ];
  # The webcam (AMD ISP4) has a driver only from 7.2; 6.18 LTS has none.
  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.extraModulePackages = [ ];
  # Early KMS, so the LUKS prompt and plymouth come up at native resolution.
  hardware.amdgpu.initrd.enable = true;

  boot.initrd.luks.devices."root" = {
    device = "/dev/disk/by-partlabel/nixultra-luks";
    allowDiscards = true;
  };

  fileSystems."/" =
    { device = "/dev/disk/by-label/nixultra";
      fsType = "btrfs";
      options = [ "subvol=root" "compress=zstd" "noatime" ];
    };

  fileSystems."/nix" =
    { device = "/dev/disk/by-label/nixultra";
      fsType = "btrfs";
      options = [ "subvol=nix" "compress=zstd" "noatime" ];
    };

  fileSystems."/home" =
    { device = "/dev/disk/by-label/nixultra";
      fsType = "btrfs";
      options = [ "subvol=home" "compress=zstd" "noatime" ];
    };

  fileSystems."/swap" =
    { device = "/dev/disk/by-label/nixultra";
      fsType = "btrfs";
      options = [ "subvol=swap" "noatime" ];
    };

  fileSystems."/boot" =
    { device = "/dev/disk/by-label/NIXBOOT";
      fsType = "vfat";
      options = [ "fmask=0077" "dmask=0077" ];
    };

  # Sized to hibernate a full 64 GB. install-nixUltra creates it with
  # `btrfs filesystem mkswapfile` at exactly this size, so activation keeps it.
  swapDevices = [
    { device = "/swap/swapfile"; size = 65536; }
  ];

  networking.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
