# nixUltra switch blackout, 2026-11-18

The failed switch tried to restart the service that provides the backing storage
for `/tmp` and `/var/tmp`. Stopping that service also stopped essential desktop
and network services. The system switch then failed before it could bring them
back. The following reboot recovered the services but lost terminal processes.

## Evidence

The previous boot is `73248b3d89294a3ea676c5e78f3dfbf5`. All times below are
Pacific time on November 18.

- At **23:26:42**, `nixos-rebuild-switch-to-configuration.service` started
  switching to generation 28,
  `/nix/store/rydp7911xw1sz9kkar0046bdhn8s87wg-nixos-system-nixUltra-26.05.20261105.c56a87d`.
- In the same second, systemd stopped the graphical, local filesystem,
  multi-user and basic targets, NetworkManager and D-Bus.
- The switch exited with status 1 after **941 ms**. D-Bus subsequently started
  again, but NetworkManager stayed down. The journal continued until 23:29:52.
- Several Chromium/CEF processes crashed with a fatal D-Bus disconnect.
- The saved generations 27 and 28 use identical kernel, systemd, Hyprland and
  dbus-broker packages, D-Bus units and temporary filesystem entries.
- `agent-storage.service` changed its `ExecStart` from
  `armf1l853c3hfncqbk5y08jpyilr1wd5-agent-storage-prepare` to
  `5qxblgvsk863al5cl19g1zvyk896v4zy-agent-storage-prepare`.
  The command changed `--size-gib 128` to `--size-gib 192`.
- The service had no `restartIfChanged = false`, so the NixOS switch planner
  treats that change as a stop followed by a start.

The dependency chain explains the otherwise surprising scope of the failure:

```text
agent-storage.service
  <- Requires: tmp.mount
       <- RequiresMountsFor=/tmp: dbus-broker.service
  <- Requires: var-tmp.mount
       <- RequiresMountsFor=/var/tmp: basic.target
            <- Requires: multi-user.target
```

Stopping a required unit stops its dependents. The switch planner uses D-Bus
itself, so losing D-Bus also interrupts the operation intended to restore the
services. The journal records the dependent shutdown and switch failure; it
does not retain the switch command's piped stderr or complete planned unit list.
The changed provider unit and dependency chain identify the storage restart as
the cause; the exact final error text is unavailable. There is no evidence of a
kernel GPU hang as the initiating event in that interval.

Inspect the retained evidence with:

```sh
journalctl -b 73248b3d89294a3ea676c5e78f3dfbf5 \
  --since '2026-11-18 23:26:41' --until '2026-11-18 23:26:47' _PID=1
diff -u /nix/var/nix/profiles/system-27-link/etc/systemd/system/agent-storage.service \
  /nix/var/nix/profiles/system-28-link/etc/systemd/system/agent-storage.service
systemctl show agent-storage.service tmp.mount var-tmp.mount \
  -p Id -p Requires -p RequiredBy
```

## Fix

`modules/nixos/agent-storage.nix` sets `restartIfChanged = false` on the provider.
An active provider keeps running when its preparation command changes; the new
command takes effect on the next boot. This also applies when first switching
from the affected configuration: the planner reads the incoming unit's policy.
Changing only `stopIfChanged` would still restart the service and propagate the
same dependency shutdown.

This follows the [NixOS switch planner's handling of the incoming unit](https://github.com/NixOS/nixpkgs/blob/c56a87d/pkgs/by-name/sw/switch-to-configuration-ng/src/main.rs).
NixOS also explicitly avoids restarting D-Bus in its
[D-Bus module](https://github.com/NixOS/nixpkgs/blob/c56a87d/nixos/modules/services/system/dbus.nix).

The module also installs a pre-switch check that rejects changing, adding or
removing the `/tmp` or `/var/tmp` fstab entries while agent storage is involved.
It runs before services are stopped, including for `test`. Storage path and
identity changes have a switch inhibitor. A size-only update can switch live,
but changing the setting does not resize the already mounted image; online
growth uses the separate resize tool.

These protections take effect when activating a configuration containing the
fix. They are specific protections for this storage failure, not a guarantee
that every desktop, driver or service update can be applied without disruption.
Do not bypass them with `NIXOS_NO_CHECK=1`.

## Updating without interrupting the desktop

For storage layout, display manager, graphics stack or other foundational
changes, build as your user and stage the result for the next boot:

```sh
cd ~/nixos
nixos-rebuild build --flake "$HOME/nixos#nixUltra" --impure --cores 6
# Continue only if the build succeeded.
notify-send 'NixOS update' 'Authorize staging the built configuration for next boot'
pkexec /run/current-system/sw/bin/nixos-rebuild boot --store-path "$(readlink -f result)"
```

`boot` updates the boot default without activating the new services. Save work
and reboot when convenient. It does not reopen loose terminals after reboot.
The boot menu retains older generations if the new one does not boot correctly.

For routine live updates, inspect the built result first:

```sh
notify-send 'NixOS update' 'Authorize previewing the built configuration'
pkexec /run/current-system/sw/bin/nixos-rebuild dry-activate --store-path "$(readlink -f result)"
```

Inspect stops and restarts of storage providers, mounts, D-Bus, login/session
services and the display manager. A preview lists direct actions; systemd's
dependency propagation can stop additional services. If the changes are suitable
for live activation:

```sh
notify-send 'NixOS update' 'Authorize activating the reviewed configuration'
pkexec /run/current-system/sw/bin/nixos-rebuild switch --store-path "$(readlink -f result)"
```

Using the same store path for preview and activation avoids rebuilding a
different configuration after files change. `nixtest` performs live activation
too: its distinction is that it leaves the boot default unchanged. It can still
interrupt the desktop, and it does not automatically roll back after a timeout.

If a future switch leaves the display unusable, try Ctrl+Alt+F3 to reach an
independent login console. A screen that accepts characters is not necessarily
a usable login shell. If the essential services or authentication are broken,
reboot and select a known working generation rather than repeatedly switching
from the damaged session.

## Validation

The mount guard has tests covering service-only updates, changed sources,
storage enable/disable, boot/preview, option ordering and missing input. The
nixUltra toplevel evaluates with the fix. Validation does not activate a system
or restart the storage provider on the running laptop.

The generated service contains `X-RestartIfChanged=false`. The generated
pre-switch script accepts the current layout, rejects mount removal for both
`switch` and `test`, and accepts the same proposed removal for `boot`.
