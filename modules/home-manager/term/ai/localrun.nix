{ lib, config, pkgs, ... }:
{
  options = {
    ai.localrun = {
      enable = lib.mkEnableOption "Enable local AI";
    };
  };
  config = lib.mkIf config.ai.localrun.enable {
    home.packages = [
      pkgs.unfree.openai-whisper
      pkgs.ollama
    ];
  };
}
