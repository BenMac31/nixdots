{ lib, config, pkgs, ... }:
{
  options = {
    boxes-dev = {
      enable = lib.mkEnableOption "Put the boxes.dev CLI (dvb) on PATH";
    };
  };
  config = lib.mkIf config.boxes-dev.enable {
    # dvb is npm's @boxes-dev/dvb in ~/.local/share/boxes-dev, where it updates
    # itself; its helpers (dvbd, dvb-update) look for node on PATH.
    home.packages = [
      (pkgs.writeShellScriptBin "dvb" ''
        d="$HOME/.local/share/boxes-dev"
        PATH="${pkgs.nodejs_22}/bin:$d/bin:$PATH"
        export PATH
        exec node "$d/lib/node_modules/@boxes-dev/dvb/dist/bin/dvb.cjs" "$@"
      '')
    ];
  };
}
