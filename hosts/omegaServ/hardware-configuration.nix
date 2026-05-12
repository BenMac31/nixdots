{ pkgs, lib, ... }: {
  boot.kernelPackages = pkgs.linuxPackages_latest;
  services.openssh.enable = true;
  documentation.enable = false;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  networking.useDHCP = lib.mkDefault true;
  services.qemuGuest.enable = true;
}
