{ config, lib, pkgs, ... }:
let
  home = config.home-manager.users.greencheetah;
  pool = home.services.ai-pool;
in
{
  # Codex reads this machine policy on every launch, including bundled copies,
  # SDK launches and other CODEX_HOMEs that never see the PATH wrappers.
  config = lib.mkIf pool.enable {
    environment.etc."codex/requirements.toml".source =
      (pkgs.formats.toml { }).generate "codex-requirements.toml" {
        model_provider = "graphide-pool";
        model_providers.graphide-pool = {
          # Codex turns on compaction, search and its other backend features
          # for the OpenAI name and the backend-api path.
          name = "OpenAI";
          base_url = "${pool.url}/backend-api/codex";
          wire_api = "responses";
          supports_websockets = true;
          supports_standalone_web_search = true;
          # Read at each request, so the key never enters the store.
          auth = {
            command = "${pkgs.coreutils}/bin/cat";
            args = [ "${home.xdg.configHome}/graphide/pool-key" ];
          };
        };
      };
  };
}
