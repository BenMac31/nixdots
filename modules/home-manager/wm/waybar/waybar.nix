{ pkgs, ... }:
{
  programs.waybar = {
    enable = true;
    systemd.enable = true;
    systemd.target = "graphical-session.target";

    settings = [
      {
        layer = "top";
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

    style = builtins.readFile (./. + "/style.css");
  };
}
