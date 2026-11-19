# Windows x64 cross-build (Linux → Windows)

Builds the SDK's `Game` target for Windows on a Linux host: Clang 20 targeting
`x86_64-pc-windows-msvc`, LLD, and an [xwin](https://github.com/Jake-Shadle/xwin)
Windows SDK/UCRT sysroot.

## Release model: the game's code is built on the player's PC

The artifact is `Game.exe` **plus a `compiler/` folder beside it** — the SDK's release
model (`XBE_GAME_DLL`, `sdk/cmake/XbeRecomp.cmake` at the pinned commit):

- `Game.exe` carries the SDK runtime, this game's `src/` overrides and the XBE SHA-1. It
  contains **no** recompiled game code.
- On the player's first start, `sdk/runtime/app/game_code.cpp` recompiles the player's own
  `default.xbe` into `Game.dll` next to the executable behind a progress window, using
  `compiler/xbe_recomp.exe`, `compiler/clang.exe`, `compiler/lld-link.exe`, the game's
  configs, the XDK layouts and the headers the generated code includes. Finished objects are
  kept, so an interrupted first start carries on next time. Nothing is compiled while the
  game is running (`IMPLEMENTATION_PLAN.md` §1, §2).

```bash
scripts/container.sh bootstrap        # once: native xbe_recomp + generated/game (Linux lane)
scripts/cross-build.sh                # cross-configure + build
out/build/cross-windows/Game.exe      # and out/build/cross-windows/compiler/ beside it
```

After a change to `config/outrun2.toml` (which includes `config/game.toml`), regenerate the
64 partitions — and the `imports.def` the executable's DLL import library is made from — and
rebuild in one step:

```bash
RECOMPILE=1 scripts/cross-build.sh
```

`DRY_RUN=1 scripts/cross-build.sh` prints the container invocation; `REBUILD=1`
rebuilds the image after a Dockerfile change; `JOBS=n` sets ninja parallelism
(default 3).

## Files

| Path | Role |
| --- | --- |
| `cross/CMakeLists.txt` | The cross project: runtime + `src/` → `Game.exe`, and the `compiler/` folder the release ships. Same sources, flags and link libraries as the root project's `add_xbe_image_dll()`. |
| `cross/fetch-llvm-windows.sh` | Fetches the pinned official LLVM for Windows and extracts `clang.exe` + `lld-link.exe` (the two tools the release's `compiler/` folder carries) into `.local/llvm-windows/bin`. |
| `cross/windows-cross.cmake` | Toolchain file: clang-cl/lld-link/llvm-lib/llvm-rc/llvm-mt, `--target` triple, `/winsysroot`, sysroot-bound `find_*`. |
| `scripts/cross-build.sh` | Host wrapper: picks docker/podman, builds the image, fetches the Windows LLVM, runs the inner script. |
| `scripts/cross-build-inner.sh` | Container side: fetches/splats xwin, configures and builds, prints `file`, SHA-256 and the compiler folder. |
| `scripts/container/Dockerfile.cross` | Ubuntu 24.04 + LLVM 20 from apt.llvm.org (Ubuntu's LLVM 18 is too old for the MSVC STL). |

## Why a separate CMake project

The root `CMakeLists.txt` includes `sdk/cmake/XbeRecomp.cmake`, whose
`add_xbe_image()` does two things that only work natively:

1. it builds `xbe_recomp` and `xbe_symbols` for the **target** platform, and
2. it runs `xbe_recomp` as a build step to regenerate `generated/game`.

In a cross-build those tools are Windows PEs and cannot run on the Linux host; the
pinned SDK commit (`b908ae7`) has no host-tools preset. So `cross/`:

- fetches the SDK's dependencies at the same tags (zydis `v4.1.1`, toml++ `v3.4.0`,
  imgui `v1.91.0`, SDL3 `release-3.4.16`, static), builds `xbe_recomp` as a Windows PE
  (`compiler/xbe_recomp.exe`, which the player's first start runs), and skips
  `xbe_symbols` (a build-host tool, not part of a release),
- compiles the `generated/game` that the **native Linux** `xbe_recomp` already wrote, and
- makes the game code DLL's import library from the `generated/game/imports.def` that run
  writes, so `Game.exe` can delay-load `Game.dll` before it exists.

Everything else mirrors `add_xbe_image_dll()`: runtime glob, `src/common` + `src/game`,
include paths, `XBE_GAME_DLL`, `UNICODE/_UNICODE/_CRT_SECURE_NO_WARNINGS`, the compiler
folder's contents (`xbe_recomp.exe`, `clang.exe`, `lld-link.exe`, `LLVM-LICENSE.txt`, the
game's configs, `xdk/<build>/layout.toml`, `include/cpu` and `include/freestanding`), the
import libraries (`d3d12 d3d11 dinput8 dxgi dxguid d3dcompiler xaudio2 ole32 windowscodecs
dbghelp winmm dwmapi ws2_32`), `-fno-strict-aliasing`, `-fuse-ld=lld` and
`/delayload:Game.dll` (`-fuse-ld` for lld, `-Xlinker` because clang-cl does not forward
`-Wl,`). The XBE SHA-1 baked into the executable comes from the same `assets/default.xbe`
the Linux lane uses.

`config/outrun2.toml` sets `[xbe] library = "Game"` at the top level: that is what makes
`xbe_recomp` write `exports.def`/`imports.def`, and it is the config `game_code.cpp` finds
when it looks for the one naming the DLL.

The SDK submodule stays untouched, and no SDK file is forked.

## Licensing and ignored files

xwin downloads Microsoft's Windows SDK/UCRT after `--accept-license`; it lives in
`.local/xwin/` (tool, cache and sysroot) and is git-ignored, as is the LLVM for Windows
(`.local/llvm-windows/`, Apache 2.0 with LLVM exceptions; its licence ships in the compiler
folder) and `out/build/cross-windows/`. No game media, generated C++, or PE is tracked.

## Runtime

`Game.exe` imports the dynamic MSVC runtime (`MSVCP140.dll`, `VCRUNTIME140.dll`,
`VCRUNTIME140_1.dll`), so a Wine/Proton prefix needs the VC++ 2015-2022 x64 runtime.
It also needs the game data beside it, exactly like the `build.bat` output, and on the
first start about 1 GB of free space and a few minutes for the compile.
