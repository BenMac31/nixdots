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
      cat = "bat";
      ls = "eza";
    };
    zplug = {
      enable = true;
      plugins = [
      { name = "zsh-users/zsh-autosuggestions"; } # Simple plugin installation
      # { name = "romkatv/powerlevel10k"; tags = [ as:theme depth:1 ]; } # Installations with additional options. For the list of options, please refer to Zplug README.
      ];
    };
  };
}
