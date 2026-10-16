{ config, lib, pkgs, ... }:
{
  options = {
    ubuntuVm = {
      enable = lib.mkEnableOption "Enable the ubuntu-vm KVM guest launcher";
    };
  };
  config = lib.mkIf config.ubuntuVm.enable {
    home.packages = [ pkgs.ubuntu-vm ];

    # `ssh ubuntu-vm` and scp/rsync to it, once `ubuntu-vm start` is up.
    programs.ssh.matchBlocks.ubuntu-vm = {
      hostname = "127.0.0.1";
      port = 2222;
      user = "ubuntu";
      identityFile = "~/.local/share/vms/ubuntu/id_ed25519";
      extraOptions.UserKnownHostsFile = "~/.local/share/vms/ubuntu/known_hosts";
    };
  };
}
