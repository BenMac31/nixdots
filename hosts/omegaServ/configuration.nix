{ config, lib, pkgs, inputs, ... }:

let
  upkgs = pkgs.unstable;
in
{
  imports =
    [
      ./hardware-configuration.nix
      ../../modules/nixos
    ];
  # services.home-assistant.enable = true;
  # services.mullvad-vpn.enable = true;
  serv = {
    enable = true;
    wireguard.enable = true;
    minecraft.enable = true;
    # media.enable = true;
    continuwuity = {
      enable = true;
      serverName = "chat.benmac.xyz";
      acmeEmail = "acme@benmac.xyz";
      dataDir = "/home/continuwuity";
    };
    mautrixBridges.enable = true;
    nextcloudAio = {
      enable = true;
      domain = "cloud.benmac.xyz";
      acmeEmail = "acme@benmac.xyz";
      timeZone = "America/New_York";
    };
    ntfy = {
      enable = true;
      hostname = "ntfy.benmac.xyz";
      acmeEmail = "acme@benmac.xyz";
      topic = "mail";
    };
    youHaveMail = {
      enable = true;
      # TODO: add the Proton address to watch, then run `you-have-mail-setup`.
      accounts = [ ];
      ntfy = [{
        name = "omegaServ";
        url = config.serv.ntfy.internal.localPublishUrl;
        authTokenFile = config.serv.ntfy.internal.publishTokenFile;
      }];
    };
  };
  services.openssh = {
    enable = true;
    ports = [ 23 ];
    settings = {
      PasswordAuthentication = false;
      AllowUsers = [ "carol" ];
      UseDns = true;
      X11Forwarding = false;
    };
  };

  networking.hostName = "omegaServ";
  custom.flakeAttr = "omegaServ";

  time.timeZone = lib.mkDefault "America/New_York";

  users.users.carol = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      ''ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQChQYMz+Q2dzTLTISmBlFHPUDRAzvupt3Sw/u2fpjZXjM3VLVU/VFq8gjmMMVVKTJBXUHwbdJiiNzvx0CobBYYXz5dMjV5Q3dubC2iikS70CX1M13n1yFzIebMsL8vTQaM/g5g0Sg9woAW8b74uWH5r6h6xmXOR7tfFi8m2tDmIllpRxXe49G9Hcmr4NQaHs3hb/A/31JTFjJDTvFqRN9BNUYgC4OR51FNFRsj2TZ8ecaYsSTcFioRG4jBYpU6URbFHLVrs3C5g9Fh8LKW6ISSd3G9XFnEYYXFAp0C8SiEZR02VYvU61N68IeDRikscjQ1JOm8r2HKGhi+Nv4Mc22qxPrpn4bg4jbAPzwms2OTX2rkI6ghZYhzXYOHzqszqe+J7bPXUdHmDLzXIb1mTNy9dAU1FY3UqbCUXb4Hqx0CjvTzbCE7R8ME537qfy0QkvtjLFek9Azh36iKzGnH7rVdmKQuzShVkYCnUqItPViamm7Py1Rbv1HPO7X4eIrsy2vc= greencheetah@fedora''
    ];
  };

  home-manager = {
    users."carol" = import ./home.nix;
  };
  system.stateVersion = "23.11"; # DO NOT CHANGE
  nix.settings.trusted-users = [ "root" "carol" ];
  virtualisation.docker.enable = true;
  virtualisation.docker.daemon.settings."data-root" = "/home/docker";
  # Minecraft (25565) and Simple Voice Chat (24454) are opened here rather than
  # in the minecraft module, so every port this host exposes is listed together.
  networking.firewall.allowedTCPPorts = [ 23 80 8080 25565 8443 3478 ];
  networking.firewall.allowedUDPPorts = [ 24454 ];
}
