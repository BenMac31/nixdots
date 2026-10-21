{ lib, config, pkgs, inputs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
in
{
  imports = [ inputs.graphide-tools.homeManagerModules.graphide ];
  graphide = {
    # A shell's `gr` runs the running daemon's build, so commands a newer
    # daemon brings (after `gdev swap`) work without a switch.
    followDaemon = config.graphide.enable;
    checkoutSync = {
      enable = lib.mkDefault config.graphide.enable;
      sshAuthSock = "%t/ssh-agent";
    };
  };
  home.packages = lib.mkIf config.graphide.enable [
    inputs.graphide-tools.packages.${system}.gdev
  ];
}
