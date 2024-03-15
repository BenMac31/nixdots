{pkgs, config, inputs, ...}:

{
  home.packages = with pkgs; [
    bat
    eza
  ];
  programs.zsh = {
    enable = true;
    shellAliases = {
      nixswitch = "sudo nixos-rebuild switch --flake $HOME/nixos/#nixBlade";
      homeswitch = "home-manager switch --flake $HOME/nixos/#nixBlade";
      nixtest = "sudo nixos-rebuild test --fast --flake $HOME/nixos/#nixBlade";
      cat = "bat";
      ls = "eza";
    };
    zplug = {
      enable = true;
      plugins = [
      { name = "zsh-users/zsh-autosuggestions"; }
      ];
    };
  };
}
