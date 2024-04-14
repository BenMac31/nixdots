{lib, config, inputs, pkgs, ...}:
{
  home.packages = [
    pkgs.lunarvim
      pkgs.neovim
      pkgs.stylua
      pkgs.python312Packages.flake8
      pkgs.shellcheck
      pkgs.luajitPackages.magick # funky images
  ];
  xdg.configFile."lvim" = {
    enable = true;
    source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nixos/confs/lvim";
  };
  home.sessionVariables = {
    EDITOR = "${pkgs.lunarvim}/bin/lvim";
  };
}
