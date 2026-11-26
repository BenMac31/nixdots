# Personal storage lifecycle scope

This proposal covers Steam games, game saves, and explicitly selected school
projects. It preserves progress and original work while reducing the local cost
of things that are rarely used. This is a design and inventory pass; no personal
data was compressed, moved, uninstalled, or deleted.

## Findings on nixUltra, November 12, 2026

- Steam runs through Flatpak. Its library is under
  `~/.var/app/com.valvesoftware.Steam/.local/share/Steam`; `~/.steam/root`
  resolves there. Discover libraries from Steam's library configuration rather
  than hardcoding the native Steam location.
- There are 27 app manifests: 26 have an installation directory, including
  15 games and 11 compatibility/runtime components. One manifest points to a
  missing installation. Existing game manifests total about 57.6 GiB including
  runtimes; manifest sizes are estimates, not physical space that can be reclaimed.
- Local Steam metadata identifies 11 installed games last played at least
  90 days ago, representing about 45.8 GiB of manifest sizes. Missing activity
  stays unknown. These dates do not authorize uninstalling anything.
- `du` reports approximately 60.3 GiB for `steamapps/common`, 11.4 GiB for
  `compatdata`, 2.8 GiB for Workshop data, 0.37 GiB for shader caches, and
  85 MiB for Steam userdata. These figures can include shared extents and do
  not measure exclusive compressed physical usage.
- Documents is about 38.9 GiB by the same measure. `Documents/Class` is about
  3.47 GiB and contains recognizable course directories. Most Documents data
  is elsewhere, so treating all of Documents as coursework would be wrong.
- `/home` uses `compress=zstd:3,noatime`. Existing compression is useful;
  last-read time is unavailable as a dependable age signal.
- The earlier 40-file compression test sampled agent artifacts, not games or
  coursework. Its percentages must not be used to predict savings here.

Detailed game names, dates, sizes, and directory inventories stay private under
`~/.local/state/disk-watch/personal-storage-*` and
`~/.local/state/disk-watch/personal-*-scope-du.txt`, outside the Nix source tree.

## Proposed behavior

| Data | Routine behavior | Later lifecycle action |
| --- | --- | --- |
| Game saves and personal configurations | Versioned local backup and separate verified offsite copy | Retain after uninstall; source disappearance never removes backups |
| Installed games | Keep launchable; sample compression candidates after 90 days without play | Remove installations through Steam only when explicitly selected and saves are covered |
| Completed school projects | Keep a verified complete archive; selectively compress retained local data | Offload only roots explicitly marked completed and configured for offloading |
| Active or pinned projects and games | Ordinary backups | Excluded from automatic compression and offloading |

### Saves first

Use [Ludusavi](https://github.com/mtkennerly/ludusavi) for its game manifest,
Steam/Proton support, preview, backups, and restore functions. Inventory all local
Steam accounts without copying authentication configuration into reports. Check
the Flatpak library, Proton prefixes, native-game paths, and relevant Flatpak
configuration/data locations. Report which paths each game covers and any
unknown games or save locations. Unknown coverage prevents uninstall automation.

Run a daily systemd user timer, skipping games that are running. Add an optional
post-exit backup through the existing Steam wrapper or launcher integration;
launching Steam itself is not proof that an individual game has exited. Do not
automatically restore over live saves before launch. Preserve custom entries for
games absent from the manifest and relevant mods/configurations.

Ludusavi's [built-in validation](https://raw.githubusercontent.com/mtkennerly/ludusavi/master/docs/help/backup-validation.md)
checks mapping validity and missing files. Add a SHA-256 inventory and a restore
into an isolated test directory, comparing restored content without writing to
live save locations. A successful CLI exit or a Steam Cloud icon is insufficient
evidence of complete save coverage. [Steam Cloud coverage is developer-defined](https://help.steampowered.com/en/faqs/view/68D2-35AB-09A9-7678).

Suggested initial retention: seven daily and four weekly recovery points, plus
the latest verified backup and a pinned pre-uninstall backup for every game.
Estimate actual save sizes before setting the local backup budget. If the budget
cannot preserve these guarantees, report pressure and postpone new offloading.
Do not age out the only verified save copy.

### Compression that preserves normal access

Use Btrfs compression directly, with a small policy controller rather than a new
storage filesystem. Start with a Zstd level 9 pilot on disposable copies of one
large inactive game and one completed course folder. Verify content, modes, and
mtimes; measure physical/exclusive effects and launcher/build behavior. Adopt
level 15 only if the measured gain justifies its CPU cost.

Use local Steam last-played metadata across accounts, plus install/update grace
periods and current process activity. Missing or inconsistent dates produce an
unknown state. Steam runtimes, Proton installations, shared redistributables,
downloads, updates, and Workshop/mod state are excluded from the game-age rule.

For school projects, use a configured root and an explicit `completed` state;
modification age alone cannot establish that a project is no longer being read.
The initial root proposal is `Documents/Class`, with other course folders added
explicitly. Do not scan all of Documents or Projects into automatic eligibility.

Proposed admission defaults: at least 90 days inactive/completed, at least 5%
estimated gain and 256 MiB per job, one job at a time, low CPU/I/O priority,
a bounded maintenance window, and at least 256 GiB of headroom after estimated
temporary allocation. Thresholds remain configurable and the pilot can revise
them. Keep the existing mount-wide compression and access-time settings.

Check shared extents before any rewrite. [Btrfs defragmentation/recompression can
break extent sharing](https://btrfs.readthedocs.io/en/latest/btrfs-filesystem.html)
with snapshots or reflinks. Skip automatic rewrites with uncertain sharing or
insufficient headroom. Do not delete personal snapshots to make compression
appear beneficial; snapshot retention remains an independent policy. Compression
must never be a reaction to emergency free-space pressure.

### Completed-project archives

Preserve source, complete Git metadata and unpublished work, untracked files,
documents, original datasets, and local LFS payloads. Keep linked worktrees,
submodules, external object stores, and external data dependencies in place until
the archive includes their dependencies or records a separately verified copy.
Only discard dependencies/build output when their rebuildability is established.

Create a versioned `.tar.zst` archive with metadata and content hashes, check it
against a stable source, upload it, and perform a test restore. Recheck process
references and source changes before offloading. Leave a small local receipt
with archive identity and an explicit restore command. A changed or active source
stays local. Restore into an empty chosen directory; never overwrite newer work.

Use a separate personal archive namespace. The existing private Graphide Azure
account is a possible destination, but its suitability for personal coursework
and the personal archive key location remain configuration decisions. No personal
archive destination has been configured in this scoping pass.

[Rclone supports Azure Blob](https://rclone.org/azureblob/) and a
[client-side encryption layer](https://rclone.org/crypt/); Ludusavi also has
[Rclone integration](https://github.com/mtkennerly/ludusavi/blob/master/docs/help/cloud-backup.md).
Use versioned copy operations with verification rather than a bidirectional sync
or a remote mirror that propagates local deletion. Keep credentials and encryption
keys in runtime files, with a recovery copy independent of this laptop; no secrets
belong in Nix. Check Azure tier minimums and retrieval costs before selecting a
retention policy for personal archives.

## Implementation boundary

Use existing tools for backup, transfer, compression, and extent measurement:
Ludusavi, Rclone, `tar`, `zstd`, `btrfs`, and `compsize`. The custom code only
handles inventory, eligibility, job coordination, state, verification, and reports.
Do not base this on swarfr: the upstream repository is archived and its policy is
oriented toward build artifacts.

Proposed Nix layout:

- `modules/home-manager/desktop/apps/ludusavi.nix`: one app enable option,
  package and runtime configuration integration; enabled by default from the
  gaming parent when the feature is adopted.
- `modules/home-manager/term/game-save-backup.{nix,py}`: one service enable
  option, backup/verification controller, timer, retention, and reporting.
- `modules/home-manager/term/personal-storage.{nix,py}`: one service enable
  option, explicit roots/pins, policy evaluation, bounded compression/archive
  jobs, and restore support.
- Runtime state under `~/.local/state/personal-storage`, with separate namespaces
  for save backups, archive receipts, hashes, and per-item job state. Share the
  existing cleanup lock where operations could race with current storage jobs.

Proposed commands are `personal-storage status`, `plan`, `compress`, `archive`,
and `restore`; they are not installed yet. Plans show item, reason, activity
confidence, save coverage, estimated versus verified savings, destination, and
the next action. Allow per-item pinning. Failures retain source data and are
visible through a summary report and systemd journal.

## Delivery and acceptance

1. Inventory and save protection: build the read-only report, wire Ludusavi to
   the Flatpak library, map coverage, establish retention and encrypted offsite
   copying, and restore a representative native and Proton save into isolation.
2. Compression pilot: benchmark representative game/course data on copies,
   inspect exclusive/shared allocation, then enable bounded local compression
   only for opted-in roots that pass the measured thresholds.
3. Project offloading and game retirement: add completed-project archives,
   verified restoration, and explicit Steam uninstall integration. Automatic
   uninstall and broad personal-folder offloading are outside the first release.

Required tests cover unknown activity, multiple Steam accounts, Flatpak paths,
runtime exclusions, active games and open files, source changes, interrupted jobs,
full disks, unavailable Azure, hash mismatch, save deletion versus backup retention,
Git/LFS dependency coverage, and restoration without touching current saves.
Before declaring a compression win, verify net space after snapshot retention,
not just the size of the newly written file.

Evaluate only the affected NixOS output, such as
`nix eval .#nixosConfigurations.nixUltra.config.system.build.toplevel.drvPath`.
No Nix implementation or activation is part of this scoping pass.

The identified inactive game payload is around 46 GiB before accounting for
compression/sharing, while the initial school root is around 3.5 GiB. This is a
useful personal-data feature, but it cannot by itself close the remaining gap to
512 GiB total disk use. The agent-workload cleanup continues separately.
