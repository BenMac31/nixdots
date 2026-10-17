{ writeShellApplication, writeText, qemu_kvm, virt-viewer, xorriso, socat, curl, openssh, coreutils, gawk }:

let
  # Runs as root in the guest. The account has no password, so nothing may
  # ask for one: GDM logs in, the screen never locks, polkit lets sudo through,
  # and the welcome wizard counts as done.
  desktop = writeText "ubuntu-vm-desktop" ''
    #!/bin/sh
    set -eu
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -q
    apt-get install -y -q -o Dpkg::Options::=--force-confold ubuntu-desktop-minimal spice-vdagent
    printf '[daemon]\nAutomaticLoginEnable=true\nAutomaticLogin=ubuntu\n' > /etc/gdm3/custom.conf
    printf '%s\n' '[org.gnome.desktop.screensaver]' 'lock-enabled=false' \
      '[org.gnome.desktop.session]' 'idle-delay=uint32 0' \
      > /usr/share/glib-2.0/schemas/90_ubuntu-vm.gschema.override
    glib-compile-schemas /usr/share/glib-2.0/schemas
    printf '%s\n' 'polkit.addRule(function (action, subject) {' \
      '  if (subject.isInGroup("sudo")) return polkit.Result.YES;' '});' \
      > /etc/polkit-1/rules.d/49-ubuntu-vm.rules
    . /etc/os-release
    cfg=/home/ubuntu/.config
    install -d -o ubuntu -g ubuntu "$cfg" "$cfg/gnome-initial-setup"
    install -o ubuntu -g ubuntu -m 644 /dev/null "$cfg/gnome-initial-setup-done"
    install -o ubuntu -g ubuntu -m 644 /dev/null "$cfg/gnome-initial-setup/upgrade-$VERSION_ID-done"
    systemctl set-default graphical.target
    systemctl restart display-manager
  '';
in
writeShellApplication {
  name = "ubuntu-vm";
  runtimeInputs = [ qemu_kvm virt-viewer xorriso socat curl openssh coreutils gawk ];
  text = ''
    release=26.04
    cpus=6
    memory=6G
    disk=32G
    port=2222

    dir="$HOME/.local/share/vms/ubuntu"
    run="$XDG_RUNTIME_DIR/ubuntu-vm"
    image="ubuntu-$release-server-cloudimg-amd64.img"
    url="https://cloud-images.ubuntu.com/releases/$release/release"

    ssh_vm() {
      ssh -i "$dir/id_ed25519" -o IdentitiesOnly=yes -o AddKeysToAgent=no \
        -o UserKnownHostsFile="$dir/known_hosts" -o StrictHostKeyChecking=accept-new \
        -p "$port" ubuntu@127.0.0.1 "$@"
    }

    prepare() {
      mkdir -p "$dir"
      cd "$dir"
      if [ ! -e "$image" ]; then
        curl -fL --retry 3 -o "$image.part" "$url/$image"
        sum=$(curl -fsSL "$url/SHA256SUMS" | awk -v f="*$image" '$2 == f { print $1 }')
        echo "$sum  $image.part" | sha256sum -c --quiet -
        mv "$image.part" "$image"
      fi
      [ -e id_ed25519 ] || ssh-keygen -q -t ed25519 -N "" -C ubuntu-vm -f id_ed25519
      if [ ! -e seed.iso ]; then
        mkdir -p seed
        printf 'instance-id: ubuntu-vm\nlocal-hostname: ubuntu-vm\n' > seed/meta-data
        {
          echo "#cloud-config"
          echo "ssh_authorized_keys:"
          for key in id_ed25519.pub "$HOME/.ssh/id_rsa.pub"; do
            if [ -e "$key" ]; then sed 's/^/  - /' "$key"; fi
          done
          # The account has no password; the console socket is as private as the key.
          printf '%s\n' \
            "write_files:" \
            "  - path: /etc/systemd/system/serial-getty@ttyS0.service.d/autologin.conf" \
            "    content: |" \
            "      [Service]" \
            "      ExecStart=" \
            "      ExecStart=-/usr/sbin/agetty --autologin ubuntu --noreset --noclear --keep-baud 115200,57600,38400,9600 - \''${TERM}" \
            "  - path: /usr/local/sbin/ubuntu-vm-desktop" \
            "    permissions: '0755'" \
            "    content: |"
          sed 's/^/      /' ${desktop}
          printf '%s\n' \
            "runcmd:" \
            "  - [systemctl, daemon-reload]" \
            "  - [systemctl, restart, serial-getty@ttyS0.service]" \
            "  - [/usr/local/sbin/ubuntu-vm-desktop]"
        } > seed/user-data
        xorriso -as genisoimage -quiet -output seed.iso -volid cidata -joliet -rock \
          seed/user-data seed/meta-data
      fi
      [ -e disk.qcow2 ] || qemu-img create -q -f qcow2 -F qcow2 -b "$image" disk.qcow2 "$disk"
    }

    # Runs as the transient unit's main process; `stop` powers it off over QMP.
    boot() {
      mkdir -p "$run"
      cd "$dir"
      exec qemu-system-x86_64 -name ubuntu-vm \
        -machine q35,accel=kvm -cpu host -smp "$cpus" -m "$memory" \
        -drive if=virtio,file=disk.qcow2,format=qcow2,discard=unmap \
        -drive if=virtio,file=seed.iso,format=raw,readonly=on \
        -nic "user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:$port-:22" \
        -device virtio-rng-pci \
        -display none -vga none -device virtio-vga-gl \
        -spice "unix=on,addr=$run/spice.sock,disable-ticketing=on,gl=on" \
        -device virtio-serial-pci -chardev spicevmc,id=vdagent,name=vdagent \
        -device virtserialport,chardev=vdagent,name=com.redhat.spice.0 \
        -device qemu-xhci -device usb-tablet \
        -chardev "socket,id=console,path=$run/console.sock,server=on,wait=off,logfile=$dir/console.log" \
        -serial chardev:console \
        -qmp "unix:$run/qmp.sock,server=on,wait=off"
    }

    powerdown() {
      printf '%s\n' '{"execute":"qmp_capabilities"}' '{"execute":"system_powerdown"}' \
        | socat - "UNIX-CONNECT:$run/qmp.sock" > /dev/null
      while kill -0 "$MAINPID" 2> /dev/null; do sleep 1; done
    }

    start() {
      if systemctl --user -q is-active ubuntu-vm; then
        echo "ubuntu-vm is already running"
      else
        prepare
        self=$(realpath "''${BASH_SOURCE[0]}")
        systemd-run --user -q --unit=ubuntu-vm --collect \
          -p TimeoutStopSec=90 -p "ExecStop=$self powerdown" "$self" boot
      fi
      echo "waiting for ssh on 127.0.0.1:$port"
      for _ in $(seq 180); do
        if ssh_vm -o BatchMode=yes -o ConnectTimeout=2 true 2> /dev/null; then
          echo "waiting for cloud-init; a new VM spends ~15 min installing the desktop"
          ssh_vm cloud-init status --wait > /dev/null \
            || echo "cloud-init reported errors: ubuntu-vm ssh cloud-init status --long" >&2
          return
        fi
        sleep 1
      done
      echo "ssh did not come up; see $dir/console.log" >&2
      exit 1
    }

    case "''${1:-ssh}" in
      start) start ;;
      view)
        systemctl --user -q is-active ubuntu-vm || start
        exec remote-viewer --title ubuntu-vm "spice+unix://$run/spice.sock"
        ;;
      stop) systemctl --user stop ubuntu-vm ;;
      status) systemctl --user status ubuntu-vm ;;
      ssh) shift || true; ssh_vm "$@" ;;
      console)
        echo "serial console; Ctrl-] to detach"
        socat -,raw,echo=0,escape=0x1d "UNIX-CONNECT:$run/console.sock"
        ;;
      boot) boot ;;
      powerdown) powerdown ;;
      *)
        echo "usage: ubuntu-vm [start|view|stop|status|ssh [cmd...]|console]" >&2
        exit 2
        ;;
    esac
  '';
}
