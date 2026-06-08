{ lib, config, inputs, upgks, pkgs, flakeAttr, ... }:
{
  config = lib.mkIf config.programs.neovim.enable {
    programs.neovim = {
      package = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.neovim-unwrapped;
      defaultEditor = true;
      vimdiffAlias = true;
      # HM 26.05 writes nvim/init.lua by default; sideload so our live symlinked config dir is not overridden.
      sideloadInitLua = true;
      withNodeJs = true;
      withPython3 = true;
      withRuby = true;
      extraLuaPackages = ps: [ ps.magick ];
      extraPackages = [
        pkgs.lsof
        pkgs.librsvg
        pkgs.imagemagick
        inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.opencode
        pkgs.jdk21
      ];
    };
    home.packages = [
      pkgs.stylua
      pkgs.python312Packages.flake8
      pkgs.shellcheck
      pkgs.rustup
      pkgs.gcc
      pkgs.tree-sitter
      pkgs.luajitPackages.magick
      pkgs.clang-tools
    ];
    xdg.configFile = lib.mkIf (flakeAttr == "nixBlade") {
      "lvim" = {
        enable = true;
        source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nixos/confs/lvim";
      };
      "nvim" = {
        enable = true;
        source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nixos/confs/nvim";
      };
    };
  };
}
