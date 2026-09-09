{ lib, config, pkgs, inputs, ... }:
let
  # DECISION 6: this deliberately skips the per-host anonymous overlay that
  # waybar-pomodoro and yc-cli go through. Those are local pkgs/*.nix files that
  # need callPackage; graphide's flake already exposes finished packages via
  # flake-utils.lib.eachDefaultSystem, so there is nothing to callPackage, and
  # `inputs` is already in extraSpecialArgs. Adding a passthrough line to all
  # five overlay blocks would buy symmetry and nothing else.
  gp = inputs.graphide.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  options = {
    graphide = {
      enable = lib.mkEnableOption "Enable Graphide (gr, grat, gred)";
      variant = lib.mkOption {
        type = lib.types.enum [ "dev" "prod" ];
        default = "dev";
        description = ''
          Which gr build to install. DECISION 3: "prod" cannot be built yet --
          gr-prod reads nix/prod-endpoints.nix and refuses while its values
          still start with REPLACE_ME, which they do until the hosted Supabase
          project exists. "dev" bakes the local stack (127.0.0.1:54321 Supabase,
          127.0.0.1:8080 API). Flipping to prod once the endpoints land is one
          word here, not a redesign.
        '';
      };
    };
  };

  config = lib.mkIf config.graphide.enable {
    home.packages = [
      # gr carries grug and grach as siblings in the same bin/ -- the triple is
      # one derivation on purpose, and gred bundles the same variant inside
      # itself so the editor and the CLI cannot point at different stacks.
      (if config.graphide.variant == "prod" then gp.gr-prod else gp.gr-dev)
      gp.grat
      gp.gred
    ];
  };
}
