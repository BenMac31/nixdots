{pkgs,inputs,config,...}:

let
playerctl = "${pkgs.playerctl}/bin/playerctl";
brightnessctl = "${pkgs.brightnessctl}/bin/brightnessctl";
pactl = "${pkgs.pulseaudio}/bin/pactl";
in {
  xdg.desktopEntries."org.gnome.Settings" = {
    name = "Settings";
    comment = "Gnome Control Center";
    icon = "org.gnome.Settings";
    exec = "env XDG_CURRENT_DESKTOP=gnome ${pkgs.gnome.gnome-control-center}/bin/gnome-control-center";
    categories = [ "X-Preferences" ];
    terminal = false;
  };
  home.sessionVariables = {
    WLR_NO_HARDWARE_CURSORS = "1";
# WLR_DRM_DEVICES="/dev/dri/card1:/dev/dri/card0";
# WLR_DRM_DEVICES="/dev/dri/card0:/dev/dri/card1";
    NIXOS_OZONE_WL = "1";
# LIBVA_DRIVER_NAME="nvidia";
# XDG_SESSION_TYPE="wayland";
# GBM_BACKEND="nvidia-drm";
# __GLX_VENDOR_LIBRARY_NAME="nvidia";
# XWAYLAND_NO_GLAMOR="1";
  };
  services.swayosd.enable = true;
  home.packages = [ #
    pkgs.swww
    pkgs.wluma
    pkgs.wlr-randr
    pkgs.networkmanagerapplet
    inputs.asztal.packages."${pkgs.system}".default
  ];
  imports = 
    [
    wm/hyprrazer.nix
    ];
  wayland.windowManager.hyprland = {
    enable = true;
    package = inputs.hyprland.packages."${pkgs.system}".hyprland;
    settings = {
      monitor= ",preferred,auto,2";
      exec-once = [
        "nmcli radio wifi off && nmcli radio wifi on" # wifi doesn't work without this.
        "swww init"
        "wluma"
        "asztal -b hypr"
      ];
      input = {
        kb_layout = "us";

        touchpad = {
          natural_scroll = true;
        };
      };

      general = with config.colorScheme.colors; {
# See https://wiki.hyprland.org/Configuring/Variables/ for more
        gaps_in = 3;
        gaps_out = 5;
        border_size = 2;
        "col.active_border" = "rgba(${base08}ee) rgba(${base0A}ee) 45deg";
        "col.inactive_border" = "rgba(${base03}aa)";
        layout = "master";
# Please see https://wiki.hyprland.org/Configuring/Tearing/ before you turn this on
        allow_tearing = false;
      };

      decoration = with config.colorScheme.colors; {
# See https://wiki.hyprland.org/Configuring/Variables/ for more

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
        enabled = true;
        # enabled = false;
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
# See https://wiki.hyprland.org/Configuring/Dwindle-Layout/ for more
        pseudotile = true; # master switch for pseudotiling. Enabling is bound to mainMod + P in the keybinds section below
        preserve_split = true; # you probably want this
      };

      master = {
# See https://wiki.hyprland.org/Configuring/Master-Layout/ for more
        new_is_master = false;
      };

      gestures = {
# See https://wiki.hyprland.org/Configuring/Variables/ for more
        workspace_swipe = true;
        workspace_swipe_forever = true;
      };

      misc = {
# See https://wiki.hyprland.org/Configuring/Variables/ for more
        force_default_wallpaper = -1;
        enable_swallow = true;
      };

# Example per-device config
# See https://wiki.hyprland.org/Configuring/Keywords/#executing for more
# device:epic-mouse-v1 {
#          sensitivity = -0.5
#        }
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
      ];

      "$mainMod" = "SUPER";

      bindni = [
        "SUPER,SUPER_L,exec,hyprrazer -f /home/greencheetah/.cache/hyprrazer/mainMod.csv"
# "SUPERSHIFT,SUPER_L,exec,hyprrazer -f /home/greencheetah/.cache/hyprrazer/mainModSHIFT.csv"
      ];
      bindirnt = with config.colorScheme.colors; [
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
        "$mainMod,S,togglespecialworkspace,magic"
        "SHIFT$mainMod,S,exec,magic"
        "$mainMod SHIFT,S,movetoworkspace,special:magic"
        "$mainMod,mouse_down,workspace,e+1"
        "$mainMod,mouse_up,workspace,e-1"
        "$mainMod,R,exec,asztal -b hypr -t applauncher"
        ",XF86PowerOff,exec,asztal -b hypr -t powermenu"
        "$mainMod,Tab,exec,asztal -b hypr -t overview"
        ",XF86Launch4,exec,asztal -b hypr -r 'recorder.start()'"
        ",Print,exec,asztal -b hypr -r 'recorder.screenshot()'"
        "SHIFT,Print,exec,asztal -b hypr -r 'recorder.screenshot(true)'"
        "$mainMod,F11,fullscreen,0"
        "CTRL$mainMod,F11,fakefullscreen,0"
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
        ",XF86MonBrightnessUp,   exec, ${brightnessctl} set +5%"
        ",XF86MonBrightnessDown, exec, ${brightnessctl} set  5%-"
        ",XF86KbdBrightnessUp,   exec, ${brightnessctl} -d asus::kbd_backlight set +1"
        ",XF86KbdBrightnessDown, exec, ${brightnessctl} -d asus::kbd_backlight set  1-"
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
# hycov = {
#   overview_gappo = 20;
#     overview_gappi = 5;
#     hotarea_size = 10;
#     hotarea_pos = 1;
#     enable_hotarea = 1;
#     enable_gesture = true;
#     swipe_fingers = 4;
# };
      };

# Move/resize windows with mainMod + LMB/RMB and dragging
      bindm = [
        "$mainMod,mouse:272,movewindow"
          "$mainMod,mouse:273,resizewindow"
      ];
    };
  };
}
