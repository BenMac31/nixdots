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
  };
  config = lib.mkIf cfg.enable
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
        };
      };
    };
}
