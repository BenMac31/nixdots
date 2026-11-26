{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.browser;
  lock-false = {
    Value = false;
    Status = "locked";
  };
  lock-true = {
    Value = true;
    Status = "locked";
  };
  lock-empty-string = {
    Value = "";
    Status = "locked";
  };
in
{
  config = lib.mkIf (config.programs.librewolf.enable && cfg.enable) {
    home.packages = [
      (pkgs.writeShellScriptBin "nixffext" ''
        wl-copy "(extension \"$(printf "$1" | awk -F '/' '{printf $7 }')\" \"$(curl -s "$1" | tr ',' '\n' | grep byGUID | tail -n 1 | awk -F '"' '{printf $4}')\")" && notify-send "ext copied"
      '')
    ];
    xdg.mimeApps.defaultApplications = {
      "text/html" = "librewolf.desktop";
      "x-scheme-handler/http" = "librewolf.desktop";
      "x-scheme-handler/https" = "librewolf.desktop";
      "x-scheme-handler/about" = "librewolf.desktop";
      "x-scheme-handler/unknown" = "librewolf.desktop";
    };
    home.file.csshacks = {
      source = inputs.firefox-css-hacks;
      target = ".librewolf/default/chrome/css-hacks";
    };
    programs.librewolf = {
      package = pkgs.librewolf.override {
        cfg = {
          enableGnomeExtensions = true;
        };
      };
      policies = {
        DisableTelemetry = true;
        DisableFirefoxStudies = true;
        DontCheckDefaultBrowser = true;
        DisablePocket = true;
        PasswordManagerEnabled = cfg.savePasswords;
        SearchBar = "unified";
        # Librewolf clears cookies on shutdown; sites with an explicit "allow"
        # cookie permission are skipped by the shutdown sanitizer.
        Cookies = {
          Allow = map (site: "https://${site}") cfg.persistentSites;
        };
        Preferences = {
          "extensions.pocket.enabled" = lock-false;
          "browser.topsites.contile.enabled" = lock-false;
          "browser.newtabpage.activity-stream.showSponsored" = lock-false;
          "browser.newtabpage.activity-stream.system.showSponsored" = lock-false;
          "browser.newtabpage.activity-stream.showSponsoredTopSites" = lock-false;

          browser.search.separatePrivateDefault = lock-false;
          "browser.search.defaultenginename" = cfg.search.default;
          "browser.search.order.1" = cfg.search.default;

          "browser.startup.page" = if cfg.restoreSession then 3 else 1;
          "privacy.resistFingerprinting.block_mozAddonManager" = lock-true;
          "extensions.webextensions.restrictedDomains" = lock-empty-string;
        };
        ExtensionSettings = lib.listToAttrs (lib.mapAttrsToList (_: extension:
          lib.nameValuePair extension.firefox.id {
            install_url = "https://addons.mozilla.org/en-US/firefox/downloads/latest/${extension.firefox.slug}/latest.xpi";
            installation_mode = "force_installed";
          }) (lib.filterAttrs (_: extension: extension.firefox != null) cfg.extensions));
      };

      profiles = {
        default = {
          name = "default";
          isDefault = true;
          search = {
            default = cfg.search.default;
            force = true;
            engines = lib.mapAttrs (_: engine: {
              urls = [{ template = engine.url; }];
              definedAliases = engine.aliases;
              icon = engine.icon;
              updateInterval = 7 * 24 * 60 * 60 * 1000;
            }) cfg.search.engines;
          };
          settings = {
            "browser.search.defaultenginename" = cfg.search.default;
            "browser.search.order.1" = cfg.search.default;
            "browser.startup.homepage" = lib.mkIf (cfg.homepage != null) cfg.homepage;
            "privacy.clearOnShutdown.cookies" = cfg.clearCookiesOnExit;
            "privacy.clearOnShutdown_v2.cookiesAndStorage" = cfg.clearCookiesOnExit;
            "signon.rememberSignons" = cfg.savePasswords;
            "font.name.sans-serif.x-western" = cfg.fonts.sans;
            "font.name.monospace.x-western" = cfg.fonts.monospace;
            "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
            "sidebar.revamp" = true;
            "sidebar.verticalTabs" = cfg.verticalTabs;
            "sidebar.main.tools" = "";
            "sidebar.expandOnHover" = cfg.expandTabsOnHover;
            "browser.tabs.groups.enabled" = true;
            # user.js reapplies these at every start: customize here, not in the UI.
            "browser.uiCustomization.state" = builtins.toJSON {
              placements = {
                widget-overflow-fixed-list = [ ];
                unified-extensions-area = [
                  "_ddd3c206-589e-431d-93d0-897378f9200a_-browser-action"
                  "addon_darkreader_org-browser-action"
                  "_a2503cd4-4083-4c2f-bef2-37767a569867_-browser-action"
                  "_6b733b82-9261-47ee-a595-2dda294a4d08_-browser-action"
                  "_aecec67f-0d10-4fa7-b7c7-609a2db280cf_-browser-action"
                  "_b7eef7b5-1504-4fe1-a48b-3d08859a7761_-browser-action"
                ];
                nav-bar = [
                  "sidebar-button"
                  "back-button"
                  "forward-button"
                  "vertical-spacer"
                  "stop-reload-button"
                  "urlbar-container"
                  "downloads-button"
                  "fxa-toolbar-menu-button"
                  "unified-extensions-button"
                  "ublock0_raymondhill_net-browser-action"
                  "_testpilot-containers-browser-action"
                  "7esoorv3_alefvanoon_anonaddy_me-browser-action"
                  "sponsorblocker_ajay_app-browser-action"
                  "reset-pbm-toolbar-button"
                  "tridactyl_vim_cmcaine_co_uk-browser-action"
                  "_446900e4-71c2-419f-a6a7-df9c091e268b_-browser-action"
                ];
                toolbar-menubar = [
                  "menubar-items"
                ];
                TabsToolbar = lib.optionals (!cfg.verticalTabs) [ "tabbrowser-tabs" ];
                vertical-tabs = lib.optionals cfg.verticalTabs [ "tabbrowser-tabs" ];
                PersonalToolbar = [
                  "import-button"
                  "personal-bookmarks"
                ];
              };
              seen = [
                "developer-button"
                "_ddd3c206-589e-431d-93d0-897378f9200a_-browser-action"
                "ublock0_raymondhill_net-browser-action"
                "addon_darkreader_org-browser-action"
                "7esoorv3_alefvanoon_anonaddy_me-browser-action"
                "_testpilot-containers-browser-action"
                "_a2503cd4-4083-4c2f-bef2-37767a569867_-browser-action"
                "_6b733b82-9261-47ee-a595-2dda294a4d08_-browser-action"
                "_446900e4-71c2-419f-a6a7-df9c091e268b_-browser-action"
                "sponsorblocker_ajay_app-browser-action"
                "screenshot-button"
                "_aecec67f-0d10-4fa7-b7c7-609a2db280cf_-browser-action"
                "_b7eef7b5-1504-4fe1-a48b-3d08859a7761_-browser-action"
                "reset-pbm-toolbar-button"
                "tridactyl_vim_cmcaine_co_uk-browser-action"
              ];
              dirtyAreaCache = [
                "nav-bar"
                "vertical-tabs"
                "unified-extensions-area"
                "PersonalToolbar"
                "toolbar-menubar"
                "TabsToolbar"
              ];
              currentVersion = 26;
              newElementCount = 6;
            };
            "browser.uiCustomization.navBarWhenVerticalTabs" = builtins.toJSON [
              "sidebar-button"
              "back-button"
              "forward-button"
              "vertical-spacer"
              "stop-reload-button"
              "urlbar-container"
              "downloads-button"
              "fxa-toolbar-menu-button"
              "unified-extensions-button"
              "ublock0_raymondhill_net-browser-action"
              "_testpilot-containers-browser-action"
              "7esoorv3_alefvanoon_anonaddy_me-browser-action"
              "sponsorblocker_ajay_app-browser-action"
            ];
            "browser.uiCustomization.horizontalTabstrip" = builtins.toJSON [
              "tabbrowser-tabs"
            ];
            "browser.toolbars.bookmarks.visibility" = if cfg.showBookmarksBar then "always" else "never";
            "browser.theme.toolbar-theme" = 0;
            "media.eme.enabled" = true;
            "browser.ml.enable" = true;
          };
          userChrome = /*css*/ ''
            @import url(css-hacks/chrome/blank_page_background.css);
            @import url(css-hacks/chrome/hide_toolbox_top_bottom_borders.css);
            @import url(css-hacks/chrome/minimal_popup_scrollbars.css);
            @import url(css-hacks/chrome/urlbar_centered_text.css);
            hbox.titlebar-spacer {
              display: none !important;
            }
            hbox#page-action-buttons {
              display: none !important;
            }
            hbox#nav-bar-customization-target {
              padding-left: var(--tab-inline-padding) !important;
            }
            toolbarbutton.titlebar-close {
              display: none !important;
            }
            toolbarbutton#back-button {
              display: none !important;
            }
            toolbarbutton#forward-button {
              display: none !important;
            }
            toolbarbutton#tabs-newtab-button {
              display: none !important;
            }
          '';
        };
      };
    };
  };
}
