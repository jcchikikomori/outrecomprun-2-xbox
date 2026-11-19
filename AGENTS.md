# AGENTS.md — working notes for this repository

Ground rules and hard-won lessons for anyone (human or agent) working on the OutRun 2
static recompilation. Read this before changing build, runtime or test tooling.

## 0. The incident to not repeat (2026-11-18/19)

The game froze on the intro. Three wrong theories were chased in order — the media layout
(ISO vs extracted folder), the machine's memory pressure, and the media location — each
producing a plausible-looking correlation that a later run broke. The real variable was in
the log the whole time: the SDK prints the game dir's **settings.toml at startup**, and a
run in `windowed` mode stalls while `borderless` passes.

Rules that come out of it:

* **Before diagnosing a stall, diff the first ~40 lines of two logs** (the Settings block,
  the caches, the media line). The SDK's log is designed to make runs comparable.
* **Normalise the game dir before an A/B**: `settings.toml`, `shadercache.bin`,
  `pipelinecache.bin` and `hdd/` all change behaviour and must be equal (or absent) in
  every dir being compared.
* A settings.toml is user-authored state: **never overwrite or delete it without asking**.
* Read the SDK source (and a peer project's README) *before* the first workaround attempt.
* **Never `pkill -f <pattern>` when the pattern appears in the agent's own command line** —
  it kills the agent's shell. Kill by PID, or use patterns that cannot match the invoking
  command, e.g. `pkill -f 'Game[.]exe$'`.
* Linux builds of the harness must run **inside the container**
  (`scripts/container.sh harness <secs> <pad>` builds *and* runs). A host
  `sdk/harness/build.sh` run dies with `'features.h' file not found`.

## 1. The one rule about game media

The user owns the disc. `default.xbe`, the ISO, the extracted `media/*.cvm` files and
`generated/` (recompiled game code) never enter Git, never go into a CI secret and never
leave the machine. `assets/`, `generated/`, `out/`, `.local/` and `*.iso|*.xbe|*.cvm` are
git-ignored; `scripts/ci/audit-tracked.sh` fails the build if that ever changes.

## 2. Game media layout (corrected)

The runtime (`sdk/runtime/app/game_files.cpp`) prefers an **extracted folder**
(`assets/default.xbe` + its tree) over an `.iso`, exactly like TGP482/BLACK-XBERecomp:

```bash
xdvdfs unpack /path/to/OutRun2.iso .local/playtest/OutRun2-Offline/assets/
# -> assets/default.xbe, update.xbe, dashupdate.xbe, media/data1.cvm, media/data2.cvm
```

Measured, with the settings confound removed:

* The extracted folder did **not** fix the stall by itself; it is still the better layout
  (the peer projects' documented pattern; no disc emulation in the read path).
* A symlink to the ISO inside `assets/` breaks the game (stalls); use real files or a
  hardlink on the same filesystem.
* `assets/` with `default.xbe` but without the rest of the tree reports a damaged disc:
  either the full tree or nothing.
* Keep the ISO out of `assets/` when the folder is there, so the runtime's choice is
  unambiguous.

## 3. The display mode stall

* `display_mode = 'windowed'` stalls the game on this machine's desktop: presents stop at
  23–117 with **no error and no guest trap**; the window stays on the intro logo.
  `vsync` made no difference. The default (`borderless`) passes.
* For playtests and CI runs the game dir must have no `settings.toml` (defaults) or one
  with `display_mode = 'borderless'`.
* A cold `shadercache.bin`/`pipelinecache.bin` also slows the first minutes; warm caches
  before timing anything.

## 4. Never conclude a runtime fix from the headless harness alone

The headless harness is the fast lane (no window, no GPU, scriptable input), but it is
not the same renderer. A hook can remove a trap and reach the race start headlessly while
the same build misbehaves under Proton.

Rule: **a runtime or hook change is only proven when both lanes pass**:

1. Headless harness: no `guest trap` in `logs/outrun2*.log`, expected frame/present count.
2. GE-Proton, game dir with borderless settings: the log advances well past the point
   where the previous build stopped, and there is no `guest trap`.

## 5. The known-good Proton setup

```bash
PROTON=$HOME/.local/share/Steam/compatibilitytools.d/GE-Proton11-11-x86_64/proton
STEAM_COMPAT_DATA_PATH=<prefix> STEAM_COMPAT_CLIENT_INSTALL_PATH=$HOME/.local/share/Steam \
STEAM_COMPAT_APP_ID=53450036 "$PROTON" run 'Z:\path\to\game\Game.exe'
```

* Keep using the same prefix for comparisons; a different one changes the D3D12 pipeline
  cache.
* `logs/outrun2.log` (the runtime's log prefix is `outrun2`, not `game`) is the primary
  evidence. `F3` dumps the guest thread stacks; `F12` saves a screenshot.
* Release builds log **Report and Error lines only** (`log.h`: `NDEBUG` kills Info/Debug).
  `XBE_FILES_LOG=1` promotes file opens/missing files to Report level — the release-safe
  diagnostic. Guest `DbgPrint` is Info level and invisible in release builds.
* Guest traps are logged as `guest trap at <addr>: divide error` followed by the SDK's
  deliberate `x86_trap -> raise -> abort`. A coredump of that abort is not memory
  corruption; it is the trap handler.

## 6. Memory is a scarce resource on the dev machine

* `/tmp` is tmpfs: everything written there is RAM. Multi-GB analysis scratch fills swap
  and makes everything (including the game) crawl. Put scratch under `~/.cache`, keep the
  big `media/` files on disk.
* Before blaming a build, check `free -h` and `df -h /tmp`.
* Heavy jobs must not overlap: one cross-build, one harness run, one game at a time.

## 7. Diagnosis routine for a guest trap or a stall

1. `grep -n 'guest trap' logs/*.log` for the address and the register dump.
2. For a stall (no trap): **diff the Settings blocks of a passing and a failing log
   first** (section 0), then `F3` for the guest thread stacks, then `XBE_FILES_LOG=1`
   for the file activity around the stop.
3. Addresses in a trap dump are guest addresses; map them with the Ghidra project
   (`analyzeHeadless -noanalysis -readOnly`, scripts in `sdk/scripts/ghidra`).
4. A full-program operand scan for a field offset is how the OUTRUN MODE trap was found.
5. The SDK's HLEs replace guest bodies (`sdk/runtime/xdk/d3d8.cpp` implements
   `D3DDevice_SetVertexShader`, `SetStreamSource`, `DrawVerticesUP` and others), so the
   guest's own bookkeeping for those never runs. Expect the same class of bug for every
   HLE'd setter.
6. Guest I/O is fully synchronous (`files.cpp` `Transfer`): a slow host read blocks the
   guest's thread, and guest waits have no timeout (`objects.cpp` `WaitFor`). So a
   "presents stop advancing" symptom is the guest blocked in a read, a wait, or a draw.

## 8. CI on this machine

* The game build runs on a **self-hosted runner** (labels `self-hosted,linux,
  outrun2-recomp`) because the build needs the user's `default.xbe`. Everything else runs
  on GitHub-hosted runners. Only machines that own a legal copy of the game can produce
  the artifact; contributor runs get validate + tools feedback and queue for the runner.
* **The self-hosted job is not contained**: it runs as the user, with the user's real
  `$HOME` — the runner's `_work/` is the only isolated part. Anything in the user's home
  (dotfiles, caches, symlinks) is visible to the job. This bit us twice, see §8.1.
* **Exactly one runner instance per work directory.** Two listeners share `_work/` and
  delete each other's job directories.
* Runs are not cancelled on a newer push (`cancel-in-progress: false`): a cancelled job
  still cleaning its temporary directory breaks the next job's checkout.
* The runner is installed as a user service (`scripts/ci/setup-runner.sh`); linger keeps
  it alive without a login, and it picks queued jobs back up after a reboot.

### 8.1 The checkout / `.gitconfig` incident (2026-11-19)

Symptom: every `Build Game.exe` run died at *Check out the repository* with
`error: could not lock config file …/_work/_temp/<uuid>/.gitconfig: No such file or
directory`, exit 255.

What happens, end to end:

1. `actions/checkout` builds a **temporary `$HOME`** to set `safe.directory` without
   touching the user's real git config (`src/git-auth-helper.ts`): it copies
   `$HOME/.gitconfig` into `$RUNNER_TEMP/<uuid>/` and runs git with that HOME.
2. `@actions/io`'s `cp` **copies symlinks verbatim** (`lstat` → `readlink` → `symlink`;
   no `dereference` option).
3. If `~/.gitconfig` is a **relative** symlink (as dotfiles managers make them), the copy
   dangles inside the temporary HOME, `git config --global` fails with the ENOENT above,
   and the step aborts.
4. Checkout then deletes its temporary HOME — which makes a directory watcher look like
   "something deleted the temp dir mid-job" and sends you chasing a runner race that is
   not there.

Evidence: the dangling file was captured live from `_work/_temp` during a run, and
`cp -P ~/.gitconfig <dir>/ && HOME=<dir> git config --global --add safe.directory /tmp/x`
reproduces the error byte for byte.

Fix (on the machine — nothing to change in the repo):

1. `~/.gitconfig` must be a **regular file**, not a symlink of any kind. `io.cp` then
   copies its *content* into the throwaway HOME, and that copy is independent —
   checkout's per-run global writes (`safe.directory`, and the auth extraheader it
   installs for the fetch) are discarded with it.
2. Do **not** "fix" it with an absolute symlink: the throwaway HOME then contains *the
   same file*, and checkout's global writes go straight into the user's real config. That
   bit us within the hour: `safe.directory` entries and a leaked
   `[http "https://github.com/"] extraheader = AUTHORIZATION: basic <CI token>`
   accumulated in the dotfiles, which (a) made personal HTTPS pushes authenticate as
   `github-actions[bot]` (403) and (b) made the runner's own fetch send the token twice —
   `remote: Duplicate header: "Authorization"` → 400 → the build job's checkout died
   again. Both were cleaned by removing the `[http]` block and the `[safe]` entries. A
   re-stow that recreates a symlink re-introduces the whole failure chain.

Related incident, same day: personal `git push` failed with
`Permission to … denied to github-actions[bot]` (403). The dotfiles'
`url."https://github.com/".insteadOf` rewrote the SSH remote to HTTPS, where the only
configured credential helper was a **WSL Windows binary** — nonexistent on this machine,
so no working credential existed, yet GitHub authenticated the push as
`github-actions[bot]`. Removing the rewrite lets pushes stay on SSH (verify with
`ssh -T git@github.com`). If HTTPS pushes are ever needed, set up a real helper once
(`gh auth login && gh auth setup-git`) and keep it in the dotfiles.

Re-running CI without fixing anything fails by definition; that was never a
counterexample.

## 9. Git rules

* Never commit or push from an agent session: the maintainer commits with GPG. Stage the
  files (`git add`), then hand over the exact commit message.
* Keep generated game code, media and build output out of the index;
  `scripts/ci/audit-tracked.sh` is the gate.
* One commit per coherent change, Conventional Commits, body that explains *why*.

## 10. Known issues

| Issue | State |
| --- | --- |
| Boot read race (frozen intro / OOM abort) | **Fixed 2026-11-19**: the title's boot compares the hard disk's voice banks against `media/data1.cvm` and fills a bank-descriptor table from it; reads that complete at once win that race, and the title then waits forever in its heap on a bogus ~2 GB allocation (the harness aborts on its OUT OF MEMORY assert; Proton showed a black screen frozen at present 23). `disc_rate = 6` in `src/common/game_info.cpp` paces reads as the console's DVD; verified: paced cold boot reaches thousands of presents, `XBE_DISC_RATE=0` reproduces the present-23 stall. |
| OUTRUN MODE divide error at `0x00195D6B` | **Fixed 2026-11-19**: `src/game/hooks.cpp` wraps `0x00195CF0`, builds the bound FVF's declaration locally with the guest builder's writes and caches it with the guest's own arithmetic. For FVF `0x1D2` that is 10 dwords = 0x28 bytes, exactly the draw's stride. Headless lane passed, no trap. See `docs/evidence/phase0/outrun-mode-trap.md`. Proton rendering-quality playtest pending. |
| Display mode | `windowed` correlates with the older stall runs; borderless stays the recommended mode (see section 3). |
| `fs:`/SEH guest paths | Hundreds of `FS:` instructions; the SDK translates them, but no guest SEH path has been exercised deliberately. |
