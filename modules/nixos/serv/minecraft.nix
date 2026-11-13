{ config, lib, pkgs, ... }:
let
  cfg = config.serv.minecraft;
  jvmArgs = pkgs.writeText "user_jvm_args.txt" ''
    -Xms${cfg.heap}
    -Xmx${cfg.heap}
    -XX:+UseG1GC
    -XX:+ParallelRefProcEnabled
    -XX:MaxGCPauseMillis=200
    -XX:+UnlockExperimentalVMOptions
    -XX:+DisableExplicitGC
    -XX:+AlwaysPreTouch
    -XX:G1NewSizePercent=30
    -XX:G1MaxNewSizePercent=40
    -XX:G1HeapRegionSize=8M
    -XX:G1ReservePercent=20
    -XX:G1HeapWastePercent=5
    -XX:G1MixedGCCountTarget=4
    -XX:InitiatingHeapOccupancyPercent=15
    -XX:G1MixedGCLiveThresholdPercent=90
    -XX:G1RSetUpdatingPauseTimePercent=5
    -XX:SurvivorRatio=32
    -XX:+PerfDisableSharedMem
    -XX:MaxTenuringThreshold=1
    -Xlog:gc*:file=logs/gc.log:time,uptime:filecount=5,filesize=20M
  '';
in
{
  options.serv.minecraft = {
    enable = lib.mkEnableOption "Enable Minecraft server";
    heap = lib.mkOption {
      type = lib.types.str;
      default = "8G";
      description = "Fixed JVM heap (-Xms and -Xmx). The host has 16 GB shared with Nextcloud, so heap plus ~2 GB JVM overhead must leave room for it.";
    };
    operators = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Users who may start, stop and restart minecraft-server without sudo, and whose ssh keys log in as sistermcserver. sshd's AllowUsers must list sistermcserver too.";
    };
  };
  config = lib.mkIf cfg.enable
    {
      users.users.sistermcserver = {
        isNormalUser = true;
        shell = pkgs.bash;
        group = "sistermcserver";
        description = "Minecraft server user";
        openssh.authorizedKeys.keys = lib.concatMap (u: config.users.users.${u}.openssh.authorizedKeys.keys) cfg.operators;
      };
      users.groups.sistermcserver = { };

      security.polkit.extraConfig = lib.mkIf (cfg.operators != [ ]) ''
        polkit.addRule(function (action, subject) {
          if (action.id == "org.freedesktop.systemd1.manage-units" &&
              action.lookup("unit") == "minecraft-server.service" &&
              ${builtins.toJSON cfg.operators}.indexOf(subject.user) >= 0) {
            return polkit.Result.YES;
          }
        });
      '';

      systemd.services.minecraft-server = {
        description = "Minecraft server in screen session";
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
        path = with pkgs; [
          jdk21
          udev
        ];
        environment = {
          JAVA_HOME = "${pkgs.jdk21.home}";
          LD_LIBRARY_PATH = lib.makeLibraryPath [ pkgs.udev ];
        };
        serviceConfig = {
          User = "sistermcserver";
          Group = "sistermcserver";
          WorkingDirectory = "/var/lib/mc/server";
          ExecStartPre = "${pkgs.coreutils}/bin/install -m 644 ${jvmArgs} /var/lib/mc/server/user_jvm_args.txt";
          ExecStart = "${pkgs.screen}/bin/screen -DmS minecraft ${pkgs.bash}/bin/bash /var/lib/mc/server/run.sh";
          Restart = "always";
          RestartSec = 10;
          TimeoutStopSec = 180;
          MemorySwapMax = 0;
          CPUWeight = 500;
          IOWeight = 500;
          UMask = "0002";
        };
      };
    };
}
