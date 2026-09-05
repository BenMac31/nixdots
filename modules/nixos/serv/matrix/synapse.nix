{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.serv.matrix;
  synapsePort = 8008;
in
{
  config = lib.mkIf cfg.enable {
    services.matrix-synapse = {
      enable = true;

      enableRegistrationScript = true;

      extraConfigFiles = [ ];

      settings = {
        server_name = cfg.serverName;
        public_baseurl = "https://${cfg.hostName}/";

        enable_registration = false;
        registration_shared_secret_path = cfg.internal.sharedSecretFile;

        report_stats = false;
        suppress_key_server_warning = true;

        listeners = [
          {
            port = synapsePort;
            bind_addresses = [ "127.0.0.1" ];
            type = "http";
            tls = false;
            x_forwarded = true;
            resources = [
              {
                names = [
                  "client"
                  "federation"
                ];
                compress = false;
              }
            ];
          }
        ];

        database = {
          name = "psycopg2";
          args.database = "matrix-synapse";
        };

        app_service_config_files = lib.optional cfg.slack.enable cfg.internal.registrationFile;

        max_upload_size = "100M";
        media_retention = {
          remote_media_lifetime = "90d";
        };

        experimental_features = {
          msc3266_enabled = true;
        };

        allow_public_rooms_over_federation = false;

        encryption_enabled_by_default_for_room_type = if cfg.encryption.enable then "all" else "off";

        url_preview_enabled = true;
        url_preview_ip_range_blacklist = [
          "127.0.0.0/8"
          "10.0.0.0/8"
          "172.16.0.0/12"
          "192.168.0.0/16"
          "100.64.0.0/10"
          "169.254.0.0/16"
          "::1/128"
          "fe80::/64"
          "fc00::/7"
        ];
      };
    };

    services.postgresql = {
      enable = true;

      initialScript = pkgs.writeText "synapse-db-init.sql" ''
        -- LOGIN is not implied by CREATE ROLE the way it is by CREATE USER.
        CREATE ROLE "matrix-synapse" LOGIN;
        CREATE DATABASE "matrix-synapse"
          WITH OWNER "matrix-synapse"
               TEMPLATE template0
               LC_COLLATE = "C"
               LC_CTYPE = "C";
      '';

      ensureDatabases = lib.optional cfg.slack.enable "mautrix-slack";
      ensureUsers = lib.optional cfg.slack.enable {
        name = "mautrix-slack";
        ensureDBOwnership = true;
      };
    };

    services.synapse-auto-compressor = {
      enable = true;
      startAt = "weekly";
    };
  };
}
