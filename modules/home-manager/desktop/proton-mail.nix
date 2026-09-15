{ lib, config, pkgs, ... }:
let
  p = config.colorScheme.palette;
  accent = if config.desktop.verdigris.enable then p.base0C else p.base0D;
  asarLib = pkgs.writeTextDir "asar.py" (builtins.readFile ./asar.py);

  mix = a: b: pct: "color-mix(in oklab, #${a}, #${b} ${toString pct}%)";
  alpha = c: pct: "color-mix(in oklab, #${c} ${toString pct}%, transparent)";

  # Proton derives hover/active states from the minor/major steps.
  scale = name: c: contrast: {
    "${name}-minor-2" = mix c p.base00 80;
    "${name}-minor-1" = mix c p.base00 70;
    ${name} = "#${c}";
    "${name}-major-1" = mix c p.base06 10;
    "${name}-major-2" = mix c p.base06 20;
    "${name}-major-3" = mix c p.base06 30;
    "${name}-contrast" = "#${contrast}";
  };

  tokens = scale "primary" accent p.base00
    // scale "interaction-norm" accent p.base00
    // scale "signal-danger" p.base08 p.base00
    // scale "signal-warning" p.base0A p.base00
    // scale "signal-success" p.base0B p.base00
    // scale "signal-info" p.base0C p.base00
    // {
      "interaction-weak-minor-2" = "#${p.base00}";
      "interaction-weak-minor-1" = "#${p.base01}";
      interaction-weak = "#${p.base02}";
      "interaction-weak-major-1" = mix p.base02 p.base03 50;
      "interaction-weak-major-2" = "#${p.base03}";
      "interaction-weak-major-3" = mix p.base03 p.base04 50;
      interaction-weak-contrast = "#${p.base06}";
      text-norm = "#${p.base06}";
      text-weak = "#${p.base04}";
      text-hint = "#${p.base03}";
      text-disabled = mix p.base02 p.base03 50;
      text-invert = "#${p.base00}";
      field-norm = "#${p.base03}";
      field-hover = "#${p.base04}";
      field-disabled = "#${p.base02}";
      focus-outline = "#${accent}";
      focus-ring = alpha accent 30;
      border-norm = "#${p.base02}";
      border-weak = "#${p.base01}";
      background-norm = "#${p.base00}";
      background-weak = "#${p.base01}";
      background-strong = "#${p.base02}";
      background-invert = "#${p.base06}";
      interaction-default = "transparent";
      interaction-default-hover = alpha p.base03 20;
      interaction-default-active = alpha p.base03 40;
      backdrop-norm = alpha p.base00 48;
      optional-scrollbar-thumb-color = "#${p.base02}";
      optional-background-elevated = "#${p.base01}";
      optional-background-lowered = mix p.base00 "000000" 30;
      optional-selection-background-color = alpha accent 40;
      optional-mini-calendar-today-color = "#${p.base06}";
      optional-logo-text-proton-color = "#${p.base06}";
      optional-logo-text-product-color = "#${p.base06}";
      optional-promotion-text-color = "#${p.base06}";
      optional-promotion-text-weak = mix p.base0E p.base06 40;
      optional-promotion-interaction-hover = alpha p.base0E 20;
      optional-promotion-background-start = alpha p.base0E 30;
      optional-promotion-background-end = alpha accent 10;
      optional-promotion-secondary-color = "#${p.base0E}";
    };

  css = ''
    :root, .ui-standard, .ui-prominent {
      color-scheme: dark !important;
    ${lib.concatStrings (lib.mapAttrsToList (k: v: "  --${k}: ${v} !important;\n") tokens)}}
  '';

  themePatcher = pkgs.writeText "proton-mail-theme-patch.py" ''
    import sys, json
    import asar

    CSS = ${builtins.toJSON css}

    # Proton Mail's UI is served from *.proton.me, so the palette is injected
    # as user-origin CSS into those pages on every load.
    INJECT = (
        "(()=>{const css=" + json.dumps(CSS) + ";"
        "require(\"electron\").app.on(\"web-contents-created\",(_,wc)=>{"
        "wc.on(\"dom-ready\",()=>{let host=\"\";"
        "try{host=new URL(wc.getURL()).hostname}catch{}"
        "if(host===\"proton.me\"||host.endsWith(\".proton.me\"))"
        "wc.insertCSS(css,{cssOrigin:\"user\"}).catch(()=>{})"
        "})})})();\n"
    )

    def transform(file_data):
        main = ".webpack/main/index.js"
        file_data[main] = INJECT.encode("utf-8") + file_data[main]
        print(f"  {main}: injected {len(CSS)} bytes of CSS")

    asar.patch(sys.argv[1], transform)
    print("Done.")
  '';

  themedProtonMail = pkgs.protonmail-desktop.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.python3 ];
    postInstall = (old.postInstall or "") + ''
      echo "Applying system palette to Proton Mail ASAR..."
      PYTHONPATH=${asarLib} python3 ${themePatcher} $out/share/proton-mail/app.asar
    '';
  });
in
{
  options.protonMail.enable = lib.mkEnableOption "Proton Mail Desktop with the system palette";

  config = lib.mkIf config.protonMail.enable {
    home.packages = [ themedProtonMail ];
  };
}
