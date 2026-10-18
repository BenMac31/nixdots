{ config, lib, pkgs, inputs, ... }:
{
  # Graphide's mail and chat client (Proton mail, and iMessage, Discord,
  # WhatsApp and Matrix through the Matrix server), and grail-mcp, the
  # outbound tools agent sessions call. Its config stays by hand in
  # ~/.config/grail/config.toml: it names the keyring entries for passwords.
  options.grail.enable = lib.mkEnableOption "grail" // { default = config.graphide.enable; };

  config = lib.mkIf (config.desktop.enable && config.grail.enable) {
    # From graphide-tools, which the Graphide updater never moves. The
    # package carries its launcher entry and icon.
    home.packages = [ inputs.graphide-tools.packages.${pkgs.stdenv.hostPlatform.system}.grail ];
  };
}
