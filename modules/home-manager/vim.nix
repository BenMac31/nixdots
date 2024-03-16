{lib, config, inputs, pkgs, ...}:
{
  home.packages = [
    pkgs.lunarvim
      pkgs.neovim
      pkgs.stylua
      pkgs.python312Packages.flake8
      pkgs.shellcheck
  ];
  xdg.configFile."lvim" = {
  enable = true;
  source = ../../confs/lvim;
  recursive = true;
  };
  home.sessionVariables = {
    EDITOR = "${pkgs.lunarvim}/bin/lvim";
  };
}
