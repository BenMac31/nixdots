{ config, pkgs, lib, ... }:
let
  # aiohttp decodes Brotli request bodies before auth (CVE-2026-111497); this
  # turns itself off once nixpkgs ships brotli 1.2.1.
  brotli = pkgs.brotli.overrideAttrs (old: {
    patches = old.patches ++ [
      (pkgs.fetchurl {
        url = "https://github.com/google/brotli/commit/0ed4268a4401abcb4472096340477cf4af7d1a2b.patch?full_index=1";
        hash = "sha256-1vliUJAAIj3vcGKVgim9CEV+XgMuftDR2U+3kLBUsfw=";
      })
    ];
  });
  home-assistant =
    if lib.versionOlder pkgs.brotli.version "1.2.1" then
      pkgs.home-assistant.override {
        packageOverrides = self: super: { brotli = super.brotli.override { inherit brotli; }; };
      }
    else
      pkgs.home-assistant;
in
{
  services.home-assistant = {
    package = home-assistant.overrideAttrs { doInstallCheck = false; };
    extraComponents = [
      # Components required to complete the onboarding
      "esphome"
      "met"
      "radio_browser"
    ];
    config = {
      # Includes dependencies for a basic setup
      # https://www.home-assistant.io/integrations/default_config/
      default_config = { };
    };
  };
  networking.firewall.allowedTCPPorts = lib.mkIf config.services.home-assistant.enable [ 8123 ];
}
