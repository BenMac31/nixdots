{
  lib,
  config,
  pkgs,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/serv
  ];

  serv.matrix = {
    enable = true;

    hostName = "matrix.graphide.net";

    acmeEmail = "matrix@graphide.net";

    admins = [ "ben" ];

    encryption.enable = true;

    slack.enable = true;

    backup = {
      enable = false;
      repository = "s3:s3.us-west-004.backblazeb2.com/graphide-matrix-backup";
      environmentFile = "/var/lib/matrix-secrets/restic.env";
      passwordFile = "/var/lib/matrix-secrets/restic.password";
    };
  };

  networking.hostName = "matrixServ";
  networking.domain = "graphide.net";

  time.timeZone = "UTC";

  services.openssh.settings.PasswordAuthentication = false;

  users.users.root.openssh.authorizedKeys.keys = [
    # graphide-prod-azure: deploy/admin key for the graphide-prod resource group
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHbSeEFeBiVuZ+LgNtQRfUtsQDh2yyAB/S6tF1H5Wwqx graphide-prod-azure"
  ];

  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 ];

  system.autoUpgrade = {
    enable = false;
    flake = "github:BenMac31/nixdots#matrixServ";
    flags = [ "--refresh" ];
    dates = "04:30";
    randomizedDelaySec = "45min";
    allowReboot = true;
    rebootWindow = {
      lower = "04:00";
      upper = "06:00";
    };
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };
  nix.settings = {
    auto-optimise-store = true;
    experimental-features = [
      "nix-command"
      "flakes"
    ];
  };

  zramSwap.enable = true;
  swapDevices = [
    {
      device = "/swapfile";
      size = 2048;
    }
  ];

  environment.systemPackages = with pkgs; [
    git
    htop
    postgresql
    restic
  ];

  system.stateVersion = "26.05";
}
