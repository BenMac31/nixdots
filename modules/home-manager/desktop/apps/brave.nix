{ config, lib, pkgs, ... }:

let
  cfg = config.browser;
  p = config.colorScheme.palette;
  colours = (if config.programs.graphide-browser.enable or false then
    config.programs.graphide-browser.colours
  else {
    page = "#${p.base00}"; chrome = "#${p.base00}"; field = "#${p.base00}";
    raised = "#${p.base01}"; text = "#${p.base05}"; muted = "#${p.base04}";
    accent = "#${p.base0C}"; selection = "#${p.base02}";
  }) // cfg.colours;
  profileRoot = "${config.home.homeDirectory}/.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser";
  search = cfg.search.engines.${cfg.search.default};
  chromiumExtensions = lib.filterAttrs (_: extension: extension.chromium != null) cfg.extensions;
  extensionPolicy = lib.listToAttrs (lib.mapAttrsToList (_: extension:
    lib.nameValuePair extension.chromium {
      installation_mode = "force_installed";
      update_url = "https://clients2.google.com/service/update2/crx";
    }) chromiumExtensions);
  policies = pkgs.writeText "brave-policies.json" (builtins.toJSON ({
    DefaultBrowserSettingEnabled = false;
    BackgroundModeEnabled = false;
    BookmarkBarEnabled = cfg.showBookmarksBar;
    PasswordManagerEnabled = cfg.savePasswords;
    ShowHomeButton = false;
    RestoreOnStartup = if cfg.restoreSession then 1 else 5;
    DefaultSearchProviderEnabled = true;
    DefaultSearchProviderName = cfg.search.default;
    DefaultSearchProviderKeyword = lib.head (search.aliases ++ [ cfg.search.default ]);
    DefaultSearchProviderSearchURL = search.url;
    SiteSearchSettings = lib.concatLists (lib.mapAttrsToList (name: engine:
      map (alias: { inherit name; shortcut = alias; url = engine.url; })
        (lib.filter (alias: alias != lib.head (search.aliases ++ [ cfg.search.default ])) engine.aliases)
    ) cfg.search.engines);
    DefaultCookiesSetting = if cfg.clearCookiesOnExit then 4 else 1;
    CookiesAllowedForUrls = map (site: "https://[*.]${site}") cfg.persistentSites;
    MetricsReportingEnabled = false;
    BraveP3AEnabled = false;
    BraveStatsPingEnabled = false;
    BraveWebDiscoveryEnabled = false;
    BraveRewardsDisabled = true;
    BraveWalletDisabled = true;
    BraveVPNDisabled = true;
    BraveNewsDisabled = true;
    ExtensionSettings = extensionPolicy // lib.optionalAttrs cfg.vimKeys {
      dbepggeogbaibhgnhhndojpepiihcmeb = {
        installation_mode = "force_installed";
        update_url = "https://clients2.google.com/service/update2/crx";
      };
    };
  } // lib.optionalAttrs (cfg.homepage != null) {
    HomepageLocation = cfg.homepage;
    HomepageIsNewTabPage = false;
    NewTabPageLocation = cfg.homepage;
  }));
  settings = pkgs.writeText "brave-settings.json" (builtins.toJSON {
    preferences = {
      browser.theme.color_scheme2 = 2;
      webkit.webprefs.fonts = {
        sansserif.Zyyy = cfg.fonts.sans;
        fixed.Zyyy = cfg.fonts.monospace;
      };
      brave = {
        tabs = {
          vertical_tabs_enabled = cfg.verticalTabs;
          vertical_tabs_collapsed = cfg.expandTabsOnHover;
          vertical_tabs_expanded_state_per_window = false;
          vertical_tabs_floating_enabled = cfg.expandTabsOnHover;
          vertical_tabs_show_title_on_window = false;
        };
        sidebar.sidebar_show_option = 3;
        show_side_panel_button = false;
        show_bookmarks_button = false;
        location_bar_is_wide = true;
        ai_chat.show_toolbar_button = false;
        wallet.show_wallet_icon_on_toolbar = false;
      };
    };
    localState.brave.tabs.compact_horizontal_tabs = true;
  });
  rgb = colour: map (offset: lib.fromHexString (builtins.substring offset 2 colour)) [ 1 3 5 ];
  theme = pkgs.writeText "brave-theme.json" (builtins.toJSON {
    manifest_version = 2;
    name = "Graphide Ink";
    # Give palette changes a new extension version so cached themes refresh.
    version = "1.${toString (lib.fromHexString (builtins.substring 0 4 (builtins.hashString "sha256" (builtins.toJSON colours))))}";
    theme.colors = lib.mapAttrs (_: rgb) {
      frame = colours.chrome;
      frame_inactive = colours.chrome;
      toolbar = colours.page;
      tab_text = colours.text;
      tab_background_text = colours.muted;
      bookmark_text = colours.text;
      ntp_background = colours.page;
      ntp_text = colours.text;
      ntp_link = colours.accent;
      button_background = colours.raised;
      toolbar_button_icon = colours.text;
      omnibox_background = colours.field;
      omnibox_text = colours.text;
      toolbar_top_separator = colours.selection;
      toolbar_bottom_separator = colours.selection;
      tab_background_separator = colours.selection;
    };
  });
  fontconfig = pkgs.writeText "brave-fonts.conf" ''
    <?xml version="1.0"?>
    <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
    <fontconfig>
      <include ignore_missing="yes">/etc/fonts/fonts.conf</include>
      <dir>${pkgs.inter}/share/fonts</dir>
      <dir>${pkgs.jetbrains-mono}/share/fonts</dir>
    </fontconfig>
  '';
  # Flatpak's /etc is private to this launch; no host policy files need root.
  sandbox = pkgs.writeText "brave-sandbox.sh" ''
    set -eu
    mkdir -p /etc/brave/policies/managed "$XDG_CONFIG_HOME/nix-browser/theme"
    ln -sf ${policies} /etc/brave/policies/managed/99-nixos.json
    ln -sf ${theme} "$XDG_CONFIG_HOME/nix-browser/theme/manifest.json"
    export FONTCONFIG_FILE=${fontconfig}
    exec /app/bin/brave --gtk-version=3 \
      --load-extension="$XDG_CONFIG_HOME/nix-browser/theme" "$@"
  '';
  launcher = pkgs.writeShellScriptBin "brave" (if cfg.enable then ''
    set -e
    ${pkgs.python3}/bin/python3 ${./brave-settings.py} ${settings} ${lib.escapeShellArg profileRoot}
    exec ${pkgs.flatpak}/bin/flatpak run --user --command=sh com.brave.Browser ${sandbox} "$@"
  '' else ''
    exec ${pkgs.flatpak}/bin/flatpak run --user com.brave.Browser "$@"
  '');
  desktop = pkgs.makeDesktopItem {
    name = "com.brave.Browser";
    desktopName = "Brave";
    genericName = "Web Browser";
    exec = "${launcher}/bin/brave %U";
    icon = "com.brave.Browser";
    terminal = false;
    categories = [ "Network" "WebBrowser" ];
    mimeTypes = [ "text/html" "application/xhtml+xml" "x-scheme-handler/http" "x-scheme-handler/https" ];
    startupNotify = true;
    startupWMClass = "brave-browser";
    actions = {
      new-window = { name = "New Window"; exec = "${launcher}/bin/brave --new-window"; };
      new-private-window = { name = "New Private Window"; exec = "${launcher}/bin/brave --incognito"; };
      new-tor-window = { name = "New Private Window with Tor"; exec = "${launcher}/bin/brave --tor"; };
    };
  };
  package = pkgs.symlinkJoin { name = "brave-flatpak"; paths = [ launcher desktop ]; };
in

{
  options.brave.enable = lib.mkEnableOption "Brave browser";
  options.brave.package = lib.mkOption {
    type = lib.types.package;
    readOnly = true;
    default = package;
    description = "Flatpak launcher with the shared browser configuration.";
  };

  config = lib.mkIf (config.desktop.enable && config.brave.enable) {
    services.flatpak.packages = [ "com.brave.Browser" ];
    services.flatpak.overrides."com.brave.Browser".Context.filesystems = lib.mkIf cfg.enable ([
      "/nix/store:ro"
    ] ++ lib.optionals (cfg.homepage != null && lib.hasPrefix "file://" cfg.homepage) [
      "${config.xdg.configHome}/startpage:ro"
      "${config.home.homeDirectory}/nixos/confs/startpage:ro"
      "${config.xdg.cacheHome}/wall.png:ro"
    ]);
    home.packages = [ package ];
    home.activation.braveSettings = lib.mkIf cfg.enable (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${pkgs.python3}/bin/python3 ${./brave-settings.py} ${settings} ${lib.escapeShellArg profileRoot}
    '');
    xdg.configFile = lib.mkIf cfg.enable {
      "browser/brave-policies.json".source = policies;
      "browser/brave-settings.json".source = settings;
    };
    xdg.dataFile."applications/com.brave.Browser.desktop".source =
      "${desktop}/share/applications/com.brave.Browser.desktop";
  };
}
