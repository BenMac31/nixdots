{ lib, config, pkgs, ... }:
let
  pool = config.services.ai-pool;
  claude = pkgs.writeShellScriptBin "t3code-claude" ''
    exec ${pool.command} claude "$@"
  '';
  cfg = config.ai.t3code;
in
{
  options = {
    ai.t3code = {
      enable = lib.mkEnableOption "the T3 Code desktop app";
      vimComposer = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Give the chat composer vim modes, by inlining
          pkgs/t3code/vim-composer.js into T3's renderer.

          T3's own keybindings cannot do this: a binding is one key plus
          modifiers with no modal state, and the command registry holds no
          text-editing command at all.

          Turn this off to run a stock T3. There is also a runtime switch that
          needs no rebuild: __t3vim.disable() in devtools, or
          localStorage['t3code:vim-composer'] = 'off'.
        '';
      };
    };
  };
  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      home.packages = [
        (pkgs.callPackage ../../../../pkgs/t3code { inherit (cfg) vimComposer; })
      ];
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
