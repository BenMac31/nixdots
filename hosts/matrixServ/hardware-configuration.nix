# AWS EC2. amazon-image.nix supplies the platform-specific bits (GRUB, ENA,
# instance-metadata SSH key, SSM agent), so there is nothing to regenerate here.
{ lib, modulesPath, ... }:
{
  imports = [ (modulesPath + "/virtualisation/amazon-image.nix") ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
