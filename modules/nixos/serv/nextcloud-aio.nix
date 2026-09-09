{ config, lib, ... }:

let
  cfg = config.serv.nextcloudAio;
in
{
  options.serv.nextcloudAio = {
    enable = lib.mkEnableOption "the Nextcloud All-in-One mastercontainer";

    domain = lib.mkOption {
      type = lib.types.str;
      example = "cloud.example.com";
      description = ''
        Public FQDN. AIO persists this in its own configuration; changing it
        makes AIO re-run domain validation.
      '';
    };

    acmeEmail = lib.mkOption {
      type = lib.types.str;
      description = "Address ACME registers the certificate under.";
    };

    apachePort = lib.mkOption {
      type = lib.types.port;
      default = 11000;
      description = ''
        Loopback port AIO's apache container listens on; only Caddy reaches it.
      '';
    };

    adminPort = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "AIO's own admin interface, reachable on the LAN.";
    };

    timeZone = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = config.time.timeZone;
      defaultText = lib.literalExpression "config.time.timeZone";
      description = ''
        Timezone passed to the mastercontainer. Null omits TZ entirely, leaving
        the timezone AIO has already persisted — which is what the default
        resolves to on hosts running services.automatic-timezoned, since that
        forces time.timeZone to null.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.oci-containers = {
      backend = "docker";

      # AIO finds itself by container name over the Docker socket, and
      # oci-containers takes that name from this attribute.
      containers.nextcloud-aio-mastercontainer = {
        image = "nextcloud/all-in-one:latest";
        ports = [ "${toString cfg.adminPort}:8080" ];
        volumes = [
          "nextcloud_aio_mastercontainer:/mnt/docker-aio-config"
          "/var/run/docker.sock:/var/run/docker.sock:ro"
        ];
        environment = {
          APACHE_PORT = toString cfg.apachePort;
          APACHE_IP_BINDING = "127.0.0.1";
        } // lib.optionalAttrs (cfg.timeZone != null) {
          TZ = cfg.timeZone;
        };
        extraOptions = [ "--init" ];
      };
    };

    services.caddy = {
      enable = true;
      email = lib.mkDefault cfg.acmeEmail;

      # Port 80 is not forwarded to this host, so the HTTP-01 challenge cannot
      # succeed; TLS-ALPN-01 rides the 443 forward that already exists.
      virtualHosts.${cfg.domain}.extraConfig = ''
        encode zstd gzip

        tls {
          issuer acme {
            disable_http_challenge
          }
        }

        header {
          Strict-Transport-Security "max-age=31536000; includeSubDomains"
        }

        reverse_proxy 127.0.0.1:${toString cfg.apachePort}
      '';
    };

    networking.firewall = {
      allowedTCPPorts = [ 443 cfg.adminPort 3478 ];
      allowedUDPPorts = [ 3478 ];
    };
  };
}
