{ lib, config, pkgs, inputs, flakeAttr, ... }:
{
  imports = [ inputs.graphide-tools.homeManagerModules.graphide ];
  graphide.releaseFlake = inputs.graphide;
  graphide.autoUpdate = {
    flakeAttr = flakeAttr;
    homeManagerPackage = inputs.home-manager.packages.${pkgs.stdenv.hostPlatform.system}.home-manager;
    sshAuthSock = "%t/ssh-agent";
  };
  graphide.checkoutSync = {
    enable = lib.mkDefault config.graphide.enable;
    checkout = "${config.home.homeDirectory}/Projects/graphide/graphide";
    sshAuthSock = "%t/ssh-agent";
    # These existing generated paths are the only local state sync may discard.
    allowlist = [ ".graphide/authored" "gred/extensions/graphide/out" ];
  };
}
