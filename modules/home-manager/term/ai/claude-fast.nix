{ config, lib, pkgs, inputs, ... }:
let
  # claude-fast: one Claude Code session on Graphide's paid Anthropic API key,
  # in fast mode, skipping the account pool (graphide-tools
  # utilities/scripts/claude-fast/README.md). The key is decrypted from the
  # pool's secret in the pinned graphide-tools with the monolith's sops age key.
  claudeFast = pkgs.writeShellScriptBin "claude-fast" ''
    export PATH=${lib.makeBinPath [ pkgs.age pkgs.python3 pkgs.curl pkgs.gnused pkgs.coreutils ]}:"$PATH"
    export GRAPHIDE_MONOLITH="''${GRAPHIDE_MONOLITH:-$HOME/Projects/graphide/graphide}"
    exec ${pkgs.bash}/bin/bash ${inputs.graphide-tools}/utilities/scripts/claude-fast/claude-fast.sh "$@"
  '';
in {
  options.ai.claude-fast.enable = lib.mkOption {
    type = lib.types.bool;
    default = config.ai.enable && config.ai.claude.enable;
    defaultText = lib.literalExpression "config.ai.enable && config.ai.claude.enable";
    description = "`claude-fast`: Claude Code in fast mode on Graphide's paid Anthropic API key.";
  };

  config = lib.mkIf config.ai.claude-fast.enable {
    home.packages = [ claudeFast ];
  };
}
