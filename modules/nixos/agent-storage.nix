{ config, lib, pkgs, ... }:
let
  cfg = config.services.agentStorage;
  prepare = pkgs.writeShellScript "agent-storage-prepare" ''
    export PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.e2fsprogs pkgs.util-linux ]}
    exec ${pkgs.python3}/bin/python3 ${./agent-storage.py} \
      --image ${lib.escapeShellArg cfg.image} \
      --bulk ${lib.escapeShellArg cfg.bulkPath} \
      --output ${lib.escapeShellArg cfg.outputPath} \
      --size-gib ${toString cfg.sizeGiB} --output-gib ${toString cfg.outputGiB} \
      --uid "$(${pkgs.coreutils}/bin/id -u ${lib.escapeShellArg cfg.user})" \
      --gid "$(${pkgs.coreutils}/bin/id -g ${lib.escapeShellArg cfg.user})"
  '';
in {
  options.services.agentStorage = {
    enable = lib.mkEnableOption "bounded agent temporary storage with a protected output reserve";
    user = lib.mkOption { type = lib.types.str; default = "greencheetah"; };
    image = lib.mkOption {
      type = lib.types.str;
      default = "/home/${cfg.user}/.local/share/agent-scratch/store/scratch.img";
    };
    bulkPath = lib.mkOption { type = lib.types.str; default = "/var/lib/agent-scratch"; };
    outputPath = lib.mkOption { type = lib.types.str; default = "/var/lib/agent-output"; };
    sizeGiB = lib.mkOption { type = lib.types.ints.positive; default = 128; };
    outputGiB = lib.mkOption { type = lib.types.ints.positive; default = 8; };
    prepareCommand = lib.mkOption { type = lib.types.path; readOnly = true; default = prepare; };
  };
  config = lib.mkMerge [{
    system.preSwitchChecks.agentStorageMounts = ''
      ${pkgs.python3}/bin/python3 ${./agent-storage-switch-check.py} "$1" "$2"
    '';
    # A targeted live installation yields to the normal generated units on activation.
    system.activationScripts.agentStorageBootstrap = lib.stringAfter [ "etc" ] ''
      capacity_override=/etc/systemd/system.control/agent-storage.service.d/60-capacity.conf
      if [ -f "$capacity_override" ] && [ "$(head -n 1 "$capacity_override")" = '# agent-storage capacity bootstrap' ]; then
        rm -f "$capacity_override" /nix/var/nix/gcroots/agent-storage-capacity
      fi
      for unit in agent-storage.service tmp.mount var-tmp.mount local-fs.target.d/90-agent-storage.conf disk-guard.service.d/99-agent-storage.conf; do
        path="/etc/systemd/system.control/$unit"
        if [ -f "$path" ] && [ "$(head -n 1 "$path")" = '# agent-storage bootstrap' ]; then
          rm -f "$path"
        fi
      done
    '';
  } (lib.mkIf cfg.enable {
    system.switch.inhibitors.agent-storage-layout = builtins.toJSON {
      inherit (cfg) image bulkPath outputPath user;
    };
    assertions = [{
      assertion = cfg.outputGiB + 8 < cfg.sizeGiB;
      message = "The agent output reserve must leave bulk scratch space.";
    }];
    boot.tmp.useTmpfs = lib.mkForce false;
    systemd.services.agent-storage = {
      description = "Mount capped agent storage without stopping existing sessions";
      # Stopping this provider stops /tmp and /var/tmp, taking D-Bus and basic.target with them.
      restartIfChanged = false;
      unitConfig = {
        DefaultDependencies = false;
        RequiresMountsFor = [ cfg.image ];
      };
      after = [ "systemd-remount-fs.service" ];
      before = [ "tmp.mount" "var-tmp.mount" ];
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; ExecStart = prepare; TimeoutStartSec = "10min"; };
      wantedBy = [ "local-fs.target" ];
    };
    fileSystems = lib.genAttrs [ "/tmp" "/var/tmp" ] (path: {
      device = "${cfg.bulkPath}/${if path == "/tmp" then "tmp" else "var-tmp"}";
      fsType = "none";
      options = [ "bind" "x-systemd.requires=agent-storage.service" "x-systemd.after=agent-storage.service" ];
    });
  })];
}
