{ config, lib, pkgs, inputs, osConfig, ... }:
let
  storageEnabled = osConfig.services.agentStorage.enable or false;
  sessionPrefix = lib.optionalString storageEnabled
    "${config.services.agentScratch.runtimePackage}/bin/agent-storage session -- ";
  codexApi = pkgs.writeShellScriptBin "codex-api" ''
    # The account selector replaces CODEX_HOME; API sessions need the vendor binary.
    export PATH=${lib.makeBinPath [ pkgs.master.unfree.codex pkgs.sops pkgs.python3 pkgs.curl pkgs.coreutils pkgs.gnused ]}:"$PATH"
    export GRAPHIDE_MONOLITH="''${GRAPHIDE_MONOLITH:-$HOME/Projects/graphide/graphide}"
    ${lib.optionalString storageEnabled "export BASH_ENV=${config.services.agentScratch.bashInit}"}
    exec ${sessionPrefix}${pkgs.bash}/bin/bash ${inputs.graphide-tools}/utilities/scripts/codex-api/codex-api.sh "$@"
  '';
in {
  options.ai.codex-api.enable = lib.mkEnableOption "Codex with Graphide's OpenAI API credits";

  config = lib.mkIf config.ai.codex-api.enable {
    home.packages = [ codexApi ];
    home.sessionVariables.GRAPHIDE_MONOLITH = "${config.home.homeDirectory}/Projects/graphide/graphide";
  };
}
