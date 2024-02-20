{pkgs, config, ...}:
{
services.thermald.enable = true;
powerManagement.powertop.enable = true;
}
