#!/usr/bin/env bash
# Cross-build the Windows x64 Game.exe on Linux, in a container.
#
#   scripts/cross-build.sh              configure and build out/build/cross-windows/Game.exe
#   RECOMPILE=1 scripts/cross-build.sh  regenerate generated/game from config/outrun2.toml first
#   DRY_RUN=1 scripts/cross-build.sh    print the container command instead
#
# The recompiled sources must exist first (the native Linux lane produces them):
#   scripts/container.sh bootstrap      tools, symbols, recompile, then the harness
# or, if the tools are already built:
#   scripts/container.sh recompile
#
# Environment:
#   CONTAINER_ENGINE=docker|podman   default: docker, else podman
#   CROSS_IMAGE=name:tag             default: outrun2-xbe-cross:24.04
#   REBUILD=1                        rebuild the image (after Dockerfile.cross changes)
#   RECOMPILE=1                      regenerate generated/game with the native Linux xbe_recomp
#                                    from the combined config/outrun2.toml before building
#   JOBS=n                           ninja parallelism, default 3
#   XWIN_HOME=path                   default: .local/xwin (tool, cache and sysroot, all ignored)
#   CROSS_BUILD_DIR=path             default: out/build/cross-windows
#   DRY_RUN=1                        print the engine invocation, build nothing
#
# xwin downloads Microsoft's Windows SDK and UCRT from Microsoft on the first run and
# accepts Microsoft's license (--accept-license). Nothing from it is committed; see
# cross/README.md. The PE needs the VC++ 2015-2022 x64 runtime under Wine/Proton.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

. scripts/game.env

die() { echo "cross-build: $*" >&2; exit 1; }

ENGINE=${CONTAINER_ENGINE:-}
if [ -z "$ENGINE" ]; then
    if command -v docker >/dev/null 2>&1; then
        ENGINE=docker
    elif command -v podman >/dev/null 2>&1; then
        ENGINE=podman
    else
        die "install docker or podman, or set CONTAINER_ENGINE"
    fi
fi
IMAGE=${CROSS_IMAGE:-outrun2-xbe-cross:24.04}

# a "docker" command may be a podman shim (common on immutable distros); its user mapping differs
ENGINE_KIND=docker
if grep -qi podman <<< "$("$ENGINE" --version 2>&1 || true)"; then
    ENGINE_KIND=podman
fi

[ -f sdk/cmake/XbeRecomp.cmake ] || die "sdk/ is missing: run 'git submodule update --init sdk'"
[ -f "assets/$GAME_XBE" ] || die "assets/$GAME_XBE is missing: extract your own legally acquired disc there first"

# config/outrun2.toml (which includes config/game.toml) is the recompiler input, so a
# config change needs generated/game regenerated before the cross-build compiles it
if [ "${RECOMPILE:-0}" = 1 ]; then
    echo "cross-build: regenerating generated/game from config/outrun2.toml (native Linux lane)"
    "$ROOT/scripts/container.sh" recompile
fi

[ -d generated/game ] ||
    die "generated/game is missing: run 'scripts/container.sh bootstrap' first (the cross-build compiles the native Linux recompiler's output)"

if [ "${DRY_RUN:-0}" != 1 ]; then
    $ENGINE info >/dev/null 2>&1 ||
        die "$ENGINE is not usable by this user (add yourself to its group; see the README)"
    if [ "${REBUILD:-0}" = 1 ] || ! $ENGINE image inspect "$IMAGE" >/dev/null 2>&1; then
        echo "cross-build: building $IMAGE (first run, a few minutes)"
        $ENGINE build -f "$ROOT/scripts/container/Dockerfile.cross" -t "$IMAGE" "$ROOT/scripts/container"
    fi
fi

USER_ARGS=(--user "$(id -u):$(id -g)")
# rootless Podman maps container root to the host user; keep-id makes the mount writable by the process
if [ "$ENGINE_KIND" = podman ] && [ "$(id -u)" -ne 0 ]; then
    USER_ARGS=(--userns=keep-id)
fi
ENV_ARGS=(-e HOME=/tmp)
for name in JOBS XWIN_HOME CROSS_BUILD_DIR; do
    if [ -n "${!name-}" ]; then
        ENV_ARGS+=(-e "$name=${!name}")
    fi
done

if [ "${DRY_RUN:-0}" = 1 ]; then
    printf '%q ' "$ENGINE" run --rm "${USER_ARGS[@]}" "${ENV_ARGS[@]}" \
        -v "$ROOT:/work" -w /work "$IMAGE" bash -lc "scripts/cross-build-inner.sh"
    printf '\n'
    exit 0
fi

$ENGINE run --rm "${USER_ARGS[@]}" "${ENV_ARGS[@]}" \
    -v "$ROOT:/work" -w /work "$IMAGE" bash -lc "scripts/cross-build-inner.sh"
