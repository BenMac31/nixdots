#!/usr/bin/env bash
# Write the nixUltra installer stick: the ISO, then a NIXSECRETS partition
# with every saved wifi profile, the GitHub key and a dev-credentials
# tarball (hosts/nixUltra/installer.nix says how each is used).
#
#   nix build .#nixosConfigurations.nixUltraInstaller.config.system.build.isoImage
#   sudo cp /etc/NetworkManager/system-connections/* <dir>/ && sudo chown "$USER" <dir>/*
#   nix shell nixpkgs#mtools nixpkgs#dosfstools nixpkgs#zstd \
#     -c scripts/nixultra-usb.sh result/iso/*.iso <dir> stick.img
#   sudo dd if=stick.img of=/dev/sdX bs=4M conv=fsync status=progress
#
# Build to an image file, then write it in one go. Writing straight to a
# chowned /dev/sdX breaks: udev resets the owner when the first dd closes.
#
# The stick ends up holding live credentials in the clear. Wipe it after.
set -euo pipefail

iso=$1 nm=$2 dev=$3
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Profiles are pinned to this laptop's wifi card and, mostly, to
# user:greencheetah, which the live USB's `nixos` login is not. Drop both so
# they autoconnect on the stick and at boot on the new machine. They go in a
# tar: SSIDs carry emoji and other names FAT cannot hold.
mkdir -p "$work/nm" "$work/s/ssh"
for f in "$nm"/*; do
  grep -q '^type=wifi' "$f" || continue
  sed '/^interface-name=/d; /^mac-address=/d; /^permissions=/d' "$f" > "$work/nm/$(basename "$f")"
done
tar -C "$work/nm" -cf "$work/s/nm.tar" .
cp ~/.ssh/id_rsa ~/.ssh/id_rsa.pub "$work/s/ssh/"

# Credentials and account state only. Transcripts, caches and logs are most
# of the bytes and come over later with migrate-from.
paths=(
  .ssh .gnupg .password-store .local/share/keyrings
  .config/gh .config/git .gitconfig .config/rbw .local/share/rbw
  .docker .azure .yc .config/github-copilot .config/.wrangler
  .claude.json .claude .codex .config/graphide .local/state/graphide
  .zsh_history .histfile
  Projects/graphide/CLAUDE.md Projects/graphide/AGENTS.md
)
present=()
for p in "${paths[@]}"; do
  if [ -e ~/"$p" ] || [ -L ~/"$p" ]; then present+=("$p"); fi
done
(cd ~ && find "${present[@]}" \
  \( -type d \( -name projects -o -name file-history -o -name jobs -o -name sessions \
     -o -name cache -o -name log -o -name shell-snapshots -o -name telemetry \
     -o -name paste-cache -o -name backups -o -name .tmp -o -name tmp \) -prune \) \
  -o \( -lname '/nix/store/*' -o -type s -o -name '.claude.json.tmp.*' \
     -o -name 'logs_*.sqlite*' -o -name 'thread_history_*.sqlite*' \) \
  -o -print0) |
  tar -C ~ --null --no-recursion -T - --zstd -cpf "$work/s/devcreds.tar.zst"

mib=$(( $(du -sm "$work/s" | cut -f1) + 64 ))
truncate -s "${mib}M" "$work/secrets.img"
mkfs.vfat -n NIXSECRETS "$work/secrets.img" >/dev/null
mcopy -s -i "$work/secrets.img" "$work/s/"* ::/

iso_bytes=$(stat -Lc %s "$iso")
start_mib=$(( (iso_bytes + 1048575) / 1048576 + 1 ))

dd if="$iso" of="$dev" bs=4M conv=fsync status=progress
dd if="$work/secrets.img" of="$dev" bs=1M seek="$start_mib" conv=fsync status=progress
echo "$(( start_mib * 2048 )),$(( mib * 2048 )),c" |
  sfdisk --append --no-reread --no-tell-kernel --wipe never "$dev"

# Sector 0 differs by the new partition entry; check the boot code before it
# and everything after it.
cmp -n 446 "$iso" "$dev"
cmp -i 512 -n "$(( iso_bytes - 512 ))" "$iso" "$dev"
cmp -n "$(( mib * 1048576 ))" "$work/secrets.img" <(dd if="$dev" bs=1M skip="$start_mib" count="$mib" status=none)
sfdisk -l "$dev"
echo "Stick written and verified: $(find "$work/nm" -type f | wc -l) wifi profiles."
