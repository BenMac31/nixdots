{ config, lib, pkgs, inputs, ... }:
let
  upstream = inputs.graphide-tools;
  system = pkgs.stdenv.hostPlatform.system;
  # Keep the shared shell pinned; apply this desktop's daily chart to its API.
  packages = upstream.packages.${system} // {
    graphide-accounts = config.services.graphide-accounts.package;
    hackerboard-api = upstream.packages.${system}.hackerboard-api.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./api.patch ];
      patchFlags = (old.patchFlags or [ "-p1" ]) ++ [ "--fuzz=0" ];
      nativeCheckInputs = (old.nativeCheckInputs or [ ]) ++ [
        (pkgs.python3.withPackages (p: [ p.httpx p.psycopg ]))
      ];
      doCheck = true;
      checkPhase = ''
        runHook preCheck
        PYTHONPATH="$PWD" python3 ${./test_daily_activity.py} -v
        runHook postCheck
      '';
    });
  };
  shell = pkgs.applyPatches {
    name = "graphide-shell-daily-activity";
    src = "${upstream}/nix/home-manager/quickshell/shell";
    patches = [ ./shell.patch ./widgets.patch ];
    patchFlags = [ "-p1" "--fuzz=0" ];
    postPatch = ''
      cp ${./ActivityChart.qml} ActivityChart.qml
      echo 'ActivityChart 1.0 ActivityChart.qml' >> qmldir
    '';
  };
in
{
  imports = [
    (import "${upstream}/nix/home-manager/quickshell.nix" (upstream // {
      packages = upstream.packages // { ${system} = packages; };
    }))
  ];

  config = lib.mkIf config.programs.graphide-shell.enable {
    xdg.configFile."quickshell/graphide".source = lib.mkForce shell;
    systemd.user.services.graphide-shell.Unit.X-Restart-Triggers = [ "${shell}" ];
  };
}
