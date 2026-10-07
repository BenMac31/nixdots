{ config, lib, pkgs, ... }:
let
  cfg = config.home-manager.users.greencheetah.services.ai-router;
  toml = pkgs.formats.toml { };
in {
  config = lib.mkIf cfg.enable {
    # Machine policy catches absolute binaries, alternate CODEX_HOME values,
    # SDK launches and bundled copies which never consult our PATH wrappers.
    # Keep the OpenAI name and backend suffix: Codex uses them to enable its
    # native compaction, search and other backend capabilities.
    environment.etc."codex/requirements.toml".source = toml.generate "ai-router-codex-requirements.toml" {
      model_provider = "account-router";
      model_providers.account-router = {
        name = "OpenAI";
        base_url = "${cfg.url}/backend-api/codex";
        wire_api = "responses";
        requires_openai_auth = true;
        supports_websockets = true;
        supports_standalone_web_search = true;
      };
    };
  };
}
