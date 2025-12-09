{ inputs, rustPlatform, pkg-config, libnotify }:

rustPlatform.buildRustPackage {
  pname = "waybar-module-pomodoro";
  version = "unstable";
  src = inputs.waybar-pomodoro;
  cargoLock.lockFile = "${inputs.waybar-pomodoro}/Cargo.lock";

  buildInputs = [ libnotify ];
  nativeBuildInputs = [ pkg-config ];

  doCheck = false;
}