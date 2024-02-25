{pkgs, inputs, upkgs, config, ...}:

{
  home.sessionVariables = {
    WLR_NO_HARDWARE_CURSORS = "1";
    # WLR_DRM_DEVICES="/dev/dri/card1:/dev/dri/card0";
    # WLR_DRM_DEVICES="/dev/dri/card0:/dev/dri/card1";
    NIXOS_OZONE_WL = "1";
  };
  services.swayosd.enable = true;
  home.packages = with pkgs; [ #
  swww
  swaynotificationcenter
  wluma
  wlr-randr
  ];
  imports = 
    [
    wm/waybar/waybar.nix
    # wm/gBar.nix
    wm/rofi.nix
    # wm/swayidle.nix
    ];
  wayland.windowManager.hyprland = {
    enable = true;
    package = inputs.hyprland.packages."${pkgs.system}".hyprland;
    plugins = [
      inputs.hycov.packages.${pkgs.system}.hycov
    ];
    settings = {
      monitor= ",preferred,auto,2";
      exec-once = [
      # "gBar bar"
      "swww init"
      "swaync"
      "wluma"
      ];
      input = {
        kb_layout = "us";

        touchpad = {
          natural_scroll = true;
        };
      };

      general = {
# See https://wiki.hyprland.org/Configuring/Variables/ for more
        gaps_in = 5;
        gaps_out = 20;
        border_size = 2;
        "col.active_border" = "rgba(33ccffee) rgba(00ff99ee) 45deg";
        "col.inactive_border" = "rgba(595959aa)";
        layout = "dwindle";
# Please see https://wiki.hyprland.org/Configuring/Tearing/ before you turn this on
        allow_tearing = false;
      };

      decoration = {
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
        "col.shadow" = "rgba(1a1a1aee)";
      };

      animations = {
        enabled = true;
        bezier = "myBezier, 0.05, 0.9, 0.1, 1.05";

        animation =[
          "windows, 1, 7, myBezier"
            "windowsOut, 1, 7, default, popin 80%"
            "border, 1, 10, default"
            "borderangle, 1, 8, default"
            "fade, 1, 7, default"
            "workspaces, 1, 6, default"
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
      };

      misc = {
# See https://wiki.hyprland.org/Configuring/Variables/ for more
        force_default_wallpaper = -1;
      };

# Example per-device config
# See https://wiki.hyprland.org/Configuring/Keywords/#executing for more
# device:epic-mouse-v1 {
#          sensitivity = -0.5
#        }

# Example windowrule v1
# windowrule = float, ^(kitty)$
# Example windowrule v2
# windowrulev2 = float,class:^(kitty)$,title:^(kitty)$
# See https://wiki.hyprland.org/Configuring/Window-Rules/ for more


# See https://wiki.hyprland.org/Configuring/Keywords/ for more
      "$mainMod" = "SUPER";

      bind = [ #
        "$mainMod, Q, exec, foot"
        "$mainMod, C, killactive, "
        "$mainMod, M, exit, "
        "$mainMod, E, exec, nautilus"
        "$mainMod, V, togglefloating, "
        "$mainMod, R, exec, rofi -show drun"
        "$mainMod, P, pseudo, # dwindle"
        "$mainMod, J, togglesplit, # dwindle"
        "$mainMod, left, movefocus, l"
        "$mainMod, right, movefocus, r"
        "$mainMod, up, movefocus, u"
        "$mainMod, down, movefocus, d"
        "$mainMod, 1, workspace, 1"
        "$mainMod, 2, workspace, 2"
        "$mainMod, 3, workspace, 3"
        "$mainMod, 4, workspace, 4"
        "$mainMod, 5, workspace, 5"
        "$mainMod, 6, workspace, 6"
        "$mainMod, 7, workspace, 7"
        "$mainMod, 8, workspace, 8"
        "$mainMod, 9, workspace, 9"
        "$mainMod, 0, workspace, 10"
        "$mainMod SHIFT, 1, movetoworkspace, 1"
        "$mainMod SHIFT, 2, movetoworkspace, 2"
        "$mainMod SHIFT, 3, movetoworkspace, 3"
        "$mainMod SHIFT, 4, movetoworkspace, 4"
        "$mainMod SHIFT, 5, movetoworkspace, 5"
        "$mainMod SHIFT, 6, movetoworkspace, 6"
        "$mainMod SHIFT, 7, movetoworkspace, 7"
        "$mainMod SHIFT, 8, movetoworkspace, 8"
        "$mainMod SHIFT, 9, movetoworkspace, 9"
        "$mainMod SHIFT, 0, movetoworkspace, 10"
        "$mainMod, S, togglespecialworkspace, magic"
        "$mainMod SHIFT, S, movetoworkspace, special:magic"
        "$mainMod, mouse_down, workspace, e+1"
        "$mainMod, mouse_up, workspace, e-1"
        # hyprcov
        "ALT,tab,hycov:toggleoverview"
        "ALT,left,hycov:movefocus,l"
        "ALT,right,hycov:movefocus,r"
        "ALT,up,hycov:movefocus,u"
        "ALT,down,hycov:movefocus,d"
        ];
      plugin = {
        hycov = {
          overview_gappo = 20;
            overview_gappi = 5;
            hotarea_size = 10;
            hotarea_pos = 1;
            enable_hotarea = 1;
            enable_gesture = true;
            swipe_fingers = 4;
        };
      };

# Move/resize windows with mainMod + LMB/RMB and dragging
      bindm = [
        "$mainMod, mouse:272, movewindow"
          "$mainMod, mouse:273, resizewindow"
      ];
    };
  };
}
