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
  boxes-dev.enable = true;
  graphide.enable = true;
  # Separate toggle: the timer moves gr/grat to each new release every 30 min.
  graphide.autoUpdate.enable = true;
  desktop = {
    enable = true;
    gaming.enable = true;
    japanese.enable = true;
  };

  home.packages = [
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
