{ lib, config, pkgs, ... }:
{
  imports = [ ./signal.nix ];

  options.comms.enable = lib.mkEnableOption "Enable communications";

  config = lib.mkIf config.comms.enable {
    signal.enable = lib.mkDefault true;

    home.packages = [
      pkgs.thunderbird
      (lib.mkIf config.desktop.japanese.input.enable (pkgs.symlinkJoin
        {
          name = "element-desktop";
          paths = [ pkgs.element-desktop ];
          buildInputs = [ pkgs.makeWrapper ];
          postBuild = ''
            wrapProgram $out/bin/element-desktop \
                  --add-flags "--enable-wayland-ime=true"
          '';
        }))
      (lib.mkIf (!config.desktop.japanese.input.enable) pkgs.element-desktop)
    ];
  };
}
