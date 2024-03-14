{ config, pkgs, ... }:
{
  boot = {
    plymouth.enable = true;
    initrd.systemd.enable = true;
  };
}
