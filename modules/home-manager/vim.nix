{lib, config, inputs, pkgs, ...}:
{
  home.packages = [
    pkgs.lunarvim
      pkgs.stylua
      pkgs.python312Packages.flake8
      pkgs.shellcheck
    pkgs.rustup
    pkgs.gcc
    pkgs.tree-sitter
      pkgs.luajitPackages.magick 
      pkgs.clang-tools
  ];
  programs.neovim = {
    enable = true;
    package = pkgs.unfree.neovim-unwrapped;
    defaultEditor = true;
    vimdiffAlias = true;
    withNodeJs = true;
    withPython3 = true;
  };
  xdg.configFile."lvim" = {
    enable = true;
    source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nixos/confs/lvim";
  };
  xdg.configFile."nvim" = {
    enable = true;
    source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nixos/confs/nvim";
  };
}
