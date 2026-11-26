{ lib, config, pkgs, ... }:
let
  pool = config.services.ai-pool;
  claude = pkgs.writeShellScriptBin "t3code-claude" ''
    exec ${pool.command} claude "$@"
  '';
  antigravity = pkgs.unfree.callPackage ../../../../pkgs/antigravity-cli.nix { };
  # agy through the pool instead of its own Google sign-in. The pool
  # (CLIProxyAPI on XiaServer) holds Antigravity credentials and serves the
  # same gemini-4-* models over the Gemini wire protocol, so agy reaches them
  # with this machine's pool key and no sign-in of its own.
  #
  # agy's route for that is `modelProvider: "gemini"` in settings.json plus
  # GEMINI_API_KEY and GOOGLE_GEMINI_BASE_URL (its 1.5.x changelog). --settings
  # is merged over the saved settings.json and never written back, so the model,
  # editor mode and trusted workspaces a session saved still apply, and a plain
  # `agy` outside T3 keeps using its own sign-in.
  #
  # `agy acp`, which is how T3 drives it, reads --settings too: with this
  # wrapper an ACP session needs no `authenticate` call and answers from the
  # pool. Only the models the pool serves answer; agy drops a model's effort
  # suffix before sending it, so Gemini 4 Neon (High) arrives as gemini-4-neon
  # and works, while Gemini 3.8 Flash (Low) arrives as gemini-3.8-flash, which
  # the pool does not carry, and the turn fails with "unknown provider".
  agy = pkgs.writeShellScriptBin "t3code-agy" ''
    key="''${GRAPHIDE_POOL_KEY:-}"
    file="''${GRAPHIDE_POOL_KEY_FILE:-''${XDG_CONFIG_HOME:-$HOME/.config}/graphide/pool-key}"
    if [ -z "$key" ] && [ -r "$file" ]; then
      read -r key < "$file" || true
    fi
    if [ -z "$key" ]; then
      echo "t3code-agy: this machine has no pool key ($file). Store one with: ai-pool setup < FILE" >&2
      exit 1
    fi
    # The pool's key must be the only thing agy can authenticate with.
    unset GOOGLE_API_KEY GOOGLE_APPLICATION_CREDENTIALS AGY_ADC_AUTH AGY_ACCOUNT
    export GEMINI_API_KEY="$key"
    export GOOGLE_GEMINI_BASE_URL="''${GRAPHIDE_POOL_URL:-${pool.url}}"
    export GRAPHIDE_POOL_ACTIVE=1
    exec ${lib.getExe antigravity} --settings '{"modelProvider":"gemini"}' "$@"
  '';
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
          binaryPath = lib.getExe (if pool.enable then agy else antigravity);
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

          With `services.ai-pool.enable`, T3 gets agy through the pool
          (`t3code-agy`), so it needs no sign-in of its own and draws on the
          pooled Antigravity accounts. Only the models the pool serves answer
          there: the gemini-4-* families and the Flash models, not agy's own
          Claude and GPT-OSS entries, and not every effort step of every model.
          Without the pool, agy signs in to a Google account itself and T3
          reads the OAuth token it writes.
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
      # `agy` is the vendor's own binary, so a session outside T3 still signs
      # in to a Google account; `t3code-agy` beside it is the pool's route.
      home.packages = [ antigravity ] ++ lib.optional pool.enable agy;
    })
    (lib.mkIf (providerInstances != { }) {
      home.activation.t3codeProviders = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run ${lib.getExe pkgs.python3} ${./t3code-settings.py} \
          "$HOME/.t3/userdata/settings.json" ${settingsPatch}
      '';
    })
  ]);
}
