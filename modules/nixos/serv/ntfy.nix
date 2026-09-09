{ config, lib, pkgs, ... }:

let
  cfg = config.serv.ntfy;

  secretsDir = "/var/lib/ntfy-secrets";
  envFile = "${secretsDir}/env";
  tokenFile = "${secretsDir}/publish.token";
  passwordFile = "${secretsDir}/${cfg.user}.password";

  listenAddress = "127.0.0.1:2586";

  # ntfy refuses hand-written tokens ("use 'ntfy token generate'"), and a
  # bcrypt hash cannot be derived at eval time, so both are minted on first
  # boot and handed to ntfy through an environment file. Nothing secret ends
  # up in the world-readable Nix store.
  provisionSecrets = pkgs.writeShellScript "ntfy-provision-secrets" ''
    set -euo pipefail

    install -d -m 0700 -o root -g root ${secretsDir}
    umask 077

    if [ ! -s ${passwordFile} ]; then
      openssl rand -base64 24 | tr -d '\n' > ${passwordFile}
    fi

    if [ ! -s ${tokenFile} ]; then
      ntfy token generate | tail -1 | tr -d '[:space:]' > ${tokenFile}
    fi

    password="$(cat ${passwordFile})"
    token="$(cat ${tokenFile})"
    hash="$(printf '%s\n%s\n' "$password" "$password" | ntfy user hash | tail -1)"

    # Single-quoted because a bcrypt hash is full of '$'; systemd strips the
    # quotes and hands the value through untouched.
    cat > ${envFile} <<EOF
    NTFY_AUTH_USERS='${cfg.user}:$hash:user'
    NTFY_AUTH_ACCESS='${cfg.user}:${cfg.topic}:rw'
    NTFY_AUTH_TOKENS='${cfg.user}:$token'
    EOF

    chmod 0600 ${envFile} ${tokenFile} ${passwordFile}
  '';

  showCredentials = pkgs.writeShellScriptBin "ntfy-phone-credentials" ''
    set -euo pipefail

    if [ "$(id -u)" -ne 0 ]; then
      echo "ntfy-phone-credentials must be run as root" >&2
      exit 1
    fi

    echo "Server:   https://${cfg.hostname}"
    echo "Topic:    ${cfg.topic}"
    echo "Username: ${cfg.user}"
    echo "Password: $(cat ${passwordFile})"
  '';
in
{
  options.serv.ntfy = {
    enable = lib.mkEnableOption "a self-hosted ntfy push server behind Caddy";

    hostname = lib.mkOption {
      type = lib.types.str;
      example = "ntfy.benmac.xyz";
      description = ''
        Public FQDN for the server. Must already resolve to this machine's
        public address, unproxied, before the first rebuild — Caddy requests a
        certificate on start-up and fails if the name does not reach it.
      '';
    };

    acmeEmail = lib.mkOption {
      type = lib.types.str;
      description = "Contact address Let's Encrypt uses for expiry notices.";
    };

    topic = lib.mkOption {
      type = lib.types.str;
      default = "mail";
      description = ''
        The single topic this server grants access to. Access is deny-all by
        default, so nothing can publish to or read any other topic.
      '';
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "phone";
      description = "Account the phone subscribes with, and that owns the publish token.";
    };

    internal.publishTokenFile = lib.mkOption {
      type = lib.types.str;
      internal = true;
      description = "Path to the generated publish token, for publishers on this host.";
    };

    internal.localPublishUrl = lib.mkOption {
      type = lib.types.str;
      internal = true;
      description = ''
        Topic URL for publishers running on this host. Deliberately loopback
        rather than the public name: this machine routes the VPS's public
        address down the WireGuard tunnel, and the VPS only DNATs traffic
        arriving on its ethernet interface, so the public URL is refused from
        here. Access control is unaffected — ntfy still requires the token.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    serv.ntfy.internal = {
      publishTokenFile = tokenFile;
      localPublishUrl = "http://${listenAddress}/${cfg.topic}";
    };

    environment.systemPackages = [ showCredentials ];

    systemd.services.ntfy-secrets = {
      description = "Mint ntfy credentials and render its environment file";
      wantedBy = [ "multi-user.target" ];
      before = [ "ntfy-sh.service" ]
        ++ lib.optional config.serv.youHaveMail.enable "you-have-mail-config.service";
      requiredBy = [ "ntfy-sh.service" ];
      path = with pkgs; [ coreutils openssl ntfy-sh ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = provisionSecrets;
      };
    };

    services.ntfy-sh = {
      enable = true;
      environmentFile = envFile;
      settings = {
        base-url = "https://${cfg.hostname}";
        listen-http = listenAddress;
        # Rate limits must key off the real client, not Caddy's loopback address.
        behind-proxy = true;
        auth-default-access = "deny-all";
      };
    };

    systemd.services.ntfy-sh.after = [ "ntfy-secrets.service" ];

    services.caddy = {
      enable = true;
      email = cfg.acmeEmail;

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

        reverse_proxy ${listenAddress}
      '';
    };

    networking.firewall.allowedTCPPorts = [ 443 ];
  };
}
