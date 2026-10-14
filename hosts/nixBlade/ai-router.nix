{ config, lib, pkgs, ... }:
let
  home = config.home-manager.users.greencheetah;
  cfg = home.services.ai-router;
  toml = pkgs.formats.toml { };
  # Keep the OpenAI name and backend suffix: Codex uses them to enable its
  # native compaction, search and other backend capabilities.
  backend = url: {
    name = "OpenAI";
    base_url = "${url}/backend-api/codex";
    wire_api = "responses";
    supports_websockets = true;
    supports_standalone_web_search = true;
  };
  router = {
    model_provider = "account-router";
    model_providers.account-router = backend cfg.url // { requires_openai_auth = true; };
  };
  # The shared pool on XiaServer holds the sign-ins; Codex sends this
  # machine's pool key, read from its file at each request, never stored here.
  pool = {
    model_provider = "graphide-pool";
    model_providers.graphide-pool = backend (home.services.ai-pool.url or "http://xiaserver:8317") // {
      auth = {
        command = "${pkgs.coreutils}/bin/cat";
        args = [ "${home.xdg.configHome}/graphide/pool-key" ];
      };
    };
  };
in {
  options.custom.codexPool = lib.mkEnableOption
    "every Codex launch through the shared account pool instead of ai-router";
  config = lib.mkIf (cfg.enable || config.custom.codexPool) {
    # Machine policy catches absolute binaries, alternate CODEX_HOME values,
    # SDK launches and bundled copies which never consult our PATH wrappers.
    environment.etc."codex/requirements.toml".source =
      toml.generate "ai-router-codex-requirements.toml"
        (if config.custom.codexPool then pool else router);
  };
}
