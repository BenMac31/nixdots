{ config, inputs, ... }:
{
  # Uploads AI-agent transcripts to XiaServer's never-deleting library every
  # 15 minutes. Only sessions started inside `roots` leave this machine, and a
  # session named with a leading "." never does; everything else stays local.
  # `graphide-transcripts --list` prints what a run would send.
  imports = [ inputs.graphide-tools.homeManagerModules.transcripts ];
  services.graphide-transcripts = {
    enable = true;
    roots = [
      "${config.home.homeDirectory}/nixos"
      "${config.home.homeDirectory}/Projects/graphide"
    ];
  };
}
