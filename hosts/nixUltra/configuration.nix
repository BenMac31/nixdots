{ config, lib, pkgs, inputs, ... }:

{
  imports =
    [
      ../../modules/nixos
      ./hardware-configuration.nix
      ./migrate.nix
      ./storage.nix
      ./scratch.nix
      ../../modules/nixos/btrfs-rescue.nix
      ../../modules/nixos/disk-guard.nix
      ./secure-boot.nix
      ./agent-throttle.nix
      ../../modules/nixos/codex-pool.nix
      ../laptop/remote-builds.nix
      ../laptop/remote-macs.nix
      ../laptop/nix-store-hygiene.nix
      ../laptop/coredump.nix
    ];
  networking.hostName = "nixUltra";
  custom.flakeAttr = "nixUltra";
  custom.tailscale.enable = true;
  # Android apps beside the desktop: Graphide's phone app on gred-rs.
  custom.waydroid.enable = true;
  head = {
    enable = true;
    gaming = true;
  };
  programs = {
    hyprland.enable = true;
    nix-ld.enable = true;
    nix-ld.libraries = with pkgs; [

      # Add any missing dynamic libraries for unpackaged programs

      # here, NOT in environment.systemPackages

      # The official Graphide editor gdev downloads and runs unmodified
      # (~/.local/share/gdev). `gdev doctor` lists what it still needs.
      alsa-lib at-spi2-atk at-spi2-core atk cairo cups dbus expat glib gtk3
      libgbm libxkbcommon nspr nss pango
      libx11 libxcomposite libxdamage libxext
      libxfixes libxrandr libxcb
      # The native app (grim) opens these for its window; libGL's EGL is its
      # fallback where Vulkan has no driver.
      fontconfig libGL libxcursor libxi vulkan-loader wayland
    ];
    # boxes.dev rewrites its launcher and boxesdesktop:// handler to exec the
    # raw AppImage on every start; binfmt runs that through appimage-run.
    appimage = {
      enable = true;
      binfmt = true;
    };
    kdeconnect.enable = true;
    noisetorch.enable = true;
  };

  fonts.packages = with pkgs; [
    nerd-fonts.fira-code
    nerd-fonts.droid-sans-mono
    nerd-fonts.jetbrains-mono
    noto-fonts-cjk-sans
    source-han-sans
    source-han-mono
    source-han-serif
    source-han-sans-vf-ttf
    source-han-sans-vf-otf

  ];

  # radeonsi VA-API comes with mesa; nothing extra to add for the 8050S.
  hardware.graphics.enable = true;

  time.timeZone = lib.mkDefault "America/New_York";
  # At boot it asks geoclue before wifi is up, gets NoReply after a minute
  # and exits, leaving the clock on UTC. Keep trying until there is a fix.
  systemd.services.automatic-timezoned.serviceConfig = {
    Restart = "on-failure";
    RestartSec = "30s";
  };
  services = {
    displayManager.defaultSession = "hyprland";
    flatpak.enable = true;
    mullvad-vpn.enable = true;

    printing.enable = true;
    fwupd.enable = true;
    fprintd.enable = true;

    xserver.enable = true;
    desktopManager.gnome.enable = true;
    # s2idle is the only sleep state the G1a firmware offers. Hibernating on
    # every lid close wrote a ~10 GB image and asked for the LUKS passphrase
    # on every open; upower still hibernates at 5%.
    logind.settings.Login = {
      HandleLidSwitch = "suspend";
      HandleLidSwitchExternalPower = "suspend";
    };
    # Same policy as nixBlade, whose configuration.nix has the history: act at
    # 5%, and let upower really hibernate instead of substituting HybridSleep.
    upower = {
      enable = true;
      allowRiskyCriticalPowerAction = true;
      percentageLow = 20;
      percentageCritical = 10;
      percentageAction = 5;
      criticalPowerAction = "Hibernate";
    };
  };
  environment.systemPackages = with pkgs; [
    android-tools
    libusb1
    powertop
    numworks-udev-rules
  ];

  users.users.greencheetah = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = [ "adbusers" "docker" "wheel" "uinput" "input" "video" ]; # Enable ‘sudo’ for the user.
  };
  boot.extraModulePackages = with config.boot.kernelPackages; [
    v4l2loopback
  ];
  # In platform mode a power-key press while the image is being written
  # makes the kernel roll back instead of powering off, and amdgpu (gfx1151)
  # dies on the rollback; the image is invalidated too, so the next boot is
  # cold. Shutdown mode powers off without that check.
  systemd.sleep.settings.Sleep.HibernateMode = "shutdown";
  # Also what resumes from the swapfile: systemd's initrd reads the
  # HibernateLocation EFI variable, so no resume_offset is needed.
  boot.initrd.systemd.enable = true;
  # Thawing devices to write the image makes mt7925e reset the chip, and its
  # reset worker oopses in napi_disable on an RX queue the MT7925 does not
  # have (c4edf9e3e0e5). The image is never written and the next boot is
  # cold: all five hibernations from 2026-10-25 to 11-05, each with the trace
  # in /var/lib/systemd/pstore. Unloaded, there is nothing to reset. Drop
  # once the kernel has "remove wm2_complete_mask from mt7925_irq_map".
  systemd.services.hibernate-unload-wifi = {
    description = "Unload mt7925e across hibernation";
    wantedBy = [ "hibernate.target" "hybrid-sleep.target" "suspend-then-hibernate.target" ];
    before = [ "systemd-hibernate.service" "systemd-hybrid-sleep.service" "systemd-suspend-then-hibernate.service" ];
    unitConfig.StopWhenUnneeded = true;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.kmod}/bin/modprobe -r mt7925e";
      ExecStop = "${pkgs.kmod}/bin/modprobe mt7925e";
    };
  };
  # At the default image_size (2/5 of RAM) preallocation leaves ~11 GB free,
  # then amdgpu evicts VRAM into RAM while devices freeze; past ~5 GB of it
  # the copy no longer fits ("Error -12 creating image", 10-25, 10-30, 11-03)
  # and the laptop stays up at 5% until it dies. 0 shrinks the image as far
  # as reclaim can first.
  systemd.tmpfiles.rules = [ "w /sys/power/image_size - - - - 0" ];

  home-manager = {
    users."greencheetah" = import ./home.nix;
  };
  services.openssh = {
    enable = true;
    ports = [ 22 ];
    settings = {
      PasswordAuthentication = true;
      UseDns = true;
      X11Forwarding = false;
      PermitRootLogin = "prohibit-password"; # "yes", "without-password", "prohibit-password", "forced-commands-only", "no"
    };
  };

  nix.package = pkgs.lix;

  system.stateVersion = "26.05"; # DO NOT CHANGE
  services.udev.extraRules = ''
  SUBSYSTEM=="usb", ATTR{idVendor}=="0483", MODE="0666"
'';
  networking.extraHosts = ''
  127.0.0.1 host.docker.internal
'';
}
