# The shared account pool on XiaServer: `ai-pool claude` and `ai-pool codex`,
# and the loopback forward the Graphide plugin steers it through. This
# machine's pool key and control token are runtime files in ~/.config/graphide,
# delivered by `ai-pool-keys`. Codex reaches the pool through
# modules/nixos/codex-pool.nix.
{ config, lib, pkgs, inputs, ... }:
{
  imports = [ inputs.graphide-tools.homeManagerModules.ai-pool ];
  services.ai-pool = {
    enable = lib.mkDefault config.ai.enable;
    # The vendors' own binaries; `claude` and `codex` on PATH are the account
    # wrappers from accounts.nix.
    claudeCommand = lib.getExe config.ai.claude.package;
    codexCommand = lib.getExe pkgs.master.unfree.codex;
  };
}
