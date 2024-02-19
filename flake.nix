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
    # nix-colors.url = "github:misterio77/nix-colors";
    xremap-flake.url = "github:xremap/nix-flake";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, ... }@inputs:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      overlay-unstable = final: prev: {
        unstable = nixpkgs-unstable.legacyPackages.${prev.system};
      };
      in
      {
        nixosConfigurations.nixBlade = nixpkgs.lib.nixosSystem {
          specialArgs = {inherit inputs;};
          modules = [ 
            ({ config, pkgs, ... }: { nixpkgs.overlays = [ overlay-unstable ]; })
            ./hosts/nixBlade/configuration.nix
# inputs.home-manager.nixosModules.default
          ];
        };

      };
}
