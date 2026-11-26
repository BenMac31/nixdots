{ lib, stdenv, fetchurl, dpkg, autoPatchelfHook, makeShellWrapper, wrapGAppsHook3
, alsa-lib, at-spi2-atk, at-spi2-core, cairo, cups, dbus, expat, glib, gtk3
, libdrm, libgbm, libnotify, libsecret, libuuid, libxkbcommon, mesa, nspr, nss
, pango, systemd, libGL, vulkan-loader, xdg-utils, xorg
}:

stdenv.mkDerivation rec {
  pname = "t3code";
  version = "0.1.12";

  src = fetchurl {
    url = "https://github.com/pingdotgg/t3code/releases/download/v${version}/T3-Code-${version}-amd64.deb";
    sha256 = "c1ca3e656e12ba10377513e9bbe20a5112540cda9601e21c70b85ba7c53f1b29";
  };

  nativeBuildInputs = [ dpkg autoPatchelfHook makeShellWrapper wrapGAppsHook3 ];

  buildInputs = [
    alsa-lib at-spi2-atk at-spi2-core cairo cups dbus expat glib gtk3 libdrm
    libgbm libnotify libsecret libuuid libxkbcommon mesa nspr nss pango
    stdenv.cc.cc.lib systemd vulkan-loader
    xorg.libX11 xorg.libXcomposite xorg.libXdamage xorg.libXext xorg.libXfixes
    xorg.libXrandr xorg.libXScrnSaver xorg.libXtst xorg.libxcb xorg.libxshmfence
  ];

  dontWrapGApps = true;

  unpackPhase = "dpkg-deb -x $src .";

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib $out/bin $out/share
    cp -r "opt/T3 Code (Beta)" $out/lib/t3code
    find $out/lib/t3code -depth \( -name '*musl*' -o -name 'linux-arm64' -o -name '*linux-arm64*' \) -exec rm -rf {} +
    cp -r usr/share/icons $out/share/
    install -Dm644 usr/share/applications/t3code.desktop $out/share/applications/t3code.desktop
    substituteInPlace $out/share/applications/t3code.desktop \
      --replace-fail 'Exec="/opt/T3 Code (Beta)/t3code"' "Exec=t3code"
    runHook postInstall
  '';

  postFixup = ''
    makeShellWrapper $out/lib/t3code/t3code $out/bin/t3code \
      "''${gappsWrapperArgs[@]}" \
      --set T3CODE_DISABLE_AUTO_UPDATE 1 \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ libGL vulkan-loader systemd ]} \
      --prefix PATH : ${lib.makeBinPath [ xdg-utils ]} \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}"
    makeShellWrapper $out/lib/t3code/t3code $out/bin/t3 \
      --set ELECTRON_RUN_AS_NODE 1 \
      --set T3CODE_CLI_PATH $out/bin/t3 \
      --set T3CODE_DISABLE_AUTO_UPDATE 1 \
      --add-flags $out/lib/t3code/resources/app.asar/apps/server/dist/bin.mjs
  '';

  meta = {
    description = "Desktop app for coding agents";
    homepage = "https://t3.codes";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "t3code";
  };
}
