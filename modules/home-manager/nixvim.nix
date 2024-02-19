{pkgs, inputs, ...}:
{
  imports = 
    [
    inputs.nixvim.homeManagerModules.nixvim
    ];
  programs.nixvim = {
    colorschemes.gruvbox.enable = true;
    enable = true;
    plugins = {
      lualine.enable = true;
      lsp = {
        enable = true;
        servers = {
          nil_ls.enable = true;
        };
      };
    };
  };
}
