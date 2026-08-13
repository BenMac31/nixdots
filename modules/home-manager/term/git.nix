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
}
