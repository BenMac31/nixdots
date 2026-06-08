{ pkgs, lib, modulesPath, ... }: {
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];
  boot.kernelPackages = pkgs.linuxPackages_latest;
  services.openssh.enable = true;
  documentation.enable = false;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  networking.useDHCP = lib.mkDefault true;
  services.qemuGuest.enable = true;

  # Placeholder for flake evaluation; replace with nixos-generate-config output on deploy.
  fileSystems."/" = {
    device = "/dev/vda1";
    fsType = "ext4";
  };
}
