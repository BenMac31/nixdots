{ config, lib, ... }:

let
  cfg = config.serv.mautrixBridges;
  matrix = config.serv.continuwuity;
  homeserverAddress = "http://127.0.0.1:${toString matrix.port}";
  socketUri = db: "postgres:///${db}?host=/run/postgresql";
in
{
  options.serv.mautrixBridges = {
    enable = lib.mkEnableOption "the mautrix puppeting bridges";

    whatsapp.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Run the WhatsApp bridge.";
    };

    discord.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Run the Discord bridge.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = matrix.enable;
        message = "serv.mautrixBridges requires serv.continuwuity.enable; the bridges have no other homeserver to register against.";
      }
    ];

    services.mautrix-whatsapp = lib.mkIf cfg.whatsapp.enable {
      enable = true;
      serviceDependencies = [ "continuwuity.service" "postgresql.service" ];

      # settings has `apply = recursiveUpdate defaultConfig`, so partial is safe
      # here, and the upstream appservice id, bot username and username_template
      # already match the container this replaces.
      settings = {
        homeserver = {
          address = homeserverAddress;
          domain = matrix.serverName;
        };
        appservice.hostname = "127.0.0.1";
        database = {
          type = "postgres";
          uri = socketUri "mautrix-whatsapp";
        };
      };
    };

    services.mautrix-discord = lib.mkIf cfg.discord.enable {
      enable = true;
      serviceDependencies = [ "continuwuity.service" "postgresql.service" ];

      # homeserver and appservice are types.attrs: a definition replaces the
      # upstream default outright rather than merging into it, so both are
      # restated in full.
      settings = {
        homeserver = {
          address = homeserverAddress;
          domain = matrix.serverName;
          software = "standard";
          status_endpoint = null;
          message_send_checkpoint_endpoint = null;
          async_media = false;
          websocket = false;
          ping_interval_seconds = 0;
        };

        appservice = {
          address = "http://127.0.0.1:29334";
          hostname = "127.0.0.1";
          port = 29334;
          database = {
            type = "postgres";
            uri = socketUri "mautrix-discord";
            max_open_conns = 20;
            max_idle_conns = 2;
            max_conn_idle_time = null;
            max_conn_lifetime = null;
          };
          id = "discord";
          bot = {
            username = "discordbot";
            displayname = "Discord bridge bot";
            avatar = "mxc://maunium.net/nIdEykemnwdisvHbpxflpDlC";
          };
          ephemeral_events = true;
          async_transactions = false;
          as_token = "This value is generated when generating the registration";
          hs_token = "This value is generated when generating the registration";
        };
      };
    };

    services.postgresql = {
      enable = true;

      ensureDatabases =
        lib.optional cfg.whatsapp.enable "mautrix-whatsapp"
        ++ lib.optional cfg.discord.enable "mautrix-discord";

      ensureUsers =
        lib.optional cfg.whatsapp.enable {
          name = "mautrix-whatsapp";
          ensureDBOwnership = true;
        }
        ++ lib.optional cfg.discord.enable {
          name = "mautrix-discord";
          ensureDBOwnership = true;
        };
    };
  };
}
