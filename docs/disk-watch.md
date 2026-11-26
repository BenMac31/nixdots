# Disk storage controls

`services.diskWatch.enable` checks free space every 30 seconds in
`background.slice`. With user lingering enabled it continues after logout.
Below 256 GiB available or 48 GiB unallocated it requests unrooted Nix garbage
collection, at most hourly. Below 192 GiB available or 24 GiB unallocated it
reports critical pressure. It never freezes sessions automatically. The separate
system disk guard retains its own emergency policy.

```sh
cat ~/.local/state/disk-watch/state.json
systemctl --user status disk-watch.timer
journalctl --user -u disk-watch.service -u disk-watch-gc.service --since yesterday
disk-guard status
```

`services.worktreePrune.enable` examines linked Git worktrees every 15 minutes.
It retires clean checkouts idle for six hours only when their HEAD is already
published. It retains primary clones, branches, unpublished commits, active
process paths, locks and interrupted Git operations. Ignored evidence is archived
and compared with its source before removal; dependency caches can be rebuilt.
The manifest and private recovery archives live under
`~/.local/state/disk-watch/`.

An explicit recovery pass can archive local edits in published worktrees idle for
at least 24 hours. This is not enabled by the timer. It saves staged and unstaged
binary patches, modified files, untracked files and ignored evidence. It checks
that the source is unchanged before retiring the checkout. Modified LFS files,
nested repositories and submodules remain in place. LFS filter changes alone do
not pin files whose raw Git object hash, index entry and mode still match HEAD.

The explicit `--archive-unpublished` mode also backs up unpublished commits in
verified Git bundles and retains recovery refs under `refs/archive/disk-budget/`.
It requires a 24-hour idle period and an archive directory; the timer never uses
it. Bundles may require published base commits, retained by their recovery refs
in the common repository. Fetch a recorded bundle's `HEAD` into a repository
containing those base commits to restore it. Unpublished LFS payloads remain in
place because Git bundles cannot contain their external object data.

```sh
journalctl --user -u worktree-prune.service --since yesterday
cat ~/.local/state/disk-watch/worktree-retirement.jsonl
```

To restore a recovery directory, read its `metadata.json` for the common Git
directory, HEAD and archive. Create a worktree at that HEAD using
`git --git-dir COMMON worktree add --detach RESTORE HEAD`. Apply `staged.patch`
with `git -C RESTORE apply --index`, then `unstaged.patch` with
`git -C RESTORE apply`; skip empty patches. Extract the recorded `.tar.zst` into
RESTORE with `tar --zstd -xf ARCHIVE -C RESTORE`. This also restores untracked
files and ignored evidence. Keep the archive until the restored state is checked.

`services.buildCachePrune.enable` runs hourly. It removes idle, verified Python
virtual environments, locked Node dependencies and stopped throwaway PostgreSQL
test clusters whose creation script proves they are disposable. It preserves
source, reports, logs, running processes, unknown environment contents and data
with a PostgreSQL PID marker. Checkout retirement and cache cleanup share a lock.

`services.gpCachePrune.enable` checks cached registry clones hourly. Only mirrors
idle for 48 hours qualify, under gp's own sidecar lock. Local changes, unpublished
commits, stashes, linked worktrees, open files and interrupted Git operations
prevent removal. The primary registry checkout is retained.

```sh
systemctl --user status worktree-prune.timer build-cache-prune.timer gp-cache-prune.timer
journalctl --user -u build-cache-prune.service -u gp-cache-prune.service --since yesterday
```

`services.agentScratch.enable` provides a fixed-capacity ext4 image, default
128 GiB, mounted through UDisks by a user service. The image is preallocated in
its own Btrfs subvolume so home snapshots do not pin it. Creation requires enough
space to leave 256 GiB available after reserving the image. No existing image is
reformatted. The legacy root-owned scratch image is disabled to avoid conflicting
mounts.

```sh
agent-scratch create
systemctl --user start agent-scratch.service
agent-scratch plan
agent-scratch --apply migrate
```

Migration copies an idle path, compares file contents, checks for new process
references, and atomically replaces the original directory with a symlink. It
removes the old data only after verification; an old copy still open or changed
is retained. Oversized or active paths remain outside the cap. Check the command
output and `~/.local/share/agent-scratch/migrations/` before treating the cap as
covering every configured path. New agent wrappers use the image's temporary
space when it exists. Mounting after reboot uses the existing UDisks policy;
failures are visible in `agent-scratch.service` and retried.

```sh
systemctl --user status agent-scratch.service
df -h ~/.local/share/agent-scratch/mount
```

A 512 GiB total disk budget also includes the Nix store, system, swap, personal
files, Git object stores and retained proof archives. The workspace cap alone
cannot enforce that total. Old home snapshots may retain deleted data; create a
fresh checkpoint before removing pre-cleanup timeline snapshots. Long-term
archives need a verified private destination before their local copies are
removed.

The November 12 recovery uses Graphide's existing private Azure container
`gharchwus/retired`, under `nixUltra-disk-2026-11-12/sha256/`, in Cool storage.
Uploads require Azure to validate each transfer block's MD5 checksum. Files up
to 64 MiB also receive a full SHA-256 read-back; larger files receive three
128 KiB read-back samples and an ETag check. Existing blobs without evidence of
validated transfer checksums receive a full read-back. Every file's SHA-256 is
recorded for restoration. See the [Azure upload validation documentation](https://learn.microsoft.com/en-us/python/api/azure-storage-blob/azure.storage.blob.blobclient?view=azure-python).
Its local index is
`~/.local/state/disk-watch/azure-archive-manifest.jsonl`; an index copy is also
uploaded. Recovery files remain local during this pass. Credentials are read at
runtime from the existing Azure login and are never stored in Nix or the index.
`~/.local/state/disk-watch/budget-progress.json` records the one-off finishing
pass, including actual disk usage and whether the 512 GiB target was reached.

The one-off cold-proof archiver considers idle task directories in Graphide
scratch, IvorySummit and Sunnyduck receipts, starting at 16 MiB. It saves full directory contents,
including a standalone clone's Git metadata, compares the archive with its
source, uploads it, and verifies the transfer as described above before retiring local
data. Repositories with external worktrees, object alternates, custom LFS storage
or external Git metadata links are retained. Active paths, mounts and directories
changed within 24 hours are retained, as are interrupted Git operations and
PostgreSQL PID markers. Each retired directory contains
`_AZURE_ARCHIVE.json` with its private URL and hash. The index is
`~/.local/state/disk-watch/azure-cold-proof-manifest.jsonl`, also uploaded.

To restore one of these directories, download its recorded blob into a temporary
file, check its SHA-256, then extract it into an empty directory:

```sh
az storage blob download --account-name gharchwus --container-name retired \
  --auth-mode key --name BLOB_NAME --file ARCHIVE.tar.zst
sha256sum ARCHIVE.tar.zst
tar --zstd -xf ARCHIVE.tar.zst -C EMPTY_RESTORE_DIRECTORY
```

The existing Azure identity can request the account key for this private store;
the key is kept in memory. [Cool-tier retention and retrieval charges](https://learn.microsoft.com/en-us/azure/storage/blobs/access-tiers-overview)
apply, including a 30-day minimum storage duration.
The archiver reserves at least 192 GiB of headroom for a local archive attempt.
If a source changes or becomes active during copying, it keeps the source.
