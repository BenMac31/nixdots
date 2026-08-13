{ config, lib, pkgs, ... }:
let
  cfg = config.omnigent;
  venv = "${config.xdg.dataHome}/omnigent";
in
{
  options.omnigent = {
    enable = lib.mkEnableOption "Omnigent meta-harness";
    version = lib.mkOption {
      type = lib.types.str;
      default = "0.9.0";
      description = "Pinned omnigent release installed into the managed venv.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Omnigent itself is not in nixpkgs, and its dependency closure
    # (omnigent-client, omnigent-ui-sdk, claude-agent-sdk, openai-agents...)
    # is not packaged either, so nix provides the interpreter and the
    # prerequisites while uv resolves the python deps into a pinned venv.
    # The venv is built on first run rather than during activation so that
    # `home-manager switch` stays offline-safe.
    home.packages = [
      pkgs.uv
      pkgs.nodejs_22 # omnigent shells out to node-based harnesses (claude, codex)
      pkgs.tmux
      pkgs.bubblewrap

      (pkgs.writeShellApplication {
        name = "omnigent";
        runtimeInputs = [ pkgs.uv pkgs.nodejs_22 pkgs.git pkgs.tmux pkgs.bubblewrap ];
        text = ''
          venv="${venv}"
          stamp="$venv/.pinned-version"

          if [ ! -x "$venv/bin/omnigent" ] || [ "$(cat "$stamp" 2>/dev/null)" != "${cfg.version}" ]; then
            echo "omnigent: provisioning ${cfg.version} into $venv" >&2
            rm -rf "$venv"
            uv venv --python ${pkgs.python312}/bin/python3.12 "$venv"
            uv pip install --python "$venv/bin/python" "omnigent==${cfg.version}"
            echo "${cfg.version}" > "$stamp"
          fi

          exec "$venv/bin/omnigent" "$@"
        '';
      })
    ];
  };
}
