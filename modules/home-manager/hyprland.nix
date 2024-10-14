{pkgs,lib,inputs,config,...}:

let
playerctl = "${pkgs.playerctl}/bin/playerctl";
brightnessctl = "${pkgs.brightnessctl}/bin/brightnessctl";
pactl = "${pkgs.pulseaudio}/bin/pactl";
in {
  xdg = {
    desktopEntries."org.gnome.Settings" = {
      name = "Settings";
      comment = "Gnome Control Center";
      icon = "org.gnome.Settings";
      exec = "env XDG_CURRENT_DESKTOP=gnome ${pkgs.gnome.gnome-control-center}/bin/gnome-control-center";
      categories = [ "X-Preferences" ];
      terminal = false;
    };
  };
  home.sessionVariables = {
    WLR_NO_HARDWARE_CURSORS = "1";
    XCURSOR_SIZE = "48";
    NIXOS_OZONE_WL = "1";
  };
  home.packages = [ #
    pkgs.swww
    pkgs.wluma
    pkgs.wlr-randr
    pkgs.networkmanagerapplet
    (pkgs.writeShellScriptBin "devbright" ''
     val=$(${brightnessctl} get)
     max=$(${brightnessctl} max)
     h="$(printf "%02x\n" "$val")"
     ${pkgs.polychromatic}/bin/polychromatic-cli -d laptop -o brightness -p "$((val*100/max))" &
     mice=$(${pkgs.libratbag}/bin/ratbagctl | ${pkgs.coreutils-full}/bin/cut -d: -f1)
     if [[ -n $mice ]]; then
       while read -r mouse; do
         ${pkgs.libratbag}/bin/ratbagctl "$mouse" led 0 set color "$h$h$h"
      done <<< "$mice"
     fi
     '')
     pkgs.grim
     pkgs.slurp
    (pkgs.writeShellScriptBin "qshot" ''
      ${pkgs.grim}/bin/grim -g "$(${pkgs.slurp}/bin/slurp)" "/tmp/clip.png" &&\
      ${pkgs.wl-clipboard}/bin/wl-copy < /tmp/clip.png
     '')
  ];
  imports = 
    [
    wm/hyprrazer.nix
    rofi/rofi.nix
    ];
  wayland.windowManager.hyprland = {
    enable = true;
    # package = inputs.hyprland.packages."${pkgs.system}".hyprland;
    settings = {
      monitor= lib.mkDefault ",preferred,auto,2";
      exec-once = [
        "nmcli radio wifi off && nmcli radio wifi on" # wifi doesn't work without this.
        "swww init"
        "wluma"
      ];
      input = {
        kb_layout = "us";

        touchpad = {
          natural_scroll = true;
        };
      };

      general = with config.colorScheme.colors; {
        gaps_in = 3;
        gaps_out = 5;
        border_size = 2;
        "col.active_border" = "rgba(${base08}ee) rgba(${base0A}ee) 45deg";
        "col.inactive_border" = "rgba(${base03}aa)";
        layout = "master";
        allow_tearing = false;
      };

      decoration = with config.colorScheme.colors; {

        rounding = 10;

        blur = {
          enabled = true;
          size = 3;
          passes = 1;
        };

        drop_shadow = true;
        shadow_range = 4;
        shadow_render_power = 3;
        "col.shadow" = "rgba(${base01}ee)";
      };

      animations = {
        enabled = lib.mkDefault true;
        bezier = "myBezier,0.05,0.9,0.1,1.05";

        animation =[
          "windows,1,7,myBezier"
            "windowsOut,1,7,default,popin 80%"
            "border,1,10,default"
            "borderangle,1,8,default"
            "fade,1,7,default"
            "workspaces,1,6,default"
        ];
      };

      dwindle = {
        pseudotile = true;
        preserve_split = true;
      };

      gestures = {
        workspace_swipe = true;
        workspace_swipe_forever = true;
      };

      misc = {
        force_default_wallpaper = -1;
        enable_swallow = true;
      };

      windowrule = let 
        f = regex: "float, ^(${regex})$";
      in [
        (f "org.gnome.Calculator")
          (f "org.gnome.Nautilus")
          (f "pavucontrol")
          (f "nm-connection-editor")
          (f "org.gnome.Settings")
          (f "org.gnome.design.Palette")
          (f "Color Picker")
          (f "xdg-desktop-portal")
          (f "xdg-desktop-portal-gnome")
          (f "com.github.Aylur.ags")
          "workspace 5,title:^(Signal)$"
          "workspace 8,class:^(steam)(.*)$"
          "workspace 8,^(org.prismlauncher.PrismLauncher)$"
          "float,title:(Bitwarden)$"
          "fullscreen,title:(Bitwarden)$"
      ];

      "$mainMod" = "SUPER";

      bindni = [
        "SUPER,SUPER_L,exec,hyprrazer -f /home/greencheetah/.cache/hyprrazer/mainMod.csv"
      ];
      bindirnt = with config.colorScheme.colors; lib.mkDefault [
        "SUPER,SUPER_L,exec,polychromatic-cli -d laptop -z main -o static -c ${base07}"
      ];
      bind = [ #
        "$mainMod,Q,exec,footclient"
        "$mainMod,C,killactive,"
        "CTRLSHIFT$mainMod,C,exit,"
        "$mainMod,E,exec,nautilus"
        "$mainMod,W,exec,firefox"
        "$mainMod,A,exec,pkill aiclip; aiclip"
        "$mainMod,V,togglefloating,"
        "$mainMod,R,exec,rofi -show drun"
        "$mainMod,H,movefocus,l"
        "$mainMod,L,movefocus,r"
        "$mainMod,K,movefocus,u"
        "$mainMod,J,movefocus,d"
        "$mainMod SHIFT,H,movewindoworgroup,l"
        "$mainMod SHIFT,L,movewindoworgroup,r"
        "$mainMod SHIFT,K,movewindoworgroup,u"
        "$mainMod SHIFT,J,movewindoworgroup,d"
        "$mainMod,S,togglespecialworkspace,magic"
        "SHIFT$mainMod,S,exec,magic"
        "$mainMod SHIFT,S,movetoworkspace,special:magic"
        "$mainMod,mouse_down,workspace,e+1"
        "$mainMod,mouse_up,workspace,e-1"
        "CTRLSHIFT$mainMod,S,exec,qshot"
        "$mainMod,F11,fullscreen,0"
        "$mainMod,M,fullscreen,1"
        "CTRL$mainMod,F11,fakefullscreen,0"
        "$mainMod,p,pin,"
        ] ++ [
        "$mainMod,1,workspace,1"
          "$mainMod,2,workspace,2"
          "$mainMod,3,workspace,3"
          "$mainMod,4,workspace,4"
          "$mainMod,5,workspace,5"
          "$mainMod,6,workspace,6"
          "$mainMod,7,workspace,7"
          "$mainMod,8,workspace,8"
          "$mainMod,9,workspace,9"
          "$mainMod,0,workspace,10"
          "$mainMod SHIFT,1,movetoworkspacesilent,1"
          "$mainMod SHIFT,2,movetoworkspacesilent,2"
          "$mainMod SHIFT,3,movetoworkspacesilent,3"
          "$mainMod SHIFT,4,movetoworkspacesilent,4"
          "$mainMod SHIFT,5,movetoworkspacesilent,5"
          "$mainMod SHIFT,6,movetoworkspacesilent,6"
          "$mainMod SHIFT,7,movetoworkspacesilent,7"
          "$mainMod SHIFT,8,movetoworkspacesilent,8"
          "$mainMod SHIFT,9,movetoworkspacesilent,9"
          "$mainMod SHIFT,0,movetoworkspacesilent,10"
          ];
      bindle = [
        ",XF86MonBrightnessUp,   exec, ${brightnessctl} set +5%; devbright"
        ",XF86MonBrightnessDown, exec, ${brightnessctl} set  5%-; devbright"
        ",XF86AudioRaiseVolume,  exec, ${pactl} set-sink-volume @DEFAULT_SINK@ +5%"
        ",XF86AudioLowerVolume,  exec, ${pactl} set-sink-volume @DEFAULT_SINK@ -5%"
        "CTRL$mainMod,H,resizeactive,-10 0"
        "CTRL$mainMod,L,resizeactive,10 0"
        "CTRL$mainMod,K,resizeactive,0 -10"
        "CTRL$mainMod,J,resizeactive,0 10"
      ];
      bindl =  [
        ",XF86AudioPlay,    exec, ${playerctl} play-pause"
          ",XF86AudioStop,    exec, ${playerctl} pause"
          ",XF86AudioPause,   exec, ${playerctl} pause"
          ",XF86AudioPrev,    exec, ${playerctl} previous"
          ",XF86AudioNext,    exec, ${playerctl} next"
          ",XF86AudioMicMute, exec, ${pactl} set-source-mute @DEFAULT_SOURCE@ toggle"
      ];
      plugin = {
      };

      bindm = [
        "$mainMod,mouse:272,movewindow"
          "$mainMod,mouse:273,resizewindow"
      ];
    };
  };
}
