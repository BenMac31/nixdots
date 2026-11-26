#!/usr/bin/env python3
"""Inline the composer vim plugin into T3 Code's renderer HTML, inside app.asar.

T3's bundle is a 270 MB asar that carries an app.asar.unpacked tree beside it,
so `asar extract` + `asar pack` is not an option: packing drops the per-entry
"unpacked" flags and would inline native modules that have to stay real files
on disk. Instead this rewrites one entry in place:

  * parse the asar header (a chromium Pickle holding a JSON directory tree)
  * append the patched index.html to the end of the payload
  * repoint only that entry's offset and size

Every other entry keeps its offset and its flags, byte for byte. The original
index.html stays in the file as ~23 KB of dead space, which nothing reads.

Fails loudly rather than shipping a half-patched bundle: Electron's
EnableEmbeddedAsarIntegrityValidation fuse is off in this build (checked), so
the only thing that can break this is T3 changing its renderer layout, and
then the build should stop so the flag can be turned off.
"""

import json
import struct
import sys

MARKER = "t3code-vim-composer"
TARGET = ("apps", "server", "dist", "client", "index.html")
ANCHOR = '<script type="module"'


def die(msg):
    sys.stderr.write("inject-vim: %s\n" % msg)
    raise SystemExit(1)


def pad4(n):
    return (4 - (n % 4)) % 4


def read_header(buf):
    """Return (header_dict, header_size, payload_start)."""
    if len(buf) < 16:
        die("app.asar is too small to be an asar")
    (field_len,) = struct.unpack_from("<I", buf, 0)
    if field_len != 4:
        die("unexpected asar size-pickle length %d (want 4)" % field_len)
    (header_size,) = struct.unpack_from("<I", buf, 4)
    (payload_size,) = struct.unpack_from("<I", buf, 8)
    (str_len,) = struct.unpack_from("<I", buf, 12)
    if 4 + payload_size != header_size:
        die("asar header pickle is inconsistent (%d vs %d)" % (4 + payload_size, header_size))
    raw = buf[16:16 + str_len]
    try:
        header = json.loads(raw.decode("utf-8"))
    except Exception as exc:
        die("asar header is not JSON: %s" % exc)
    return header, header_size, 8 + header_size


def write_header(header):
    raw = json.dumps(header, separators=(",", ":")).encode("utf-8")
    body = struct.pack("<I", len(raw)) + raw
    body += b"\0" * pad4(len(body))
    payload_size = len(body)
    header_size = 4 + payload_size
    return struct.pack("<II", 4, header_size) + struct.pack("<I", payload_size) + body


def entry(header, path):
    node = header
    for part in path[:-1]:
        files = node.get("files")
        if not isinstance(files, dict) or part not in files:
            die("asar has no directory %r (T3's renderer layout changed)" % part)
        node = files[part]
    files = node.get("files")
    if not isinstance(files, dict) or path[-1] not in files:
        die("asar has no file %r (T3's renderer layout changed)" % path[-1])
    return files[path[-1]]


def main():
    if len(sys.argv) != 3:
        die("usage: inject-vim.py <app.asar> <vim-composer.js>")
    asar_path, plugin_path = sys.argv[1], sys.argv[2]

    with open(plugin_path, "rb") as fh:
        plugin = fh.read().decode("utf-8")
    if "</script" in plugin:
        die("the plugin contains a closing script tag and cannot be inlined")

    with open(asar_path, "rb") as fh:
        buf = fh.read()

    header, _, payload_start = read_header(buf)
    item = entry(header, TARGET)
    if "offset" not in item or "size" not in item:
        die("index.html entry has no offset/size (is it unpacked?)")

    off = payload_start + int(item["offset"])
    size = int(item["size"])
    html = buf[off:off + size].decode("utf-8")

    if MARKER in html:
        die("app.asar is already patched")
    if ANCHOR not in html:
        die("renderer html has no %r anchor; T3's entry point changed" % ANCHOR)

    tag = (
        '<script id="%s">\n/* injected by nixos/pkgs/t3code */\n%s\n</script>\n    '
        % (MARKER, plugin)
    )
    patched = html.replace(ANCHOR, tag + ANCHOR, 1).encode("utf-8")

    payload = buf[payload_start:]
    item["offset"] = str(len(payload))
    item["size"] = len(patched)

    out = write_header(header) + payload + patched
    with open(asar_path, "wb") as fh:
        fh.write(out)

    # Prove the entry reads back as the patched html.
    header2, _, start2 = read_header(out)
    it2 = entry(header2, TARGET)
    got = out[start2 + int(it2["offset"]):start2 + int(it2["offset"]) + int(it2["size"])]
    if got != patched:
        die("verification failed: patched entry does not read back")
    if MARKER not in got.decode("utf-8"):
        die("verification failed: marker missing from the patched entry")

    sys.stderr.write(
        "inject-vim: composer vim mode inlined (%d bytes of js, html %d -> %d)\n"
        % (len(plugin), size, len(patched))
    )


if __name__ == "__main__":
    main()
