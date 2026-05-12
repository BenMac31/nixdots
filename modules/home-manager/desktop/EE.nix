{ lib, config, inputs, pkgs, ... }:
{
  options = {
    engineer = {
      enable = lib.mkEnableOption "Enable AI";
      localrun.enable = lib.mkEnableOption "Enable local AI";
    };
  };
  config = lib.mkIf config.ai.enable {
    home.packages = [
      pkgs.aichat
      (pkgs.writeShellApplication
        {
          name = "getchips";
          runtimeInputs = [ pkgs.rofi pkgs.zathura];
          text = ''
            ls ~/Documents/Chips | rofi -dmenu | xargs -I {} zathura "~/Documents/Chips/{}"
          '';
        })
      (lib.mkIf config.ai.localrun.enable pkgs.unfree.openai-whisper)
      (lib.mkIf config.ai.localrun.enable pkgs.ollama)
    ];
  };
}
