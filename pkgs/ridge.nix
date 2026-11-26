{ rustPlatform }:

rustPlatform.buildRustPackage {
  pname = "ridge";
  version = "0.2.0";
  src = ./ridge-src;
  cargoLock.lockFile = ./ridge-src/Cargo.lock;
}
