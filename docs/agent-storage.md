# Bounded agent storage

On nixUltra, `services.agentStorage` mounts the existing, bounded 256 GiB agent
scratch image. It validates the configured size at startup; it does not grow
the image automatically. `/tmp` and `/var/tmp` bind to directories on this
filesystem. An 8 GiB, fully allocated
filesystem image **inside scratch** reserves space for agent command output.
The original image remains excluded from home snapshots and has No_COW set.

New Claude, Codex and codex-api launches use a mount namespace in which the
agent's `/tmp`, `/var/tmp` and `TMPDIR` use the output reserve. Agent caches
use bulk scratch. Bash and Zsh tool commands use bulk temporary storage and
cannot write into the output reserve. Session temporary writes therefore no
longer depend on free bulk space, including code using a literal `/tmp` path.

Each ordinary command gets a private `TMPDIR` under `bulk/tasks/<UUID>/tmp`.
A detached Linux subreaper supervises its descendants, including redirected
background children that double-fork or create their own session. The tool gets
its command's exit status without waiting for redirected background work. The
supervisor records completion only after every descendant exits; an unavailable
or crashed supervisor leaves the directory retained during the same boot.
A valid record from an earlier boot proves that its tracked descendants are
gone and makes its scratch eligible for cleanup. No task is killed to make
space. Shell hooks preserve the original options and positional arguments.
Commands with a controlling terminal run directly to preserve terminal prompts
and job control; their temporary directories remain untracked and are retained.

Explicit `/tmp` and `/var/tmp` paths remain shared between commands for existing
file handoffs. Save artifacts, worktrees and files needed by later commands
outside the command-specific `TMPDIR`; that directory is disposable. Work
submitted to an external service manager needs its own storage lifetime.

Command stdout and stderr each have an 8 MiB display limit. Excess output is
drained, with a truncation notice, so producers do not block on full pipes.
Redirect large results to a file in scratch when their full contents are needed.
Concurrent commands reserve output budget; the final 256 MiB is kept out of
normal job admission. With less than 8 GiB of bulk space free, new commands are
deferred with exit status 75. Recovery commands remain eligible. Agents are not
frozen or terminated by this policy.

Bulk admission uses actual available filesystem space by default. Optional
`commandReserveGiB` estimates are disabled (`0`): long-lived agent descendants
make a fixed estimate per command consume the concurrency budget without a
matching allocation. Existing estimates are ignored while disabled. This is
not a filesystem quota; running commands can still consume the remaining space.
Output admission keeps its separate bounded display budget.

`agent-storage status` is read-only and shows bulk, output and home capacity,
available inodes, task completion counts and admission state. The existing
cleanup timer saves capacity samples; status reports the consumption rate and
estimated time until full when successive samples show growth. This is an
extrapolation over the displayed interval, not a capacity guarantee. Monitoring
does not traverse all scratch file contents.
Samples also form a bounded, rotating `state/capacity-history.jsonl` history on
the output filesystem. Status identifies the runtime source and reports bulk
commitments separately from filesystem capacity. Below 24 GiB free, desktop
pressure alerts are limited to one every 15 minutes.
`agent-storage usage --area tasks` explicitly scans a selected area and prints
bytes per immediate child directory to identify large consumers. Areas are
`all`, `tasks`, `tmp` and `cache`; this potentially slow scan is never scheduled.

Recovery commands bypass ordinary output-budget admission. A cleanup request
inside a tool command's read-only reserve namespace delegates to the host user
service; a service connection failure is reported without stopping the agent.

`agent-storage cleanup` removes expired GitHub response cache entries and closed temporary
output files. A timer runs every minute. Build-cache, registry and published
worktree cleaners run on their independent timers, so low space does not launch
expensive workspace scans every minute. Source code,
unpublished work, active output files and chat history are not deleted by this
cleaner. The disk guard's blanket temporary-file purge is disabled.
The cleaner also recognizes abandoned GitHub response-cache partial writes
(`64-hex-digits.json.PID`). It requires the writer PID to be absent, a one-hour
age grace, and no open file reference. Unknown filenames remain retained.
On nixUltra, pressure cleanup also reduces recognized Go build-cache hash
entries toward 2 GiB, preserving open entries and entries written in the last
hour. It asks UV to prune its own unused cache entries. These are reproducible
build caches; arbitrary shared temporary directories remain retained.
Closed output files from older agents still using the host RAM `/tmp` are also
eligible; under RAM-temporary-space pressure their retention drops to a minute.
Open output files are retained.

The registry cleaner checks both `gp` and custom `gp-*` cache namespaces every
minute, including the physical scratch cache on nixUltra. It retains clones
for 48 hours normally. Below 32 GiB free in scratch, it can reclaim clones idle
for one hour. Both paths require the same clean/published Git checks, no stashes
or recovery refs, no linked worktrees, no process references and an exclusive gp
lifetime lock. The primary `gp/registry-greencheetah` clone in the configured
cache roots stays protected by filesystem identity, including bind aliases.
Temporary copies bearing the same name are eligible for the usual checks.
Reclaimed mirrors are downloaded again when needed. A dry run is available with
the service's executable followed by `--dry-run`; decisions are recorded in
`journalctl --user -u gp-cache-prune`.
Discovery also covers immediate child namespaces with GP sidecar lock files
and nested `gp`, `gp-*`, and `gpcache` namespaces under scratch's shared temporary
directory. This includes arbitrary names such as `gpc.SEK8` and `native-proof-1116`.
It does not search source trees recursively. Bind aliases are deduplicated by
filesystem device and inode.

Below 24 GiB free, the registry cleaner also considers recently used mirrors,
while retaining all Git, process and lifetime-lock checks. This emergency pass
stops once 32 GiB is free. Active commands and unpublished work stay protected;
reclaimed caches may need downloading again.

## Capacity investigation, November 15, 2026

A live allocation scan found the following approximate usage before cleanup:

| Area | GiB |
| --- | ---: |
| Cache namespaces | 59.9 |
| Workspaces under `home/Projects` | 28.5 |
| Shared `tmp` | 18.8 |
| Preallocated output reserve | 7.9 |
| Command-owned task directories | less than 0.003 |

The main `gp` namespace alone occupied 31.4 GiB; additional custom `gp-*`
namespaces were outside the original cleaner's scope. Many registry clones cost
about 0.8 GiB each. The Go build cache was 4.9 GiB, so command-task cleanup or
another Go-cache purge would not address the largest consumer.

The first cleanup removed 18 verified idle mirrors in scratch, increasing free
space from 9.8 to about 23.3 GiB while agents continued running. The installed
service then removed 25 additional eligible legacy mirrors. Targeted runtime
and unit installation records, including previous symlink targets, are under
`~/.local/state/agent-storage-rollout`; a GC root retains the registry units.

Shared temporary directories contain source checkouts, Git/LFS fixtures and
review evidence, so directory age alone does not authorize their removal.
New ephemeral work should use the command-owned `TMPDIR`. Persistent work needs
an explicit completion/archive lifecycle, and large builds should use remote
workers. If retained active/unpublished work exceeds the pool, the admission
threshold still defers jobs; automatic deletion cannot safely solve that case.

`services.agentScratch.taskCleanup.enable` additionally reclaims only
launcher-created temporary directories with a supervisor's confirmed completion
record. The option defaults to false and is enabled on nixUltra with Ben's
approval on November 14, 2026: "Approve task-exit cleanup (Recommended)".
Status and cleanup still show eligible directories while disabled. There is no
age-based deletion of incomplete task work. Existing capacity, retention and
output limits are unchanged by this addition.

`agent-scratch --children --apply migrate` migrates configured idle directories
using a verified copy, filesystem sync and atomic symlink exchange. It never
reformats an existing image, replaces an unknown destination, or removes an old
copy that became active. Automatic migration is disabled on nixUltra so it does
not consume cleanup headroom. Other hosts may enable the hourly migration
service, with four successful moves per pass. Explicit migration must leave
32 GiB free after the copy. Oversized directories remain in place; this is
reported rather than expanding the image or discarding data. The original
paths continue working through symlinks after migration.

`agent-scratch --apply boundary` first redirects workspace roots and cache
namespaces into scratch. Existing children remain linked to their original
inodes, so open files and running processes survive; newly created children
are allocated in the image immediately. The migration service subsequently
copies idle legacy children into the image. Oversized or active legacy children
stay linked until they can be moved safely.

## Existing sessions and limits

The live installation does not replace a mounted `/tmp` underneath existing
processes. Existing command shells receive output limits and a scratch TMPDIR;
the entire temporary namespace is installed when a new agent session starts.
The host `/tmp` and `/var/tmp` change mounts at the next boot. Temporary systemd
overrides and the `agent-storage-bootstrap` profile entry make the targeted
installation persistent; ordinary NixOS/Home Manager activation removes these
overrides in favor of the generated configuration.

This routes and limits agent temporary files, caches and migrated worktrees.
It is not a security sandbox against an agent deliberately writing elsewhere
in its user account. Existing source trees and saved chat histories that have
not been migrated still occupy the host filesystem. They require sufficient
scratch capacity or an explicit archive decision before they can be moved.

All images and credentials remain runtime files. No image data or tokens are
copied into the Nix store.

The reserve does not relocate account databases or chat histories. They remain
at their existing paths and are never deleted by task cleanup. Their home
filesystem's free space is reported separately. Moving open databases or a
running session's history directory is outside this installation.

## Remote build workers

The existing worker pool is Graphide's shared remote build and test machines,
accessed through `graphide-tools/utilities/scripts/remote.sh` and `fleet job`.
It is separate from customer CI machines. `remote.sh` transfers the current
checkout, including uncommitted edits, and returns the remote command's status.
Use the existing unpinned route for large builds and tests so their compiler
outputs and dependency installations do not consume this agent host's scratch.
For example, from the checkout being tested:

```sh
/home/greencheetah/Projects/graphide/graphide-tools/utilities/scripts/remote.sh make test
```

Storage pressure messages point to that route. Commands are not automatically
rerouted, which could change their environment or replay side effects.

## Targeted live installation

`python3 scripts/install-agent-storage.py --build-only` builds isolated outputs
for the runtime, migration CLI, existing Claude/Codex launchers, shell hooks and matching
cleanup/registry units and timers.
`--apply` installs those user-level changes without activating unrelated
pending NixOS or Home Manager changes. Existing vendor and account binaries
remain pinned to the live wrappers. Inputs are checked again before applying.
Prior symlink targets and the named profile entry are recorded under
`~/.local/state/agent-storage-rollout/`; a failed apply records its completed
steps and attempts to restore the previous links and profile. Loaded service
commands and timers are checked against their persistent files after two
manager reloads. The installer also disables the migration timer when the
declarative policy disables migration. A later ordinary Home Manager activation replaces
the bootstrap with the corresponding declarative configuration.
The installed bootstrap also references both generated hook/unit outputs, so
Nix garbage collection cannot remove them while the profile is installed.

An older system generation can rerun Home Manager at boot, uninstalling that
profile entry and restoring old storage hooks. The targeted installer therefore
also creates an independent GC root and an `agent-storage-restore` user service
and timer. The service runs at user startup and checks once a minute. It repairs
only recorded, recognized old file contents or missing links, and waits while
Home Manager is activating. Unrecognized configuration changes are preserved
and reported in its journal. It does not evaluate Nix or download a new build
during recovery; it reinstalls the already rooted package.

The current declarative Home Manager activation retires this temporary repair
service and independent root when replacing it with the current configuration.
`python3 tests/test-restore-agent-storage.py` checks safe restoration and
preservation of unknown changes. A live test also removed the profile and
reinstated the actual legacy storage links, then verified automatic restoration.

Existing Zsh-based commands get the updated hook on subsequent launches.
Already running commands and Bash sessions pinned to an old immutable
`BASH_ENV` retain their old runtime until relaunched. The protected parent
`/tmp` mapping applies to newly launched agent sessions.

## Validation

`python3 tests/test-agent-storage.py` covers admission, output limits, image
validation, output budget leases, recovery with an exhausted normal budget,
shell argument preservation, and a disposable full-filesystem session probe.
Set `AGENT_STORAGE_BWRAP` to the installed bubblewrap executable when it is not
on PATH. `python3 tests/test-agent-task-storage.py` covers descendant completion,
supervisor failure and safe cleanup. `python3 tests/test-install-agent-storage.py`
checks the targeted installer. The opt-in root integration test
(`AGENT_STORAGE_INTEGRATION=1`) creates disposable filesystems inside scratch,
fills the test bulk filesystem, and verifies that the nested output filesystem
remains writable. It does not fill the real scratch pool.

## Bounded capacity increase, November 16, 2026

The 128 GiB image again approached the physical admission floor while the
repaired runtime remained installed. Retained projects, shared temporary data
and caches occupied approximately 47, 37 and 23 GiB respectively. These include
active and unpublished work that cleanup deliberately retains.

`scripts/resize-agent-storage.py` expanded the existing image to 192 GiB online,
without changing its filesystem UUID or unmounting it. The tool checks that
preallocation leaves at least 96 GiB free on the host, verifies the mounted
image and loop-device identity, and installs a rooted boot command before
changing capacity. The boot command accepts both the original and expanded
size, so an interrupted expansion does not leave the old boot command rejecting
the image. Both host Nix options now specify 192 GiB.

Until the updated full system is activated, the boot compatibility command is
retained by `/nix/var/nix/gcroots/agent-storage-capacity` and selected through
`/etc/systemd/system.control/agent-storage.service.d/60-capacity.conf`. The
current declarative activation retires this marked override. The resize journal
is `/var/lib/agent-storage-resize/record.json`.

The increase restored about 72 GiB of scratch headroom while retaining about
123 GiB of host headroom. It is a fixed capacity increase, not an automatic
growth policy or a quota on running jobs. Continued growth of retained work
still requires retirement or additional explicitly budgeted capacity.
