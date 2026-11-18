# OUTRUN MODE: divide-error trap at guest 0x00195D6B

Status: fixed in `config/outrun2.toml` + `src/game/hooks.cpp` (guest-side instruction hook); verified in the
headless harness, where OUTRUN MODE now reaches the race start.

## Symptom

Choosing OUTRUN MODE from the main menu aborted the game before the race started. The runtime logged a guest
trap and then the deliberate abort path (`x86_trap` -> `abort`):

```
error: guest trap at 00195D6B: divide error
error:   eax 000007FF ecx 00000046 edx 00000000 ebx 00000000 esp D005FDC8 ebp D005FDE8 esi 001A4150 edi 00000002
error:   [esp+010] 001A4D24
error:   [esp+018] 001A4150
error:   [esp+01C] 001A50E4
error:   [esp+024] 0002AE3B
```

The same registers and return addresses reproduce in the headless harness (see Reproduction).

## Guest addresses

| Address | Meaning |
| --- | --- |
| `0x00195CF0` | `D3DDevice_DrawIndexedVerticesUP` (XDK library routine the SDK does not name or HLE) |
| `0x00195D6B` | `DIV dword ptr [ESI+0xBC8]` - the trapping instruction |
| `0x001A4150` | the static `CDevice` (`DAT_001a4148` points at it), ESI at the trap |
| `0x001A4D18` | `CDevice+0xBC8`, cached total vertex size in dwords - **the zero divisor** |
| `0x001A4D1C` | `CDevice+0xBCC`, first vertex input's byte offset |
| `0x001A4D20` | `CDevice+0xBD0`, first offset minus the end offset |
| `0x001A4D24` | `CDevice+0xBD4`, per-input size/gap pairs in dwords (read at the trap's `[esp+010]`) |
| `0x001A4DA4` | `CDevice+0xC54`, number of cached inputs |
| `0x0002AB40` | title draw that reaches the trap: `FUN_00195CF0(6, 0x46, indices, base, 0x28)` at `0x0002AE36` |
| `0x00196200` | builds the FVF declaration object at `0x001A67C8` for an FVF code (`SetVertexShader`) |
| `0x0019E9E0` | copies the bound shader's declaration into the `CDevice` cache (the only writer of `0x001A4D18`) |

`FUN_00195CF0` batches a user-pointer indexed draw: it computes `0x7FF / [CDevice+0xBC8]` vertices per push
buffer (2047 dwords is the push buffer limit), then copies each vertex using the cached size/gap pairs before
pushing it. `0x7FF` is the dword budget, not a projection value.

## Root cause: the SDK HLE replaces the writers of the cache

A Ghidra scan of every instruction whose operands mention `0xBC8` or `0x1A4D18` finds exactly five:

```
00195c08  DIV dword ptr [EDI + 0xbc8]      D3DDevice_DrawVerticesUP@00195b80
00195c1a  MOV ESI,dword ptr [EDI + 0xbc8]  D3DDevice_DrawVerticesUP@00195b80
00195d6b  DIV dword ptr [ESI + 0xbc8]      FUN_00195cf0@00195cf0     <- the trap
00195d7d  MOV ESI,dword ptr [ESI + 0xbc8]  FUN_00195cf0@00195cf0
0019eaf6  MOV dword ptr [ESI + 0xbc8],EAX  FUN_0019e9e0@0019e9e0     <- the only writer
```

`0x0019EAF6` is inside `FUN_0019E9E0`, in the block guarded by the D3D dirty flag `0x20`:

* `D3DDevice_SetVertexShader` (`0x00196DF0`) would set `DAT_001a3ca8 |= 0x70` and, for an FVF code, call
  `FUN_00196200` to fill the FVF object at `0x001A67C8` (in the image that object is all zeros; the
  declaration is built at run time).
* `D3DDevice_SetStreamSource` (`0x001969D0`) would set `DAT_001a3ca8 |= 0x70` as well.
* The next draw calls `FUN_0019E9E0`; with `0x20` set it walks the bound shader's declaration, computes the
  sizes and gaps, and writes the cache.

Both setters are `HLE_STDCALL` overrides in `sdk/runtime/xdk/d3d8.cpp` (`D3DDevice_SetVertexShader` and
`D3DDevice_SetStreamSource`), so their guest bodies - and therefore `FUN_00196200` - never run. The draws'
`FUN_0019E9E0` still runs, but it only rebuilds the cache when dirty bit `0x20` is set, and nothing else
sets it in this title's paths: the cached value is still 0 at the trap (the same was true for the earlier
Proton run). `D3DDevice_DrawVerticesUP` (`0x00195B80`) is HLE'd too and does not need the cache, but
`D3DDevice_DrawIndexedVerticesUP` (`0x00195CF0`) is not named by the SDK's export list, so the title's
direct call at `0x0002AE36` still runs guest code and divides by the stale zero.

The OUTRUN MODE banner is the first such draw with at least `0x11` indices (`CMP ECX,0x10` selects the divide
path; this call has `0x46`):

```
0002AB40  FUN_00195CF0(6, 0x46, param_2, param_1, 0x28)   // prim, indices, base, stride 0x28
```

### What the value should be

For FVF `0x1D2` (the shader set at `0x0002ADDC` in the same function) `FUN_00196200` builds a contiguous
declaration: `XYZ` at 0, `NORMAL` at 0xC, `DIFFUSE` at 0x18, `SPECULAR` at 0x1C, one texture coordinate at
0x20, with formats `0x32, 0x32, 0x40, 0x40, 0x22`. `FUN_0019E9E0`'s format tables (`0x001A1E0C`,
`0x001A1E14`) turn those into `3+3+1+1+2 = 10` dwords = `0x28` bytes, exactly the stride passed to the draw.
So the divisor must be **10**, not a projection-derived scale. The `d3d: projection far w 3201.86` line just
before the trap is `SetTransform` logging from the mode's setup and is unrelated (2047/3201.86 is a
coincidence; the cached value is a vertex size, not a projection scale).

## Fix

A [[hook]] runs at `0x00195D09`, immediately after `FUN_00195CF0`'s call to `FUN_0019E9E0` and before the
cache is read, and describes the draw as the single interleaved user-pointer stream it is:

* `config/outrun2.toml`: `[[hook]] at = 0x00195D09, call = "FixIndexedVerticesUpLayout"`.
* `src/game/hooks.cpp`: reads the fifth argument (stride, `[ebp+0x18]`) and writes
  `0x001A4D18 = stride/4`, `0x001A4D1C = 0`, `0x001A4D20 = -stride`, `0x001A4D24 = stride/4`,
  `0x001A4D28 = 0`, `0x001A4DA4 = 1`. It logs once:
  `hooks: 00195CF0 vertex layout 10 dwords (stride 40), cached at 001A4D18`.

The hook only changes the cached layout (which the HLE no longer maintains); the guest draw code, the HLE
state and the pushed vertex data are untouched. Other modes use the same helper through the same call site,
so they get the same per-draw stride.

## Reproduction (headless)

```
sdk/harness/build.sh -r . -g generated/game -o .local/harness -n game      # in scripts/container's image
mkdir run && cp -a .local/playtest/OutRun2-Offline/hdd run/                # a profile, as the reporter had
cd run && SCRIPT=<repo>/scripts/pad/none.txt .local/harness/game <game folder with default.xbe + media/*.cvm>
```

The pad script cannot drive the menus because a static screen stops presenting and its vblank clock stops
with it; write `cmd` files into the run folder instead (`buttons [vblanks held]`), cycling
`START`/`A`/`DOWN` every few seconds. The harness sometimes stalls on the intro in this environment
(all guest threads idle, no presents; also seen before this fix, with the pre-fix binary). Several
attempts were needed for every successful run: the 4th before the fix (the trap log), and the 6th and
3rd after it (the log and the frame captures below).

Before the fix (`/tmp/opencode/outrun2-mode-test/c4-trap.log`, 44.940 s):

```
[   44.938] d3d: projection far w 3201.86
[   44.939] d3d: MultiSampleMode 2 with target 83AB5C40 (128x128, data 03A30100), not a frame buffer: drawn 1x1 to a pixel
[   44.940] error: guest trap at 00195D6B: divide error
[   44.940] error:   eax 000007FF ecx 00000046 edx 00000000 ebx 00000000 esp D005FDC8 ebp D005FDE8 esi 001A4150 edi 00000002
[   44.940] error:   [esp+010] 001A4D24
[   44.940] error:   [esp+024] 0002AE3B
```

The abort stack (maintainer's systemd-coredump) is `raise -> abort -> x86_trap -> sub_00195CF0 ->
sub_0002AB40 -> sub_0002AED0 -> sub_00092C70 -> sub_00049890 -> sub_0004A0D0 -> sub_00097930 ->
sub_000557C0 -> sub_000558C0 -> sub_000F3359 -> sub_000F309B`.

## Validation

Cross-build (new Game.exe):

```
$ RECOMPILE=1 scripts/cross-build.sh ; echo $?
0
out/build/cross-windows/Game.exe: PE32+ executable (GUI) x86-64, for MS Windows, 7 sections
e2e82879c09b16f8ce7c2debe20c2b6816a01d7fc78815269dea2bc224e21561  out/build/cross-windows/Game.exe
12840960 bytes
```

`generated/game` was regenerated from the config and the hook was emitted at the intended instruction:

```
// 00195D04 call 0x0019E9E0
X86_PUSH32(0x195D09u); sub_0019E9E0(ctx, base);
X86_SAVE_FLAGS();
FixIndexedVerticesUpLayout(ctx, base); ...
// 00195D09 mov eax, [esi]
```

After the fix, the same reproduction (`/tmp/opencode/outrun2-mode-test/fixed-run.log`) reaches the exact
point the trap used to be at, runs the hook, and continues - no trap, 5700 frames over 109 s:

```
[   41.598] d3d: projection far w 3201.86
[   41.598] d3d: MultiSampleMode 2 with target 83AB5C40 (128x128, data 03A30100), not a frame buffer: drawn 1x1 to a pixel
[   41.599] hooks: 00195CF0 vertex layout 10 dwords (stride 40), cached at 001A4D18
[   41.899] renderer: frame 2220, 144621 draws, 62 empty frames, vblank 2219
...
[  109.446] renderer: frame 5700, 3593533 draws, 62 empty frames, vblank 5699
```

Second after-fix run with frame captures (`/tmp/opencode/outrun2-mode-test/snap3/`, same trap point at
41.573 s): `snap_1.png` shows the in-race menu over a race with the `Total Time / Time / Score` HUD;
`snap_2.png` shows the race start line with the countdown (`Total Time 0'11"993`, `Time 71`, 0 mph) and the
player car. OUTRUN MODE starts.

## Still unproven / next steps

* The fixed `Game.exe` was not re-played under GE-Proton on the Deck from this lane: a scratch Proton run
  was set up, but its window rendered black and stopped presenting in this session (host was at 12 GiB RAM,
  swap full), so it produced no usable evidence. The headless proof above uses the same recompiled code and
  runtime; re-test OUTRUN MODE with the new `Game.exe` on the reporter's Proton setup.
* Other modes and the non-UP draws were not separately exercised; they use the same helper and the HLE
  state is unchanged. The hook only describes the layout of the call it is placed in, using that call's own
  stride.
