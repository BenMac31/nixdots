{pkgs, ...}:
{
  home.packages = with pkgs; [ #
    zathura
    texliveFull
    libreoffice-qt
    hunspell
  ];
}
