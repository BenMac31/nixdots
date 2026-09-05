{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.serv.matrix;

  wellKnownServer = builtins.toJSON { "m.server" = "${cfg.hostName}:443"; };
  wellKnownClient = builtins.toJSON {
    "m.homeserver".base_url = "https://${cfg.hostName}";
    "org.matrix.msc3575.proxy".url = "https://${cfg.hostName}";
  };

  elementWeb = pkgs.element-web.override {
    conf = {
      default_server_config = {
        "m.homeserver" = {
          base_url = "https://${cfg.hostName}";
          server_name = cfg.serverName;
        };
      };
      brand = "Graphide Chat";
      disable_custom_urls = true;
      disable_guests = true;
      show_labs_settings = true;
      default_country_code = "US";
    };
  };
in
{
  config = lib.mkIf cfg.enable {
    services.caddy = {
      enable = true;
      email = cfg.acmeEmail;

      virtualHosts.${cfg.hostName}.extraConfig = ''
        encode zstd gzip

        header {
          Strict-Transport-Security "max-age=31536000; includeSubDomains"
          X-Content-Type-Options "nosniff"
          Referrer-Policy "same-origin"
        }

        handle /_matrix/* {
          request_body {
            max_size 100MB
          }
          reverse_proxy 127.0.0.1:8008
        }

        handle /_synapse/client/* {
          reverse_proxy 127.0.0.1:8008
        }

        handle /.well-known/matrix/server {
          header Content-Type application/json
          header Access-Control-Allow-Origin *
          respond `${wellKnownServer}` 200
        }

        handle /.well-known/matrix/client {
          header Content-Type application/json
          header Access-Control-Allow-Origin *
          respond `${wellKnownClient}` 200
        }

        handle {
          root * ${elementWeb}
          try_files {path} /index.html
          file_server
        }
      '';
    };

    networking.firewall.allowedTCPPorts = [
      80
      443
    ];
  };
}
