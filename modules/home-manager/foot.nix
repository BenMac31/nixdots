{pkgs, ...}:
{
  programs.foot = {
    enable = true;
    server.enable = true;
    settings = {
      main = {
        font = "FiraCodeNerdFont-Regular:size=10";
      };
    };
  };
}
