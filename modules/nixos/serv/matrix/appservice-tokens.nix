{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.serv.matrix;
  slack = cfg.slack;

  secretsDir = "/var/lib/matrix-secrets";
  synapseDir = config.services.matrix-synapse.dataDir;

  registrationFile = "${synapseDir}/appservices/${slack.appserviceId}.yaml";
  sharedSecretFile = "${synapseDir}/registration-shared-secret";
  bridgeConfigFile = "/var/lib/mautrix-slack/config.yaml";

  escapedDomain = lib.replaceStrings [ "." ] [ "\\." ] cfg.serverName;

  registrationTemplate = pkgs.writeText "${slack.appserviceId}-registration.yaml" ''
    id: ${slack.appserviceId}
    url: http://127.0.0.1:${toString slack.port}
    as_token: "@AS_TOKEN@"
    hs_token: "@HS_TOKEN@"
    sender_localpart: "@SENDER_LOCALPART@"
    rate_limited: false
    namespaces:
      users:
        # single quotes: YAML double-quoted scalars treat \ as an escape
        - regex: '^@${slack.botLocalpart}:${escapedDomain}$'
          exclusive: true
        - regex: '^@${slack.usernamePrefix}.*:${escapedDomain}$'
          exclusive: true
        # non-exclusive catch-all enables double puppeting
        - regex: '^@.*:${escapedDomain}$'
          exclusive: false
    de.sorunome.msc2409.push_ephemeral: true
    receive_ephemeral: true
  '';
in
{
  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${secretsDir} 0700 root root -"
    ];

    systemd.services.matrix-appservice-tokens = {
      description = "Generate Matrix appservice tokens and registration files";
      wantedBy = [ "multi-user.target" ];
      before = [
        "matrix-synapse.service"
        "mautrix-slack.service"
      ];
      requiredBy = [ "matrix-synapse.service" ];
      path = with pkgs; [
        coreutils
        openssl
        gnused
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -euo pipefail

        install -d -m 0700 -o root -g root ${secretsDir}

        gen_secret() {
          local f="${secretsDir}/$1"
          if [ ! -s "$f" ]; then
            ( umask 077; openssl rand -hex 32 > "$f" )
          fi
          chmod 0600 "$f"
          cat "$f"
        }

        as_token="$(gen_secret slack.as_token)"
        hs_token="$(gen_secret slack.hs_token)"
        sender_localpart="$(gen_secret slack.sender_localpart)"
        gen_secret synapse.registration_shared_secret > /dev/null

        install -d -m 0700 -o matrix-synapse -g matrix-synapse ${synapseDir}
        install -d -m 0700 -o matrix-synapse -g matrix-synapse ${synapseDir}/appservices

        install -m 0400 -o matrix-synapse -g matrix-synapse \
          ${secretsDir}/synapse.registration_shared_secret ${sharedSecretFile}

        umask 077
        tmp="$(mktemp)"
        trap 'rm -f "$tmp"' EXIT

        sed -e "s|@AS_TOKEN@|$as_token|g" \
            -e "s|@HS_TOKEN@|$hs_token|g" \
            -e "s|@SENDER_LOCALPART@|$sender_localpart|g" \
            ${registrationTemplate} > "$tmp"
        install -m 0400 -o matrix-synapse -g matrix-synapse "$tmp" ${registrationFile}

      ''
      + lib.optionalString slack.enable ''
        install -d -m 0700 -o mautrix-slack -g mautrix-slack /var/lib/mautrix-slack

        sed -e "s|@DOUBLE_PUPPET_SECRET@|as_token:$as_token|g" \
            -e "s|@AS_TOKEN@|$as_token|g" \
            -e "s|@HS_TOKEN@|$hs_token|g" \
            ${config.serv.matrix.internal.slackConfigTemplate} > "$tmp"
        install -m 0400 -o mautrix-slack -g mautrix-slack "$tmp" ${bridgeConfigFile}
      '';
    };

    serv.matrix.internal = {
      inherit registrationFile sharedSecretFile bridgeConfigFile;
    };
  };

  options.serv.matrix.internal = {
    registrationFile = lib.mkOption {
      type = lib.types.str;
      internal = true;
    };
    sharedSecretFile = lib.mkOption {
      type = lib.types.str;
      internal = true;
    };
    bridgeConfigFile = lib.mkOption {
      type = lib.types.str;
      internal = true;
    };
    slackConfigTemplate = lib.mkOption {
      type = lib.types.path;
      internal = true;
    };
  };
}
