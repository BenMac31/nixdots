{ lib, config, ... }:
let
  cfg = config.serv.matrix;
in
{
  options.serv.matrix = {
    enable = lib.mkEnableOption "the Matrix homeserver stack";

    hostName = lib.mkOption {
      type = lib.types.str;
      example = "matrix.graphide.net";
      description = ''
        Public DNS name of this machine. TLS is obtained for this name and all
        HTTP endpoints are served from it.
      '';
    };

    serverName = lib.mkOption {
      type = lib.types.str;
      default = cfg.hostName;
      defaultText = lib.literalExpression "config.serv.matrix.hostName";
      description = ''
        Synapse `server_name`: the part after the colon in every user ID. It is
        baked into every event the server has signed, so it cannot change after
        the first start.

        Leaving it equal to {option}`hostName` means no delegation is needed.
      '';
    };

    admins = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "ben" ];
      description = ''
        Localparts of accounts that get bridge admin rights. These still have to
        be created once with `matrix-synapse-register_new_matrix_user`.
      '';
    };

    acmeEmail = lib.mkOption {
      type = lib.types.str;
      description = "Contact address Let's Encrypt uses for expiry warnings.";
    };

    encryption = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Enable end-to-bridge encryption so the bridge can join encrypted rooms.
        '';
      };
    };

    slack = {
      enable = lib.mkEnableOption "the mautrix-slack bridge" // {
        default = true;
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 29335;
        description = "Loopback port the bridge's appservice listener binds to.";
      };

      appserviceId = lib.mkOption {
        type = lib.types.str;
        default = "slack";
        description = "Appservice ID. Must be stable once registered with Synapse.";
      };

      usernamePrefix = lib.mkOption {
        type = lib.types.str;
        default = "slack_";
        description = ''
          Localpart prefix for Slack ghost users. Changing it orphans every ghost
          the bridge has already created.
        '';
      };

      botLocalpart = lib.mkOption {
        type = lib.types.str;
        default = "slackbot";
        description = "Localpart of the bridge's management bot.";
      };
    };

    backup = {
      enable = lib.mkEnableOption "nightly restic backups of Synapse and the bridge";

      repository = lib.mkOption {
        type = lib.types.str;
        example = "s3:s3.us-west-004.backblazeb2.com/graphide-matrix-backup";
        description = "Restic repository URL.";
      };

      environmentFile = lib.mkOption {
        type = lib.types.path;
        example = "/var/lib/matrix-secrets/restic.env";
        description = ''
          File holding the repository credentials as environment variables, e.g.
          `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`. Create it out of band with
          mode 0600; it is never copied into the store.
        '';
      };

      passwordFile = lib.mkOption {
        type = lib.types.path;
        example = "/var/lib/matrix-secrets/restic.password";
        description = "File holding the restic repository password.";
      };
    };
  };
}
