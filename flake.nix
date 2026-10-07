{
  description = "Nixos config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-master.url = "github:nixos/nixpkgs/master";
    claude-code = {
      url = "github:sadjow/claude-code-nix";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    nix-flatpak = {
      url = "github:gmodena/nix-flatpak";
    };
    lanzaboote = {
      url = "git+https://github.com/nix-community/lanzaboote?ref=refs/tags/v1.2.0&shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-colors.url = "github:misterio77/nix-colors";
    firefox-css-hacks = { url = "github:MrOtherGuy/firefox-csshacks"; flake = false; };
    fcitx5-gruvbox = { url = "github:ayamir/fcitx5-gruvbox"; flake = false; };
    gruvbox-wallpapers = { url = "github:AngelJumbo/gruvbox-wallpapers"; flake = false; };
    gruvbox-kvantum = { url = "github:isouravgope/Gruvbox-Kvantum"; flake = false; };
    waybar-pomodoro = {
      url = "github:Andeskjerf/waybar-module-pomodoro";
      flake = false;
    };
    graphide = {
      # git+ssh, not `github:`: the repo is private and the GitHub *API*
      # fetcher `github:` uses needs an access token in nix.conf, which this
      # machine deliberately does not have. SSH reuses the key git already
      # authenticates with. Still a GitHub-hosted, revision-locked input --
      # NOT the local ~/Projects checkout, whose branch state is shared by
      # concurrent sessions and has been stale.
      url = "git+ssh://git@github.com/graphideHQ/monolith";
      # Deliberately NO inputs.nixpkgs.follows. graphide keeps its own tested
      # nixpkgs pin (nixos-25.11) independent of this flake's nixos-26.05, so
      # the installed gr/grat/gred is exactly what graphide's own dev shell and
      # CI built and tested. The cost -- a second nixpkgs evaluated and fetched,
      # and a larger closure -- is accepted on purpose. Do not "tidy" a follows
      # back in: move graphide forward in its own repo first, where the move can
      # be tested, rather than rebuilding it here against an untried channel.
    };
    # Reusable modules/tools have their own pin: the release updater replaces
    # `graphide` with its tested editor artifact without rolling these back.
    graphide-tools.url = "git+ssh://git@github.com/GraphideHQ/monolith";
  };

  outputs = { self, nixpkgs, home-manager, nixpkgs-master, nixpkgs-unstable, ... }@inputs:
    let
      system = "x86_64-linux";
      nixpkgsConfig = {
        permittedInsecurePackages = [
          "electron-39.8.10"
          "olm-3.2.16"
        ];
      };
      pkgs = import nixpkgs {
        inherit system;
        config = nixpkgsConfig;
      };
      overlay-unfree = final: prev: {
        unfree = import nixpkgs {
          inherit system;
          config = nixpkgsConfig // {
            allowUnfree = true;
          };
        };
      };
      overlay-unstable-unfree = final: prev: {
        unstable.unfree = import nixpkgs-unstable {
          inherit system;
          config = nixpkgsConfig // {
            allowUnfree = true;
          };
        };
      };
      overlay-master-unfree = final: prev: {
        master.unfree = import nixpkgs-master {
          inherit system;
          config = nixpkgsConfig // {
            allowUnfree = true;
          };
        };
      };
    in
    rec {
      nixosConfigurations.nixWorks = nixpkgs.lib.nixosSystem rec {
        specialArgs = { inherit inputs; };
        modules = [
          ({ config, pkgs, ... }: {
            nixpkgs.config = nixpkgsConfig;
            nixpkgs.overlays = [
              overlay-unfree
              overlay-master-unfree
              overlay-unstable-unfree
              (final: prev: {
                waybar-pomodoro = prev.callPackage ./pkgs/waybar-module-pomodoro.nix { inherit inputs; };
              })
            ];
          })
          ./hosts/nixBlade/configuration.nix
        ];
      };
      homeConfigurations.nixWorks = home-manager.lib.homeManagerConfiguration {
        extraSpecialArgs = {
          inherit inputs;
          osConfig = nixosConfigurations.nixWorks.config;
          flakeAttr = "nixWorks";
        };
        inherit pkgs;
        modules = [
          ({ config, pkgs, ... }: {
            nixpkgs.config = nixpkgsConfig;
            nixpkgs.overlays = [
              overlay-unfree
              overlay-unstable-unfree
              overlay-master-unfree
              (final: prev: {
                waybar-pomodoro = prev.callPackage ./pkgs/waybar-module-pomodoro.nix { inherit inputs; };
              })
            ];
          })
          ./hosts/nixBlade/home.nix
        ];
      };
      nixosConfigurations.nixUltra = nixpkgs.lib.nixosSystem rec {
        specialArgs = { inherit inputs; };
        modules = [
          ({ config, pkgs, ... }: {
            nixpkgs.config = nixpkgsConfig;
            nixpkgs.overlays = [
              overlay-unfree
              overlay-master-unfree
              overlay-unstable-unfree
              (final: prev: {
                waybar-pomodoro = prev.callPackage ./pkgs/waybar-module-pomodoro.nix { inherit inputs; };
              })
            ];
          })
          ./hosts/nixUltra/configuration.nix
        ];
      };
      homeConfigurations.nixUltra = home-manager.lib.homeManagerConfiguration {
        extraSpecialArgs = {
          inherit inputs;
          osConfig = nixosConfigurations.nixUltra.config;
          flakeAttr = "nixUltra";
        };
        inherit pkgs;
        modules = [
          ({ config, pkgs, ... }: {
            nixpkgs.config = nixpkgsConfig;
            nixpkgs.overlays = [
              overlay-unfree
              overlay-unstable-unfree
              overlay-master-unfree
              (final: prev: {
                waybar-pomodoro = prev.callPackage ./pkgs/waybar-module-pomodoro.nix { inherit inputs; };
              })
            ];
          })
          ./hosts/nixUltra/home.nix
        ];
      };
      # nix build .#nixosConfigurations.nixUltraInstaller.config.system.build.isoImage
      nixosConfigurations.nixUltraInstaller = nixpkgs.lib.nixosSystem {
        modules = [ ./hosts/nixUltra/installer.nix ];
      };
      nixosConfigurations.phantomServ = nixpkgs.lib.nixosSystem rec {
        specialArgs = { inherit inputs; };
        modules = [
          ({ config, pkgs, ... }: { nixpkgs.config = nixpkgsConfig; nixpkgs.overlays = [ overlay-unfree overlay-master-unfree overlay-unstable-unfree ]; })
          ./hosts/phantomServ/configuration.nix
        ];
      };
      homeConfigurations.phantomServ = home-manager.lib.homeManagerConfiguration {
        extraSpecialArgs = {
          inherit inputs;
          osConfig = nixosConfigurations.phantomServ.config;
          flakeAttr = "phantomServ";
        };
        inherit pkgs;
        modules = [
          ({ config, pkgs, ... }: {
            nixpkgs.config = nixpkgsConfig;
            nixpkgs.overlays = [
              overlay-unfree
              overlay-unstable-unfree
              overlay-master-unfree
              (final: prev: {
                waybar-pomodoro = prev.callPackage ./pkgs/waybar-module-pomodoro.nix { inherit inputs; };
              })
            ];
          })
          ./hosts/phantomServ/home.nix
        ];
      };
      nixosConfigurations.omegaServ = nixpkgs.lib.nixosSystem rec {
        specialArgs = { inherit inputs; };
        modules = [
          ({ config, pkgs, ... }: {
            nixpkgs.config = nixpkgsConfig;
            nixpkgs.overlays = [
              overlay-unfree
              overlay-master-unfree
              overlay-unstable-unfree
              (final: prev: {
                waybar-pomodoro = prev.callPackage ./pkgs/waybar-module-pomodoro.nix { inherit inputs; };
              })
            ];
          })
          ./hosts/omegaServ/configuration.nix
        ];
      };
      homeConfigurations.omegaServ = home-manager.lib.homeManagerConfiguration {
        extraSpecialArgs = {
          inherit inputs;
          osConfig = nixosConfigurations.omegaServ.config;
          flakeAttr = "omegaServ";
        };
        inherit pkgs;
        modules = [
          ({ config, pkgs, ... }: {
            nixpkgs.config = nixpkgsConfig;
            nixpkgs.overlays = [
              overlay-unfree
              overlay-unstable-unfree
              overlay-master-unfree
              (final: prev: {
                waybar-pomodoro = prev.callPackage ./pkgs/waybar-module-pomodoro.nix { inherit inputs; };
              })
            ];
          })
          ./hosts/omegaServ/home.nix
        ];
      };
    };
}
