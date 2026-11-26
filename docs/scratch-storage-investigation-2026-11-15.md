**Scratch storage investigation — November 15, 2026**

The repeated incidents are a lifecycle and deployment problem, not simply a
missing cleanup timer. The machine has a fixed pool shared by persistent
worktrees, temporary checkouts and caches. Several producers have no ownership
or byte budget. The ownership-aware runtime in this repository is not the
runtime used by the observed commands or the installed general cleanup service.
Registry cleanup is now working, but it cannot reclaim all those other classes.

This investigation inspected the live host as well as the agent's mount
namespace, installed immutable scripts, process arguments, selected storage
environment variables, directory allocation and the user-service journal.
No source/workspace/cache data was manually deleted during this investigation.
The existing automatic cleaners continued running. A small lifecycle probe was
created and then removed.

**What “full” meant in the observed incidents**

The first snapshot in this conversation had 7.9 GiB available. New commands
require 8 GiB, so they were refused even though the filesystem was not literally
100% occupied. Later reports coincided with renewed pressure: 17.3 GiB free on
the second recurrence and 23.5 GiB at the beginning of this audit. These samples
do not rule out lower transient values between observations.

The pool is a 128 GiB image with 124.93 GiB reported filesystem capacity.
Approximately 7.9 GiB of its allocation is the nested output-reserve image.
The separate output filesystem was nearly empty, with 7.75 GiB available.
Inodes were only 26% used. Output logs and inode exhaustion were not the measured
dominant consumers.

The allocation scan started around 20:24 PST. These are approximate GiB,
measured while jobs and automatic cleanup were running, not an atomic snapshot:

| Data class | Allocated GiB | Lifecycle today |
| --- | ---: | --- |
| `home/Projects`, almost entirely `Projects/wt` | 39.7 | Preserved when dirty, unpublished, active or otherwise unverifiable |
| Shared `tmp` | 29.9 | Arbitrary checkouts, fixtures, environments, caches and evidence; no general ownership cleanup |
| `home/.cache` | 18.8 | Only selected cache formats are covered |
| Nested output-reserve image | about 7.9 | Deliberately reserved |
| `tasks` | about 0.002 | Negligible; does not contain the observed commands' working data |

The cache total includes 5.3 GiB in `tmp-overflow`, 1.7 GiB in `go-build` and
1.5 GiB in `uv`. Shared temporary storage includes a 3.4 GiB LFS fixture under
`tmp/p1216`, a 2.7 GiB registry-cache namespace under `tmp/ororev/gpcache`, a
2.1 GiB checkout under `tmp/wepost-read`, and about 2.0 GiB of GitHub-response
cache under `tmp/ghc/cache`. A directory name containing “tmp” or “cache” does
not prove its contents can be discarded.

**Confirmed failure 1: the deployed writer/cleaner runtime is old**

Observed storage-wrapped commands all used:

`/nix/store/iw3s2z78xa462xbcl2wfca2bvk9wx3ps-agent-storage.py`

There were 20 such commands in the first process sample and 14 in the later
host sample. Neither sample contained `--task-helper` or `--task-cleanup`.
That script has no `task_module` implementation. The installed
`agent-storage-cleanup.service` invokes the same old script through
`/nix/store/4n3gavhmb9rbdrirhpyzzfjg4y4wggwq-agent-storage/bin/agent-storage`.
The installed `.zshenv` also explicitly names this old wrapper.

The journal identifies a specific regression during my earlier registry fix:

| Time, PST | Evidence |
| --- | --- |
| Through 15:30:27 | General cleanup ran `kwwz428...-agent-storage.py` with `--task-helper` and `--task-cleanup`; its last task report retained 112 tasks |
| 15:30:42–15:30:43 | My registry-service rollout requested a systemd user-manager reload |
| 15:31:21–15:31:22 | My timer rollout requested another reload |
| From 15:31:30 | General cleanup ran `iw3s2z...-agent-storage.py`, without either task option; task reports disappeared |

The general cleanup unit's on-disk symlink dates to 00:50 and resolves through
the old Home Manager generation. The newer loaded definition had not been made
the persistent source of truth. Reloading the manager brought the older on-disk
definition back into effect. I updated the registry units but failed to audit
and preserve this related unit. The stale capacity sample is also consistent
with this transition. This was a deployment regression I introduced, not a
case of a timer mysteriously failing.

That regression is not the entire capacity explanation: before it, the newer
cleaner already reported all 112 task directories retained, and those directories
total only about 2 MiB now. The large unowned temporary and workspace data still
would not have been reclaimed merely by restoring that cleaner.

The repository's [runtime](../modules/home-manager/term/agent-storage.py) and
[module](../modules/home-manager/term/agent-scratch.nix) contain per-command
ownership and task-cleanup support. Their presence, and passing tests against
them, did not establish that these features were deployed.

A real tool-command probe confirmed `TMPDIR=/var/lib/agent-scratch/tmp`, no
`AGENT_TASK_ID`, and a marker remaining after command exit. The probe was removed
after inspection. This was an ownership-path check, not a test of a full timer
interval.

**Confirmed failure 2: actual temporary-file routing differs from the docs**

A host-side `/proc` sample found 26 Claude/Codex processes, including helper
children. All 26 resolved literal `/tmp` and `/var/tmp` to scratch device 1792,
not output device 1793. Eighteen advertised `TMPDIR=/var/lib/agent-output/tmp`
and a storage-session flag; eight advertised the shared bulk TMPDIR instead.
The environment variable alone therefore did not establish where literal
`/tmp` writes landed.

The old runtime's session implementation explicitly binds bulk scratch to
`/tmp`. Its commands also use the shared bulk TMPDIR. The newer runtime changes
session routing and assigns owned TMPDIRs to ordinary commands, but it still
intentionally shares explicit `/tmp` paths between commands. Deploying the newer
runtime alone will not clean arbitrary explicitly named temporary workspaces.

Host and agent views also differ for `~/.cache`: the host path is on Btrfs,
while the observed agent namespace binds scratch over that path. The registry
service correctly includes both the host cache and physical scratch cache.
Diagnostics must identify the filesystem, not assume identical path strings
mean identical storage in every namespace.

**Confirmed failure 3: cleanup coverage does not match the data being produced**

The general installed cleaner removes expired response-cache JSON and closed
output files. It does not retire arbitrary shared temporary checkouts, Go build
cache, UV cache, or persistent worktrees.

The [registry cleaner](../modules/home-manager/term/gp-cache-prune.py) discovers
`gp/registry-*` and `gp-*/registry-*` underneath configured cache roots. It does
not discover `tmp/*/gpcache/registry-*`. Earlier manual cleanup of those temporary
namespaces did not add them to routine discovery. The current scan still found
2.7 GiB under one such namespace.

The [build-cache cleaner](../modules/home-manager/term/build-cache-prune.py)
supports verified `.venv`, `node_modules` with an adjacent package manifest and
lockfile, and a specific reproducible test-database layout. It does not cover
the main Go or UV caches. Its latest completed pass reported 51 directories
without the required dependency lockfile. Since 15:00, the captured journal
contains 67 starts, 19 lock-related skips, and one logged cache removal.

These refusals are not permission to delete more aggressively: some directories
contain original work. The missing feature is a producer-declared lifecycle,
not a blanket age-based deletion rule.

**Confirmed failure 4: persistent data keeps entering the temporary-storage pool**

The migration timer moved 80 directories into scratch during the captured day,
including 16 after the 15:30 cleanup. It checks whether the copy fits with only
8 GiB left. The desired cleanup headroom is 32 GiB. It can therefore add data
while the pool is already below the cleanup target. At 18:18, for example, its
journal reported 17.3 GiB free while considering a large source, then migrated
four other worktree directories.

Migration does reject copies that do not fit: the 69.1 GiB `amberchapel` source
was retained outside the pool. The issue is that its admission floor competes
with cleanup, not that it unconditionally copies every source.

The latest completed worktree sweep retained 439 worktrees for local changes,
37 for unpublished commits, 164 for recent use, and others for locks, active
processes or verification failures; it removed two. These counts cover all
configured roots, not exclusively scratch. They demonstrate why repeatedly
starting that cleaner cannot empty the persistent-work class safely.

**Confirmed failure 5: the 8 GiB check is not a storage reservation**

Both old and new command runtimes check current free space before launching.
They do not reserve an expected number of bulk bytes per admitted command.
Already running commands continue writing. Multiple jobs and migration can
therefore pass the same free-space check and collectively exceed the remainder.

For example, four hypothetical 4 GiB jobs could all pass an 8 GiB admission
floor with 12 GiB initially free. The implementation has no accounting for their
16 GiB aggregate commitment. This is an illustration of the code, not a measured
reconstruction of a particular incident.

**What the registry fixes accomplished, and what they did not**

The currently installed registry script matches the repository. Its one-minute
timer and emergency mode are live. At 20:24 it entered zero-age emergency mode
and removed five verified mirrors; free space rose during this audit. The
captured journal contains 324 registry-service starts and 52 logged removals
since 15:00, excluding manual cleanup outside that service. This is not a
stopped-timer problem.

Earlier age limits delayed reclaiming recently used but idle copies. Shortening
them helped. However, copies are recreated for later work, and the registry
cleaner does not govern shared temporary storage, all build caches, migration,
or retained source. Faster registry eviction is mitigation, not a complete
capacity policy.

The legacy general cleaner also requests registry/worktree/build scans under
pressure, in addition to their timers. This explains redundant starts and lock
skips. A successful oneshot exit often means “nothing eligible” or “another pass
is running,” not “space recovered.”

One 833 MiB registry has an empty Git object and an invalid HEAD. Its deletion
check fails closed. It should be repaired or explicitly recovered after checking
for unique work, not force-deleted. The evidence does not establish when or why
the corruption occurred; it is not large enough to explain the overall problem.

**Why previous verification missed this**

The newer capacity sample is still timestamped 15:30, while the old installed
status command exposes no task ownership or growth diagnostics. There is no
continuous per-writer byte history from which to reconstruct every allocation.
The filesystem also uses `noatime`, so access times cannot establish a reliable
last-use policy for caches.

My earlier “fixed” statements verified immediate free space and a particular
cleaner, but not deployment of the full storage runtime, preservation of other
loaded unit definitions across reload, or sustained operation under the real
launch paths. That was insufficient verification. The observed gap is not
repaired merely by making another source change or passing another unit-test
suite.

**Prevention plan, in dependency order**

1. **Make the deployed runtime observable and consistent.** Build a focused
   storage rollout from the intended source; install its general cleaner,
   launch wrappers, shell hooks and environment together. Expose the runtime
   version and task-cleanup state in status. Inventory existing sessions and
   transition them when idle; do not kill active work. Verify both GUI and
   terminal launch paths and both Bash and Zsh. A service-only update is not a
   completed rollout. Compare loaded `ExecStart` with unit files on disk before
   and after daemon reload, and repeat that check after a new login/reboot.
   Keep immutable outputs rooted and maintain one authoritative generation;
   manually loaded improvements must not coexist with older persistent units.
2. **Give every produced directory a lifecycle.** Use owned command TMPDIRs for
   disposable data, with cleanup after the last descendant exits. Either map
   literal `/tmp` to that same ownership boundary or provide a separate explicit
   handoff/workspace API with an owner, retention state and pin. Keep source and
   durable evidence in a persistent workspace class. Never infer disposability
   from a directory's name or age.
3. **Budget the producers, not just the remaining disk.** Account for bytes
   promised to concurrent jobs and migration. Suspend optional migrations unless
   at least the target headroom plus the estimated copy and in-flight commitments
   remain. Enforce per-job/workspace limits where a strict guarantee is needed.
   Offload large builds using the existing remote-worker route. More disk buys
   time but does not correct an unbounded producer.
4. **Complete cache coverage at creation time.** Register custom registry-cache
   namespaces, including those under shared temporary roots. Reuse canonical
   mirrors where feasible; keep lock and unpublished-work checks. Add bounded
   policies for verified Go/UV/package caches using explicit usage information
   or tool-supported management, not `noatime` timestamps. Separate cache byte
   limits from source-retention decisions.
5. **Make pressure handling measurable.** Keep a rolling history of free bytes,
   bytes created/reclaimed by class, last successful cleanup and retained reasons.
   Alert on low headroom, growing unowned data, stale runtime versions and
   repeated zero-reclaim passes. Avoid repeatedly launching expensive worktree
   scans while an equivalent pass holds the lock. Report remaining capacity even
   when the cleaner exits successfully.
6. **Verify steady state before declaring the problem fixed.** Exercise the real
   installed launcher with ordinary and detached-child commands; observe owned
   directories disappear only after completion. Test literal `/tmp`, custom
   cache roots and GUI-launched sessions. Run concurrent reserved-size jobs,
   migrations and repeated cache recreation through multiple pressure cycles.
   Require bounded usage, preserved unpublished work, useful alerts and a
   documented fallback when live/pinned data alone exceeds capacity.

The safety boundary is explicit: no cleanup policy can guarantee indefinite
operation if active or retained source is allowed to consume an unlimited share
of a fixed pool. That requires admission/backpressure, a deliberate capacity
increase, or relocation of persistent work—not deletion of unverified work.

**Evidence and limits**

Sanitized host process/mount snapshots, installed-source hashes, selected service
state, allocation totals, the lifecycle probe and timestamped journal messages
are saved under
`~/.local/state/agent-storage-audit/20261115-2024/`. Only storage-related
environment fields were collected; credentials and agent prompts were not.

This proves the active-runtime mismatch, uncovered classes, conflicting
headroom policies and ineffective repeated cleanup attempts. It does not prove
the originating process for every historical byte or a particular instant of
ENOSPC. Historical free-space observations come from this conversation, and
directory allocation changed while the live scan ran.

**Deployed remediation, November 15 at 21:22 PST**

The targeted installer deployed the current runtime, descendant tracker,
Claude/Codex launchers, Zsh/Bash hooks, migration CLI, and matching cleanup and
registry units. This avoided activating unrelated pending system changes.
The final rollout record is
`~/.local/state/agent-storage-rollout/20261116T052152.561435Z/record.json`.
Installed runtime and task-helper bytes were checked against the repository;
loaded service commands and timers matched their persistent files after two
manager reloads. The bootstrap profile keeps these store paths reachable.

Automatic migration is disabled on nixUltra, including its live timer. Explicit
migration now requires enough space for the copy plus 32 GiB. Ordinary commands
commit 2 GiB each under a shared admission lock and must leave 8 GiB plus other
outstanding commitments free. Commitments last through tracked background
descendants and stop blocking after a reboot. This is conservative admission
accounting, not an enforced byte quota. Interactive terminal commands retain
their scratch without a permanent commitment.

The registry cleaner now includes immediate-child temporary gp/gpcache
namespaces and deduplicates bind aliases by inode. It reclaimed two previously
missed temporary mirrors; a separate verified recovery pass reclaimed two more
idle mirrors while preserving locks, process references and unpublished work.
Pressure cleanup limits recognized Go cache entries toward 2 GiB, with a
one-hour write grace and open-file protection by device/inode. UV uses its own
pruning and nonblocking lock acquisition: a live cache lock is reported as
`busy`, with no force override. The latest cleanup completed in about 1.2 seconds.
Capacity samples now have bounded rotating history and pressure notifications.

The five focused test files ran 90 tests: 89 passed and the opt-in root image
integration test was skipped. Bubblewrap-dependent tests ran with the installed
executable. Live probes additionally verified fresh Zsh command ownership and
argument preservation, retention while a detached child remained alive,
reclamation after that child exited, and preservation of a shared handoff file.
Probe results and installed-source verification are beside the original audit
evidence as `installed-*-probe.json` and `installed-runtime-verification.json`.

Scratch had approximately 27.9 GiB free after remediation. Active work was not
stopped and unverified source was retained. Already running commands and old
Bash environments pinned to an immutable hook keep their previous runtime;
fresh Zsh command launches use the updated hook, and new agent sessions receive
the protected parent temporary namespace. Shared literal `/tmp` handoffs and
persistent worktrees still have no filesystem quota. A running job can exceed
its admission estimate, so these fixes do not guarantee that unlimited retained
or active writes can never fill the fixed image.

**Follow-up incident and correction, November 15 at 22:33–22:37 PST**

The new fixed-size admission estimates caused another guard rejection while
scratch still had 24.87 GiB physically free. Eight live task supervisors held
16 GiB of estimates. Adding the 8 GiB floor and the next command's 2 GiB estimate
required 26 GiB, so ordinary commands returned 75. The supervisors had surviving
descendants; these were not eight dead records that task cleanup could remove.
I introduced this policy in the earlier remediation and chose a fixed estimate
that did not fit long-lived agent process trees. Its synthetic concurrency
limit was the immediate cause of this incident.

The default `commandReserveGiB` is now zero. Both command admission and status
ignore outstanding estimates when this policy is disabled; ordinary admission
continues to check the physical 8 GiB floor and separate output budget. Existing
estimate fields were cleared under the global admission and individual record
locks without changing task lifecycle fields. A temporary recovery service
kept commands admitted during rollout and exited after the disabled policy was
installed. No active task was stopped.

Cleanup reclaimed approximately 5.5 GiB gross: three verified disposable mirrors
(2.58 GiB), old closed Go hash entries (1.56 GiB), and an abandoned GitHub response
cache write (1.36 GiB). Ongoing allocations mean the net free-space increase was
smaller. The partial file was named `64-hex-digits.json.437393`; its writer PID
was absent. The cache writer saves through this temporary name before atomic
rename, but neither its own pruning nor the storage cleaner matched unfinished
writes. The cleaner now recognizes this exact filename pattern and requires
an absent writer PID, at least one hour of age, and no open file reference.

The corrected runtime and hooks are deployed, with the persistent service
commands checked again after reloads. Normal wrapped command execution and
admission were verified at 29.49 GiB free. The focused runtime test file ran 25
tests: 24 passed, including disabled-estimate and abandoned-write regressions;
the opt-in root integration test was skipped. The rollout record is
`~/.local/state/agent-storage-rollout/20261116T063648.758151Z/record.json`, and
verification is in `~/.local/state/agent-storage-audit/20261115-2233/verification.json`.

**Boot-time rollback, November 16**

The next recurrence had a different immediate trigger: at 21:33 scratch had
7.49 GiB free, below the real 8 GiB admission floor. The installed command and
cleanup service again used `iw3s2z78xa462xbcl2wfca2bvk9wx3ps-agent-storage.py`,
without task ownership, partial-cache cleanup or current diagnostics. Registry
cleanup also ran its old executable and retained 15 mirrors as recently used.

The system journal identifies the overwrite. At 15:26:38 on November 16,
`home-manager-greencheetah.service` activated the system's embedded older Home
Manager generation, executed `agentStorageBootstrap`, and explicitly removed
the `agent-storage-bootstrap` profile entry. It then relinked old home files.
The prior installation survived a user-manager reload but did not survive
this boot-time reactivation. I missed that distinction in the previous rollout.

Emergency recovery removed 13 verified disposable mirrors and restored the
current runtime, shell hooks, and cleaners. Free space rose to about 20 GiB
while other work continued; it was 18.91 GiB at final verification. Active or
unpublished work was retained. The task cleaner now also accepts a valid,
tracked record from a previous boot as proof that its descendants are gone;
28 such old records were cleaned, while untracked data remained untouched.

The targeted installer now additionally roots its package independently of the
user profile and installs a separate startup/periodic restoration service. The
service retains fingerprints from successful deployments, checks all affected
files before writing anything, and repairs only recognized legacy contents or
missing links. It defers during Home Manager activation, preserves unknown
configuration changes, and requires no evaluation or network download to
restore its rooted package. The current declarative configuration retires this
compatibility repair when a current full Home Manager generation is activated.

The live test replayed the exact storage portion of the failure: it removed the
bootstrap profile, relinked the actual old shell and service files, and reloaded
the manager. The independent GC root remained present. Starting the enabled
restoration service restored all expected file contents, the current profile,
and working admission; a second pass changed nothing. The system was not
rebooted and running agent jobs were not stopped. Unit tests also cover unknown
file preservation, activation deferral, historical fingerprints and cleanup of
tracked previous-boot scratch. The four focused test files ran 64 tests: 63
passed, with the optional root filesystem integration test skipped.

Final rollout:
`~/.local/state/agent-storage-rollout/20261117T053850.540714Z/record.json`.
Boot journal, restore journal, live simulation and final capacity are saved in
`~/.local/state/agent-storage-audit/20261116-persistence/`.


**Physical capacity recurrence, November 16 at 23:55 PST**

The repaired runtime and boot restoration remained installed; this was not
another rollback or a synthetic command reservation. Scratch had about 9 GiB
free when inspected, close to the physical 8 GiB admission floor. An allocation
scan found approximately 47 GiB in `home/Projects`, 37 GiB in shared `tmp`, and
23 GiB in `home/.cache`. Command-owned task directories were below 0.5 GiB.
These totals include active projects and unpublished source; deleting old task
records alone could not resolve the capacity mismatch.

GP discovery also missed arbitrary temporary namespaces such as `gpc.SEK8`,
`calmridge-gp`, `gpcache-review-native-lint` and `native-proof-1116`. Its global
name exclusion protected temporary copies named `registry-greencheetah` as
though they were the primary cache. Discovery now recognizes immediate
temporary namespaces by GP sidecar locks and protects only the actual primary
cache's filesystem identity. All Git, active-process and lifetime-lock checks
remain required. The deployed cleaner subsequently removed an eligible
`gp-opusrpsplit/registry-greencheetah` mirror.

The existing preallocated image was expanded online from 128 to a bounded
192 GiB. Both declarative host settings were updated. Before allocation, the
resize tool installed a GC-rooted boot command compatible with either image
size; the installed older boot preparation otherwise rejects a different size.
The grow operation retained the ext4 UUID and mounted filesystem, completed
without stopping agent jobs, and successfully ran the new preparation command.
Post-resize scratch had about 72 GiB free and the host retained about 123 GiB.
A later sample after cleanup showed about 73 GiB free.

The 20 GP cleaner tests and three resize validation tests pass. The final
focused deployment retains startup/periodic restoration and disabled synthetic
command reservations. Capacity monitoring, protected output, task cleanup and
mirror cleanup remain enabled. A finite pool still cannot absorb unlimited
active or unpublished writes; source retirement must be explicit.

Final deployment: `~/.local/state/agent-storage-rollout/20261117T080019.130339Z/record.json`.
Verification: `~/.local/state/agent-storage-audit/20261117-capacity/verification.json`.
The installed GP source matches the tested repository file; restoration found
no differences. Restore, task cleanup and GP cleanup services completed
successfully, their timers are enabled, and ordinary command admission passed
with 72.64 GiB free. The capacity boot override and its independent GC root
were verified.
