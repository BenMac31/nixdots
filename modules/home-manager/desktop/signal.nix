{ lib, config, pkgs, ... }:
let
  p = config.colorScheme.palette;

  gruvboxPatcher = pkgs.writeText "signal-gruvbox-patch.py" ''
    import sys, json, struct, re, hashlib

    ASAR = sys.argv[1]

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
        "#6191f3": "#${p.base0D}",
        "#2c6bed": "#${p.base0D}",
        "#336ba3": "#${p.base0D}",
        "#406ec9": "#${p.base0D}",
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

    def sha256_blocks(data, block_size):
        return [
            hashlib.sha256(data[i:i + block_size]).hexdigest()
            for i in range(0, len(data), block_size)
        ]

    with open(ASAR, "rb") as f:
        raw = f.read()

    hdr_size = struct.unpack_from("<I", raw, 12)[0]
    pad = (-hdr_size) % 4
    data_start = 16 + hdr_size + pad
    header = json.loads(raw[16:16 + hdr_size])

    def collect(node, path=""):
        out = {}
        if "files" in node:
            for name, child in node["files"].items():
                out.update(collect(child, f"{path}/{name}" if path else name))
        elif "offset" in node:
            out[path] = node
        return out

    file_index = collect(header)
    file_data = {
        path: raw[data_start + int(node["offset"]):data_start + int(node["offset"]) + node["size"]]
        for path, node in file_index.items()
    }

    for css_path in ("stylesheets/manifest.css", "stylesheets/manifest_bridge.css"):
        if css_path in file_data:
            original = file_data[css_path].decode("utf-8", errors="replace")
            patched = patch_css(original)
            file_data[css_path] = patched.encode("utf-8")
            print(f"  {css_path}: {len(original)} -> {len(patched)} bytes")

    current_offset = 0
    file_list = []

    def update(node, path=""):
        global current_offset
        if "files" in node:
            for name, child in node["files"].items():
                update(child, f"{path}/{name}" if path else name)
        elif "offset" in node:
            data = file_data[path]
            node["offset"] = str(current_offset)
            node["size"] = len(data)
            if "integrity" in node:
                bs = node["integrity"].get("blockSize", 4194304)
                blocks = sha256_blocks(data, bs)
                node["integrity"] = {
                    "algorithm": "SHA256",
                    "hash": hashlib.sha256(data).hexdigest(),
                    "blockSize": bs,
                    "blocks": blocks,
                }
            current_offset += len(data)
            file_list.append(data)

    update(header)

    new_hdr = json.dumps(header, separators=(",", ":")).encode("utf-8")
    new_pad = (-len(new_hdr)) % 4
    new_hdr_padded = new_hdr + b"\x00" * new_pad
    n = len(new_hdr_padded)

    with open(ASAR, "wb") as f:
        # ASAR header: [4][padded+8][padded+4][raw_json_len][json][padding][data...]
        f.write(struct.pack("<IIII", 4, n + 8, n + 4, len(new_hdr)))
        f.write(new_hdr_padded)
        for data in file_list:
            f.write(data)

    print("Done.")
  '';

  themedSignal = pkgs.signal-desktop.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.python3 ];
    postInstall = (old.postInstall or "") + ''
      echo "Applying Gruvbox theme to Signal ASAR..."
      python3 ${gruvboxPatcher} $out/share/signal-desktop/app.asar
    '';
  });

  flags = lib.concatStringsSep " " (
    [ "--hide-menu-bar" ]
    ++ lib.optional config.desktop.japanese.input.enable "--enable-wayland-ime=true"
  );
in
{
  options.signal.enable = lib.mkEnableOption "Signal Desktop with Gruvbox theme";

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
