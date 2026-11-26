{ lib, stdenvNoCC, fetchurl, patchelf, makeWrapper, glibc, bash, bubblewrap, socat }:

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
      --prefix PATH : ${lib.makeBinPath [ bubblewrap socat ]} \
      --set-default REASON_CLI_LAUNCHER_PATH $out/libexec/reason-worker \
      --set-default REASON_NO_UPDATE_NOTICE 1
    # The worker probes /bin/bash even when Bash is already on PATH.
    cat > $out/libexec/reason-worker <<EOF
    #!${lib.getExe bash}
    if [ -x /bin/bash ]; then
      exec $out/bin/reason "\$@"
    fi
    exec ${lib.getExe bubblewrap} --die-with-parent --dev-bind / / --tmpfs /bin \\
      --ro-bind /bin/sh /bin/sh --ro-bind ${lib.getExe bash} /bin/bash \\
      -- $out/bin/reason "\$@"
    EOF
    chmod +x $out/libexec/reason-worker
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
