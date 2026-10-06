{ lib, pkgs, modulesPath, ... }:
# Live USB that installs nixUltra: boot it, run `sudo install-nixUltra`.
#
# Nothing secret is in this image -- it is built on XiaServer and its store
# is readable there. Every saved wifi profile, the GitHub key and a tarball of
# dev credentials ride on a separate NIXSECRETS FAT partition that
# scripts/nixultra-usb.sh appends to the stick after the ISO. usb-secrets
# below loads the wifi and the key at boot, before NetworkManager starts;
# the install unpacks the tarball into the new home, so gh, ssh, gpg/pass and
# the Claude/Codex accounts work at first login, before `migrate-from` runs.
let
  install = pkgs.writeShellApplication {
    name = "install-nixUltra";
    runtimeInputs = with pkgs; [
      btrfs-progs coreutils cryptsetup curl dosfstools git gnutar gptfdisk
      openssh util-linux zstd nixos-install-tools
    ];
    text = ''
      [ "$(id -u)" = 0 ] || { echo "run as root: sudo install-nixUltra"; exit 1; }

      disk="''${1:-}"
      if [ -z "$disk" ]; then
        mapfile -t nvme < <(lsblk -dnpo NAME,TRAN | awk '$2 == "nvme" { print $1 }')
        [ "''${#nvme[@]}" = 1 ] || { lsblk -d; echo "pass the target disk: install-nixUltra /dev/..."; exit 1; }
        disk="''${nvme[0]}"
      fi
      case "$disk" in *[0-9]) part="''${disk}p" ;; *) part="$disk" ;; esac

      until curl -sfI --max-time 10 https://github.com >/dev/null; do
        echo "No network. Connect with nmtui (in another tty), then press enter."
        read -r
      done

      eval "$(ssh-agent -s)"
      trap 'ssh-agent -k >/dev/null' EXIT
      ssh-add /root/.ssh/id_rsa
      rm -rf /tmp/nixos
      git clone git@github.com:BenMac31/nixdots.git /tmp/nixos

      lsblk "$disk"
      read -r -p "Everything on $disk will be erased. Type ERASE to continue: " answer
      [ "$answer" = ERASE ] || exit 1

      wipefs -af "$disk"
      sgdisk --zap-all "$disk"
      sgdisk -n1:0:+1G -t1:ef00 -c1:NIXBOOT -n2:0:0 -t2:8309 -c2:nixultra-luks "$disk"
      udevadm settle
      mkfs.fat -F32 -n NIXBOOT "''${part}1"

      echo "Choose the disk encryption passphrase:"
      cryptsetup luksFormat --type luks2 -q --verify-passphrase "''${part}2"
      echo "Enter it once more to unlock:"
      cryptsetup open --allow-discards "''${part}2" root
      mkfs.btrfs -f -L nixultra /dev/mapper/root

      mount /dev/mapper/root /mnt
      for sv in root nix home swap; do btrfs subvolume create "/mnt/$sv"; done
      umount /mnt
      mount -o subvol=root,compress=zstd,noatime /dev/mapper/root /mnt
      mkdir -p /mnt/nix /mnt/home /mnt/swap /mnt/boot
      mount -o subvol=nix,compress=zstd,noatime /dev/mapper/root /mnt/nix
      mount -o subvol=home,compress=zstd,noatime /dev/mapper/root /mnt/home
      mount -o subvol=swap,noatime /dev/mapper/root /mnt/swap
      mount -o fmask=0077,dmask=0077 "''${part}1" /mnt/boot
      btrfs filesystem mkswapfile --size 64g /mnt/swap/swapfile

      mkdir -p /mnt/home/greencheetah
      cp -a /tmp/nixos /mnt/home/greencheetah/nixos
      nixos-install --flake /mnt/home/greencheetah/nixos#nixUltra --no-root-passwd --no-channel-copy

      install -d -m 700 /mnt/etc/NetworkManager/system-connections
      cp /etc/NetworkManager/system-connections/* /mnt/etc/NetworkManager/system-connections/ || true
      chmod 600 /mnt/etc/NetworkManager/system-connections/*
      install -d -m 700 /mnt/home/greencheetah/.ssh
      install -m 600 /root/.ssh/id_rsa /mnt/home/greencheetah/.ssh/id_rsa
      install -m 644 /root/.ssh/id_rsa.pub /mnt/home/greencheetah/.ssh/id_rsa.pub
      if [ -e /run/usb-secrets/devcreds.tar.zst ]; then
        tar --zstd -xpf /run/usb-secrets/devcreds.tar.zst -C /mnt/home/greencheetah
      fi
      mkdir -p /mnt/home/greencheetah/Projects/graphide
      git clone git@github.com:graphideHQ/monolith /mnt/home/greencheetah/Projects/graphide/graphide
      git clone git@github.com:GraphideHQ/agent-config.git /mnt/home/greencheetah/Projects/graphide/agent-config
      chmod 700 /mnt/home/greencheetah
      chown -R 1000:100 /mnt/home/greencheetah

      echo "Set the login password for greencheetah:"
      until nixos-enter --root /mnt -c 'passwd greencheetah'; do :; done

      echo "Done. Remove the USB stick and run: reboot"
    '';
  };
in
{
  imports = [ (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix") ];

  nixpkgs.hostPlatform = "x86_64-linux";
  networking.hostName = "nixUltra-installer";
  networking.networkmanager.enable = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  # Level 19 (the default) is minutes of CPU per rebuild for a stick that
  # gets written once.
  isoImage.squashfsCompression = "zstd -Xcompression-level 6";

  programs.ssh.knownHosts."github.com".publicKey =
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";

  environment.systemPackages = [ install pkgs.git pkgs.rsync ];

  systemd.services.usb-secrets = {
    description = "Load wifi profiles and the GitHub key from the NIXSECRETS partition";
    wantedBy = [ "multi-user.target" ];
    before = [ "NetworkManager.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = with pkgs; [ coreutils gnutar util-linux ];
    script = ''
      dev=/dev/disk/by-label/NIXSECRETS
      for _ in $(seq 20); do [ -e "$dev" ] && break; sleep 0.5; done
      [ -e "$dev" ] || { echo "no NIXSECRETS partition"; exit 0; }
      mkdir -p /run/usb-secrets
      mount -o ro,umask=0077 "$dev" /run/usb-secrets
      install -d -m 700 /etc/NetworkManager/system-connections
      tar -C /etc/NetworkManager/system-connections --no-same-owner -xf /run/usb-secrets/nm.tar
      chmod 600 /etc/NetworkManager/system-connections/*
      install -d -m 700 /root/.ssh
      install -m 600 /run/usb-secrets/ssh/id_rsa /root/.ssh/id_rsa
      install -m 644 /run/usb-secrets/ssh/id_rsa.pub /root/.ssh/id_rsa.pub
    '';
  };
}
