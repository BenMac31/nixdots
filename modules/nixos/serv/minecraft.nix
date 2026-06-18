{ config, lib, pkgs, ... }:
{
  options.serv.minecraft.enable = lib.mkEnableOption "Enable Minecraft server";
  config = lib.mkIf config.serv.minecraft.enable
    {
      users.users.sistermcserver = {
        isNormalUser = true;
        shell = pkgs.bash;
        group = "sistermcserver";
        description = "Minecraft server user";
      };
      users.groups.sistermcserver = { };

      systemd.services.minecraft-server = {
        description = "Minecraft server in screen session";
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          User = "sistermcserver";
          Group = "sistermcserver";
          WorkingDirectory = "/var/lib/mc/server";
          ExecStart = "${pkgs.screen}/bin/screen -DmS minecraft ${pkgs.bash}/bin/bash /var/lib/mc/server/run.sh";
          Restart = "always";
          RestartSec = 10;
        };
      };
    };
}
