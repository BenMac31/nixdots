{ lib, config, pkgs, ... }:
let
  pool = config.services.ai-pool;
  claude = pkgs.writeShellScriptBin "t3code-claude" ''
    exec ${pool.command} claude "$@"
  '';
  antigravity = pkgs.unfree.callPackage ../../../../pkgs/antigravity-cli.nix { };
  cfg = config.ai.t3code;
  # T3 owns settings.json at runtime, so Nix folds these in on activation
  # rather than writing the whole file. Codex is left out: it already reaches
  # the pool through /etc/codex/requirements.toml.
  providerInstances =
    lib.optionalAttrs pool.enable {
      claudeAgent = {
        driver = "claudeAgent";
        config.binaryPath = lib.getExe claude;
      };
    }
    // lib.optionalAttrs cfg.antigravity {
      antigravity = {
        driver = "antigravity";
        config = {
          enabled = true;
          binaryPath = lib.getExe antigravity;
        };
      };
    };
  settingsPatch = pkgs.writeText "t3code-settings-patch.json"
    (builtins.toJSON { inherit providerInstances; });
in
{
  options = {
    ai.t3code = {
      enable = lib.mkEnableOption "the T3 Code desktop app";
      antigravity = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Turn on T3's Antigravity provider and point it at our own build of
          Google's agy CLI, which serves the Gemini 4 models (Neon, Carbon,
          Argon, Hydrogen) plus Claude and GPT-OSS through a Google account.

          Both halves have to come from here. T3 ships the driver in
          DEFAULT_DISABLED_PROVIDER_DRIVERS and hides its `enabled` flag from
          the settings form, so nothing in the UI switches it on; and the
          runtime T3 would otherwise download from Google's auto-updater is
          linked against /lib64/ld-linux-x86-64.so.2, which does not exist
          here.

          Signing in is still interactive: `agy` writes its own OAuth token,
          which both it and T3 read.
        '';
      };
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
    (lib.mkIf cfg.antigravity {
      home.packages = [ antigravity ];
    })
    (lib.mkIf (providerInstances != { }) {
      home.activation.t3codeProviders = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run ${lib.getExe pkgs.python3} ${./t3code-settings.py} \
          "$HOME/.t3/userdata/settings.json" ${settingsPatch}
      '';
    })
  ]);
}
