# AGENTS.md — working notes for this repository

Ground rules and hard-won lessons for anyone (human or agent) working on the OutRun 2
static recompilation. Read this before changing build, runtime or test tooling.

## 0. The incident to not repeat (2026-11-18/19)

The game froze on the SUMO intro. Three wrong theories were chased in order — the media
layout (ISO vs extracted folder), the machine's memory pressure, and the media location
(tmpfs vs disk) — each producing a plausible-looking correlation that a later run broke.
The real variable was in the log the whole time: the SDK prints the game dir's
**settings.toml at startup**, and a run done in `windowed` mode stalls on this Deck while
`borderless` passes. Nobody diffed the Settings blocks of the passing and failing logs
until much later.

Rules that come out of it:

* **Before diagnosing a stall, diff the first ~40 lines of two logs** (the Settings block,
  the caches, the media line). The SDK's log is designed to make runs comparable.
* **Normalise the game dir before an A/B**: `settings.toml`, `shadercache.bin`,
  `pipelinecache.bin` and `hdd/` all change behaviour and must be equal (or absent) in
  every dir being compared.
* A settings.toml is user-authored state: **never overwrite or delete it without asking**.
* Read the SDK source (and a peer project's README) *before* the first workaround attempt;
  an hour of reading would have saved the whole session.
* **Never `pkill -f <pattern>` when the pattern appears in the agent's own command line** —
  it kills the agent's shell (happened twice on 2026-11-19). Kill by PID, or use patterns
  that cannot match the invoking command, e.g. `pkill -f 'Game[.]exe$'`.
* Linux builds of the harness must run **inside the container**
  (`scripts/container.sh harness <secs> <pad>` builds *and* runs). A host `sdk/harness/build.sh`
  run dies with `'features.h' file not found` (the host lacks the dev headers the image has).

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

What was measured (2026-11-19), with the settings confound removed:

* ISO on disk with borderless settings reached 2093 presents and the race start — so the
  ISO mode itself is **not** the stall cause.
* The extracted folder with windowed settings still stalled — so the extracted folder did
  **not** fix anything by itself. It is still the better layout (BLACK-XBERecomp's
  documented pattern; no disc emulation in the read path), but it was not the fix.
* A symlink to the ISO inside `assets/` does break the game (stalls); use real files or a
  hardlink on the same filesystem.
* `assets/` with `default.xbe` but without the rest of the tree reports a damaged disc:
  either the full tree or nothing.
* Keep the ISO out of `assets/` when the folder is there, so the runtime's choice is
  unambiguous.

## 3. The display mode stall (the real cause of the intro freeze)

| Run (same exe, same ISO, same prefix) | settings.toml | presents | result |
| --- | --- | --- | --- |
| OutRun2-Offline 20:53 | default (`borderless`) | 2093 | race reached |
| OutRun2-Offline 23:46–23:54 | `windowed` | 23–116 | stalled |
| OutRun2-Offline 00:15 (extracted folder) | `windowed` | 117 | stalled |
| iso-disk-test 00:10 | default (`borderless`), cold caches | 26 | stalled |
| tmpfs build dir 23:59, 00:07 | default (`borderless`), warm caches | 2055, 1658 | race reached |

* `display_mode = 'windowed'` stalls the game on this Deck (X11, kwin): presents stop at
  23–117 with **no error and no guest trap**; the window stays on the SUMO logo.
  `vsync = false|true` made no difference — it is the mode, not vsync.
* Default mode is `borderless` and passes. For playtests and CI runs the game dir must
  have no `settings.toml` (defaults) or one with `display_mode = 'borderless'`.
* A cold `shadercache.bin`/`pipelinecache.bin` also slows the first minutes (26 presents
  in 40 s); warm caches before timing anything.

## 4. Never conclude a runtime fix from the headless harness alone

The headless harness is the fast lane (no window, no GPU, scriptable input), but it is not
the same renderer. Counterexample from 2026-11-18: the `FixIndexedVerticesUpLayout` hook
removed the OUTRUN MODE divide trap and the harness reached the race start — and under
Proton the same build hung on the SUMO intro. (That hang was partly the windowed-mode
stall, but the vertex-layout correctness still has to be proven under Proton: the guest's
push-buffer vertex layout has to match the bound FVF declaration, not just the draw's total
stride.)

Rule: **a runtime or hook change is only proven when both lanes pass**:

1. Headless harness: no `guest trap` in `logs/outrun2*.log`, expected frame/present count.
2. GE-Proton 11 on the Deck, game dir with borderless settings: the log advances well past
   the point where the previous build stopped, and there is no `guest trap`.

## 5. The known-good Proton setup

```bash
PROTON=$HOME/.local/share/Steam/compatibilitytools.d/GE-Proton11-11-x86_64/proton
STEAM_COMPAT_DATA_PATH=<prefix> STEAM_COMPAT_CLIENT_INSTALL_PATH=$HOME/.local/share/Steam \
STEAM_COMPAT_APP_ID=53450036 "$PROTON" run 'Z:\path\to\game\Game.exe'
```

* The prefix at `.local/playtest/OutRun2-Offline/proton-prefix` works; keep using the same
  one for comparisons, a different prefix can change the D3D12 pipeline cache and the intro.
* `logs/outrun2.log` (the runtime's log prefix is `outrun2`, not `game`) is the primary
  evidence. `F3` dumps the guest thread stacks; `F12` saves a screenshot.
* Release builds log **Report and Error lines only** (`log.h`: `NDEBUG` kills Info/Debug),
  so the SDK's file-activity and `LOG_FIRST` lines are hidden; `XBE_FILES_LOG=1` promotes
  file opens/missing files to Report level and is the release-safe diagnostic. `DbgPrint`
  from the guest is Info level and invisible in release builds — do not look for it.
* Guest traps are logged as `guest trap at <addr>: divide error` followed by the SDK's
  deliberate `x86_trap -> raise -> abort`. A systemd coredump of that abort is not memory
  corruption; it is the trap handler.

## 6. This Deck has 14 GiB RAM and 8.5 GiB swap — treat memory as the scarce resource

* `/tmp` is **tmpfs**: everything written there is RAM. Analysis scratch of several GB
  fills the swap and makes everything (including the game) crawl. Put scratch on `/home`
  or in `~/.cache/outrun2-scratch`; keep the big `media/` files on disk.
* Before blaming a build, check `free -h` and `df -h /tmp`. During the 2026-11-18 session,
  5.6 GB of tmpfs scratch had pushed swap to 100 %.
* Heavy jobs must not overlap: one cross-build, one harness run, one game at a time.
* But note: the "~115 presents then silence" symptom that was once attributed to memory
  starvation turned out to be the windowed-mode stall (section 3). Memory pressure is a
  real hazard, it is just not the cause of that particular freeze.

## 7. Diagnosis routine for a guest trap or a stall

1. `grep -n 'guest trap' logs/*.log` for the address and the register dump.
2. For a stall (no trap): **diff the Settings blocks of a passing and a failing log
   first** (see section 0), then `F3` for the guest thread stacks, then
   `XBE_FILES_LOG=1` for the file activity around the stop.
3. The divisor/object addresses in a trap dump are guest addresses: `0x001A4150` is the
   static `CDevice`, `0x001A4D18` is `CDevice+0xBC8` (the cached vertex layout).
4. Ghidra headless (`~/.cache/ghidra-12.1.4/.../support/analyzeHeadless`), project
   `/tmp/opencode/ghidra-projects/OutRun2Phase0`, program `game.exe`, with the SDK's
   scripts in `sdk/scripts/ghidra` (Disasm, Decomp, Callers, FindOperand). Use
   `-noanalysis -readOnly`.
5. A full-program operand scan for a field offset is how the OUTRUN MODE trap was found:
   only five instructions mention `0xBC8`, and exactly one writes it.
6. The SDK's HLEs replace guest bodies: `sdk/runtime/xdk/d3d8.cpp` implements
   `D3DDevice_SetVertexShader`, `SetStreamSource`, `DrawVerticesUP` and others, so the
   guest's own bookkeeping for those never runs. Expect the same class of bug for every
   HLE'd setter.
7. Guest I/O is fully synchronous (`files.cpp` `Transfer`): a slow host read blocks the
   guest's thread, and guest waits have no timeout (`objects.cpp` `WaitFor`). There is no
   readahead/cache in `kernel/disc.cpp`. So a "presents stop advancing" symptom is the
   guest blocked in a read, a wait, or a draw, and the log will tell you which.

## 8. CI on this machine

* The game build runs on a self-hosted runner on this Deck (`steamdeck-outrun2`, labels
  `self-hosted,linux,outrun2-recomp`) because the build needs the user's `default.xbe`.
  Everything else runs on GitHub-hosted runners.
* **Exactly one runner instance per work directory.** Two listeners share `_work/` and
  delete each other's job directories; the second job then fails with
  `could not lock config file .../_temp/<id>/.gitconfig`.
* Runs are not cancelled on a newer push (`cancel-in-progress: false`): a cancelled job
  that is still cleaning its temporary directory breaks the next job's checkout.
* The runner is installed as the user service `actions-runner.service`
  (`scripts/ci/setup-runner.sh`); `loginctl enable-linger` keeps it alive without a login.

## 9. Git rules

* Never commit or push from an agent session: the maintainer commits with GPG. Stage the
  files (`git add`), then hand over the exact commit message.
* Keep generated game code, media and build output out of the index;
  `scripts/ci/audit-tracked.sh` is the gate.
* One commit per coherent change, Conventional Commits, body that explains *why*.

## 10. Known issues

| Issue | State |
| --- | --- |
| Intro freeze, presents stop at 23–117, no error | **Cause found**: `display_mode = 'windowed'` on this Deck's X11/kwin. Borderless passes. See section 3. |
| Headless harness freezes during the boot audio load | Flaky, pre-dates the current hook work (2026-11-18 23:31, old binary: 7 of 9 attempts froze at frame 120–900; 2026-11-19 01:16: 10 of 10 froze at ~4 s during the `z:\*.xwb` voice-bank opens). **Diagnosed 2026-11-19 01:10**: it is the guest aborting on its own OUT OF MEMORY assert (`__break`, `0x000ccfb0`) with a ~2 GB allocation request (`eax=0x7FFFFFE0`) — a bank-descriptor size read before it was filled, a race that instant unpaced disc reads expose (`sdk/runtime/kernel/files.cpp` `DiscPace` exists for exactly this). `XBE_DISC_RATE=6` shifts the timing but does not remove it. Sometimes it surfaces as a host SEGV in early boot instead. Roughly 1–3 attempts in 10 get through; the retry driver (`/tmp/opencode/outrun2-mode-test/cr2-retry.sh`, freeze-detecting, ~20 s per dead attempt) handles that. Un-fixed. |
| OUTRUN MODE divide error at `0x00195D6B` (cached vertex layout is 0) | **Fixed 2026-11-19**: `src/game/hooks.cpp` wraps `0x00195CF0`, builds the bound FVF's declaration locally with `FUN_00196200`'s writes and caches it with `FUN_0019E9E0`'s arithmetic into the CDevice (`+0xBC8`…). For FVF `0x1D2` that is 10 dwords = 0x28 bytes, exactly the draw's stride. Headless lane passed (`layout 10 dwords … end 40`, no trap; banner draw + race reached). The guest's `hle::Call` variant and the SDK's widened declaration (25 dwords) were rejected - see `docs/evidence/phase0/outrun-mode-trap.md`. Proton playtest pending (build `2b3a4cf6…` in `~/.cache/outrun2-scratch/cr2/pgame/`). |
| Earlier "extracted folder fixes the stall" claim | Retracted — confounded by the windowed settings.toml (section 0/2). |
| Earlier "memory starvation causes the ~115-present freeze" claim | Retracted — that was the windowed-mode stall (section 6). |
| `fs:`/SEH guest paths | 547 `FS:` instructions in 200 labels; the SDK translates them, but no guest SEH path has been exercised deliberately. |
