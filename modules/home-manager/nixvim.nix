{pkgs, inputs, ...}:
{
imports = 
  [
    inputs.nixvim.homeManagerModules.nixvim
  ];
  programs.nixvim = {
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
