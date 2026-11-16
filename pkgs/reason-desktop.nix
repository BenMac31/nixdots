{ lib, stdenv, fetchurl, dpkg, autoPatchelfHook, makeShellWrapper, wrapGAppsHook3
, alsa-lib, at-spi2-atk, at-spi2-core, cairo, cups, dbus, expat, glib, gtk3
, libdrm, libgbm, libnotify, libsecret, libuuid, libxkbcommon, mesa, nspr, nss
, pango, systemd, libGL, vulkan-loader, xdg-utils, xorg
}:

stdenv.mkDerivation rec {
  pname = "reason-desktop";
  version = "0.1.123";

  src = fetchurl {
    url = "https://reasonmachines.com/linux/stable/apt/pool/main/reason-desktop_${version}_amd64.deb";
    sha256 = "355d478f117bff6d8f2ca771cf5462281efe2303cb3b4adb213de54103defefb";
  };

  nativeBuildInputs = [ dpkg autoPatchelfHook makeShellWrapper wrapGAppsHook3 ];

  buildInputs = [
    alsa-lib at-spi2-atk at-spi2-core cairo cups dbus expat glib gtk3 libdrm
    libgbm libnotify libsecret libuuid libxkbcommon mesa nspr nss pango
    xorg.libX11 xorg.libXcomposite xorg.libXdamage xorg.libXext xorg.libXfixes
    xorg.libXrandr xorg.libXScrnSaver xorg.libXtst xorg.libxcb xorg.libxshmfence
  ];

  dontWrapGApps = true;

  unpackPhase = "dpkg-deb -x $src .";

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib $out/bin $out/share
    cp -r opt/Reason $out/lib/reason-desktop
    cp -r usr/share/icons $out/share/
    install -Dm644 usr/share/applications/reason-desktop.desktop $out/share/applications/reason-desktop.desktop
    substituteInPlace $out/share/applications/reason-desktop.desktop \
      --replace-fail "Exec=/opt/Reason/reason-desktop" "Exec=reason-desktop"
    runHook postInstall
  '';

  postFixup = ''
    makeShellWrapper $out/lib/reason-desktop/reason-desktop $out/bin/reason-desktop \
      "''${gappsWrapperArgs[@]}" \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ libGL vulkan-loader systemd ]} \
      --prefix PATH : ${lib.makeBinPath [ xdg-utils ]} \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}"
  '';

  meta = {
    description = "Reason Machines desktop app";
    homepage = "https://reasonmachines.com";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "reason-desktop";
  };
}
