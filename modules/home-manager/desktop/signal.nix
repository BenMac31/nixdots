{ lib, config, pkgs, ... }:
let
  p = config.colorScheme.palette;
  accent = if config.desktop.verdigris.enable then p.base0C else p.base0D;
  asarLib = pkgs.writeTextDir "asar.py" (builtins.readFile ./asar.py);

  themePatcher = pkgs.writeText "signal-theme-patch.py" ''
    import sys, re, math
    import asar

    ASAR = sys.argv[1]
    PALETTE = ${builtins.toJSON (p // { inherit accent; })}

    COLOR_MAP = {
        "#121212": "#${p.base00}",
        "#1b1b1b": "#${p.base00}",
        "#2e2e2e": "#${p.base01}",
        "#3b3b3b": "#${p.base01}",
        "#4a4a4a": "#${p.base02}",
        "#545454": "#${p.base02}",
        "#5e5e5e": "#${p.base03}",
        "#848484": "#${p.base04}",
        "#b9b9b9": "#${p.base05}",
        "#dedede": "#${p.base05}",
        "#e9e9e9": "#${p.base06}",
        "#f6f6f6": "#${p.base06}",
        "#fff":    "#${p.base06}",
        "#ffffff": "#${p.base06}",
        "#6191f3": "#${accent}",
        "#2c6bed": "#${accent}",
        "#336ba3": "#${accent}",
        "#406ec9": "#${accent}",
        "#f44336": "#${p.base08}",
        "#cf163e": "#${p.base08}",
        "#3b7845": "#${p.base0B}",
        "#1d8663": "#${p.base0C}",
        "#077d92": "#${p.base0C}",
        "#6058ca": "#${p.base0E}",
        "#9932c8": "#${p.base0E}",
        "#aa377a": "#${p.base0E}",
        "#c73f0a": "#${p.base0F}",
        "#8f616a": "#${p.base0E}",
        "#71717f": "#${p.base03}",
        "#6f6a58": "#${p.base03}",
    }

    REPLACEMENTS = sorted(COLOR_MAP.items(), key=lambda x: -len(x[0]))

    def patch_css(css):
        result = []
        i = 0
        n = len(css)
        while i < n:
            brace = css.find("{", i)
            if brace == -1:
                result.append(css[i:])
                break
            selector = css[i:brace]
            is_dark = ".dark-theme" in selector
            depth = 0
            j = brace
            while j < n:
                c = css[j]
                if c == "{":
                    depth += 1
                elif c == "}":
                    depth -= 1
                    if depth == 0:
                        break
                j += 1
            block = css[brace:j + 1]
            if is_dark:
                for old, new in REPLACEMENTS:
                    block = re.sub(re.escape(old) + r"(?![0-9a-fA-F])", new, block)
            result.append(selector)
            result.append(block)
            i = j + 1
        return "".join(result)

    def to_linear(c):
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    def to_srgb(c):
        c = min(max(c, 0.0), 1.0)
        return c * 12.92 if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055

    def rgb_to_oklab(r, g, b):
        r, g, b = to_linear(r), to_linear(g), to_linear(b)
        l = math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        m = math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        s = math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return (
            0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
        )

    def oklab_to_hex(L, a, b, alpha):
        l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3
        m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3
        s = (L - 0.0894841775 * a - 1.2914855480 * b) ** 3
        rgb = (
            4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s,
        )
        out = "#" + "".join(f"{round(to_srgb(c) * 255):02x}" for c in rgb)
        if alpha < 1:
            out += f"{round(alpha * 255):02x}"
        return out

    def hex_to_oklab(h):
        return rgb_to_oklab(*(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)))

    def parse_color(tok):
        tok = tok.strip()
        m = re.fullmatch(r"#([0-9a-fA-F]{3,8})", tok)
        if m:
            h = m.group(1)
            if len(h) in (3, 4):
                h = "".join(c * 2 for c in h)
            if len(h) not in (6, 8):
                return None
            alpha = int(h[6:8], 16) / 255 if len(h) == 8 else 1.0
            return (*hex_to_oklab(h[:6]), alpha)
        m = re.fullmatch(r"rgba?\(([^)]*)\)", tok)
        if m:
            parts = [x for x in re.split(r"[\s,/]+", m.group(1).strip()) if x]
            if len(parts) < 3:
                return None
            rgb = [float(x.rstrip("%")) / (100 if x.endswith("%") else 255) for x in parts[:3]]
            alpha = float(parts[3].rstrip("%")) / (100 if parts[3].endswith("%") else 1) if len(parts) > 3 else 1.0
            return (*rgb_to_oklab(*rgb), alpha)
        m = re.fullmatch(r"oklab\(([^)]*)\)", tok)
        if m:
            parts = [x for x in re.split(r"[\s/]+", m.group(1).strip()) if x]
            if len(parts) < 3:
                return None
            num = lambda x: 0.0 if x == "none" else float(x.rstrip("%"))
            L = num(parts[0]) / (100 if parts[0].endswith("%") else 1)
            alpha = num(parts[3]) / (100 if parts[3].endswith("%") else 1) if len(parts) > 3 else 1.0
            return (L, num(parts[1]), num(parts[2]), alpha)
        return None

    # Signal's dark greys, each pinned to the palette grey it stands in for.
    GREY_RAMP = [
        (hex_to_oklab(src)[0], hex_to_oklab(PALETTE[dst]))
        for src, dst in (
            ("1b1b1b", "base00"), ("3b3b3b", "base01"), ("545454", "base02"),
            ("5e5e5e", "base03"), ("848484", "base04"), ("dedede", "base05"),
            ("ffffff", "base06"),
        )
    ]

    HUES = [
        (20, "base0E"), (45, "base08"), (75, "base09"), (115, "base0A"),
        (180, "base0B"), (300, "accent"), (360, "base0E"),
    ]

    def remap(tok):
        c = parse_color(tok)
        if c is None:
            return tok
        L, a, b, alpha = c
        if alpha == 0 or L < 0.05:
            return tok
        if math.hypot(a, b) < 0.03:
            if L <= GREY_RAMP[0][0]:
                return oklab_to_hex(*GREY_RAMP[0][1], alpha)
            for (l0, c0), (l1, c1) in zip(GREY_RAMP, GREY_RAMP[1:]):
                if L <= l1:
                    t = (L - l0) / (l1 - l0)
                    return oklab_to_hex(*(x + (y - x) * t for x, y in zip(c0, c1)), alpha)
            return oklab_to_hex(*GREY_RAMP[-1][1], alpha)
        hue = math.degrees(math.atan2(b, a)) % 360
        name = next(n for limit, n in HUES if hue < limit)
        return oklab_to_hex(*hex_to_oklab(PALETTE[name]), alpha)

    def split_args(s):
        depth, start, out = 0, 0, []
        for i, ch in enumerate(s):
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
            elif ch == "," and depth == 0:
                out.append(s[start:i])
                start = i + 1
        out.append(s[start:])
        return out

    def patch_light_dark(css):
        out, i = [], 0
        while True:
            j = css.find("light-dark(", i)
            if j == -1:
                out.append(css[i:])
                return "".join(out)
            k, depth = j + len("light-dark("), 1
            while depth:
                depth += {"(": 1, ")": -1}.get(css[k], 0)
                k += 1
            args = split_args(css[j + len("light-dark("):k - 1])
            out.append(css[i:j])
            if len(args) == 2:
                lead = args[1][:len(args[1]) - len(args[1].lstrip())]
                out.append(f"light-dark({args[0]},{lead}{remap(args[1])})")
            else:
                out.append(css[j:k])
            i = k

    def transform(file_data):
        for css_path in ("stylesheets/manifest.css", "stylesheets/manifest_bridge.css", "stylesheets/tailwind.css"):
            if css_path in file_data:
                original = file_data[css_path].decode("utf-8", errors="replace")
                patched = patch_light_dark(patch_css(original))
                file_data[css_path] = patched.encode("utf-8")
                print(f"  {css_path}: {len(original)} -> {len(patched)} bytes")

    asar.patch(ASAR, transform)

    print("Done.")
  '';

  themedSignal = pkgs.signal-desktop.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.python3 ];
    postInstall = (old.postInstall or "") + ''
      echo "Applying system palette to Signal ASAR..."
      PYTHONPATH=${asarLib} python3 ${themePatcher} $out/share/signal-desktop/app.asar
    '';
  });

  flags = lib.concatStringsSep " " (
    [ "--hide-menu-bar" ]
    ++ lib.optional config.desktop.japanese.input.enable "--enable-wayland-ime=true"
  );
in
{
  options.signal.enable = lib.mkEnableOption "Signal Desktop with the system palette";

  config = lib.mkIf config.signal.enable {
    home.packages = [
      (pkgs.symlinkJoin {
        name = "signal-desktop";
        paths = [ themedSignal ];
        buildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/signal-desktop --add-flags "${flags}"
        '';
      })
    ];
  };
}
