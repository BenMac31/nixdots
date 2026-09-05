{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.serv.matrix;
  backup = cfg.backup;

  dumpDir = "/var/lib/matrix-backup";

  dumpScript = pkgs.writeShellApplication {
    name = "matrix-backup-dump";
    runtimeInputs = [
      pkgs.postgresql
      pkgs.coreutils
      pkgs.util-linux
      pkgs.gnugrep
    ];
    text = ''
      install -d -m 0700 "${dumpDir}"
      for db in matrix-synapse mautrix-slack; do
        if runuser -u postgres -- psql -lqt | cut -d'|' -f1 | grep -qw "$db"; then
          runuser -u postgres -- pg_dump --format=custom "$db" > "${dumpDir}/$db.dump"
        fi
      done
    '';
  };
in
{
  config = lib.mkIf (cfg.enable && backup.enable) {
    services.restic.backups.matrix = {
      initialize = true;
      repository = backup.repository;
      environmentFile = backup.environmentFile;
      passwordFile = backup.passwordFile;

      backupPrepareCommand = "${lib.getExe dumpScript}";

      paths = [
        dumpDir
        "${config.services.matrix-synapse.dataDir}/media_store"
        "/var/lib/matrix-secrets"
      ];

      timerConfig = {
        OnCalendar = "03:15";
        RandomizedDelaySec = "30m";
        Persistent = true;
      };

      pruneOpts = [
        "--keep-daily 7"
        "--keep-weekly 5"
        "--keep-monthly 12"
      ];
    };

    systemd.tmpfiles.rules = [
      "d ${dumpDir} 0700 root root -"
    ];
  };
}
