{ config, lib, pkgs, inputs, osConfig, ... }:
{
  programs.git = {
    enable = true;
    userName = "Benjamin McIntyre";
    userEmail = "mcintybi@mail.uc.edu";
    aliases = {
      # Push HEAD as it was at the current moment (useful for resetting a branch
      # to its state before a rebase/amend that happened "just now").
      pushtillnow = ''!git push origin $(git rev-list -1 --before="@{now}" HEAD):master'';
    };
  };

  # gh serves github.com https credentials to git and sits on PATH, so a store
  # garbage collection cannot break a helper path pinned in ~/.gitconfig.
  programs.gh = {
    enable = true;
    gitCredentialHelper.enable = true;
    settings.aliases.co = "pr checkout";
  };
}
