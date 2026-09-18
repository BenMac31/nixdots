{ config, lib, pkgs, inputs, osConfig, ... }:

{
  imports = [
    ../../modules/home-manager
    ../../modules/home-manager/graphide.nix
  ];
  programs.home-manager.enable = true;
  home.username = "greencheetah";
  home.homeDirectory = "/home/greencheetah";
  sync.enable = true;
  programming.enable = true;
  ai.enable = true;
  yc.enable = true;
  graphide.enable = true;
  # Separate toggle: the timer reinstalls gr/grat/gred under you every 30 min.
  graphide.autoUpdate.enable = true;
  # The editor build runs on XiaServer over ssh from a background unit, so it
  # needs a key that works with no agent loaded; id_rsa has a passphrase.
  graphide.autoUpdate.sshIdentityFile = "/home/greencheetah/.ssh/id_ed25519_voxi";
  desktop = {
    enable = true;
    gaming.enable = true;
    japanese.enable = true;
  };

  home.packages = [
    # pkgs.unfree.android-studio
    # pkgs.mullvad-vpn
    pkgs.nix-output-monitor
    pkgs.fractal
    (pkgs.calibre.overrideAttrs
      (attrs: {
        preFixup = (
          builtins.replaceStrings
            [
              ''
                --prefix PYTHONPATH : $PYTHONPATH \
              ''
            ]
            [
              ''
                --prefix LD_LIBRARY_PATH : ${pkgs.libressl.out}/lib \
                --prefix PYTHONPATH : $PYTHONPATH \
              ''
            ]
            attrs.preFixup
        );
      }))
  ];


  programs = {
    password-store.enable = true;
    rbw.enable = true;
  };
  home.stateVersion = "23.11"; # Do not change
}
