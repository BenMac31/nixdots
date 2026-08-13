{ config, lib, pkgs, flakeAttr, ... }:
{
  options.startpage.enable = lib.mkEnableOption "startpage" // { default = true; };

  config = lib.mkIf (config.desktop.enable && config.startpage.enable && flakeAttr == "nixWorks") {
    xdg.configFile."startpage" = {
      source = config.lib.file.mkOutOfStoreSymlink
        "${config.home.homeDirectory}/nixos/confs/startpage";
    };

    programs.librewolf.profiles.default.settings = {
      "browser.startup.homepage" =
        "file:///home/${config.home.username}/.config/startpage/index.html";
    };

    # HTTP bridge: proxies waybar-module-pomodoro over localhost:9421
    # so the startpage can toggle/poll it without native messaging.
    systemd.user.services.pomo-bridge = {
      Unit = {
        Description = "HTTP bridge for waybar-module-pomodoro";
        After       = [ "graphical-session.target" ];
        PartOf      = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = lib.concatStringsSep " " [
          "${pkgs.python3}/bin/python3"
          "%h/.config/startpage/pomo-bridge.py"
          "${pkgs.waybar-pomodoro}/bin/waybar-module-pomodoro"
        ];
        Restart    = "on-failure";
        RestartSec = "3s";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
