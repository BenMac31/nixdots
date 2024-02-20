{pkgs, inputs, ...}:
{
# home.packages = [
# inputs.gBar.defaultPackage.x86_64-linux
# ];
  imports = [ inputs.gBar.homeManagerModules.x86_64-linux.default ];
  programs.gBar = {
    enable = true;
    config = {
      Location = "T";
      EnableSNI = true;
      SNIIconSize = {
        Discord = 26;
        OBS = 23;
      };
      WorkspaceSymbols = [ " " " " ];
      CenterTime = true;
    };
    extraConfig = ''
      WidgetsRight: [Tray, Audio, Bluetooth, Network, VRAM, GPU, RAM, CPU, Battery]
      '';
  };
}
