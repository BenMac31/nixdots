{ config, lib, pkgs, modulesPath, ... }:

let
  benKey = ''ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQChQYMz+Q2dzTLTISmBlFHPUDRAzvupt3Sw/u2fpjZXjM3VLVU/VFq8gjmMMVVKTJBXUHwbdJiiNzvx0CobBYYXz5dMjV5Q3dubC2iikS70CX1M13n1yFzIebMsL8vTQaM/g5g0Sg9woAW8b74uWH5r6h6xmXOR7tfFi8m2tDmIllpRxXe49G9Hcmr4NQaHs3hb/A/31JTFjJDTvFqRN9BNUYgC4OR51FNFRsj2TZ8ecaYsSTcFioRG4jBYpU6URbFHLVrs3C5g9Fh8LKW6ISSd3G9XFnEYYXFAp0C8SiEZR02VYvU61N68IeDRikscjQ1JOm8r2HKGhi+Nv4Mc22qxPrpn4bg4jbAPzwms2OTX2rkI6ghZYhzXYOHzqszqe+J7bPXUdHmDLzXIb1mTNy9dAU1FY3UqbCUXb4Hqx0CjvTzbCE7R8ME537qfy0QkvtjLFek9Azh36iKzGnH7rVdmKQuzShVkYCnUqItPViamm7Py1Rbv1HPO7X4eIrsy2vc= greencheetah@fedora'';
in
{
  imports = [
    "${modulesPath}/virtualisation/google-compute-image.nix"
    ../../modules/nixos/serv/minecraft.nix
  ];

  # c4d only boots UEFI images from NVMe and only has gVNIC networking.
  virtualisation.googleComputeImage.efi = true;
  boot.initrd.availableKernelModules = [ "gve" ];
  # OS Login's PAM account check refuses every local user, root and carol too.
  security.googleOsLogin.enable = lib.mkForce false;

  serv.minecraft = {
    enable = true;
    heap = "16G";
    operators = [ "carol" ];
  };

  networking.hostName = "mcServ";
  time.timeZone = "America/New_York";

  # GCP's firewall admits 22, 25565 and 24454/udp; this one also keeps RCON
  # (25575, bound on every interface) off the network.
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 25565 ];
    allowedUDPPorts = [ 24454 ];
  };

  services.openssh.settings = {
    PermitRootLogin = "prohibit-password";
    PasswordAuthentication = false;
  };
  users.users.root.openssh.authorizedKeys.keys = [ benKey ];
  users.users.carol = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [ benKey ];
  };

  environment.systemPackages = with pkgs; [ git htop rsync mcrcon ];

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" ];
  };
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  nixpkgs.hostPlatform = "x86_64-linux";
  system.stateVersion = "26.05";
}
