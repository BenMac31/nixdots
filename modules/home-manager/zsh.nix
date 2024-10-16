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
    gitrestore() {
    git log --diff-filter=D --summary | grep delete | awk '{print $4}' | fzf -m | while read -r file; do
  commit="$(git log --diff-filter=D --name-only --pretty=format:"%H" | awk -v file="$file" '/./{p = p $0 "\n"}/^$/{if(p ~ file) print p; p = ""} END{if(p ~ file) print p}' | head -n 1)"
  git restore --source="$commit^" -- "$file"
done
}
    rep() {for i in $(seq 1 $2); do echo "$1"; done}
    '';
  };
}
