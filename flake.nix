{
  description = "Nixos config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.11";
    home-manager = {
      url = "github:nix-community/home-manager/release-23.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
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
    hyprland.url = "github:hyprwm/Hyprland";
    hycov={
      url = "github:DreamMaoMao/hycov";
      inputs.hyprland.follows = "hyprland";
    };
    # hypridle.url = "github:hyprwm/hypridle";
    # ags.url = "github:Aylur/ags";
    # ollama = {
    #   url = "github:abysssol/ollama-flake/cuda-testing";
    #   inputs.nixpkgs.follows = "nixpkgs"; };
    llamacpp.url = "github:ggerganov/llama.cpp";
    asztal.url = "github:Aylur/dotfiles";
  };

  outputs = { self, nixpkgs, home-manager, nixpkgs-unstable, ... }@inputs:
    let
    system = "x86_64-linux";
  pkgs = nixpkgs.legacyPackages.${system};
  overlay-unstable = final: prev: {
      unstable = nixpkgs-unstable.legacyPackages.${prev.system};
  };
  overlay-unstable-unfree = final: prev: {
    unstable-unfree = import nixpkgs-unstable {
      inherit system;
      config.allowUnfree = true;
    };
  };
  in rec {
    nixosConfigurations.nixBlade = nixpkgs.lib.nixosSystem rec {
      specialArgs = {inherit inputs;};
      modules = [ 
        ({ config, pkgs, ... }: { nixpkgs.overlays = [ overlay-unstable overlay-unstable-unfree ]; })
        ./hosts/nixBlade/configuration.nix
        inputs.home-manager.nixosModules.default
        ({
         home-manager = {
         useGlobalPkgs = true;
         useUserPackages = true;
         extraSpecialArgs = specialArgs;
         users.greencheetah = import ./hosts/nixBlade/home.nix;
         };
         })
      ];
    };
    homeConfigurations.nixBlade = home-manager.lib.homeManagerConfiguration {
      extraSpecialArgs = {inherit inputs;};
      inherit pkgs;
      modules = [
        ({ config, pkgs, ... }: { nixpkgs.overlays = [ overlay-unstable overlay-unstable-unfree ]; })
        ./hosts/nixBlade/home.nix 
      ];
    };
  };
}
