{ config, lib, pkgs, ... }:
let
  python = pkgs.python3.withPackages (ps: [ ps.tomlkit ]);
in {
  options.ai.codex.enable = lib.mkEnableOption "Codex settings";

  config = lib.mkIf config.ai.codex.enable {
    # Codex rewrites this file and account profiles share it, so keep it writable.
    home.activation.codexWorkerLimit = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${lib.getExe python} ${./codex-settings.py} "$HOME/.codex/config.toml"
    '';
  };
}
