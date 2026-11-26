{ config, lib, ... }:

let
  inherit (lib) mkOption types;
  cfg = config.browser;
  engine = types.submodule {
    options = {
      url = mkOption { type = types.str; description = "Search URL containing {searchTerms}."; };
      aliases = mkOption { type = types.listOf types.str; default = [ ]; };
      icon = mkOption { type = types.str; };
    };
  };
  extension = types.submodule {
    options = {
      firefox = mkOption {
        type = types.nullOr (types.submodule {
          options = {
            id = mkOption { type = types.str; };
            slug = mkOption { type = types.str; };
          };
        });
        default = null;
      };
      chromium = mkOption { type = types.nullOr types.str; default = null; };
    };
  };
in
{
  options.browser = {
    enable = lib.mkEnableOption "shared LibreWolf and Brave settings";
    homepage = mkOption { type = types.nullOr types.str; default = null; };
    restoreSession = mkOption { type = types.bool; default = true; };
    verticalTabs = mkOption { type = types.bool; default = true; };
    expandTabsOnHover = mkOption { type = types.bool; default = true; };
    showBookmarksBar = mkOption { type = types.bool; default = false; };
    vimKeys = mkOption { type = types.bool; default = true; };
    savePasswords = mkOption { type = types.bool; default = false; };
    clearCookiesOnExit = mkOption { type = types.bool; default = true; };
    persistentSites = mkOption {
      type = types.listOf types.str;
      default = [
        "claude.ai" "anthropic.com" "chatgpt.com" "openai.com" "discord.com"
        "github.com" "proton.me" "protonmail.com" "ycombinator.com" "linkedin.com" "x.com"
      ];
      description = "Domains whose cookies survive closing the browser.";
    };
    fonts = {
      sans = mkOption { type = types.str; default = "Inter"; };
      monospace = mkOption { type = types.str; default = "JetBrains Mono"; };
    };
    colours = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Shared colour overrides; unspecified tokens follow the Graphide browser theme.";
    };
    search = {
      default = mkOption { type = types.str; default = "brave"; };
      engines = mkOption {
        type = types.attrsOf engine;
        default = {
          brave = {
            url = "https://search.brave.com/search?q={searchTerms}";
            aliases = [ "!br" ];
            icon = "https://brave.com/favicon.ico";
          };
          nyaa = {
            url = "https://nyaa.si/?f=0&c=0_0&q={searchTerms}";
            aliases = [ "!ny" ];
            icon = "https://nyaa.si/static/favicon.png";
          };
          PirateBay = {
            url = "https://thepiratebay.org/search.php?q={searchTerms}";
            aliases = [ "!tpb" ];
            icon = "https://thepiratebay.org/favicon.ico";
          };
        };
      };
    };
    extensions = mkOption {
      type = types.attrsOf extension;
      default = {
        containers.firefox = { slug = "multi-account-containers"; id = "@testpilot-containers"; };
        ublock-origin.firefox = { slug = "ublock-origin"; id = "uBlock0@raymondhill.net"; };
        bitwarden = {
          firefox = { slug = "bitwarden-password-manager"; id = "{446900e4-71c2-419f-a6a7-df9c091e268b}"; };
          chromium = "nngceckbapebfimnlniiiahkandclblb";
        };
        libredirect.firefox = { slug = "libredirect"; id = "7esoorv3@alefvanoon.anonaddy.me"; };
        darkreader = {
          firefox = { slug = "darkreader"; id = "addon@darkreader.org"; };
          chromium = "eimadpbcbfnmbkopoojfekhnkhdbieeh";
        };
        deep-fake-detector.firefox = { slug = "deep-fake-detector"; id = "{ddd3c206-589e-431d-93d0-897378f9200a}"; };
        furiganaize.firefox = { slug = "furiganaize"; id = "{a2503cd4-4083-4c2f-bef2-37767a569867}"; };
        yomitan = {
          firefox = { slug = "yomitan"; id = "{6b733b82-9261-47ee-a595-2dda294a4d08}"; };
          chromium = "likgccmbimhjbgkjambclfkhldnlhbnn";
        };
        sponsorblock = {
          firefox = { slug = "sponsorblock"; id = "sponsorBlocker@ajay.app"; };
          chromium = "mnjggcdmjocbbbhaepdhchncahnbgone";
        };
      };
      description = "Extension choices and their store IDs; null skips installation in that browser.";
    };
  };

  config = lib.mkIf (config.desktop.enable && cfg.enable) {
    assertions = [{
      assertion = builtins.hasAttr cfg.search.default cfg.search.engines;
      message = "browser.search.default must name an entry in browser.search.engines.";
    }];
  };
}
