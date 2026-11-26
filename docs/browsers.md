# Shared browser settings

`modules/home-manager/desktop/apps/browser.nix` defines the `browser.*`
Home Manager options consumed by LibreWolf and Brave. Override these options
in a host's Home Manager configuration, or change their shared defaults there.

```nix
browser = {
  savePasswords = false;
  verticalTabs = true;
  expandTabsOnHover = true;
  showBookmarksBar = false;
  restoreSession = true;
  fonts.sans = "Inter";
  fonts.monospace = "JetBrains Mono";
};
```

The shared surface also covers `homepage`, `search`, `extensions`, `vimKeys`,
`colours`, `clearCookiesOnExit`, and `persistentSites`. Colour overrides use
Graphide theme tokens such as `chrome`, `page`, `field`, `text`, and `accent`.
The startpage module supplies the same local home page to both browsers.

Bitwarden is installed in both browsers, and built-in password saving defaults
to off. Existing saved passwords are preserved. Extensions have separate
Firefox and Chromium store IDs; a null entry skips that browser. Firefox-only
extensions and Tridactyl's custom commands are not translated automatically;
Brave uses Vimium for Vim navigation and its own Shields for content blocking.

Apply configuration with `homeswitch`. Open Brave through the desktop launcher
or the `brave` command so its Flatpak receives the generated policies, theme,
and fonts. A direct `flatpak run com.brave.Browser` bypasses that setup.
Preference changes apply the next time Brave starts after fully quitting;
activation leaves a running browser and its profile alone.

Brave's runtime files are under
`~/.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser`.
The original native profile remains at `~/.config/BraveSoftware/Brave-Browser`.
The preference updater preserves unrelated settings, backs up each original
file as `*.before-nix-browser`, and never stores profile data in Nix.

Generated settings can be inspected at `~/.config/browser/brave-settings.json`
and `~/.config/browser/brave-policies.json`. `brave://policy` shows which
policies the running browser has loaded.
