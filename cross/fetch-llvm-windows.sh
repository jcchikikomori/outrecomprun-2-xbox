#!/usr/bin/env bash
# Fetch the Windows LLVM whose clang.exe and lld-link.exe the release's compiler folder ships.
#
# The release model builds the player's Game.dll on the player's own PC, so the two tools in
# out/build/cross-windows/compiler must be Windows PEs. A Linux cross-build host has only ELF
# clang/lld, so this script takes them from the official LLVM Windows release instead (pinned by
# version and SHA-256). cross/CMakeLists.txt picks them up through XBE_LLVM_WINDOWS_DIR.
#
#   cross/fetch-llvm-windows.sh          download and extract, or do nothing if already there
#   XBE_LLVM_WINDOWS_DIR=dir ...         install into dir (the folder holding clang.exe)
#
# Needs curl, sha256sum and 7-Zip (the official Windows release is an NSIS installer). The
# download and the extracted tools live in .local/llvm-windows/, which is git-ignored, like the
# Windows SDK .local/xwin/ holds (see cross/windows-cross.cmake).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DEST=${XBE_LLVM_WINDOWS_DIR:-$ROOT/.local/llvm-windows/bin}
CACHE=$ROOT/.local/llvm-windows

VERSION=20.1.8
ASSET=LLVM-${VERSION}-win64.exe
URL=https://github.com/llvm/llvm-project/releases/download/llvmorg-${VERSION}/${ASSET}
SHA256=3197846a2b19063687dd56e93e34cd941e3548d907f23a6131571321bdf9fe7b

die() { echo "fetch-llvm-windows: $*" >&2; exit 1; }

if [ -f "$DEST/clang.exe" ] && [ -f "$DEST/lld-link.exe" ]; then
    echo "fetch-llvm-windows: $DEST already has clang.exe and lld-link.exe"
    exit 0
fi

command -v curl >/dev/null 2>&1 || die "curl is missing"
command -v sha256sum >/dev/null 2>&1 || die "sha256sum is missing"
SEVEN=
for tool in 7z 7za 7zr; do
    if command -v "$tool" >/dev/null 2>&1; then SEVEN=$tool; break; fi
done
[ -n "$SEVEN" ] || die "7-Zip (7z) is missing: it extracts LLVM's Windows installer (p7zip-full on Debian/Ubuntu)"

mkdir -p "$CACHE" "$DEST"
archive=$CACHE/$ASSET
if [ ! -f "$archive" ]; then
    echo "fetch-llvm-windows: fetching LLVM $VERSION for Windows (about 370 MiB) into $CACHE"
    curl -fsSL --retry 3 -o "$archive.part" "$URL" || die "downloading $URL failed"
    mv "$archive.part" "$archive"
fi
echo "$SHA256  $archive" | sha256sum -c - >/dev/null ||
    die "$archive is not the pinned LLVM $VERSION Windows release: remove it and retry"

echo "fetch-llvm-windows: extracting bin/clang.exe and bin/lld-link.exe into $DEST"
stage=$CACHE/extract
rm -rf "$stage"
"$SEVEN" x -y -o"$stage" "$archive" bin/clang.exe bin/lld-link.exe >/dev/null ||
    die "extracting $archive failed"
for tool in clang.exe lld-link.exe; do
    [ -f "$stage/bin/$tool" ] || die "$archive has no bin/$tool"
    cp -f "$stage/bin/$tool" "$DEST/$tool"
done
rm -rf "$stage"
ls -l "$DEST/clang.exe" "$DEST/lld-link.exe"
