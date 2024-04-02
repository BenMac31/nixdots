{pkgs, config, inputs, ...}:

{
  home.packages = with pkgs; [
    bat
    eza
  ];
  programs.zsh = {
    enable = true;
    history.extended = true;
    shellAliases = {
      nixswitch = "sudo nixos-rebuild switch --flake $HOME/nixos/#nixBlade";
      homeswitch = "home-manager switch --flake $HOME/nixos/#nixBlade";
      nixtest = "sudo nixos-rebuild test --fast --flake $HOME/nixos/#nixBlade";
      cat = "bat";
      ls = "eza";
      vpnexit = "mullvad split-tunnel add \$\$";
    };
    zplug = {
      enable = true;
      plugins = [
      { name = "zsh-users/zsh-autosuggestions"; }
      ];
    };
    initExtra = ''
    rn() {${pkgs.coreutils}/bin/shuf -i 1-$1 -n 1} # Random number
    getip() { ${pkgs.curl}/bin/curl -s https://json.geoiplookup.io/"$1" | ${pkgs.jq}/bin/jq '.ip, .city, .isp' }
    '';
  };
}
