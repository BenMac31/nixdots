{ pkgs, ... }:
# `migrate-from [host]` pulls /home/greencheetah from the old laptop over ssh.
# Safe to re-run: the first pass while nixWorks is still in use, a last one
# after closing everything there. Nothing is deleted on either side.
#
# Profiles and generation links point into the old machine's store, so they
# stay behind; the closing home-manager restart relinks the managed dotfiles
# rsync just overwrote with the old ones.
let
  migrate = pkgs.writeShellApplication {
    name = "migrate-from";
    runtimeInputs = with pkgs; [ rsync openssh ];
    text = ''
      src="''${1:-nixworks}"
      rsync -aHAXS --partial --info=progress2 \
        --exclude=/.cache/ \
        --exclude=/.local/share/Trash/ \
        --exclude=/.local/state/nix/ \
        --exclude=/.local/state/home-manager/ \
        --exclude=/.nix-profile \
        --exclude=/.nix-defexpr/ \
        "greencheetah@$src:/home/greencheetah/" /home/greencheetah/
      sudo systemctl restart home-manager-greencheetah.service
    '';
  };
in
{
  environment.systemPackages = [ migrate ];
}
