{ lib
, stdenvNoCC
, fetchurl
, autoPatchelfHook
}:

let
  version = "0.0.20";
  baseUrl = "https://bookface-public.s3.us-west-2.amazonaws.com/cli";

  sources = {
    x86_64-linux = {
      asset = "yc-linux-x64";
      hash = "sha256-07/397ByjhsYcA47Iy5F3/h/XL/BA/BsC7Lqr9yC+4Y=";
    };
    aarch64-linux = {
      asset = "yc-linux-arm64";
      hash = "sha256-WvDDNDkmJC0dYGADYk3FrhtrbehK7r3fkCD/f8CX0AI=";
    };
    x86_64-darwin = {
      asset = "yc-darwin-x64";
      hash = "sha256-N1FFGwQUqTxqN+Sm8495OOsYvbZwSBQQAxmSrsCKj04=";
    };
    aarch64-darwin = {
      asset = "yc-darwin-arm64";
      hash = "sha256-JvTf8B/JULnws8NMT+e7PFWFq9Gn3Diqji6jeDFy0CE=";
    };
  };

  inherit (stdenvNoCC.hostPlatform) system;
  source = sources.${system} or (throw "yc-cli: unsupported system ${system}");
in
stdenvNoCC.mkDerivation {
  pname = "yc-cli";
  inherit version;

  src = fetchurl {
    url = "${baseUrl}/${version}/${source.asset}";
    inherit (source) hash;
  };

  dontUnpack = true;
  # stripping corrupts the Bun single-file executable's appended payload
  dontStrip = true;

  nativeBuildInputs = lib.optionals stdenvNoCC.hostPlatform.isLinux [
    autoPatchelfHook
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/yc
    runHook postInstall
  '';

  doInstallCheck = stdenvNoCC.buildPlatform.canExecute stdenvNoCC.hostPlatform;
  installCheckPhase = ''
    runHook preInstallCheck
    actual=$($out/bin/yc -v)
    if [ "$actual" != "${version}" ]; then
      echo "yc-cli: expected version ${version}, got '$actual'" >&2
      exit 1
    fi
    runHook postInstallCheck
  '';

  meta = {
    description = "Search Bookface and chat with the YC Agent from the terminal";
    homepage = "https://bookface.ycombinator.com/cli";
    platforms = lib.attrNames sources;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    mainProgram = "yc";
  };
}
