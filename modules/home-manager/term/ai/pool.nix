# The shared account pool on XiaServer (graphide-tools' services.ai-pool):
# `ai-pool claude` and `ai-pool codex` on PATH, the loopback forward the
# Graphide plugin steers the pool through (127.0.0.1:18318), and the pool's
# card in the Quickshell accounts panel. This machine's key and the control
# token are files in ~/.config/graphide, delivered by `ai-pool-keys`; nothing
# here holds one.
#
# graphide-tools gained the module at monolith 0e248d07a4. Until the lock
# reaches that commit this file does nothing, so the bump that brings the
# module in also switches it on.
{ config, lib, pkgs, inputs, ... }:
let
  pool = inputs.graphide-tools.homeManagerModules.ai-pool or null;
in {
  imports = lib.optional (pool != null) pool;
  config = lib.optionalAttrs (pool != null) {
    services.ai-pool = {
      enable = lib.mkDefault config.ai.enable;
      # The vendors' own binaries. `claude` and `codex` on PATH are the
      # account wrappers (accounts.nix), which pick a local sign-in.
      claudeCommand = lib.getExe config.ai.claude.package;
      codexCommand = lib.getExe pkgs.master.unfree.codex;
    };
  };
}
