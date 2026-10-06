{ config, lib, pkgs, inputs, ... }:

# The ZBook that replaces nixWorks. Same desktop and home as nixBlade; the
# nixBlade files that are not tied to the Framework or its i7 are imported
# from there rather than copied. Left out on purpose:
#   - agent-throttle.nix: sized for four cores and 15 GB.
#   - prochot-watch.nix: Intel MSRs and the Framework EC.
{
  imports =
    [
      ../../modules/nixos
      ./hardware-configuration.nix
      ./migrate.nix
      ../nixBlade/remote-builds.nix
      ../nixBlade/remote-macs.nix
      ../nixBlade/nix-store-hygiene.nix
      ../nixBlade/coredump.nix
    ];
  networking.hostName = "nixUltra";
  custom.flakeAttr = "nixUltra";
  custom.tailscale.enable = true;
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

    ];
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
  services = {
    displayManager.defaultSession = "hyprland";
    flatpak.enable = true;
    mullvad-vpn.enable = true;

    printing.enable = true;
    fwupd.enable = true;
    fprintd.enable = true;

    xserver.enable = true;
    desktopManager.gnome.enable = true;
    logind.settings.Login = {
      HandleLidSwitch = "hibernate";
      HandleLidSwitchExternalPower = "hibernate";
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
  # Also what resumes from the swapfile: systemd's initrd reads the
  # HibernateLocation EFI variable, so no resume_offset is needed.
  boot.initrd.systemd.enable = true;

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
