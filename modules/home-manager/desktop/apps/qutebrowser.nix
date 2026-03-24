{ config, lib, pkgs, inputs, ... }:

let
  lock-false = {
    Value = false;
    Status = "locked";
  };
  lock-true = {
    Value = true;
    Status = "locked";
  };
  lock-empty-string = {
    Value = "";
    Status = "locked";
  };
in
{
  config = lib.mkIf config.programs.qutebrowser.enable {
    programs.qutebrowser = {
      enable = lib.mkDefault true;
      package = pkgs.qutebrowser.override {
        pythonPackages = ps: with ps; [
          pkgs.python3Packages.requests
          pkgs.python3Packages.beautifulsoup4
          pkgs.python3Packages.pygments
        ];
      };
      
      settings = {
        "aliases" = {
          "w" = "session-save";
          "q" = "quit";
          "wq" = "quit --save";
          "qa" = "quit --save --all";
        };
        
        "colors" = {
          "hints.bg" = config.colorScheme.palette.base08;
          "hints.fg" = config.colorScheme.palette.base05;
          "statusbar.normal.bg" = config.colorScheme.palette.base00;
          "statusbar.normal.fg" = config.colorScheme.palette.base05;
          "statusbar.insert.bg" = config.colorScheme.palette.base0D;
          "statusbar.insert.fg" = config.colorScheme.palette.base00;
          "statusbar.command.bg" = config.colorScheme.palette.base08;
          "statusbar.command.fg" = config.colorScheme.palette.base00;
          "statusbar.caret.bg" = config.colorScheme.palette.base0B;
          "statusbar.caret.fg" = config.colorScheme.palette.base00;
          "statusbar.progress.bg" = config.colorScheme.palette.base0D;
          "tabs.selected.even.bg" = config.colorScheme.palette.base0D;
          "tabs.selected.even.fg" = config.colorScheme.palette.base00;
          "tabs.selected.odd.bg" = config.colorScheme.palette.base0D;
          "tabs.selected.odd.fg" = config.colorScheme.palette.base00;
          "tabs.even.bg" = config.colorScheme.palette.base00;
          "tabs.even.fg" = config.colorScheme.palette.base03;
          "tabs.odd.bg" = config.colorScheme.palette.base00;
          "tabs.odd.fg" = config.colorScheme.palette.base03;
          "tabs.pinned.even.bg" = config.colorScheme.palette.base03;
          "tabs.pinned.even.fg" = config.colorScheme.palette.base01;
          "tabs.pinned.odd.bg" = config.colorScheme.palette.base03;
          "tabs.pinned.odd.fg" = config.colorScheme.palette.base01;
          "tabs.selected.inactive.even.bg" = config.colorScheme.palette.base0D;
          "tabs.selected.inactive.even.fg" = config.colorScheme.palette.base00;
          "tabs.selected.inactive.odd.bg" = config.colorScheme.palette.base0D;
          "tabs.selected.inactive.odd.fg" = config.colorScheme.palette.base00;
        };
        
        "content" = {
          "host_blocking.enabled" = lock-true;
          "host_blocking.lists" = [
            "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
            "https://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&showintro=0&mimetype=plaintext"
          ];
        };
        
        "editor.command" = ["foot" "lvim" "{file}"];
        
        "fonts" = {
          "default_family" = config.colorScheme.fonts.primary;
          "default_size" = "12pt";
          "monospace" = config.colorScheme.fonts.monospace;
        };
        
        "hints" = {
          "auto_follow" = "always";
          "auto_follow_timeout" = 0;
          "border" = config.colorScheme.palette.base0D;
          "chars" = "asdfghjkl";
          "mode" = "letter";
        };
        
        "keyhint.blacklist" = [
          "j"
          "k"
          "h"
          "l"
          "gg"
          "G"
          "0"
          "$"
          "d"
          "u"
          "r"
          "gi"
          "gf"
          "zi"
          "zo"
          "zz"
          "/"
          "?"
          "n"
          "N"
          ":"
          "o"
          "t"
          "O"
          "T"
          "b"
          "S"
          ";"
          "f"
          "F"
          "H"
          "I"
          "."
        ];
        
        "bindings" = {
          "normal" = {
            "j" = "scroll down";
            "k" = "scroll up";
            "h" = "scroll left";
            "l" = "scroll right";
            "gg" = "scroll to top";
            "G" = "scroll to bottom";
            "0" = "scroll to left";
            "$" = "scroll to right";
            "d" = "scroll down 1/2 page";
            "u" = "scroll up 1/2 page";
            "r" = "reload";
            "gi" = "focus input";
            "gf" = "mode enter insert";
            "zi" = "zoom in";
            "zo" = "zoom out";
            "zz" = "zoom reset";
            "/" = "enter-mode /";
            "?" = "enter-mode ?";
            "n" = "search-next";
            "N" = "search-prev";
            ":" = "enter-mode :";
            "o" = "enter-mode o";
            "t" = "enter-mode t";
            "O" = "tab-new";
            "T" = "tab-take";
            "b" = "enter-mode b";
            "S" = "enter-mode S";
            ";" = "enter-mode ;";
            "f" = "hint";
            "F" = "hint -t";
            "H" = "back";
            "I" = "enter-mode I";
            "." = "repeat-command";
            "," = "command-accept";
            "J" = "tab-next";
            "K" = "tab-prev";
            "<Ctrl-f>" = "scroll-page 0 1";
            "<Ctrl-b>" = "scroll-page 0 -1";
            "<Ctrl-d>" = "scroll-page 0 0.5";
            "<Ctrl-u>" = "scroll-page 0 -0.5";
            "<Ctrl-e>" = "scroll down";
            "<Ctrl-y>" = "scroll up";
            "<Ctrl-l>" = "clear-messages";
            "<Ctrl-p>" = "print";
            "<Ctrl-s>" = "save";
            "<Ctrl-r>" = "reload";
            "<Ctrl-w>" = "tab-close";
            "<Ctrl-t>" = "tab-new";
            "<Ctrl-Tab>" = "tab-next";
            "<Ctrl-Shift-Tab>" = "tab-prev";
            "<Alt-Left>" = "back";
            "<Alt-Right>" = "forward";
            "<Alt-Up>" = "tab-next";
            "<Alt-Down>" = "tab-prev";
          "<F1>" = "help";
          "<F2>" = "set";
          "<F3>" = "quickmark-save";
          "<F4>" = "history";
          "<F5>" = "reload";
          "<F6>" = "tab-take";
          "<F7>" = "tab-pin";
          "<F8>" = "tab-move";
          "<F9>" = "tab-detach";
          "<F10>" = "tab-attach";
          "<F11>" = "fullscreen";
          "<F12>" = "devtools";
            "<Home>" = "scroll to top";
            "<End>" = "scroll to bottom";
            "<PageUp>" = "scroll up 1 page";
            "<PageDown>" = "scroll down 1 page";
            "<Insert>" = "mode-enter insert";
            "<Delete>" = "mode-enter caret";
            "<Escape>" = "mode-leave";
            "<Return>" = "follow";
            "<Space>" = "mode-leave";
          };
          
          "insert" = {
            "<Escape>" = "mode-leave";
            "<Return>" = "follow";
            "<Backspace>" = "fake-key <Backspace>";
            "<Delete>" = "fake-key <Delete>";
            "<Tab>" = "fake-key <Tab>";
            "<Shift-Tab>" = "fake-key <Shift-Tab>";
            "<Ctrl-a>" = "fake-key <Home>";
            "<Ctrl-e>" = "fake-key <End>";
            "<Ctrl-f>" = "fake-key <Right>";
            "<Ctrl-b>" = "fake-key <Left>";
            "<Ctrl-n>" = "fake-key <Down>";
            "<Ctrl-p>" = "fake-key <Up>";
            "<Ctrl-d>" = "fake-key <Delete>";
            "<Ctrl-h>" = "fake-key <Backspace>";
            "<Ctrl-k>" = "fake-key <Shift-End> fake-key <Delete>";
            "<Ctrl-u>" = "fake-key <Shift-Home> fake-key <Delete>";
            "<Ctrl-w>" = "fake-key <Ctrl-Backspace>";
          };
          
          "command" = {
            "<Escape>" = "mode-leave";
            "<Return>" = "command-accept";
            "<Backspace>" = "command-delete";
            "<Delete>" = "command-delete";
            "<Tab>" = "command-completion default";
            "<Shift-Tab>" = "command-completion backward";
            "<Ctrl-a>" = "command-beginning-of-line";
            "<Ctrl-e>" = "command-end-of-line";
            "<Ctrl-f>" = "command-forward-char";
            "<Ctrl-b>" = "command-backward-char";
            "<Ctrl-n>" = "command-next-history";
            "<Ctrl-p>" = "command-previous-history";
            "<Ctrl-d>" = "command-delete";
            "<Ctrl-h>" = "command-delete";
            "<Ctrl-k>" = "command-kill-line";
            "<Ctrl-u>" = "command-kill-line";
            "<Ctrl-w>" = "command-delete-backward-word";
            "<Ctrl-x>" = "command-delete-forward-word";
          };
          
          "/" = {
            "<Escape>" = "mode-leave";
            "<Return>" = "search";
            "<Backspace>" = "search-delete";
            "<Delete>" = "search-delete";
            "<Tab>" = "search-next";
            "<Shift-Tab>" = "search-prev";
            "<Ctrl-a>" = "search-home";
            "<Ctrl-e>" = "search-end";
            "<Ctrl-f>" = "search-forward-char";
            "<Ctrl-b>" = "search-backward-char";
            "<Ctrl-n>" = "search-next-history";
            "<Ctrl-p>" = "search-previous-history";
            "<Ctrl-d>" = "search-delete";
            "<Ctrl-h>" = "search-delete";
            "<Ctrl-k>" = "search-kill-line";
            "<Ctrl-u>" = "search-kill-line";
            "<Ctrl-w>" = "search-delete-backward-word";
            "<Ctrl-x>" = "search-delete-forward-word";
          };
          
          "?" = {
            "<Escape>" = "mode-leave";
            "<Return>" = "search";
            "<Backspace>" = "search-delete";
            "<Delete>" = "search-delete";
            "<Tab>" = "search-next";
            "<Shift-Tab>" = "search-prev";
            "<Ctrl-a>" = "search-home";
            "<Ctrl-e>" = "search-end";
            "<Ctrl-f>" = "search-forward-char";
            "<Ctrl-b>" = "search-backward-char";
            "<Ctrl-n>" = "search-next-history";
            "<Ctrl-p>" = "search-previous-history";
            "<Ctrl-d>" = "search-delete";
            "<Ctrl-h>" = "search-delete";
            "<Ctrl-k>" = "search-kill-line";
            "<Ctrl-u>" = "search-kill-line";
            "<Ctrl-w>" = "search-delete-backward-word";
            "<Ctrl-x>" = "search-delete-forward-word";
          };
          
          "o" = {
            "<Escape>" = "mode-leave";
            "<Return>" = "open";
            "<Backspace>" = "completion-item-del";
            "<Delete>" = "completion-item-del";
            "<Tab>" = "completion-item-focus";
            "<Shift-Tab>" = "completion-item-focus prev";
            "<Ctrl-a>" = "completion-home";
            "<Ctrl-e>" = "completion-end";
            "<Ctrl-f>" = "completion-forward-char";
            "<Ctrl-b>" = "completion-backward-char";
            "<Ctrl-n>" = "completion-item-focus";
            "<Ctrl-p>" = "completion-item-focus prev";
            "<Ctrl-d>" = "completion-item-del";
            "<Ctrl-h>" = "completion-item-del";
            "<Ctrl-k>" = "completion-kill-line";
            "<Ctrl-u>" = "completion-kill-line";
            "<Ctrl-w>" = "completion-delete-backward-word";
            "<Ctrl-x>" = "completion-delete-forward-word";
          };
          
          "t" = {
            "<Escape>" = "mode-leave";
            "<Return>" = "tab-new";
            "<Backspace>" = "completion-item-del";
            "<Delete>" = "completion-item-del";
            "<Tab>" = "completion-item-focus";
            "<Shift-Tab>" = "completion-item-focus prev";
            "<Ctrl-a>" = "completion-home";
            "<Ctrl-e>" = "completion-end";
            "<Ctrl-f>" = "completion-forward-char";
            "<Ctrl-b>" = "completion-backward-char";
            "<Ctrl-n>" = "completion-item-focus";
            "<Ctrl-p>" = "completion-item-focus prev";
            "<Ctrl-d>" = "completion-item-del";
            "<Ctrl-h>" = "completion-item-del";
            "<Ctrl-k>" = "completion-kill-line";
            "<Ctrl-u>" = "completion-kill-line";
            "<Ctrl-w>" = "completion-delete-backward-word";
            "<Ctrl-x>" = "completion-delete-forward-word";
          };
          
          "b" = {
            "<Escape>" = "mode-leave";
            "<Return>" = "quickmark-save";
            "<Backspace>" = "completion-item-del";
            "<Delete>" = "completion-item-del";
            "<Tab>" = "completion-item-focus";
            "<Shift-Tab>" = "completion-item-focus prev";
            "<Ctrl-a>" = "completion-home";
            "<Ctrl-e>" = "completion-end";
            "<Ctrl-f>" = "completion-forward-char";
            "<Ctrl-b>" = "completion-backward-char";
            "<Ctrl-n>" = "completion-item-focus";
            "<Ctrl-p>" = "completion-item-focus prev";
            "<Ctrl-d>" = "completion-item-del";
            "<Ctrl-h>" = "completion-item-del";
            "<Ctrl-k>" = "completion-kill-line";
            "<Ctrl-u>" = "completion-kill-line";
            "<Ctrl-w>" = "completion-delete-backward-word";
            "<Ctrl-x>" = "completion-delete-forward-word";
          };
          
          "S" = {
            "<Escape>" = "mode-leave";
            "<Return>" = "set";
            "<Backspace>" = "completion-item-del";
            "<Delete>" = "completion-item-del";
            "<Tab>" = "completion-item-focus";
            "<Shift-Tab>" = "completion-item-focus prev";
            "<Ctrl-a>" = "completion-home";
            "<Ctrl-e>" = "completion-end";
            "<Ctrl-f>" = "completion-forward-char";
            "<Ctrl-b>" = "completion-backward-char";
            "<Ctrl-n>" = "completion-item-focus";
            "<Ctrl-p>" = "completion-item-focus prev";
            "<Ctrl-d>" = "completion-item-del";
            "<Ctrl-h>" = "completion-item-del";
            "<Ctrl-k>" = "completion-kill-line";
            "<Ctrl-u>" = "completion-kill-line";
            "<Ctrl-w>" = "completion-delete-backward-word";
            "<Ctrl-x>" = "completion-delete-forward-word";
          };
          
          ";" = {
            "<Escape>" = "mode-leave";
            "<Return>" = "command-accept";
            "<Backspace>" = "command-delete";
            "<Delete>" = "command-delete";
            "<Tab>" = "command-completion default";
            "<Shift-Tab>" = "command-completion backward";
            "<Ctrl-a>" = "command-beginning-of-line";
            "<Ctrl-e>" = "command-end-of-line";
            "<Ctrl-f>" = "command-forward-char";
            "<Ctrl-b>" = "command-backward-char";
            "<Ctrl-n>" = "command-next-history";
            "<Ctrl-p>" = "command-previous-history";
            "<Ctrl-d>" = "command-delete";
            "<Ctrl-h>" = "command-delete";
            "<Ctrl-k>" = "command-kill-line";
            "<Ctrl-u>" = "command-kill-line";
            "<Ctrl-w>" = "command-delete-backward-word";
            "<Ctrl-x>" = "command-delete-forward-word";
          };
          
          "I" = {
            "<Escape>" = "mode-leave";
            "<Return>" = "follow";
            "<Backspace>" = "fake-key <Backspace>";
            "<Delete>" = "fake-key <Delete>";
            "<Tab>" = "fake-key <Tab>";
            "<Shift-Tab>" = "fake-key <Shift-Tab>";
            "<Ctrl-a>" = "fake-key <Home>";
            "<Ctrl-e>" = "fake-key <End>";
            "<Ctrl-f>" = "fake-key <Right>";
            "<Ctrl-b>" = "fake-key <Left>";
            "<Ctrl-n>" = "fake-key <Down>";
            "<Ctrl-p>" = "fake-key <Up>";
            "<Ctrl-d>" = "fake-key <Delete>";
            "<Ctrl-h>" = "fake-key <Backspace>";
            "<Ctrl-k>" = "fake-key <Shift-End> fake-key <Delete>";
            "<Ctrl-u>" = "fake-key <Shift-Home> fake-key <Delete>";
            "<Ctrl-w>" = "fake-key <Ctrl-Backspace>";
          };
          
          "caret" = {
            "<Escape>" = "mode-leave";
            "<Return>" = "follow";
            "<Backspace>" = "fake-key <Backspace>";
            "<Delete>" = "fake-key <Delete>";
            "<Tab>" = "fake-key <Tab>";
            "<Shift-Tab>" = "fake-key <Shift-Tab>";
            "<Ctrl-a>" = "fake-key <Home>";
            "<Ctrl-e>" = "fake-key <End>";
            "<Ctrl-f>" = "fake-key <Right>";
            "<Ctrl-b>" = "fake-key <Left>";
            "<Ctrl-n>" = "fake-key <Down>";
            "<Ctrl-p>" = "fake-key <Up>";
            "<Ctrl-d>" = "fake-key <Delete>";
            "<Ctrl-h>" = "fake-key <Backspace>";
            "<Ctrl-k>" = "fake-key <Shift-End> fake-key <Delete>";
            "<Ctrl-u>" = "fake-key <Shift-Home> fake-key <Delete>";
            "<Ctrl-w>" = "fake-key <Ctrl-Backspace>";
          };
        };
      };
    };
  };
}
    };
  };
}