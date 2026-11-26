{ lib, ... }:

{
  imports = [ ../laptop/home.nix ];

  composal.enable = lib.mkDefault true;
  ubuntuVm.enable = true;

  # Reclaim only launcher-created temporary data after every tracked child exits.
  services.agentScratch.taskCleanup.enable = true;
  services.agentScratch.cacheCleanup.enable = true;
  services.agentScratch.migration.enable = false;
  services.agentScratch.sizeGiB = 256;
  services.gpCachePrune = {
    cacheRoots = [ "/home/greencheetah/.cache" "/var/lib/agent-scratch/home/.cache" ];
    pressurePath = "/var/lib/agent-scratch";
    temporaryRoots = [ "/var/lib/agent-scratch/tmp" ];
  };

  # The 2880x1800 OLED: 1.6 is the nearest scale Hyprland accepts (1800x1125
  # logical); nixBlade's 1.56667 is not a whole-pixel divisor here.
  wayland.windowManager.hyprland.settings.monitor = lib.mkForce [
    ",preferred,auto,1.6"
    "DP-2,preferred,auto,1.6"
  ];
}
