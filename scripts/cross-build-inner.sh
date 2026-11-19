#!/usr/bin/env bash
# Container-side half of the Linux -> Windows cross-build. Run by scripts/cross-build.sh;
# it can also be run directly inside the cross image or on a host that has Clang >= 19,
# LLD, CMake, Ninja and an xwin sysroot.
#
#   JOBS=3                ninja parallelism (default: 3; each recompiled partition is large)
#   XWIN_HOME=path        where xwin and its sysroot live (default: .local/xwin)
#   XWIN_DIR=path         an existing xwin --use-winsysroot-style sysroot to use as-is
#   CROSS_BUILD_DIR=path  build directory (default: out/build/cross-windows)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

. scripts/game.env

die() { echo "cross-build: $*" >&2; exit 1; }

JOBS=${JOBS:-3}
XWIN_HOME=${XWIN_HOME:-$ROOT/.local/xwin}
XWIN_DIR=${XWIN_DIR:-$XWIN_HOME/sysroot}
BUILD_DIR=${CROSS_BUILD_DIR:-out/build/cross-windows}

# --- inputs ---------------------------------------------------------------------
[ -f sdk/cmake/XbeRecomp.cmake ] ||
    die "sdk/ is missing: run 'git submodule update --init sdk'"
[ -f "assets/$GAME_XBE" ] ||
    die "assets/$GAME_XBE is missing: extract your own legally acquired disc there first"
[ -d generated/game ] ||
    die "generated/game is missing: run 'scripts/container.sh bootstrap' first (it builds the native Linux xbe_recomp and recompiles the XBE)"
for tool in clang-cl-20 lld-link-20 llvm-lib-20 llvm-rc-20 llvm-mt-20 cmake ninja sha256sum curl tar file; do
    command -v "$tool" >/dev/null 2>&1 || die "$tool is missing: use scripts/container/Dockerfile.cross"
done

# a build directory records the absolute source path: a host build and a container build cannot share it
if [ -f "$BUILD_DIR/CMakeCache.txt" ]; then
    configured=$(sed -n 's/^CMAKE_HOME_DIRECTORY:INTERNAL=//p' "$BUILD_DIR/CMakeCache.txt" | head -1)
    [ "$configured" = "$ROOT/cross" ] ||
        die "$BUILD_DIR was configured for '$configured'; remove it to build here"
fi

# --- Windows SDK/UCRT through xwin ----------------------------------------------
# Microsoft's SDK license is accepted here, as in tijayfly/gt64_recomp/docs/WINDOWS_CROSS.md.
XWIN_VERSION=0.10.0
XWIN_SHA256=d870eb4b2f390878af6da1ccd3cf321d22fcb72720984853b4be732ae597fc88
XWIN_TGZ=xwin-${XWIN_VERSION}-x86_64-unknown-linux-musl.tar.gz
if [ ! -x "$XWIN_HOME/bin/xwin" ]; then
    echo "cross-build: fetching xwin $XWIN_VERSION into $XWIN_HOME/bin"
    mkdir -p "$XWIN_HOME/bin"
    tmp=$(mktemp -d)
    curl -fsSL -o "$tmp/$XWIN_TGZ" \
        "https://github.com/Jake-Shadle/xwin/releases/download/${XWIN_VERSION}/${XWIN_TGZ}"
    echo "$XWIN_SHA256  $tmp/$XWIN_TGZ" | sha256sum -c -
    tar xzf "$tmp/$XWIN_TGZ" -C "$tmp"
    mv "$tmp/xwin-${XWIN_VERSION}-x86_64-unknown-linux-musl/xwin" "$XWIN_HOME/bin/xwin"
    chmod +x "$XWIN_HOME/bin/xwin"
    rm -rf "$tmp"
fi
if [ ! -d "$XWIN_DIR/VC/Tools/MSVC" ] || [ ! -d "$XWIN_DIR/Windows Kits/10/Lib" ]; then
    echo "cross-build: splatting the Windows SDK/UCRT into $XWIN_DIR"
    "$XWIN_HOME/bin/xwin" --accept-license --arch x86_64 \
        --cache-dir "$XWIN_HOME/cache" \
        splat --use-winsysroot-style --preserve-ms-arch-notation \
        --output "$XWIN_DIR"
fi

# --- configure and build ---------------------------------------------------------
mkdir -p logs
echo "cross-build: configure (Release, x86_64-pc-windows-msvc, lld-link)"
cmake -S cross -B "$BUILD_DIR" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE="$ROOT/cross/windows-cross.cmake" \
    -DXWIN_DIR="$XWIN_DIR" \
    2>&1 | tee logs/cross-configure.log

echo "cross-build: build (${JOBS} jobs, ${GAME_PARTITIONS:-64} partitions)"
cmake --build "$BUILD_DIR" --parallel "$JOBS" 2>&1 | tee logs/cross-build.log

# --- report ----------------------------------------------------------------------
EXE=$BUILD_DIR/Game.exe
[ -f "$EXE" ] || die "the build finished without $EXE"
echo
echo "cross-build: $EXE"
ls -l "$EXE"
file "$EXE"
sha256sum "$EXE" | tee logs/cross-sha256.txt

# the release model ships the compiler folder beside the executable (app/game_code.cpp builds
# the game's DLL from it on the player's first start)
COMPILER=$BUILD_DIR/compiler
[ -d "$COMPILER" ] || die "the build finished without the compiler folder $COMPILER"
echo
echo "cross-build: $COMPILER"
ls -l "$COMPILER" "$COMPILER/config" "$COMPILER/include" "$COMPILER/xdk"
echo "cross-build: compiler folder $(du -sh "$COMPILER" | cut -f1), $(find "$COMPILER" -type f | wc -l) files"
