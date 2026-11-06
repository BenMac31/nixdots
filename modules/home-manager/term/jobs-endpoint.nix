{ config, lib, inputs, osConfig, ... }:
let
  modules = inputs.graphide-tools.homeManagerModules;
  # The module arrived in graphide-tools 8ba69eba (2026-11-06); until this
  # flake's lock passes it, this file does nothing.
  present = modules ? jobs-endpoint;
in
{
  # The job tracker on loopback port 8471 for Graphide's jobs plugin
  # (<leader>jj): its socket starts it on the first request, and it exits
  # after 15 idle minutes. Only this laptop has the tracker's checkout.
  imports = lib.optional present modules.jobs-endpoint;
}
// lib.optionalAttrs present {
  services.graphide-jobs-endpoint = lib.mkIf (osConfig.networking.hostName == "nixUltra") {
    enable = true;
    command = "python3 ${config.home.homeDirectory}/Projects/graphide/graphide-tools/utilities/testworker/jobtracker";
  };
}
