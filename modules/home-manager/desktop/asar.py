import hashlib, json, struct


def sha256_blocks(data, block_size):
    return [
        hashlib.sha256(data[i:i + block_size]).hexdigest()
        for i in range(0, len(data), block_size)
    ]


def patch(asar, transform):
    """Rewrite an ASAR in place. `transform` gets a {path: bytes} dict of the
    packed files and mutates it; offsets, sizes and integrity are recomputed."""
    with open(asar, "rb") as f:
        raw = f.read()

    hdr_size = struct.unpack_from("<I", raw, 12)[0]
    data_start = 16 + hdr_size + (-hdr_size) % 4
    header = json.loads(raw[16:16 + hdr_size])

    def collect(node, path=""):
        out = {}
        if "files" in node:
            for name, child in node["files"].items():
                out.update(collect(child, f"{path}/{name}" if path else name))
        elif "offset" in node:
            out[path] = node
        return out

    file_data = {
        path: raw[data_start + int(node["offset"]):data_start + int(node["offset"]) + node["size"]]
        for path, node in collect(header).items()
    }

    transform(file_data)

    file_list = []
    offset = 0

    def update(node, path=""):
        nonlocal offset
        if "files" in node:
            for name, child in node["files"].items():
                update(child, f"{path}/{name}" if path else name)
        elif "offset" in node:
            data = file_data[path]
            node["offset"] = str(offset)
            node["size"] = len(data)
            if "integrity" in node:
                bs = node["integrity"].get("blockSize", 4194304)
                node["integrity"] = {
                    "algorithm": "SHA256",
                    "hash": hashlib.sha256(data).hexdigest(),
                    "blockSize": bs,
                    "blocks": sha256_blocks(data, bs),
                }
            offset += len(data)
            file_list.append(data)

    update(header)

    new_hdr = json.dumps(header, separators=(",", ":")).encode("utf-8")
    new_hdr_padded = new_hdr + b"\x00" * ((-len(new_hdr)) % 4)
    n = len(new_hdr_padded)

    with open(asar, "wb") as f:
        # ASAR header: [4][padded+8][padded+4][raw_json_len][json][padding][data...]
        f.write(struct.pack("<IIII", 4, n + 8, n + 4, len(new_hdr)))
        f.write(new_hdr_padded)
        for data in file_list:
            f.write(data)
