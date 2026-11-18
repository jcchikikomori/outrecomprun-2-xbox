# Windows x64 cross-build (Linux → Windows)

Builds the SDK's `Game` target for Windows on a Linux host: Clang 20 targeting
`x86_64-pc-windows-msvc`, LLD, and an [xwin](https://github.com/Jake-Shadle/xwin)
Windows SDK/UCRT sysroot. Developer model only — `XBE_GAME_DLL` is never defined, so
all 64 recompiled partitions link into `Game.exe`.

```bash
scripts/container.sh bootstrap        # once: native xbe_recomp + generated/game (Linux lane)
scripts/cross-build.sh                # cross-configure + build
out/build/cross-windows/Game.exe
```

After a change to `config/outrun2.toml` (which includes `config/game.toml`), regenerate the
64 partitions and rebuild in one step:

```bash
RECOMPILE=1 scripts/cross-build.sh
```

`DRY_RUN=1 scripts/cross-build.sh` prints the container invocation; `REBUILD=1`
rebuilds the image after a Dockerfile change; `JOBS=n` sets ninja parallelism
(default 3).

## Files

| Path | Role |
| --- | --- |
| `cross/CMakeLists.txt` | The cross project: runtime + `src/` + `generated/game` → `Game.exe`. Same sources, flags and link libraries as the root project's `add_xbe_image()`. |
| `cross/windows-cross.cmake` | Toolchain file: clang-cl/lld-link/llvm-lib/llvm-rc/llvm-mt, `--target` triple, `/winsysroot`, sysroot-bound `find_*`. |
| `scripts/cross-build.sh` | Host wrapper: picks docker/podman, builds the image, runs the inner script. |
| `scripts/cross-build-inner.sh` | Container side: fetches/splats xwin, configures and builds, prints `file` and SHA-256. |
| `scripts/container/Dockerfile.cross` | Ubuntu 24.04 + LLVM 20 from apt.llvm.org (Ubuntu's LLVM 18 is too old for the MSVC STL). |

## Why a separate CMake project

The root `CMakeLists.txt` includes `sdk/cmake/XbeRecomp.cmake`, whose
`add_xbe_image()` does two things that only work natively:

1. it builds `xbe_recomp` and `xbe_symbols` for the **target** platform, and
2. it runs `xbe_recomp` as a build step to regenerate `generated/game`.

In a cross-build those tools are Windows PEs and cannot run on the Linux host; the
pinned SDK commit (`b908ae7`) has no host-tools preset. So `cross/`:

- fetches the SDK's dependencies at the same tags (toml++ `v3.4.0`, imgui `v1.91.0`,
  SDL3 `release-3.4.16`, static) without the host-tool targets, and
- compiles the `generated/game` that the **native Linux** `xbe_recomp` already wrote.

Everything else mirrors `add_xbe_image()`: runtime glob, `src/common` + `src/game`,
include paths, `UNICODE/_UNICODE/_CRT_SECURE_NO_WARNINGS`, the generated-source flags,
the import libraries (`d3d12 d3d11 dinput8 dxgi dxguid d3dcompiler xaudio2 ole32
windowscodecs dbghelp winmm dwmapi ws2_32`), `-fno-strict-aliasing` and
`-fuse-ld=lld`. The XBE SHA-1 baked into the executable comes from the same
`assets/default.xbe` the Linux lane uses.

The SDK submodule stays untouched, and no SDK file is forked.

## Licensing and ignored files

xwin downloads Microsoft's Windows SDK/UCRT after `--accept-license`; it lives in
`.local/xwin/` (tool, cache and sysroot) and is git-ignored, as is
`out/build/cross-windows/`. No game media, generated C++, or PE is tracked.

## Runtime

`Game.exe` imports the dynamic MSVC runtime (`MSVCP140.dll`, `VCRUNTIME140.dll`,
`VCRUNTIME140_1.dll`), so a Wine/Proton prefix needs the VC++ 2015-2022 x64 runtime.
It also needs the game data beside it, exactly like the `build.bat` output.
