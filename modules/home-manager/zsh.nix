{ pkgs, config, inputs, ... }:

{
  home.packages = with pkgs; [
    bat
    eza
  ];
  programs.zsh = {
    enable = true;
    history.extended = true;
    syntaxHighlighting.enable = true;
    enableCompletion = true;
    defaultKeymap = "viins";
    oh-my-zsh = {
      enable = true;
      plugins = [ "git" "thefuck" ];
      theme = "robbyrussell";
    };
    shellAliases = {
      nixswitch = "sudo nixos-rebuild switch --flake $HOME/nixos/#nixBlade";
      homeswitch = "home-manager switch --flake $HOME/nixos/#nixBlade";
      nixtest = "sudo nixos-rebuild test --fast --flake $HOME/nixos/#nixBlade";
      nixwatch = "cd ~/nixos && dirwatch nixtest";
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
          genpas() {tr -dc A-Za-z0-9 </dev/urandom | head -c $1; echo}
          std() {
            echo 'echo """' > /tmp/out
            \cat * `rep $1 $2` |\
                awk '{if ($1 ~ /^[0-9]+$/) for(i=0; i<$1; i++) print $0; else print $0}' |\
                sed 's/^[0-9]* //g' |\
                shuf -n 1 >> /tmp/out
                echo '"""' >> /tmp/out
                zsh /tmp/out
                }
          gitrestore() {
          git log --diff-filter=D --summary | grep delete | awk '{print $4}' | fzf -m | while read -r file; do
        commit="$(git log --diff-filter=D --name-only --pretty=format:"%H" | awk -v file="$file" '/./{p = p $0 "\n"}/^$/{if(p ~ file) print p; p = ""} END{if(p ~ file) print p}' | head -n 1)"
        git restore --source="$commit^" -- "$file"
      done
      }
          rep() {for i in $(seq 1 $2); do echo "$1"; done}

          dirwatch() {
          while [ true ]; do
            local a="$(\ls -l -R)"
            if [ "$a" != "$b" ]; then
              eval "$@"
              local b="$a"
              echo "Waiting for next update"
            fi
            sleep 3
          done
          }
    '';
  };
}
