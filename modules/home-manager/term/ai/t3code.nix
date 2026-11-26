{ lib, config, pkgs, ... }:
let
  pool = config.services.ai-pool;
  claude = pkgs.writeShellScriptBin "t3code-claude" ''
    exec ${pool.command} claude "$@"
  '';
in
{
  options = {
    ai.t3code = {
      enable = lib.mkEnableOption "the T3 Code desktop app";
    };
  };
  config = lib.mkIf config.ai.t3code.enable (lib.mkMerge [
    {
      home.packages = [ (pkgs.callPackage ../../../../pkgs/t3code.nix { }) ];
      xdg.mimeApps.defaultApplications = {
        "x-scheme-handler/t3code" = "t3code.desktop";
      };
    }
    # Codex already reaches the pool through /etc/codex/requirements.toml.
    (lib.mkIf pool.enable {
      home.activation.t3codeClaudePool = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run ${lib.getExe pkgs.python3} ${./t3code-settings.py} \
          "$HOME/.t3/userdata/settings.json" ${lib.getExe claude}
      '';
    })
  ]);
}
