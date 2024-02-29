{config, inputs, pkgs, ...}:
let
# system = "x86_64-linux";
# overlay-unstable2 = final: prev: {
#   unstable2 = import inputs.nixpkgs-unstable {
#     inherit system;
#     enableCuda = true;
#     config.enableCuda = true;
#   };
# };
in {
  # nixpkgs.overlays = [ overlay-unstable2 ];
  home.packages = [
    # (inputs.pkgs.ollama.override {
    #  enableCuda = true;
    #  })
  #   inputs.ollama.packages.${pkgs.system}.cuda
    # inputs.llamacpp.packages.${pkgs.system}.cuda
  ];
}
