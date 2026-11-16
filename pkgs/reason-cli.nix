{ lib, stdenvNoCC, fetchurl, patchelf, makeWrapper, glibc }:

stdenvNoCC.mkDerivation rec {
  pname = "reason-cli";
  version = "0.2.754";

  src = fetchurl {
    url = "https://reasonmachines.com/cli/releases/download/cli-v${version}/reason-machines-cli-linux-x64-${version}.tgz";
    sha256 = "5fce0de96b94c6b20578d528e1c69123006aedd5c541cd77fec2feb4dc370639";
  };

  nativeBuildInputs = [ patchelf makeWrapper ];

  # A Bun executable carries its JavaScript after the ELF; stripping drops it.
  dontStrip = true;
  dontPatchELF = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/libexec/reason $out/bin
    cp -r bin/. $out/libexec/reason/
    patchelf --set-interpreter ${glibc}/lib/ld-linux-x86-64.so.2 \
      --set-rpath ${lib.makeLibraryPath [ glibc ]} $out/libexec/reason/reason
    makeWrapper $out/libexec/reason/reason $out/bin/reason \
      --set-default REASON_NO_UPDATE_NOTICE 1
    runHook postInstall
  '';

  meta = {
    description = "Reason Machines CLI: run and steer Reason Agent sessions";
    homepage = "https://reasonmachines.com";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "reason";
  };
}
