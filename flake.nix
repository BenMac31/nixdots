{
  description = "Nixos config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixpkgs-master.url = "github:nixos/nixpkgs/master";
# arkenfox = {
#   url = "github:dwarfmaster/arkenfox-nixos";
#   inputs.nixpkgs.follows = "nixpkgs";
# };
    nix-flatpak = {
      url = "github:gmodena/nix-flatpak";
    };
# nixvim = {
#   url = "github:nix-community/nixvim/nixos-23.11";
#   inputs.nixpkgs.follows = "nixpkgs";
# };
    nix-colors.url = "github:misterio77/nix-colors";
    gBar.url = "github:scorpion-26/gBar";
    xremap-flake.url = "github:xremap/nix-flake";
    hyprland = {
      url = "github:hyprwm/Hyprland";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # hyprrazer={
    #   url = "github:benmac31/hyprrazer/flake";
    # };
    # hypridle.url = "github:hyprwm/hypridle";
    # ags.url = "github:Aylur/ags";
    ollama = {
      url = "github:abysssol/ollama-flake";
      inputs.nixpkgs.follows = "nixpkgs"; 
     };
    llamacpp.url = "github:ggerganov/llama.cpp";
    asztal.url = "github:Aylur/dotfiles";
    firefox-css-hacks = { url = "github:MrOtherGuy/firefox-csshacks"; flake = false; };
    fcitx5-gruvbox = { url = "github:ayamir/fcitx5-gruvbox"; flake = false; };
  };

  outputs = { self, nixpkgs, home-manager, nixpkgs-master, ... }@inputs:
    let
    system = "x86_64-linux";
  pkgs = nixpkgs.legacyPackages.${system};
  overlay-master = final: prev: {
      master = nixpkgs-master.legacyPackages.${prev.system};
  };
  overlay-unfree = final: prev: {
    unfree = import nixpkgs{
      inherit system;
      config.allowUnfree = true;
    };
  };
  overlay-master-unfree = final: prev: {
    master.unfree = import nixpkgs-master{
      inherit system;
      config.allowUnfree = true;
    };
  };
  in rec {
    nixosConfigurations.nixBlade = nixpkgs.lib.nixosSystem rec {
      specialArgs = {inherit inputs;};
      modules = [ 
        ({ config, pkgs, ... }: { nixpkgs.overlays = [ overlay-unfree overlay-master overlay-master-unfree ]; })
        ./hosts/nixBlade/configuration.nix
      ];
    };
    homeConfigurations.nixBlade = home-manager.lib.homeManagerConfiguration {
      extraSpecialArgs = {inherit inputs;};
      inherit pkgs;
      modules = [
        ({ config, pkgs, ... }: { nixpkgs.overlays = [ overlay-unfree overlay-master overlay-master-unfree ]; })
        ./hosts/nixBlade/home.nix 
      ];
    };
  };
}
