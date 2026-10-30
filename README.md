# nixos

NixOS and Home Manager configurations for my machines.

| Flake attribute | Host | Machine |
| --- | --- | --- |
| `nixUltra` | `hosts/nixUltra` | HP ZBook, the daily laptop |
| `nixWorks` | `hosts/nixBlade` | Framework laptop |
| `omegaServ` | `hosts/omegaServ` | Home server: Matrix, Minecraft, WireGuard |
| `phantomServ` | `hosts/phantomServ` | Home Assistant and media |
| `nixUltraInstaller` | `hosts/nixUltra/installer.nix` | Install ISO for nixUltra |

## Switching

```sh
nixswitch     # sudo nixos-rebuild switch --flake ~/nixos#<this machine>
homeswitch    # home-manager switch --flake ~/nixos#<this machine>
nixtest       # nixos-rebuild test, nothing made permanent
```

The aliases come from `modules/home-manager/term/zsh.nix` and pick the
machine from `custom.flakeAttr`.

## Layout

- `flake.nix`: inputs and the host list. Every machine gets the same package
  set: stable nixpkgs, plus `pkgs.unfree`, `pkgs.unstable.unfree` and
  `pkgs.master.unfree`.
- `hosts/<host>/`: `configuration.nix`, `home.nix` and hardware for one
  machine. `hosts/laptop/` holds the files both laptops import, home included;
  nixBlade uses that home as it is.
- `modules/nixos/`: system modules every host imports; `head/` is the desktop,
  `serv/` the services.
- `modules/home-manager/`: `desktop/`, `term/` (shell, editors, AI tools) and
  `themes/`. `graphide.nix` is the Graphide setup, imported by the laptops.
- `confs/`: config that is not Nix (Neovim, the browser start page).
- `pkgs/`, `scripts/`: one local package and a few one-off machine scripts.

## Graphide

`graphide-autoupdate` keeps the released `gr` and `grug` in a Nix profile of its
own, so no Graphide release is pinned here. `graphide-tools` pins
GraphideHQ/graphide-tools: the shared Home Manager modules, grail, gdev and the
internal scripts, which left the monolith when it was split (2026-10-28). It
locks the monolith it builds against itself. `graphide-website` supplies the
brand mark fastfetch draws. Bump them with upstream Nix, since Lix cannot
resolve graphide-tools' monolith input by its branch ref:

```sh
nix run nixpkgs#nixVersions.latest -- --extra-experimental-features 'nix-command flakes' \
  flake update graphide-tools graphide-website
```

Codex goes through the shared account pool on XiaServer
(`modules/nixos/codex-pool.nix`), and `ai-pool claude` runs Claude through it.
Local sign-ins stay with the account wrappers in
`modules/home-manager/term/ai/accounts.nix`.
