{
  nixpkgs,
  system,
  nixpkgsConfig,
}:
(import (nixpkgs + "/nixos/lib/testing-python.nix") { inherit system; }).makeTest {
  name = "graphide-matrix";

  nodes.machine =
    { lib, pkgs, ... }:
    {
      imports = [ ../modules/nixos/serv/matrix ];

      nixpkgs.config = nixpkgsConfig;

      virtualisation = {
        memorySize = 3072;
        diskSize = 6144;
        cores = 2;
      };

      serv.matrix = {
        enable = true;
        hostName = "matrix.test";
        acmeEmail = "test@matrix.test";
        admins = [ "ben" ];
        encryption.enable = true;
        slack.enable = true;
      };

      services.caddy.enable = lib.mkForce false;

      environment.systemPackages = [
        pkgs.curl
        pkgs.jq
      ];
    };

  testScript = ''
    machine.start()

    with subtest("tokens and registration are generated"):
        machine.wait_for_unit("matrix-appservice-tokens.service")
        machine.succeed("test -s /var/lib/matrix-secrets/slack.as_token")
        machine.succeed("test -s /var/lib/matrix-synapse/appservices/slack.yaml")
        machine.succeed(
            "test \"$(stat -c %U /var/lib/matrix-synapse/appservices/slack.yaml)\" = matrix-synapse"
        )

    with subtest("synapse accepts the appservice registration and starts"):
        machine.wait_for_unit("matrix-synapse.service")
        machine.wait_for_open_port(8008)
        machine.succeed("curl -sf http://127.0.0.1:8008/_matrix/client/versions")

    with subtest("accounts can be created with the generated shared secret"):
        machine.succeed(
            "matrix-synapse-register_new_matrix_user -u ben -p sixteencharacters! -a"
        )

    with subtest("the as_token may masquerade as a local user (double puppeting)"):
        as_token = machine.succeed("cat /var/lib/matrix-secrets/slack.as_token").strip()
        whoami = machine.succeed(
            f"curl -sf -H 'Authorization: Bearer {as_token}' "
            "'http://127.0.0.1:8008/_matrix/client/v3/account/whoami"
            "?user_id=%40ben%3Amatrix.test'"
        )
        assert '"@ben:matrix.test"' in whoami, f"masquerade rejected: {whoami}"

    with subtest("the bridge connects to the homeserver"):
        machine.wait_for_unit("mautrix-slack.service")
        machine.wait_until_succeeds(
            "journalctl -u mautrix-slack --no-pager | grep -qi 'bridge started'", timeout=120
        )
        machine.succeed("systemctl is-active mautrix-slack")

    with subtest("the bridge bot exists on the homeserver"):
        as_token = machine.succeed("cat /var/lib/matrix-secrets/slack.as_token").strip()
        machine.succeed(
            f"curl -sf -H 'Authorization: Bearer {as_token}' "
            "'http://127.0.0.1:8008/_matrix/client/v3/profile/%40slackbot%3Amatrix.test'"
        )
  '';
}
