# Phase 0 Media Inventory

- **Date:** 2026-11-18
- **Target:** European Original Xbox release of *OutRun 2*
- **Inspection tool:** `xdvdfs-cli 0.8.3`

## 1. Source Image

The source image remains unchanged on the removable volume:

```text
/run/media/deck/SN512/Roms/xbox/OutRun 2 (Europe) (En,Fr,De,Es,It).iso
```

| Property | Observed value |
| --- | --- |
| Size | 1,140,195,328 bytes |
| Modified time | 2026-07-23 14:47:38 +0800 |
| SHA-256 | `3ebd704fd1eb49401d1ffe1a863582f9e902fdcc6524e87a375883c64afbfcc0` |
| SHA-1 | `9470f2151a266f8f470c223e94dc8782ab847983` |
| XDVDFS content checksum | `03e263d7595ecfbb346f17d1f3770ce0bc60ffbce6cfd2cd98b7457ac39f8e25` |
| XDVDFS validity | Valid |

The content checksum is `xdvdfs checksum`'s condensed data checksum. It is not interchangeable with
the outer SHA-256 above.

## 2. XDVDFS Tree

```text
/media/                 0 bytes
/update.xbe             2,326,528 bytes
/default.xbe            3,137,536 bytes
/dashupdate.xbe        58,421,248 bytes
/media/data1.cvm      755,478,528 bytes
/media/data2.cvm      320,706,560 bytes
```

The image contains five files with a total listed size of 1,140,070,400 bytes.

## 3. Game Executable

`default.xbe` was exported to a private analysis directory without modifying the source image.

| Property | Observed value |
| --- | --- |
| Size | 3,137,536 bytes |
| SHA-256 | `3a931cd1866814c7aba5587db05f280c8178fa2ffeca91a34cdd6ba34024a84a` |
| SHA-1 | `852559543447f57f568fa470f64ebce441a0f658` |
| Identification | Microsoft Xbox executable `OutRun2`, serial `SE-054`, Rest of World, signed |
| Title ID | `53450036` |
| Entry point | `0xF33CD` |
| XDK build | `5849` |
| Partition count | `64` |

The XBE links the following libraries at version `1.0.5849`:

```text
XAPILIB D3D8 D3DX8 XGRAPHC DSOUND XBOXKRNL XVOICE VOICMAIL XONLINES LIBCMT LIBCPMT
```

`xbe_symbols` found 186 of 278 known functions and 12 of 13 known data objects. A zero address in
the generated configuration means that the library symbol was not identified; it does not by itself
prove that *OutRun 2* calls that function.

The 92 unmatched functions were cross-checked against the XBE's `.XTLID` export table. Of these,
43 have a signature with an expected export ID, but that ID is absent from this XBE. No symbol with
an export ID present in the XBE remained unresolved. The other 49 are optional API or CRT variants
without an export ID, including Bink, spatial-audio, fence, and alternate shader entry points.

Ghidra found callers of `D3DDevice_SetPixelShader`, but none of `D3DDevice_CreatePixelShader`; the
game selects predefined shader handles rather than dynamically creating pixel shaders. The remaining
unmatched CRT entries are therefore not a static blocker. Runtime trap logs remain the safety net
for any call that static matching cannot classify.

The identified code sections are:

```text
.text D3D D3DX XGRPH DSOUND WMADEC XNET XONLINE PSGSFD00 PSGSFD_I PSGSFD_B PSGSFD_P XPP
```

## 4. Other Executables

| File | Identification | SHA-256 | Classification |
| --- | --- | --- | --- |
| `update.xbe` | Online Updater Application, `SE-054` | `257dffe0112052a5aafb3c156c6fca1e66ca82eadadf9fdfc12bbb7d9b4a7853` | Xbox online updater, not a gameplay image by identification |
| `dashupdate.xbe` | Xbox Dashboard Updater, `SE-054` | `3cafbd8c43d2cf9d5d61a9132fe16f88f78c17a4688ef4e2ef2a66690dbf537d` | Dashboard updater, not a gameplay image by identification |

Both executables also match XDK `5849`. They should not receive gameplay `add_xbe_image` targets
unless an `XLaunchNewImage` reference proves that the game launches them.

## 5. Analysis Export

The SDK's `xbe2pe.py` produced the flat PE used for static analysis:

| Property | Observed value |
| --- | --- |
| Path in private analysis storage | `/tmp/opencode/outrun2-analysis/game.exe` |
| Size | 6,926,336 bytes |
| SHA-256 | `c4c78d03cfaff88d9e670eef2c77817463c0df42a46e0a05c2c4f74f01ce840c` |
| Format | PE32, Intel i386, two sections |

The flat PE and all extracted files are private analysis artifacts. They are not repository inputs.

## 6. Recompiler Feasibility

The `xbe_recomp` tool from the `hk21x` fork successfully processed the complete `default.xbe` in a
Linux container. This proves that the XBE is accepted by the current lifter and that the XDK 5849
analysis configuration is sufficient to generate a complete native-code unit set.

| Metric | Observed value |
| --- | ---: |
| Generated partitions | 64 |
| Generated code size | 96 MiB |
| Functions | 12,691 |
| Instructions | 721,662 |
| Jump tables | 359 |
| Callback entries | 15 |
| C++ catch blocks | 6 |
| C++ continuations | 2 |

The analyzer also reported overlapping decodes and a set of uncommon x86 instructions marked
unimplemented. Many such hits can come from data bytes explored by gap filling and are not proof
that an executable path uses them. The generated C++ must still compile, and the runtime logs must
show whether any reachable function reaches a trap.

The generated code is private analysis output. It is not committed or redistributed.

## 7. Headless Boot Validation

The generated code was compiled with Clang in the Ubuntu container and linked into the `hk21x`
Linux headless harness.

| Property | Observed value |
| --- | ---: |
| Harness size | 23,964,016 bytes |
| Generated object files | 65 |
| ELF architecture | x86-64 Linux |
| Harness SHA-256 | `0980e6b4080171fc221cdd933068534f90867d8a547b15cdd0237570d51c2809` |

Passing the ISO directly to the harness mounted it as the Xbox DVD and booted the real executable:

- Title `53450036` and entry `000F33CD` were recognized.
- All 12,691 recompiled functions were dispatched.
- The Xbox kernel initialized threads, the UDATA/TDATA filesystem, XAPI input, and XNet.
- Direct3D 8 created a 640×480 device and the headless renderer received 50–110 draws per frame.
- A ten-second run reached frame 240 with 231 draws.
- A sixty-second run reached frame 2,340 with 14,168 draws and no unimplemented-instruction trap.
- With `XBE_PERF=1`, frames 240–720 advanced at exactly one 60-frame interval per second. This confirms
  the startup/menu vblank cadence, but not yet the race simulation cadence.
- The CPU reference renderer captured the Sega AM2 “Created by” screen and the Sumo Digital startup
  screen.

The startup log reported one kernel import without an implementation, `XcPKGetKeyLen`. Its
import slot is `0x22925C`, and Ghidra found no code or data reference to that slot. The import is
therefore present but statically unused; the runtime would trap only if an indirect path reached it.

The startup log also reported optional missing metadata and `heart_startend.bin`. These were not
reached as fatal traps during the startup capture, but the later CPU reference-renderer stall remains
a diagnostic item.

The headless executable and captures remain private analysis artifacts. They are not repository
inputs.

## 8. Segment-Register and Push-Command Findings

Ghidra 12.1.4 identified **547 `FS:`-prefixed instructions in 200 containing function labels**. The
recurring guest SEH sequence is:

```text
mov eax, fs:[0]
mov dword ptr fs:[0], esp
...
mov dword ptr fs:[0], ecx
```

Both SDK candidates have explicit `fs:` support:

- `runtime/cpu/x86_context.h` defines the guest `fs_base`.
- `tools/recomp/codegen.cpp` adds `fs_base` when lifting `fs:` memory operands.
- `runtime/kernel/threads.cpp` initializes `fs_base` from the guest thread's KPCR.
- `runtime/kernel/xboxkrnl.cpp` walks and updates the guest SEH chain through `fs_base`.

Therefore, `fs:` support is no longer an unknown implementation gap. It remains a runtime
verification gate because the XBE uses the path extensively.

The generated configuration identifies both raw push APIs:

```text
D3DDevice_BeginPush = 0x198DF0
D3DDevice_EndPush   = 0x198E10
```

Ghidra confirmed seven direct call sites, containing nine complete push sequences across six
functions:

| Pair | `BeginPush` call | `EndPush` call | Containing function |
| --- | --- | --- | --- |
| 1 | `0x84CDF` | `0x84D52` | `FUN_00084B50` |
| 2 | `0x86F3B` | `0x87103` | `FUN_00086C30` |
| 3 | `0x9DB08` | `0x9DC7B` | `FUN_0009D8F0` |
| 4 | `0xD2361` | `0xD2433` | `FUN_000D1EE0` |
| 5 | `0xD43E1` | `0xD478A` | `FUN_000D4250` |
| 6 | `0xD4A2F` | `0xD4CCE` | `FUN_000D4820` |
| 7 | `0xD4D9D` | `0xD4F5A` | `FUN_000D4820` |

The decompiled sequences use only two NV2A command methods:

- `0x17FC`, the begin/end primitive marker.
- `0x1818`, an inline vertex array with a variable element count.

The fork explicitly handles both methods in `runtime/xdk/d3d8.cpp`: `kBeginEnd` and `kInlineArray`.
Canonical upstream also recognizes both methods. No `CreatePushBuffer`, `RunPushBuffer`, or
`D3DPushBuffer` reference was found in the analyzed image.

This resolves the static push-command coverage gate. Runtime rendering remains a later gate because
static method recognition cannot prove correct vertex layout or state ordering.

## 9. Media Container Inventory

The two CVM archives were extracted into private analysis storage and inventoried without copying
their contents into the repository.

| Container | SHA-256 | Listed entries | Extracted files |
| --- | --- | ---: | ---: |
| `data1.cvm` | `91dc00fab314d6863e5d4b78b3237db33ef4d8f6bc177bc49c4f993581af0069` | 428 | 427 |
| `data2.cvm` | `b1941652a634d292cb101bd964d1f1715092ac1616bc85cc04eca9cce2803e40` | 936 | 935 |

Across both containers, 1,362 files were extracted with a total size of 1,074,519,245 bytes. The
outer archives contain custom compressed `.gz` streams plus game-specific formats:

```text
.gz 1051  .tgt 93  .rec 79  .adx 54  .xwb 35
.bin 30    .sfd 15  .dat 2   .wav 1   .xpr 1  .rom 1
```

The 15 `.SFD` files are MPEG-1 video in an MPEG Program Stream. `ffprobe` identified the sample
`1_25_IMAGE_MOVIE.SFD` as MPEG-1 video, 352×240, with an average rate of 30/1.001 fps. The single
`SEGA48.WAV` file is mono 16-bit PCM at 48 kHz.

No Bink or `.xmv` media was found. The XBE contains a `WMADEC` code section, so the statically
linked Windows Media decoder will be recompiled as part of the guest image. Video playback still
requires runtime verification.

## 10. Controller and Force-Feedback Audit

Ghidra found one input-management function, `FUN_000A6C00`, that:

- Iterates over exactly four XInput ports.
- Calls `XInputGetState` with a 16-byte standard Xbox controller state.
- Reads standard left-stick, right-stick, and button fields.
- Calls `XInputSetState` with the standard motor/rumble fields.

The XBE contains no strings identifying wheels, pedals, force feedback, Logitech, Fanatec, or
Thrustmaster, and the input path contains no wheel device-type branch. No wheel-specific XID packet
construction was found.

The core game therefore does not appear to require native wheel force feedback for Version 1.0.
Standard controller rumble is required, and host-side wheel force feedback can remain an optional
enhancement if the game exposes only the standard analog axes.

## 11. SDK Comparison

| Revision | Commit | Date | `fs:`/SEH | Push handling | Headless harness |
| --- | --- | --- | --- | --- | --- |
| Canonical `TGP482/XboxXBERecomp` | `cc9edda3a821a4204dc28783f429b88a27ade4f9` | 2026-11-08 | Implemented | Basic raw commands and `RunPushBuffer` | Not present |
| `hk21x/XboxXBERecomp` fork | `b908ae7f05908ff335f94037c673e4b437c7c1d6` | 2026-11-15 | Implemented | Ordered recording, replay, and fixups | Present |

The `hk21x` fork is the selected baseline because this XBE uses raw push commands and the fork
provides the stronger implementation, required diagnostics, and the successful Windows/Proton build.

## 12. Tooling Evidence

The host lacks native development headers, so `xbe_symbols` and `xbe_recomp` were built in an
ephemeral Ubuntu 24.04 container using Docker/Podman. The container was removed after each build.
The resulting Linux tools successfully generated the symbol configuration and complete C++ unit set
used by this report.

The user-provided Ghidra installation is at:

```text
/home/deck/.local/opt/ghidra_12.1.4_PUBLIC/Ghidra/
```

Its current tree does not contain `support/analyzeHeadless`, so the headless audit used a complete
temporary Ghidra 12.1.4 distribution. REA provider configuration remains a separate local setup
task.

## 13. Windows Cross-Build and Proton Validation

The repository's Linux-to-Windows workflow successfully built a Windows x64 executable with Clang 20,
LLD, and an `xwin` Windows SDK 10.0.26100/UCRT sysroot.

| Property | Observed value |
| --- | --- |
| Artifact | `out/build/cross-windows/Game.exe` |
| Size | 12,840,960 bytes |
| SHA-256 | `b7df49740315c05b09df08e9340ba8c2538bec7468740a0a5d1b964d22fa6832` |
| Format | PE32+ GUI executable, x86-64, seven sections |
| Developer model | All 64 recompiled partitions linked directly; no first-start DLL build |

GE-Proton 11.11 and vkd3d-proton launched the executable on the Steam Deck. The real disc mounted
from `assets/OutRun2.iso`, Direct3D 12 selected the RADV device, and the game rendered the Sega
startup screen, the **OutRun 2 Profiles** screen, and a 3D tunnel scene.

The first playable run exposed a deterministic access violation at the former profile-scene
transition:

```text
exception C0000005
read 200000004, guest 00000004
guest thread 14
```

Ghidra traced the fault to guest function `0x196D00`, which dereferences
`CDevice_VertexShader` at device offset `0x794`. The guest's original device initialization at
`0x19A6D0` stores the default FVF shader object at `0x1A67C8` in that field. SDK 5849 has no
`D3D_FvfShader` data signature, so the host-side `Direct3D_CreateDevice` left the field null.

The title-specific configuration now supplies the missing data object:

```toml
[data]
D3D_FvfShader = 0x001A67C8
```

After regenerating all 64 partitions and rebuilding, two independent fixed-build runs lasted 203
and 186 seconds. They reached the profile/3D path, created 317 textures in the longer fresh-profile
run, and recorded no access violation or crash dump. The manual Steam Deck capture at 50 seconds
showed the in-game tunnel scene.

One separate run recorded a divide-error trap at `0x195D6B`. It did not reproduce in the later
186-second run or the manual playtest, so it remains a watch item rather than a confirmed blocker.

A local manual bundle is available under `.local/playtest/OutRun2-Offline/`. It contains the fixed
executable, the user's ISO, a prepared Proton prefix, and an offline launcher. It is git-ignored and
must not be published because it contains the user's game image.

## 14. Remaining Phase 0 Gates

- [x] Identify the functions containing the seven push call sites.
- [x] Enumerate the NV2A commands written by the nine push sequences.
- [x] Prove that the selected SDK statically recognizes those command methods.
- [x] Inventory the two CVM containers for video and audio formats.
- [x] Classify wheel and force-feedback packet handling.
- [x] Classify the unmatched `xbe_symbols` entries and identify the runtime trap safety net.
- [x] Generate the complete 64-partition C++ unit set with `xbe_recomp`.
- [x] Compile the generated code and link the Linux headless harness.
- [x] Boot the real disc image in the headless harness and capture the startup sequence.
- [x] Classify the missing `XcPKGetKeyLen` kernel import as statically unused.
- [x] Prove the Linux-to-Windows cross-build and launch it under Wine, Bottles, or Proton.
- [x] Supply the missing XDK 5849 `D3D_FvfShader` data object and verify the profile path.
- [ ] Measure the original update and presentation cadence from the running build.
- [ ] Exercise at least one guest `fs:[0]` SEH path in the runtime.

## 15. Deployment Decision

No native Windows PC is currently available. The active deployment decision is therefore:

1. Use the `hk21x` Linux headless harness for deterministic development and regression testing.
2. Cross-build the existing Direct3D 12, XAudio2, and DirectInput executable from Linux.
3. Run that executable on the Steam Deck through Wine, Bottles, or Proton.
4. Defer a native Linux Vulkan renderer, even though existing XboxXBERecomp ports demonstrate that a
   Vulkan backend is possible.

The validated cross-build uses Clang 20 with an `xwin`-provided Windows SDK and UCRT, LLD, and a
game-side CMake toolchain file. It uses the developer model so generated game code links directly into
the executable. Direct3D 12 runs through vkd3d-proton; the SDK's Direct3D 11/DXVK path remains the
fallback if a native `d3dcompiler_47` proves necessary on another machine.

The current host already exposes Vulkan 1.4.350 through RADV and includes GE-Proton 11,
CachyOS Proton 11, Proton Experimental, and other compatibility-tool installations.

This preserves the existing SDK patterns and avoids adding a second renderer before the core port
is stable. The prepared manual bundle and Proton prefix support offline single-player testing. A
native Windows x64 release build remains deferred until a Windows host is available.

## 16. Copyright Boundary

This report contains only file names, hashes, metadata, and analysis findings. It contains no game
media, extracted assets, keys, or generated lifted code. The source ISO, extracted XBE files, CVM
containers, flat PE, and generated configurations remain local and outside version control.
