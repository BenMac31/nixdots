{
  description = "Ben's NixOS and Home Manager configurations";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-master.url = "github:nixos/nixpkgs/master";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    lanzaboote = {
      url = "git+https://github.com/nix-community/lanzaboote?ref=refs/tags/v1.2.0&shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    claude-code = {
      url = "github:sadjow/claude-code-nix";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    nix-flatpak.url = "github:gmodena/nix-flatpak";
    nix-colors.url = "github:misterio77/nix-colors";
    firefox-css-hacks = { url = "github:MrOtherGuy/firefox-csshacks"; flake = false; };
    fcitx5-gruvbox = { url = "github:ayamir/fcitx5-gruvbox"; flake = false; };
    gruvbox-kvantum = { url = "github:isouravgope/Gruvbox-Kvantum"; flake = false; };
    waybar-pomodoro = { url = "github:Andeskjerf/waybar-module-pomodoro"; flake = false; };

    # Private, so SSH rather than `github:`, which would need an API token.
    # No nixpkgs follows: gr and grat stay on the nixpkgs Graphide tests them with.
    graphide.url = "git+ssh://git@github.com/graphideHQ/monolith";
    # The shared modules and tools, pinned apart so the release updater can
    # move `graphide` without rolling them back.
    graphide-tools.url = "git+ssh://git@github.com/GraphideHQ/monolith";
  };

  outputs = { self, nixpkgs, home-manager, ... }@inputs:
    let
      system = "x86_64-linux";
      nixpkgsConfig.permittedInsecurePackages = [ "electron-39.8.10" "olm-3.2.16" ];
      unfree = channel: import channel {
        inherit system;
        config = nixpkgsConfig // { allowUnfree = true; };
      };
      packageSet = {
        nixpkgs.config = nixpkgsConfig;
        nixpkgs.overlays = [
          (final: prev: {
            unfree = unfree nixpkgs;
            unstable.unfree = unfree inputs.nixpkgs-unstable;
            master.unfree = unfree inputs.nixpkgs-master;
            waybar-pomodoro = prev.callPackage ./pkgs/waybar-module-pomodoro.nix { inherit inputs; };
          })
        ];
      };

      host = configuration: nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs; };
        modules = [ packageSet configuration ];
      };
      home = name: configuration: home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs { inherit system; config = nixpkgsConfig; };
        extraSpecialArgs = {
          inherit inputs;
          osConfig = self.nixosConfigurations.${name}.config;
          flakeAttr = name;
        };
        modules = [ packageSet configuration ];
      };
    in
    {
      nixosConfigurations = {
        nixWorks = host ./hosts/nixBlade/configuration.nix;
        nixUltra = host ./hosts/nixUltra/configuration.nix;
        phantomServ = host ./hosts/phantomServ/configuration.nix;
        omegaServ = host ./hosts/omegaServ/configuration.nix;
        # nix build .#nixosConfigurations.nixUltraInstaller.config.system.build.isoImage
        nixUltraInstaller = nixpkgs.lib.nixosSystem {
          modules = [ ./hosts/nixUltra/installer.nix ];
        };
      };

      homeConfigurations = {
        nixWorks = home "nixWorks" ./hosts/laptop/home.nix;
        nixUltra = home "nixUltra" ./hosts/nixUltra/home.nix;
        phantomServ = home "phantomServ" ./hosts/phantomServ/home.nix;
        omegaServ = home "omegaServ" ./hosts/omegaServ/home.nix;
      };
    };
}
