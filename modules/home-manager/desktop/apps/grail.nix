{ config, lib, pkgs, inputs, ... }:
{
  # Graphide's mail and chat client (Proton mail, and iMessage, Discord,
  # WhatsApp and Matrix through the Matrix server), and grail-mcp, the
  # outbound tools agent sessions call. Its config stays by hand in
  # ~/.config/grail/config.toml: it names the keyring entries for passwords.
  options.grail.enable = lib.mkEnableOption "grail" // { default = config.graphide.enable; };

  config = lib.mkIf (config.desktop.enable && config.grail.enable) (let
    grail = inputs.graphide-tools.packages.${pkgs.stdenv.hostPlatform.system}.grail;
  in {
    # From graphide-tools, which the Graphide updater never moves. The
    # package carries its launcher entry and icon.
    home.packages = [ grail ];

    # The bug watch: a pass over new mail and chats every five minutes,
    # filing what the reader takes for a Graphide bug (grail/README.md,
    # "Bug watch"). Its settings are `[bug_watch]` in the config, whose key
    # commands run `nix shell`, hence the system's PATH.
    systemd.user.services.grail-bug-watch = {
      Unit.Description = "Read grail's new mail and chats for Graphide bugs";
      Service = {
        Type = "oneshot";
        ExecStart = "${grail}/bin/grail-mcp bug-watch";
        Environment = [ "PATH=/run/current-system/sw/bin:/etc/profiles/per-user/${config.home.username}/bin" ];
      };
    };
    systemd.user.timers.grail-bug-watch = {
      Unit.Description = "Read grail's new mail and chats for Graphide bugs every five minutes";
      Timer = {
        OnCalendar = "*:2/5";
        Persistent = true;
      };
      Install.WantedBy = [ "timers.target" ];
    };

    # Sends the outbound emails grail scheduled (outside sending hours or
    # over the day's cap) once they fall due, catching up after sleep
    # (grail/README.md, `grail-mcp send-due`). Without it a
    # scheduled email never goes.
    systemd.user.services.grail-send-due = {
      Unit.Description = "Send grail's due scheduled emails";
      Service = {
        Type = "oneshot";
        ExecStart = "${grail}/bin/grail-mcp send-due";
        Environment = [ "PATH=/run/current-system/sw/bin:/etc/profiles/per-user/${config.home.username}/bin" ];
      };
    };
    systemd.user.timers.grail-send-due = {
      Unit.Description = "Check grail's scheduled emails every five minutes";
      Timer = {
        OnCalendar = "*:0/5";
        Persistent = true;
      };
      Install.WantedBy = [ "timers.target" ];
    };
  });
}
