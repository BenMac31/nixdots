{ config, lib, pkgs, inputs, ... }:
{
  # Graphide's mail and chat client (Proton mail, and iMessage, Discord,
  # WhatsApp and Matrix through the Matrix server), and grail-mcp, the
  # outbound tools agent sessions call. Its config stays by hand in
  # ~/.config/grail/config.toml: it names the keyring entries for passwords.
  options.grail.enable = lib.mkEnableOption "grail" // { default = config.graphide.enable; };

  config = lib.mkIf (config.desktop.enable && config.grail.enable) {
    # From graphide-tools, which the Graphide updater never moves.
    home.packages = [ inputs.graphide-tools.packages.${pkgs.stdenv.hostPlatform.system}.grail ];

    xdg.desktopEntries.grail = {
      name = "grail";
      genericName = "Mail and chat";
      exec = "grail";
      terminal = false;
      categories = [ "Network" "Email" "Chat" ];
    };
  };
}
