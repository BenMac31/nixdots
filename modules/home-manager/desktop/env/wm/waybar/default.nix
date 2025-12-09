{ pkgs, config, ... }:
{
  home.packages = [
    pkgs.waybar-pomodoro
  ];
  programs.waybar = {
    systemd.enable = true;
    systemd.target = "graphical-session.target";

    settings = [
      {
        layer = "top";
        outputs = [ "eDP-1" ];
        position = "top";
        mod = "dock";
        height = 40;
        exclusive = true;
        passthrough = false;
        gtk-layer-shell = true;

        modules-left = [
          "custom/left"
          "custom/rofi"
          "backlight"
          "pulseaudio"
          "battery"
          "custom/right"
        ];
        modules-center = [
          "custom/left"
          "hyprland/workspaces"
          "custom/right"
        ];
        modules-right = [
          "custom/left"
          "tray"
          "mpris"
          "custom/pomodoro"
          "clock"
          "custom/right"
        ];

        # Network Module
        network = {
          tooltip = true;
          format-wifi = "<span foreground='#FF8B49'> {bandwidthDownBytes}</span> <span foreground='#FF6962'> {bandwidthUpBytes}</span>";
          format-ethernet = "<span foreground='#FF8B49'> {bandwidthDownBytes}</span> <span foreground='#FF6962'> {bandwidthUpBytes}</span>";
          tooltip-format = "Network: <big><b>{essid}</b></big>\nSignal strength: <b>{signaldBm}dBm ({signalStrength}%)</b>\nFrequency: <b>{frequency}MHz</b>\nInterface: <b>{ifname}</b>\nIP: <b>{ipaddr}/{cidr}</b>\nGateway: <b>{gwaddr}</b>\nNetmask: <b>{netmask}</b>";
          format-linked = "󰈀 {ifname} (No IP)";
          format-disconnected = "󰖪";
          tooltip-format-disconnected = "Disconnected";
          interval = 2;
          on-click-right = "~/.config/waybar/network.py";
        };

        # Temperature Module
        temperature = {
          format = "{temperatureC}°C ";
        };

        # Custom Rofi Launcher
        "custom/rofi" = {
          format = "  {}";
          on-click = "rofi -show drun";
        };

        # Workspaces
        "hyprland/workspaces" = {
          format = "{icon}";
          disable-scroll = true;
          on-click = "activate";
          all-outputs = true;
          format-icons = {
            "1" = "󰖟";
            "2" = "";
            "5" = "";
            "6" = "󰝚";
            "8" = "󰮂";
            "urgent" = "";
          };
          sort-by-number = true;
        };

        # Battery Module
        battery = {
          states = {
            good = 95;
            warning = 30;
            critical = 20;
            "Fuck off Switch off" = 10;
          };
          format = "{icon} {capacity}%";
          format-charging = " {capacity}%";
          format-plugged = " {capacity}%";
          format-alt = "{time} {icon}";
          format-icons = [
            "󰂎"
            "󰁺"
            "󰁻"
            "󰁼"
            "󰁽"
            "󰁾"
            "󰁿"
            "󰂀"
            "󰂁"
            "󰂂"
            "󰁹"
          ];
        };

        # PulseAudio Module
        pulseaudio = {
          format = "{icon} {volume}";
          format-muted = "󰖁";
          on-click = "pavucontrol -t 3";
          on-click-middle = "~/.config/hypr/scripts/volumecontrol.sh -o m";
          on-scroll-up = "~/.config/hypr/scripts/volumecontrol.sh -o i";
          on-scroll-down = "~/.config/hypr/scripts/volumecontrol.sh -o d";
          tooltip-format = "{icon} {desc} // {volume}%";
          scroll-step = 5;
          format-icons = {
            headphone = "";
            hands-free = "";
            headset = "";
            phone = "";
            portable = "";
            car = "";
            default = [
              ""
              ""
              ""
            ];
          };
        };

        # Tray Module
        tray = {
          icon-size = 20;
          spacing = 9;
        };

        # Clock Module
        clock = {
          format = " {:%H:%M}";
          on-click = "~/.config/eww/scripts/toggle_control_center.sh";
        };

        mpris = {
          format = "{player_icon} {dynamic}";
          format-paused = "{status icon} <i>{dynamic}</i>";
          player-icons = {
            "default" = "▶";
            "mpv" = "🎵";
          };
          status-icons = {
            "paused" = "⏸";
          };
          dynamic-len = 48;
          dynamic-order = [
            "artist"
            "title"
            "album"
          ];
        };

        "custom/pomodoro" = {
          format = "{}";
          return-type = "json";
          exec = "waybar-module-pomodoro";
          on-click = "waybar-module-pomodoro toggle";
          on-click-right = "waybar-module-pomodoro reset";
        };

        # Backlight Module
        backlight = {
          device = "intel_backlight";
          on-scroll-up = "light -A 7";
          on-scroll-down = "light -U 7";
          format = "{icon} {percent}%";
          format-icons = [
            "󰃞"
            "󰃟"
            "󰃠"
            "󱩎"
            "󱩏"
            "󱩐"
            "󱩑"
            "󱩒"
            "󱩓"
            "󰛨"
          ];
        };

        # Padding Custom Modules
        "custom/left" = {
          format = " ";
          interval = "once";
          tooltip = false;
        };

        "custom/right" = {
          format = " ";
          interval = "once";
          tooltip = false;
        };
      }
    ];

    style = with config.colorScheme.palette; /* css */ ''
      @define-color base00 #${base00};
      @define-color base01 #${base01};
      @define-color base02 #${base02};
      @define-color base03 #${base03};
      @define-color base04 #${base04};
      @define-color base05 #${base05};
      @define-color base06 #${base06};
      @define-color base07 #${base07};
      @define-color base08 #${base08};
      @define-color base09 #${base09};
      @define-color base0A #${base0A};
      @define-color base0B #${base0B};
      @define-color base0C #${base0C};
      @define-color base0D #${base0D};
      @define-color base0E #${base0E};
      @define-color base0F #${base0F};
      ${builtins.readFile (./. + "/style.css")}
    '';
  };
}
