{ lib, config, pkgs, inputs, flakeAttr, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
in
{
  imports = [ inputs.graphide-tools.homeManagerModules.graphide ];
  graphide = {
    releaseFlake = inputs.graphide;
    # A shell's `gr` runs the running daemon's build, so commands a newer
    # daemon brings (after `gdev swap`) work without a switch.
    followDaemon = config.graphide.enable;
    autoUpdate = {
      inherit flakeAttr;
      homeManagerPackage = inputs.home-manager.packages.${system}.home-manager;
    };
    checkoutSync = {
      enable = lib.mkDefault config.graphide.enable;
      sshAuthSock = "%t/ssh-agent";
    };
  };
  # From graphide-tools, not the release, so the updater never rolls it back.
  home.packages = lib.mkIf config.graphide.enable [
    inputs.graphide-tools.packages.${system}.gdev
  ];
}
