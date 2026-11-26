{ lib, stdenv, fetchurl, dpkg, autoPatchelfHook, wrapGAppsHook3, alsa-lib
, at-spi2-core, cairo, cups, dbus, expat, glib, gtk3, libgbm, libGL, libsecret, libx11
, libxcb, libxcomposite, libxdamage, libxext, libxfixes, libxi, libxkbcommon
, libxrandr, nspr, nss, pango, systemd, vulkan-loader, xdg-utils
}:

stdenv.mkDerivation rec {
  pname = "composal-desktop";
  version = "0.1.185";

  src = fetchurl {
    url = "https://dl.composal.com/desktop/v${version}/linux-x64/Composal-linux-x64.deb";
    hash = "sha256-VMduP7OoLop/ezDuM/CjpjC79f/7GzfYxneQ+b9CUNU=";
  };

  nativeBuildInputs = [ dpkg autoPatchelfHook wrapGAppsHook3 ];
  buildInputs = [
    alsa-lib at-spi2-core cairo cups dbus expat glib gtk3 libgbm libx11 libxcb
    libxcomposite libxdamage libxext libxfixes libxi libxkbcommon libxrandr
    nspr nss pango stdenv.cc.cc.lib systemd
  ];

  dontUnpack = true;
  dontStrip = true;
  installPhase = ''
    runHook preInstall
    dpkg-deb --fsys-tarfile "$src" | tar -xf - --exclude='./usr/lib/composal-desktop/chrome-sandbox'
    mkdir -p "$out/bin"
    mv usr/lib usr/share "$out/"
    makeWrapper "$out/lib/composal-desktop/Composal" "$out/bin/composal-desktop" \
      --prefix PATH : ${lib.makeBinPath [ xdg-utils ]} \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ libGL libsecret vulkan-loader ]}
    runHook postInstall
  '';

  meta = {
    description = "Composal desktop client for Sparks";
    homepage = "https://composal.com";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "composal-desktop";
  };
}
