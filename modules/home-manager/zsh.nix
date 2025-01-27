{ pkgs, config, inputs, ... }:

{
  home.packages = with pkgs; [
    bat
    eza
  ];
  programs.zsh = {
    completionInit = "";
    enable = true;
    history = {
      extended = true;
      ignoreAllDups = true;
      ignoreSpace = true;
      path = "$HOME/.local/share/zsh/history";
    };
    # syntaxHighlighting.enable = true;
    enableCompletion = false;
    defaultKeymap = "viins";
    # autosuggestion = {
    #   enable = true;
    #   strategy = [
    #     "history"
    #     "completion"
    #   ];
    # };
    shellAliases = {
      nixswitch = "sudo nixos-rebuild switch --flake $HOME/nixos/#nixBlade && notify-send 'updated'";
      homeswitch = "home-manager switch --flake $HOME/nixos/#nixBlade && notify-send 'updated'";
      nixtest = "sudo nixos-rebuild test --fast --flake $HOME/nixos/#nixBlade && notify-send 'updated'";
      nixwatch = "cd ~/nixos && dirwatch nixtest";
      homewatch = "cd ~/nixos && dirwatch homeswitch";
      cat = "bat";
      ls = "eza";
      vpnexit = "mullvad split-tunnel add \$\$";
    };
    initExtraBeforeCompInit = ''
            # Set the root name of the plugins files (.txt and .zsh) antidote will use.
      zsh_plugins=''${ZDOTDIR:-~}/.zsh_plugins

      # Ensure the .zsh_plugins.txt file exists so you can add plugins.
      [[ -f ''${zsh_plugins}.txt ]] || touch ''${zsh_plugins}.txt

      # Lazy-load antidote from its functions directory.
      fpath=(${pkgs.antidote}/share/antidote/functions $fpath)
      autoload -Uz antidote

      # Generate a new static file whenever .zsh_plugins.txt is updated.
      if [[ ! ''${zsh_plugins}.zsh -nt ''${zsh_plugins}.txt ]]; then
        antidote bundle <''${zsh_plugins}.txt >|''${zsh_plugins}.zsh
      fi

      # Source your static plugins file.
      source ''${zsh_plugins}.zsh
    '';
    initExtra = ''
            source $HOME/.p10k.zsh
            rn() {${pkgs.coreutils}/bin/shuf -i 1-$1 -n 1} # Random number
            getip() { ${pkgs.curl}/bin/curl -s https://json.geoiplookup.io/"$1" | ${pkgs.jq}/bin/jq '.ip, .city, .isp' }
            genpas() {tr -dc A-Za-z0-9 </dev/urandom | head -c $1; echo}
            std() {
              echo 'echo """' > /tmp/out
              (`rep $1 $2`; ls) | xargs -n 1 nl -s$' ' -w1 |\
                  awk '{if ($2 ~ /^[0-9]+$/) for(i=0; i<$2; i++) print $0; else print $0}' |\
                  sed 's/^\([0-9]*\) [0-9]* /\1 /g' |\
                  sed '/^[0-9]* .*[0-9].*/!p' |\
                  shuf -n 1 >> /tmp/out
                  echo '"""' >> /tmp/out
                  zsh /tmp/out
                  nvim `awk 'NR == 2 {print $2}' /tmp/out` +`awk 'NR == 2 {print $1}' /tmp/out`
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
            nix-shell-unstable() {
            echo """
      { pkgs ? import <nixpkgs> {} }:
      let
        unstable = import <nixos-unstable> {};
      in
      pkgs.mkShell {
        nativeBuildInputs = [
          unstable.$1
        ];
      }
      """ > /tmp/nix-shell-unstable.nix
      shift
      nix-shell /tmp/nix-shell-unstable.nix $@
      }
      swap() {
        local a=$1
        local b=$2
        local tmp=$(mktemp)
        mv $a $tmp
        mv $b $a
        mv $tmp $b
      }
    '';
  };
  home.file.".zsh_plugins.txt".text = ''
    jeffreytse/zsh-vi-mode
    zsh-users/zsh-autosuggestions
    zdharma-continuum/fast-syntax-highlighting kind:defer
    romkatv/powerlevel10k
  '';
}
