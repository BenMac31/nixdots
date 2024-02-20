{pkgs, config, ...}:
{
  programs.rofi = {
    enable = true;
    package = pkgs.rofi-wayland;
    extraConfig = {
      show-icons = true;
    };
    # Rounded from <https://github.com/newmanls/rofi-themes-collection>
    theme = with config.colorScheme.colors; let
    inherit (config.lib.formats.rasi) mkLiteral;
    in {
      "*" = {
        font = "Roboto 12";
        background-color = mkLiteral "transparent";
        text-color = mkLiteral "#${base06}";
        margin = mkLiteral "0px";
        padding = mkLiteral "0px";
        spacing = mkLiteral "0px";
      };

      "window" = {
        location = mkLiteral "center";
        width = mkLiteral "480";
        border-radius = mkLiteral "24px";

        background-color = mkLiteral "#${base00}";
      };

      "mainbox" = {
        padding = mkLiteral "12px";
      };

      "inputbar" = {
        background-color = mkLiteral "#${base01}";
        border-color = mkLiteral "#${base04}";

        border = mkLiteral "2px";
        border-radius = mkLiteral "16px";

        padding = mkLiteral "8px 16px";
        spacing = mkLiteral "8px";
        children = mkLiteral "[ prompt, entry ]";
      };

      "prompt" = {
        text-color = mkLiteral "#${base07}";
      };

      "entry" = {
        placeholder = "Search";
        placeholder-color = mkLiteral "#${base08}";
      };

      "message" = {
        margin = mkLiteral "12px 0 0";
        border-radius = mkLiteral "16px";
        border-color = mkLiteral "#${base03}";
        background-color = mkLiteral "#${base03}";
      };

      "textbox" = {
        padding = mkLiteral "8px 24px";
      };

      "listview" = {
        background-color = mkLiteral "transparent";

        margin = mkLiteral "12px 0 0";
        lines = mkLiteral "8";
        columns = mkLiteral "1";

        fixed-height = mkLiteral "false";
      };

      "element" = {
        padding = mkLiteral "8px 16px";
        spacing = mkLiteral "8px";
        border-radius = mkLiteral "16px";
      };

      "element normal active" = {
        text-color = mkLiteral "#${base04}";
      };

      "element selected normal, element selected active" = {
        background-color = mkLiteral "#${base04}";
      };

      "element-icon" = {
        size = mkLiteral "1em";
        vertical-align = mkLiteral "0.5";
      };

      "element-text" = {
        text-color = mkLiteral "inherit";
      };
    };
  };
}
