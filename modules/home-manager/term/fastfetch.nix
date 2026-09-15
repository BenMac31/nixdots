{ config, lib, inputs, pkgs, ... }:
let
  # Fastfetch's image protocols expect a raster image. Render the public,
  # transparent brand mark rather than using the application's icon plate.
  flatLogo = pkgs.runCommand "graphide-flat-logo.png" {
    nativeBuildInputs = [ pkgs.librsvg ];
  } ''
    rsvg-convert -w 512 -h 512 ${inputs.graphide-tools}/website/public/logo.svg > "$out"
  '';
in {
  programs.fastfetch = lib.mkIf config.programs.fastfetch.enable {
    settings = lib.mkIf config.desktop.verdigris.enable {
      logo = {
        type = "kitty";
        source = "${flatLogo}";
        width = 18;
        height = 9;
        padding = { top = 1; left = 1; right = 4; };
      };
      display = {
        separator = "  ·  ";
        color = { keys = "#4fa396"; title = "#6dbcb0"; output = "#bcc6cd"; };
      };
      # No usernames, network addresses, account data, or company metrics.
      modules = [
        { type = "os"; key = "System"; }
        { type = "kernel"; key = "Kernel"; }
        { type = "wm"; key = "Desktop"; }
        { type = "terminal"; key = "Terminal"; }
        { type = "shell"; key = "Shell"; }
        "break"
        { type = "cpu"; key = "Compute"; }
        { type = "memory"; key = "Memory"; }
        { type = "uptime"; key = "Uptime"; }
        "break"
        "colors"
      ];
    };
  };
}
