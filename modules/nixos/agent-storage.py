"""Mount an existing agent scratch image and a preallocated output reserve."""

import argparse
import json
import os
from pathlib import Path
import subprocess


GIB = 1024**3


def run(*args):
    return subprocess.check_output([str(arg) for arg in args], text=True).strip()


def identity(image):
    values = dict(line.split("=", 1) for line in run("blkid", "-p", "-o", "export", image).splitlines()
                  if "=" in line)
    if values.get("TYPE") != "ext4":
        raise RuntimeError(f"{image} is not ext4; refusing to mount or format it")
    return values["UUID"]


def mount_image(image, target):
    uuid = identity(image)
    target.mkdir(mode=0o755, parents=True, exist_ok=True)
    if target.is_symlink():
        raise RuntimeError(f"mount target is a symlink: {target}")
    if os.path.ismount(target):
        actual = run("findmnt", "-n", "-o", "UUID", "--mountpoint", target)
        if actual != uuid:
            raise RuntimeError(f"a different filesystem is mounted on {target}")
        return
    loops = json.loads(run("losetup", "--json", "--list", "--associated", image,
                           "--output", "NAME"))["loopdevices"]
    if len(loops) > 1:
        raise RuntimeError(f"multiple loop devices reference {image}")
    if loops:
        device = loops[0]["name"]
        locations = subprocess.run(["findmnt", "-n", "-o", "TARGET", "--source", device],
                                   text=True, capture_output=True)
        if locations.returncode == 0 and locations.stdout.strip():
            run("mount", "--bind", locations.stdout.splitlines()[0], target)
            return
    run("mount", "-t", "ext4", "-o", "loop,nosuid,nodev,noatime", image, target)


def reserve_image(path, size_gib, uid, gid):
    expected = size_gib * GIB
    if path.exists():
        if path.is_symlink() or path.stat().st_size != expected:
            raise RuntimeError("existing output image size/type differs; refusing to replace it")
        identity(path)
        return
    if os.statvfs(path.parent).f_bavail * os.statvfs(path.parent).f_frsize < expected + 8 * GIB:
        raise RuntimeError("not enough scratch space to reserve output and retain 8 GiB for bulk work")
    partial = path.with_suffix(".partial")
    # Initialized extents keep output writable even when the outer filesystem fills.
    with partial.open("xb", buffering=0) as stream:
        os.chmod(partial, 0o600)
        os.posix_fallocate(stream.fileno(), 0, expected)
        block = bytes(8 * 1024**2)
        for offset in range(0, expected, len(block)):
            stream.write(block[:min(len(block), expected - offset)])
        os.fsync(stream.fileno())
    run("mkfs.ext4", "-q", "-F", "-m", "0", "-L", "agent-output", "-E",
        f"nodiscard,root_owner={uid}:{gid}", partial)
    partial.replace(path)


def prepare(image, bulk, output, size_gib, output_gib, uid, gid):
    if not image.is_file() or image.is_symlink() or image.stat().st_size != size_gib * GIB:
        raise RuntimeError("the configured scratch image is missing or has an unexpected size")
    mount_image(image, bulk)
    for name, mode in [("tmp", 0o1777), ("var-tmp", 0o1777), ("home/.cache", 0o700)]:
        path = bulk / name
        path.mkdir(mode=mode, parents=True, exist_ok=True)
        os.chown(path, uid, gid)
        path.chmod(mode)
    reserved = bulk / ".output-reserve"
    if reserved.is_symlink():
        raise RuntimeError("output reserve directory must not be a symlink")
    reserved.mkdir(mode=0o755, exist_ok=True)
    os.chown(reserved, 0, 0)
    reserved.chmod(0o755)
    reserve = reserved / "output.img"
    reserve_image(reserve, output_gib, uid, gid)
    os.chown(reserve, 0, 0)
    reserve.chmod(0o600)
    mount_image(reserve, output)
    for name in ("tmp", "state"):
        path = output / name
        path.mkdir(mode=0o700, exist_ok=True)
        os.chown(path, uid, gid)
        path.chmod(0o700)
    print(json.dumps({"bulk": str(bulk), "output": str(output),
                      "total_gib": size_gib, "reserved_output_gib": output_gib}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", type=Path, required=True)
    parser.add_argument("--bulk", type=Path, default=Path("/var/lib/agent-scratch"))
    parser.add_argument("--output", type=Path, default=Path("/var/lib/agent-output"))
    parser.add_argument("--size-gib", type=int, default=128)
    parser.add_argument("--output-gib", type=int, default=8)
    parser.add_argument("--uid", type=int, required=True)
    parser.add_argument("--gid", type=int, required=True)
    args = parser.parse_args()
    if not 0 < args.output_gib < args.size_gib - 8:
        parser.error("output reserve must leave at least 8 GiB for bulk work")
    prepare(args.image, args.bulk, args.output, args.size_gib, args.output_gib, args.uid, args.gid)


if __name__ == "__main__":
    main()
