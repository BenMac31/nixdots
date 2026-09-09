{ config, lib, ... }:

let
  cfg = config.serv.continuwuity;
  listenAddress = "127.0.0.1:${toString cfg.port}";
in
{
  options.serv.continuwuity = {
    enable = lib.mkEnableOption "the continuwuity Matrix homeserver";

    serverName = lib.mkOption {
      type = lib.types.str;
      default = "chat.benmac.xyz";
      description = ''
        The Matrix domain. Every user and room id in the database carries it as
        a suffix, so it cannot be changed after the first start without
        orphaning all of them.
      '';
    };

    hostname = lib.mkOption {
      type = lib.types.str;
      default = cfg.serverName;
      defaultText = lib.literalExpression "config.serv.continuwuity.serverName";
      description = "Public FQDN Caddy obtains a certificate for.";
    };

    acmeEmail = lib.mkOption {
      type = lib.types.str;
      description = "Address ACME registers the certificate under.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 6167;
      description = "Loopback port the homeserver listens on; only Caddy reaches it.";
    };

    dataDir = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/home/continuwuity";
      description = ''
        Directory the database is bind-mounted onto, for hosts whose root
        filesystem is too small to hold it. Null leaves it in
        /var/lib/continuwuity. Upstream pins `database_path` read-only to that
        location, so a bind mount is the only way to relocate it.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.matrix-continuwuity = {
      enable = true;

      settings.global = {
        server_name = cfg.serverName;
        address = [ "127.0.0.1" ];
        port = [ cfg.port ];

        allow_registration = false;
        allow_federation = true;
        trusted_servers = [ "matrix.org" ];
        max_request_size = 50000000;

        well_known = {
          client = "https://${cfg.hostname}";
          server = "${cfg.hostname}:443";
        };
      };
    };

    services.caddy = {
      enable = true;

      # mkDefault so this can coexist with serv.ntfy, which sets email outright.
      email = lib.mkDefault cfg.acmeEmail;

      # Port 80 is not forwarded to this host, so the HTTP-01 challenge cannot
      # succeed; TLS-ALPN-01 rides the 443 forward that already exists.
      virtualHosts.${cfg.hostname}.extraConfig = ''
        encode zstd gzip

        tls {
          issuer acme {
            disable_http_challenge
          }
        }

        header {
          Strict-Transport-Security "max-age=31536000; includeSubDomains"
          X-Content-Type-Options "nosniff"
          Referrer-Policy "same-origin"
        }

        handle /_matrix/* {
          request_body {
            max_size 50MB
          }
          reverse_proxy ${listenAddress}
        }

        handle /.well-known/matrix/* {
          reverse_proxy ${listenAddress}
        }
      '';
    };

    networking.firewall.allowedTCPPorts = [ 443 ];

    # database_path is readOnly upstream, pinned to the systemd StateDirectory,
    # so relocating the database off the root filesystem needs a bind mount.
    # DynamicUser makes /var/lib/continuwuity a symlink, hence the private path.
    systemd.tmpfiles.rules = lib.mkIf (cfg.dataDir != null) [
      "d ${cfg.dataDir} 0700 root root -"
      "d /var/lib/private 0700 root root -"
      "d /var/lib/private/continuwuity 0700 root root -"
    ];

    # Deliberately systemd.mounts and not fileSystems: a fileSystems entry is
    # boot-critical, so a failure here would fail local-fs.target and drop the
    # whole machine to emergency mode with no sshd. RequiresMountsFor on the
    # service below pulls this in and confines a failure to continuwuity.
    systemd.mounts = lib.mkIf (cfg.dataDir != null) [
      {
        what = cfg.dataDir;
        where = "/var/lib/private/continuwuity";
        type = "none";
        options = "bind";
        unitConfig.RequiresMountsFor = cfg.dataDir;
      }
    ];

    systemd.services.continuwuity.unitConfig = lib.mkIf (cfg.dataDir != null) {
      RequiresMountsFor = "/var/lib/private/continuwuity";
    };
  };
}
