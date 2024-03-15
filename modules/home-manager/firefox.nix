{config, pkgs, inputs, ... }:

let
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
in {
  xdg.mimeApps.defaultApplications = {
    "text/html"                = "firefox.desktop";
    "x-scheme-handler/http"    = "firefox.desktop";
    "x-scheme-handler/https"   = "firefox.desktop";
    "x-scheme-handler/about"   = "firefox.desktop";
    "x-scheme-handler/unknown" = "firefox.desktop";
  };
  programs.firefox = {
    enable = true;

    policies = {
      DisableTelemetry = true;
      DisableFirefoxStudies = true;
      DontCheckDefaultBrowser = true;
      DisablePocket = true;
      SearchBar = "unified";
      Preferences = {
        "extensions.pocket.enabled" = lock-false;
        "browser.topsites.contile.enabled" = lock-false;
        "browser.newtabpage.activity-stream.showSponsored" = lock-false;
        "browser.newtabpage.activity-stream.system.showSponsored" = lock-false;
        "browser.newtabpage.activity-stream.showSponsoredTopSites" = lock-false;
        "browser.search.defaultenginename" = "brave";
        "browser.search.order.1" = "brave";
      };
      ExtensionSettings = {
        "uBlock0@raymondhill.net" = {
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
          installation_mode = "force_installed";
        };
        "{446900e4-71c2-419f-a6a7-df9c091e268b}" = {
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/bitwarden-password-manager/latest.xpi";
          installation_mode = "force_installed";
        };
      };
    };

    profiles = {
      default = {
        name = "default";
        isDefault = true;
        search = {
          default = "brave";
          force = true;
          engines = {
            "brave" = {
              urls = [{
                template = "https://search.brave.com/search";
                params = [
                { name = "q"; value = "{searchTerms}"; }
                ];
              }];
              definedAliases = [ "@br" ];
            };
          };
        };
        settings = {
          "browser.search.defaultenginename" = "brave";
          "browser.search.order.1" = "brave";
        };
      };
    };
  };
}
