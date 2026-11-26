{ lib, stdenv, fetchurl, autoPatchelfHook }:

# Google's Antigravity agent CLI (the `agy` ACP runtime). T3 Code drives it as
# a provider, and that is the only way to reach the Gemini models it serves
# (gemini-4-neon among them). T3 can download its own copy from Google's
# auto-updater, but that build wants /lib64/ld-linux-x86-64.so.2, so on NixOS
# it has to come from here instead.
#
# Bumping the version: the manifest T3 reads is
#   https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/linux_amd64.json
# It gives the version, the url below (the number after the version is a build
# id that changes every release) and a sha512 to check the download against.
stdenv.mkDerivation rec {
  pname = "antigravity-cli";
  version = "1.5.18";

  src = fetchurl {
    url = "https://storage.googleapis.com/antigravity-public/antigravity-cli/${version}-6386224290725888/linux-x64/cli_linux_x64.tar.gz";
    hash = "sha256-pJYHI+2c9bWscu1UHbjfTWJ0F5UmHrk6RoEAbMsj1a0=";
  };

  nativeBuildInputs = [ autoPatchelfHook ];

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    # T3 Code looks for `agy` on PATH; Google's own tarball calls it
    # `antigravity`. Install both names so either lookup finds it.
    install -Dm755 antigravity $out/bin/agy
    ln -s agy $out/bin/antigravity
    runHook postInstall
  '';

  meta = {
    description = "Google Antigravity agent CLI, the agy ACP runtime";
    homepage = "https://antigravity.google";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "agy";
  };
}
