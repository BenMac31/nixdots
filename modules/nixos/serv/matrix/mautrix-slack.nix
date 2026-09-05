{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.serv.matrix;
  slack = cfg.slack;

  adminPermissions = lib.listToAttrs (
    map (localpart: lib.nameValuePair "@${localpart}:${cfg.serverName}" "admin") cfg.admins
  );

  configTemplate = (pkgs.formats.yaml { }).generate "mautrix-slack-config.yaml" {
    homeserver = {
      address = "http://127.0.0.1:8008";
      domain = cfg.serverName;
      software = "standard";
    };

    appservice = {
      address = "http://127.0.0.1:${toString slack.port}";
      hostname = "127.0.0.1";
      port = slack.port;
      id = slack.appserviceId;
      bot = {
        username = slack.botLocalpart;
        displayname = "Slack bridge bot";
        avatar = "mxc://maunium.net/pVtzLmChZejGxLqmXtQjFxem";
      };
      ephemeral_events = true;
      as_token = "@AS_TOKEN@";
      hs_token = "@HS_TOKEN@";
      username_template = "${slack.usernamePrefix}{{.}}";
    };

    database = {
      type = "postgres";
      uri = "postgres:///mautrix-slack?host=/run/postgresql";
    };

    bridge = {
      command_prefix = "!slack";
      permissions = {
        "${cfg.serverName}" = "user";
      }
      // adminPermissions;
    };

    double_puppet = {
      # leading @ keeps the value quoted in YAML; an unquoted scalar would be
      # mis-parsed as a nested mapping
      secrets = {
        "${cfg.serverName}" = "@DOUBLE_PUPPET_SECRET@";
      };
      servers = { };
      allow_discovery = false;
    };

    encryption = {
      allow = cfg.encryption.enable;
      default = cfg.encryption.enable;
      require = false;
      allow_key_sharing = true;
      pickle_key = "generate";
    };

    backfill = {
      enabled = true;
      max_initial_messages = 50;
      max_catchup_messages = 500;
    };

    provisioning.shared_secret = "disable";

    logging = {
      min_level = "info";
      writers = [
        {
          type = "stdout";
          format = "json";
        }
      ];
    };
  };
in
{
  config = lib.mkIf (cfg.enable && slack.enable) {
    serv.matrix.internal.slackConfigTemplate = configTemplate;

    users.users.mautrix-slack = {
      isSystemUser = true;
      group = "mautrix-slack";
      home = "/var/lib/mautrix-slack";
    };
    users.groups.mautrix-slack = { };

    systemd.services.mautrix-slack = {
      description = "mautrix-slack Matrix-Slack puppeting bridge";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [
        "network-online.target"
        "postgresql.service"
        "matrix-synapse.service"
        "matrix-appservice-tokens.service"
      ];
      requires = [
        "postgresql.service"
        "matrix-appservice-tokens.service"
      ];

      serviceConfig = {
        Type = "simple";
        User = "mautrix-slack";
        Group = "mautrix-slack";
        StateDirectory = "mautrix-slack";
        StateDirectoryMode = "0700";
        WorkingDirectory = "/var/lib/mautrix-slack";
        ExecStart = "${lib.getExe pkgs.mautrix-slack} --config ${cfg.internal.bridgeConfigFile} --no-update";

        Restart = "always";
        RestartSec = "30s";

        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        ProtectClock = true;
        ProtectHostname = true;
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
        ];
        # AF_NETLINK is required for the Go runtime to resolve names
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
          "AF_NETLINK"
        ];
      };
    };
  };
}
