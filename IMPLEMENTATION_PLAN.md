# OutRun 2 Original Xbox Recompilation Implementation Plan

**Plan date:** 2026-11-18  
**Primary target:** Native Windows x64  
**Source media:** User-supplied Original Xbox DVD image for *OutRun 2*  
**Design baseline:** `/home/deck/Documents/OutRun2 Xbox Static/OutRun 2 Original Xbox Static Recomp Design Document.md`

## 1. Objective and Planning Assumptions

The objective is to produce a native Windows x64 build of the 2004 Original Xbox version of
*OutRun 2* by statically recompiling `default.xbe`.

The target is a **PC port**, not software intended to run on Original Xbox hardware.

The plan assumes:

- The user owns or otherwise has lawful access to an Original Xbox *OutRun 2* disc image.
- The ISO, extracted game assets, generated lifted code, and game-specific keys remain local.
- Version 1.0 prioritizes faithful boot, menus, gameplay, audio, input, saves, and frame pacing.
- Modern presentation features and online-service emulation are deferred until the original
  game is stable.
- A clean-room reference implementation is allowed to use the public
  [XboxXBERecomp SDK](https://github.com/TGP482/XboxXBERecomp), but no original game code or assets
  are redistributed with the project.

A successful result is a build that starts from the user's own disc, reaches the title screen,
plays a complete race, saves progress, and remains stable across repeated sessions.

## 2. Scope Boundaries

### Version 1.0 includes

- A reproducible source build on Windows x64.
- A native executable generated from the user's `default.xbe`.
- Boot to the title screen and navigation through the menus.
- At least one complete race course, followed by coverage of all five OutRun courses.
- Faithful Xbox-era visuals, audio, controls, and original simulation cadence.
- Save-game persistence with recoverable backups.
- Controller input plus keyboard and mouse fallback.
- Two-player System Link over LAN or direct IP.
- Diagnostic tooling for symbols, rendering, input replay, frame timing, and crashes.
- A local disc verifier that rejects unsupported or damaged media.

### Version 1.0 excludes

- Xbox Live 1.0 matchmaking or any replacement online service.
- Original Xbox hardware output.
- Ultrawide rendering, HDR10, arbitrary high frame rates, and custom music.
- A Linux, macOS, Android, or console backend.
- A polished end-user launcher.
- Steering-wheel force feedback unless the Phase 0 audit proves it is required for the original
  game to function.

These items remain valid post-1.0 candidates, but they must not delay the core port.

## 3. Corrections to the Initial Design Document

The upstream toolchain and command sequence in the design document are broadly sound. The following
details should be corrected before implementation:

| Design-document statement | Planning decision |
| --- | --- |
| `pgr2-recomp` uses canonical `TGP482/XboxXBERecomp` directly. | It uses the `hk21x/XboxXBERecomp` fork, which contains useful harness, Ghidra, and input work. Compare both before choosing the pinned SDK. |
| Wheel force feedback is an entirely unsolved runtime feature. | `pgr2-recomp` demonstrates a reusable DirectInput force-feedback layer. OutRun 2-specific XID behavior still requires analysis. |
| XboxXBERecomp cannot support NV2A push-buffer commands. | Canonical upstream has basic push-command and `RunPushBuffer` handling; the `hk21x` fork adds ordered push-buffer recording and fixups. This XBE actively calls `BeginPush` and `EndPush`, so the exact command patterns must be verified against the selected SDK. |
| The selected SDK does not translate `fs:` segment accesses. | Both canonical upstream and the `hk21x` fork implement an `fs_base` guest segment, lift `fs:` accesses through it, initialize it from the thread's KPCR, and handle SEH frames. Runtime verification is still required. |
| Recompiled code is generated only at developer build time. | Upstream also supports a release model that builds the user's game code locally on first start. Choose either model deliberately during packaging. |
| `bustinout-recomp` is a verified keyboard/mouse reference. | No such repository was verified. Use `fuzionfrenzy-recomp` or `urbz-recomp` as the keyboard/mouse references instead. |
| The `takedawn` Vulkan/Metal claims, exact verifier timing, and compilation timings are established. | Treat these as unverified until they are measured or supported by primary documentation. |
| Emulator issue reports are direct evidence of current runtime defects. | Treat them as investigation leads only. Reproduce each failure in the new runtime before designing a fix. |

The `xbe_symbols`, `xbe2pe.py`, `add_xbe_image`, `X86_FUNC`, `gpu::Extension`, `app::kGame`, and
`XLaunchNewImage` interfaces were confirmed in current upstream documentation.

## 4. Architecture Decision

### Recommended baseline

Use the public [XboxXBERecomp SDK](https://github.com/TGP482/XboxXBERecomp) as the architectural
base and the [PGR2 recomp project](https://github.com/hk21x/pgr2-recomp) as the closest implementation
reference.

Phase 0 compared these revisions:

1. Canonical `TGP482/XboxXBERecomp` at `cc9edda3a821a4204dc28783f429b88a27ade4f9`.
2. The `hk21x/XboxXBERecomp` fork used by `pgr2-recomp` at
   `b908ae7f05908ff335f94037c673e4b437c7c1d6`.
3. The `pgr2-recomp` game-side configuration and scripts.

The **provisional selection is the `hk21x` fork**. It is newer, retains the upstream `fs:` and SEH
translation, adds ordered push-buffer recording and fixups, and includes the Linux headless harness
and Ghidra scripts needed for this title's evidence path. Canonical upstream remains the compatibility
fallback and the source for any runtime fix that must be proposed upstream.

This selection remains provisional until the Ghidra command-pattern audit proves that the fork
covers the push sequences used by *OutRun 2*. Pin the final SDK to an exact commit and record the
decision in the repository.

### Runtime boundaries

- The guest Xbox executable remains the source of game behavior.
- Xbox kernel, XDK, Direct3D 8, DirectSound, XInput, and XNet calls are supplied by the host
  runtime.
- Game-specific fixes belong in `config/outrun2.toml`, `src/game/`, or narrowly scoped runtime
  changes.
- Generated lifted code is never edited or committed.

## 5. Repository Shape

```text
outrun-2-xbox-recomp/
├── CMakeLists.txt
├── build.bat
├── sdk/                       # Pinned SDK submodule
├── assets/                    # Local only: ISO, XBE, extracted media
├── generated/                 # Local only: generated lifted code
├── .local/                    # Local only: analysis exports and scratch output
├── config/
│   ├── game.toml              # Generated by xbe_symbols
│   └── outrun2.toml           # Hand-authored analysis and hook configuration
├── scripts/
│   ├── inventory-disc.*       # Image and XBE identity checks
│   ├── audit-xbe.*            # Headless static-analysis helpers
│   ├── replay-input.*         # Deterministic controller sequences
│   └── verify-assets.*        # Local disc manifest verification
├── src/
│   ├── common/                # Application, input, settings, and runtime glue
│   └── game/                  # Title-specific function overrides
└── docs/
    ├── evidence/              # Redacted findings and test evidence
    └── verification.md        # Verification matrix and exit criteria
```

The repository must enforce ignores for `assets/`, `generated/`, `.local/`, crash dumps, logs, and
user data. A tracked-file audit is part of every release gate.

## 6. Phased Delivery Plan

### Phase 0: Media Intake and Feasibility Spike

**Goal:** Establish that the target disc and existing runtime can support a viable PC port before
building a full game project.

#### Completed baseline

- The supplied European ISO was inventoried without modification. Its identity and XDVDFS tree are
  recorded in `docs/evidence/phase0/media-inventory.md`.
- `default.xbe` was exported and identified as the signed European `SE-054` title `53450036`.
- `xbe_symbols` matched XDK `5849`, reported **64 partitions**, and found 186 of 278 known functions
  plus 12 of 13 known data objects.
- `update.xbe` and `dashupdate.xbe` were classified as the Online Updater Application and Xbox
  Dashboard Updater. They are not gameplay images unless an `XLaunchNewImage` reference proves
  otherwise.
- A flat PE was exported for Ghidra and its SHA-256 was recorded.
- Ghidra found 547 `FS:`-prefixed instructions in 200 containing function labels. Both SDK
  candidates implement the required `fs_base` translation and SEH support.
- Ghidra found seven direct `BeginPush`/`EndPush` call sites containing nine push sequences. Those
  sequences use only NV2A methods `0x17FC` and `0x1818`, both recognized by the selected SDK. No
  `CreatePushBuffer` or `RunPushBuffer` reference was found.
- Both CVM containers were inventoried. The 15 `.SFD` files are MPEG-1 Program Streams; no Bink or
  `.xmv` media was found.
- The 92 unmatched functions were classified against the XBE's `.XTLID` table. No symbol with an
  export ID present in the XBE remains unresolved.
- The input path uses four standard XInput ports and standard rumble state. No wheel-specific XID
  packet path was found, so native force feedback is not a Version 1.0 blocker.
- Both SDK candidates were inspected. The `hk21x` fork additionally provides ordered push-buffer
  recording, fixups, and the required headless diagnostics.

#### Remaining tasks

1. Build the selected SDK on a clean Windows host with the documented toolchain.
2. Carry the `fs:`/SEH and push-command audits into the Phase 1 runtime boot test.

The working symbol and flat-PE commands are:

```powershell
xbe_symbols assets\default.xbe sdk\xdk --out config\game.toml
python sdk\tools\symbols\xbe2pe.py config\game.toml .local\game.exe
```

#### Exit gate

Phase 0 passes only if all of the following are true:

- The ISO and XBE identities are recorded and repeatable.
- XDK `5849` signatures match, and the generated configuration uses 64 partitions.
- The `fs:` implementation is confirmed statically and scheduled for runtime verification.
- Every raw push command emitted by the nine identified sequences is covered by the selected SDK.
- The video inventory is complete, and the input-device and unmatched-symbol audits have explicit
  outcomes.
- A native Windows toolchain can compile the selected SDK and its dependencies.
- No copyrighted media, generated game code, or keys are tracked by Git.

#### Stop conditions

Stop and revise the architecture if a runtime test finds an unsupported push command or proves that
`fs:`/SEH translation is incomplete.

### Phase 1: Reproducible Skeleton and Title/Menu Boot

**Goal:** Produce the first native executable that reaches the title screen and menus.

#### Tasks

1. Create the project from the selected SDK or `pgr2-recomp` skeleton.
2. Pin `sdk/` as a submodule and configure `add_xbe_image` for *OutRun 2* with 64 partitions.
3. Populate `app::kGame` with title, window, logging, settings, and lifecycle fields.
4. Create `config/outrun2.toml` for title-specific overrides without hand-editing generated code.
5. Resolve boot-time trapping stubs in small batches, recording each resolved address and evidence.
6. Build the application in a clean checkout with the documented command sequence.
7. Add deterministic input replay for title and menu navigation.
8. Capture a crash dump and symbol map for every unresolved failure.
9. Establish a local manifest of required disc files and their hashes.
10. Measure the game's update and presentation cadence from the running build and record whether the
    simulation is 60 Hz, 30 Hz, or variable.
11. Exercise an SEH or C++ exception path that reaches the guest's `fs:[0]` chain.

#### Exit gate

- A clean source checkout builds on a documented Windows host.
- The executable reaches the title screen without manual debugger intervention.
- Every menu can be entered and exited with scripted input.
- The title screen and each menu have repeatable PNG evidence.
- Every remaining trapping stub has an owner and a disposition.
- The measured simulation cadence is documented and stable before race work begins.
- The guest `fs:[0]` SEH chain behaves correctly in at least one exercised failure path.

### Phase 2: Race Rendering and Simulation Parity

**Goal:** Complete a race on the original, measured simulation cadence without visual or timing
defects.

#### Tasks

1. Render one course at a fixed baseline resolution with no modern enhancements enabled.
2. Validate road surfaces, car geometry, lighting, palettes, textures, and HUD placement.
3. Reproduce and fix menu texture swizzling and car-selector behavior if present.
4. Confirm bound-resource lifetime by running through repeated course transitions.
5. Verify ordered push-buffer handling in the selected SDK and extend it only if the Phase 0 audit
   found an unsupported command pattern.
6. Separate simulation cadence from render presentation and enforce the cadence measured in Phase 1.
7. Measure frame timing with `XBE_PERF`; do not infer frame rate from visual appearance alone.
8. Complete one course end to end, then repeat across all five courses.

#### Exit gate

- One full course completes in native Direct3D 12 without missing geometry, corrupted textures, or
  mid-race crashes.
- The simulation advances at the cadence established in Phase 1.
- HUD and menus remain visually coherent at the baseline resolution.
- Repeated course starts and transitions do not expose resource-lifetime faults.
- Failures seen in emulator reports are either reproduced and fixed or explicitly shown not to apply.

### Phase 3: Modes, Audio, Input, and Saves

**Goal:** Make the ordinary single-player experience complete and stable.

#### Tasks

1. Validate all available game modes and progression unlocks.
2. Verify music, effects, and voice clips, including transitions where the original may truncate
   speech.
3. Reproduce the reported pause-menu restart problem and fix it at the responsible synchronization
   boundary.
4. Implement keyboard and mouse fallback using a virtual controller port.
5. Validate hot-plug, remapping, and rumble for supported SDL3 controllers.
6. Audit whether the original XBE sends native wheel-actuator packets.
7. Adapt the `pgr2-recomp` DirectInput wheel layer only if native force feedback is required.
8. Validate save creation, reload, corruption recovery, and backup rotation.
9. Run a soak test covering menu use, race completion, pause/restart, and multiple reloads.

#### Exit gate

- All single-player modes are traversable.
- Voice and music clips complete at menu-to-course transitions.
- At least 100 scripted pause/restart cycles complete without a hang.
- Save data survives a normal restart and a forced process termination.
- A one-hour automated soak completes without a crash, unbounded memory growth, or stuck state.

### Phase 4: System Link and Local Release

**Goal:** Deliver a reproducible local build and verify the supported multiplayer path.

#### Tasks

1. Verify two local instances can establish a System Link session.
2. Expand to the supported player count after the two-instance path is stable.
3. Test direct-IP joining separately from LAN discovery.
4. Add an asset verifier that checks the supported disc against the local manifest.
5. Decide between a developer source build and a clean-room launcher that compiles the user's XBE
   locally.
6. Package the runtime, diagnostics, legal notices, and source-build instructions.
7. Run a clean-machine reproduction test using only documented prerequisites.
8. Audit all tracked files and release artifacts for game assets and generated code.

#### Exit gate

- Two-player System Link completes a race without desynchronization or crash.
- The supported disc passes the asset verifier.
- A clean machine can build and launch using documented steps.
- No tracked or packaged file contains user media or generated lifted code.
- The release notes accurately state supported regions, revisions, and known limitations.

### Phase 5: Optional Enhancements

Only begin this phase after Version 1.0 is stable.

Evaluate each feature independently:

- Native ultrawide rendering with an undistorted HUD.
- MSAA, anisotropic filtering, and HDR10.
- Wheel force feedback beyond the original game's behavior.
- User-owned MP3 or FLAC soundtracks.
- Linux Vulkan runtime.
- Replacement online lobby service.

Each enhancement requires its own regression gate and must not alter game simulation unless separately
verified.

## 7. Phase 0 Static Feasibility Audit

The audit uses the flat PE and a Ghidra project containing the `Decomp`, `FindOperand`, and `Callers`
scripts used by the `pgr2-recomp` reference project.

| Question | Evidence required | Current result | Remaining gate |
| --- | --- | --- | --- |
| Does the game use raw NV2A push commands? | Import/caller reports plus reviewed decompilation of every hit. | Nine sequences across seven call sites use only methods `0x17FC` and `0x1818`; both SDKs recognize them. | Verify rendered output and state ordering in Phase 2. |
| Does the game use `fs:` segment accesses for TLS, the TIB, or SEH? | Operand search, caller review, and runtime segment-handling inspection. | Ghidra found 547 `FS:` instructions in 200 containing labels. Both SDKs translate them through `fs_base`. | Exercise a guest SEH path in the Phase 1 runtime. |
| Does the disc contain secondary XBE images? | XDVDFS tree plus `XLaunchNewImage` references. | `update.xbe` is the Online Updater Application; `dashupdate.xbe` is the Dashboard Updater. | Confirm no gameplay path launches them. |
| Which video formats are present? | Media inventory and decoder calls in the XBE. | The 15 `.SFD` files are MPEG-1 Program Streams; the `WMADEC` section is part of the guest XBE. | Verify movie playback in Phase 1 or 2. |
| Does the input layer send wheel-specific XID packets? | XInput and USB device-call paths plus packet construction review. | Four standard XInput ports and standard rumble state were found; no wheel-specific path was found. | Treat native force feedback as optional, not a Version 1.0 gate. |
| Which XDK build produced the XBE? | `xbe_symbols` output and XBE library versions. | XDK `5849` matched. | Review unmatched entries for actual calls. |
| What is the actual partition count and code layout? | `xbe_symbols` output and XBE section table. | 64 partitions and 13 code sections were identified. | Use 64 in `add_xbe_image` and validate the first build. |

The `hk21x/XboxXBERecomp` SDK fork includes a `scripts/ghidra/PushBufferScan.java` helper. Reuse it
only after checking that its addresses and assumptions match the *OutRun 2* XBE.

## 8. Verification Matrix

| Claim | Minimum evidence | Acceptance condition | Owner |
| --- | --- | --- | --- |
| The selected disc is identified correctly. | Outer image digest, XBE digests, metadata, and file tree. | All values are recorded and repeatable. | Implementer |
| The XBE can be symbol-matched. | `xbe_symbols` report and generated configuration. | XDK 5849 matches; every unmatched entry is proven unused or reviewed. | Implementer |
| The native toolchain is reproducible. | Clean-checkout build log and version manifest. | Build succeeds using only documented prerequisites. | Implementer |
| Push-buffer and segment assumptions are valid. | Static-audit report with reviewed call sites. | Every use is supported or has an approved implementation. | Implementer and reviewer |
| The game boots correctly. | Automated input sequence and PNG captures. | Title and all menus are reached without intervention. | Implementer |
| Rendering is faithful enough to play. | Fixed-resolution frame captures and course completion. | No missing road, corrupted texture, or rendering crash. | Implementer and reviewer |
| Simulation timing is preserved. | `XBE_PERF` or equivalent time series. | The cadence measured in Phase 1 is met across repeated runs. | Implementer |
| Restart and save flows are stable. | Repetition script and save comparisons. | No hang; saves reload and recover as designed. | Implementer |
| Multiplayer is stable. | Two-instance and multi-instance session logs. | Supported sessions complete without desynchronization. | Implementer |
| Copyright separation is maintained. | `git ls-files`, ignore audit, and package scan. | No media, keys, or generated game code is tracked or shipped. | Reviewer |

### Verification budget

- Run the complete automated suite only at phase exits.
- Run focused tests after each hook, runtime, or configuration change.
- Reuse captures and logs while the corresponding code, media, and configuration are unchanged.
- Repeat expensive graphics and soak tests after changes that affect timing, resource lifetime,
  threads, or the renderer.
- Treat visual comparisons as supporting evidence; gameplay completion is the primary gate.

## 9. Primary Risks and Responses

| Risk | Probability | Impact | Response and trigger |
| --- | --- | --- | --- |
| Push command semantics are not fully honored at runtime. | Medium | Medium | Static analysis found only methods `0x17FC` and `0x1818`, both recognized. Verify state ordering and rendered output in Phase 2. |
| Incomplete `fs:`/SEH behavior despite static translation support. | Medium | High | Both SDKs implement `fs_base`; require a runtime exception-path test in Phase 1. |
| Unmatched XDK function is actually required. | Medium | Medium | XDK 5849 matched 186 of 278 functions; prove each unmatched entry is unused or add a reviewed signature. |
| Rendering-state or resource-lifetime mismatch. | High | Medium | Fixed-resolution captures, deferred release, and repeated transition tests. |
| Frame-rate change alters physics. | Medium | High | Measure the original cadence in Phase 1, preserve it in Version 1.0, and defer higher rates. |
| Threading or restart deadlock. | Medium | High | Reproduce early and test at least 100 restart cycles. |
| Upstream or fork drift. | High | Medium | Pin exact commits and keep game-specific patches outside generated code. |
| Video codec gap. | Medium | Medium | Inventory media before finalizing the boot gate. |
| Sensitive assets enter source control. | Low | High | Ignore rules, local-only storage, and tracked-file audits. |
| Wheel behavior expands scope. | Medium | Low | Ship standard controller support first; audit native FFB before adding it. |

## 10. Tooling and Host Setup

### Windows development host

Use the host recommended by the selected SDK for release builds:

- Windows 10 or 11 x64.
- Visual Studio 2022 with Desktop development with C++.
- The C++ Clang tools for Windows component.
- CMake, Ninja, LLD, Python, and Git.
- A Direct3D 12-capable GPU and current display drivers.

### Linux analysis host

The current workstation supports source inspection and static analysis. It has Git, CMake, Clang,
LLD, Python, Java, Cargo, Wine, `xdvdfs`, and Ghidra 12.1.4. The host lacks native development
headers and Ninja, so the Linux `xbe_symbols` tool was built in an ephemeral Ubuntu container with
Docker/Podman instead of changing the host installation.

Do not assume the Linux host can build the final D3D12/XAudio2 runtime until the selected SDK proves
that path. Keep analysis and release builds separate until that is demonstrated.

### Disc inspection example

On a system with `xdvdfs-cli` installed:

```bash
xdvdfs info "/path/to/outrun2.iso"
xdvdfs tree "/path/to/outrun2.iso"
xdvdfs checksum "/path/to/outrun2.iso"
xdvdfs copy-out "/path/to/outrun2.iso" "/default.xbe" "assets/default.xbe"
sha256sum "/path/to/outrun2.iso"
sha1sum "assets/default.xbe"
```

Use the exact internal path reported by `xdvdfs tree`. Do not treat the Xbox DVD as an ordinary
ISO filesystem, and do not edit the source image.

## 11. How to Use the ISO

1. Keep the supplied *OutRun 2* Original Xbox disc image unchanged.
2. Place it in the local, ignored `assets/` directory or keep it in a separate private asset
   directory.
3. Inspect it with XDVDFS-aware tools before extracting anything.
4. Export `default.xbe` and the required data directories.
5. Record hashes for the source image and XBE.
6. Build from the local XBE and local media.
7. Keep the ISO, extracted assets, generated code, saves, and logs out of Git.

The supplied image is:

`/run/media/deck/SN512/Roms/xbox/OutRun 2 (Europe) (En,Fr,De,Es,It).iso`

Its outer SHA-256 is
`3ebd704fd1eb49401d1ffe1a863582f9e902fdcc6524e87a375883c64afbfcc0`. The image remains on the
removable volume and is not copied into the repository.

## 12. First Ten Working Days

1. [x] Obtain the ISO path and record its identity.
2. [ ] Establish the Windows build host and pin the selected SDK commit.
3. [x] Inventory and hash the ISO.
4. [x] Extract `default.xbe` and record its identity.
5. [x] Run `xbe_symbols` and confirm XDK `5849` with 64 partitions.
6. [x] Export the flat PE and open it in Ghidra.
7. [ ] Complete the input-device and unmatched-symbol audits.
8. [ ] Create the reproducible project skeleton and first native build.
9. [ ] Resolve the first boot-time failures and establish crash/log evidence.
10. [ ] Reach the title screen and turn the menu traversal into a repeatable test.

## 13. Definition of Done for Version 1.0

Version 1.0 is complete when:

- A clean Windows checkout builds the native executable using only documented prerequisites.
- The user's supported disc is identified and verified locally.
- The title screen, menus, all five courses, audio, saves, and supported input work.
- Race simulation preserves the cadence measured from the original release.
- Repeated restart, save, and course-transition tests pass.
- Two-player System Link passes.
- No game assets, keys, or generated game code are tracked or distributed.
- Known limitations and supported regional revisions are documented accurately.

## 14. Primary References

- [XboxXBERecomp SDK documentation](https://github.com/TGP482/XboxXBERecomp)
- [hk21x XboxXBERecomp fork](https://github.com/hk21x/XboxXBERecomp)
- [PGR2 recomp reference project](https://github.com/hk21x/pgr2-recomp)
- [xdvdfs inspection and extraction tool](https://github.com/antangelo/xdvdfs)
- [XboxDev Ghidra XBE loader](https://github.com/XboxDev/ghidra-xbe)
- [Disc dumping guide](https://wiki.redump.info/Microsoft_Xbox_and_Xbox_360_Dumping_Guide)
- [Xbox game disc format reference](https://xboxdevwiki.net/Xbox_Game_Disc)
