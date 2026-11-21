# mcServ: the Minecraft server on GCP

The NeoForge pack (Minecraft Industrial Complex) moved off omegaServ on
2026-11-21, with Dan's OK, to a dedicated Google Cloud VM.

| | |
| --- | --- |
| Project | `graphide-mc-da559c` (Graphide org, billing account `01B9F8-5D58B7-D0A974`) |
| VM | `mcserv`, `c4d-standard-32` (32 vCPU, 124 GB), zone `us-east5-a` |
| Disk | `mcserv`, 200 GB hyperdisk-balanced, not deleted with the VM, daily snapshots kept 14 days (`mcserv-daily`) |
| Address | static `34.144.176.121` (`mcserv-ip`), `mc.benmac.xyz` |
| GCP firewall | `allow-minecraft`: 25565/tcp, 24454/udp; the default network also admits 22 |
| Server | `/var/lib/mc/server`, unit `minecraft-server`, user `sistermcserver`, 16G heap |

Players connect to `benmac.xyz` as before: the `_minecraft._tcp.benmac.xyz`
SRV record sends clients to `mc.benmac.xyz:25565`. Anyone who typed
`benmac.xyz:25565` with the port skips SRV, so the VPS (192.3.130.121) also
DNATs 25565/tcp and 24454/udp to the GCP address
(`/usr/local/sbin/wg-portforward.sh`); those players show up with the VPS's IP.

## Access

`ssh root@34.144.176.121` or `ssh carol@34.144.176.121` with the usual key.
carol has the same levers as on omegaServ: rw on the server directory and
`systemctl start|stop|restart minecraft-server` without sudo. RCON listens on
25575; the host firewall keeps it local.

GCE's OS Login is off (`security.googleOsLogin`), because its PAM account
check refused every local user.

## Deploying

The VM has no checkout of this repo. Build here and push the closure:

```sh
TOP=$(nix build --no-link --print-out-paths .#nixosConfigurations.mcServ.config.system.build.toplevel)
nix copy --to ssh://root@34.144.176.121 "$TOP"
ssh root@34.144.176.121 "nix-env -p /nix/var/nix/profiles/system --set $TOP && $TOP/bin/switch-to-configuration switch"
```

A fresh VM comes from the image:
`nix build .#nixosConfigurations.mcServ.config.system.build.googleComputeImage`,
uploaded to `gs://graphide-mc-da559c-images` and created with
`gcloud compute images create ... --guest-os-features=UEFI_COMPATIBLE,GVNIC`.
c4d needs UEFI, NVMe and gVNIC, and Secure Boot off (GRUB is unsigned).

## The old copy on omegaServ

omegaServ keeps its last copy of the server and world in `/var/lib/mc/server`
as a fallback. A `.moved-to-gcp` file there makes its `run.sh` idle instead
of starting Java, and `serv.minecraft` is off in its config.
