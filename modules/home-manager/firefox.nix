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
  home.file.csshacks = {
     source = inputs.firefox-css-hacks;
     target = ".mozilla/firefox/default/chrome/css-hacks";
  };
  home.file.verttabs = {
     source = inputs.firefox-vertical-tabs;
     target = ".mozilla/firefox/default/chrome/verttabs";
  };
  programs.firefox = {
    enable = true;
    package = pkgs.firefox.override {
      cfg = {
        enableGnomeExtensions = true;
      };
      nativeMessagingHosts = [
        pkgs.tridactyl-native
      ];
    };
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
              definedAliases = [ "!br" ];
            };
            "nyaa" = {
              urls = [{
                template = "https://nyaa.si/";
                params = [
                { name = "f"; value = "0";}
                { name = "c"; value = "0_0";}
                { name = "q"; value = "{searchTerms}"; }
                ];
              }];
              definedAliases = [ "!ny" ];
            };
            "PirateBay" = {
              urls = [{
                template = "https://thepiratebay.org/search.php";
                params = [
                { name = "q"; value = "{searchTerms}"; }
                ];
              }];
              definedAliases = [ "!tpb" ];
            };
          };
        };
        settings = {
          "browser.search.defaultenginename" = "brave";
          "browser.search.order.1" = "brave";
          "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
        };
        userChrome = ''
        @import url(verttabs/userChrome.css);
        @import url(css-hacks/chrome/blank_page_background.css);
        @import url(css-hacks/chrome/hide_toolbox_top_bottom_borders.css);
        @import url(css-hacks/chrome/vertical_context_navigation.css);
        @import url(css-hacks/chrome/minimal_popup_scrollbars.css);
        @import url(css-hacks/chrome/urlbar_centered_text.css);
        '';
      };
    };
  };
  xdg.configFile."tridactyl/tridactylrc".text = ''
" Comment toggler for Reddit, Hacker News and Lobste.rs
bind ;c hint -Jc [class*="expand"],[class*="togg"],[class="comment_folder"]

bind d composite tabprev; tabclose #
bind D tabclose
" Make gu take you back to subreddit from comments
bindurl reddit.com gu urlparent 4

" Only hint search results on Google and DDG
bindurl www.google.com f hint -Jc #search a
bindurl www.google.com F hint -Jbc #search a

" Handy multiwindow/multitasking binds
bind gd tabdetach
bind gD composite tabduplicate; tabdetach

" Binds for new reader mode
bind gr reader
bind gR reader --tab

" set editorcmd to foot, or use the defaults on other platforms
js tri.browserBg.runtime.getPlatformInfo().then(os=>{const editorcmd = os.os=="linux" ? "foot lvim" : "auto"; tri.config.set("editorcmd", editorcmd)})

" Sane hinting mode
set hintfiltermode vimperator-reflow

set hintdelay 100
xamo_quiet

jsb browser.webRequest.onHeadersReceived.addListener(tri.request.clobberCSP,{urls:["<all_urls>"],types:["main_frame"]},["blocking","responseHeaders"])

command translate js let googleTranslateCallback = document.createElement('script'); googleTranslateCallback.innerHTML = "function googleTranslateElementInit(){ new google.translate.TranslateElement(); }"; document.body.insertBefore(googleTranslateCallback, document.body.firstChild); let googleTranslateScript = document.createElement('script'); googleTranslateScript.charset="UTF-8"; googleTranslateScript.src = "https://translate.google.com/translate_a/element.js?cb=googleTranslateElementInit&tl=&sl=&hl="; document.body.insertBefore(googleTranslateScript, document.body.firstChild);

autocmd DocStart ^http(s?)://www.reddit.com js tri.excmds.urlmodify("-t", "www", "old")
set smoothscroll true
bind J tabnext
bind K tabprev
  '';
}
