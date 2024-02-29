{pkgs, config, ...}:
{
  home.file.".config/hyprrazer/colormap.conf".text = with config.colorScheme.colors; ''
  exec,${base08}
  killactive,${base09}
  kill,${base0A}
  togglefloating,${base0B}
  pseudo,${base0C}
  movefocus,${base0D}
  workspace,${base0E}
  togglespecialworkspace,${base0E}
  exit,${base0F}
  '';
}
