# Working in this repo

- One option per feature: `options.<name>.enable = lib.mkEnableOption ...`, the
  config under `lib.mkIf`, and `lib.mkDefault true` from the parent module that
  turns a group on. Apps follow `desktop/apps/`, one file per program.
- Put new code next to the code it most resembles, not at the bottom of a file.
- Comments explain a why the code cannot show, in a line or two. No history.
- No secrets in Nix: they end up in the world-readable store. Keys stay runtime
  files (see `modules/home-manager/term/ai/pool.nix`).
- Check that a change evaluates one output at a time, for example
  `nix eval .#nixosConfigurations.nixUltra.config.system.build.toplevel.drvPath`.
  Never evaluate all of `.#nixosConfigurations` or `.#homeConfigurations` at
  once.
- Do not run `nix fmt` here: it reformats the whole tree.
- `nixtest` tries a system change without making it the boot default.
