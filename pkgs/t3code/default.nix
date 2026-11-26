{ lib, stdenv, fetchurl, dpkg, autoPatchelfHook, makeShellWrapper, wrapGAppsHook3
, python3
, alsa-lib, at-spi2-atk, at-spi2-core, cairo, cups, dbus, expat, glib, gtk3
, libdrm, libgbm, libnotify, libsecret, libuuid, libxkbcommon, mesa, nspr, nss
, pango, systemd, libGL, vulkan-loader, xdg-utils, xorg

# Inline ./vim-composer.js into the renderer, giving the chat composer vim
# modes. T3's own keybinding layer cannot do this: a binding is one key plus
# modifiers with no modal state, and its command registry holds no
# text-editing command at all. Set this false to get a stock T3 back; the
# build also fails loudly rather than shipping a half-patched bundle if a T3
# release moves the renderer entry point.
, vimComposer ? true
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

  # app.asar carries an app.asar.unpacked tree beside it, so extract-and-repack
  # is out: packing drops the per-entry "unpacked" flags and would inline
  # native modules that have to stay real files. inject-vim.py rewrites the one
  # index.html entry in place instead and leaves the other 2787 byte-identical.
  postInstall = lib.optionalString vimComposer ''
    chmod u+w $out/lib/t3code/resources/app.asar
    ${python3.interpreter} ${./inject-vim.py} \
      $out/lib/t3code/resources/app.asar \
      ${./vim-composer.js} \
      ${./page-vim.js}
    chmod a-w $out/lib/t3code/resources/app.asar
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

  passthru = { inherit vimComposer; };

  meta = {
    description = "Desktop app for coding agents"
      + lib.optionalString vimComposer " (composer patched for vim modes)";
    homepage = "https://t3.codes";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "t3code";
  };
}
