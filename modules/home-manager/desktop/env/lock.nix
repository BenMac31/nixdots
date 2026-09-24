{ lib, config, ... }:
let
  p = config.colorScheme.palette;
in
{
  programs.hyprlock.settings = lib.mkIf config.programs.hyprlock.enable {
    general = {
      hide_cursor = true;
      grace = 0;
    };
    auth."fingerprint:enabled" = true;
    background = [{
      path = "screenshot";
      blur_passes = 3;
      blur_size = 8;
      color = "rgb(${p.base00})";
    }];
    input-field = [{
      size = "320, 52";
      position = "0, -80";
      halign = "center";
      valign = "center";
      outline_thickness = 2;
      rounding = 12;
      outer_color = "rgb(${p.base0F})";
      inner_color = "rgba(${p.base00}e6)";
      font_color = "rgb(${p.base05})";
      check_color = "rgb(${p.base0A})";
      fail_color = "rgb(${p.base08})";
      font_family = "JetBrainsMono Nerd Font Mono";
      placeholder_text = "󰌾  password or finger";
      fail_text = "$FAIL ($ATTEMPTS)";
      fade_on_empty = false;
    }];
    label = [
      {
        text = "$TIME";
        font_size = 72;
        font_family = "JetBrainsMono Nerd Font Mono";
        color = "rgb(${p.base06})";
        position = "0, 120";
        halign = "center";
        valign = "center";
      }
      {
        text = "$FPRINTPROMPT";
        font_size = 12;
        font_family = "JetBrainsMono Nerd Font Mono";
        color = "rgb(${p.base04})";
        position = "0, -150";
        halign = "center";
        valign = "center";
      }
    ];
  };

  services.hypridle.settings = lib.mkIf config.services.hypridle.enable {
    general = {
      lock_cmd = "pidof hyprlock || hyprlock";
      before_sleep_cmd = "loginctl lock-session";
      after_sleep_cmd = "hyprctl dispatch dpms on";
    };
    listener = [
      {
        timeout = 300;
        on-timeout = "loginctl lock-session";
      }
      {
        timeout = 330;
        on-timeout = "hyprctl dispatch dpms off";
        on-resume = "hyprctl dispatch dpms on";
      }
    ];
  };

  wayland.windowManager.hyprland.settings = lib.mkIf config.programs.hyprlock.enable {
    misc.allow_session_lock_restore = true;
    bind = [ "$mainMod,Escape,exec,loginctl lock-session" ];
  };
}
