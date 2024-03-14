{lib, config, inputs, pkgs, ...}:
{
  # nixpkgs.overlays = [ overlay-unstable2 ];
  home.packages = [
    pkgs.aichat
    (pkgs.master.unfree.ollama.override {
     acceleration = "cuda";
     })
    # inputs.ollama.packages.${pkgs.system}.cuda
    # inputs.llamacpp.packages.${pkgs.system}.cuda
  ];
}
