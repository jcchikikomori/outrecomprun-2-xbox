#!/usr/bin/env bash
# Run the SDK's Linux tools and headless harness in a container, so the host needs no development headers.
#
#   scripts/container.sh bootstrap [harness args]   tools, symbols (first run), recompile, then the harness
#   scripts/container.sh tools                      build xbe_symbols and xbe_recomp (sdk/scripts/linux-tools.sh)
#   scripts/container.sh symbols                    rewrite config/game.toml from assets/default.xbe
#   scripts/container.sh recompile                  regenerate generated/game
#   scripts/container.sh harness [harness args]     build and run the headless harness (assets, or an external GAME=)
#   scripts/container.sh cross-build [args]         the Windows Game.exe cross-build (scripts/cross-build.sh)
#   scripts/container.sh shell                      an interactive shell in the image
#
# Environment:
#   CONTAINER_ENGINE=docker|podman   default: docker, else podman
#   IMAGE=name:tag                   default: outrun2-xbe-tools:24.04
#   REBUILD=1                        rebuild the image
#   FORCE=1                          bootstrap: rescan config/game.toml even if it has [symbols]
#   GAME=path                        harness: another game folder or disc image; a path outside this repository
#                                    is bind-mounted read-only at the same absolute path inside the container
#   DRY_RUN=1                        print the container command and mounts instead of running it
#   REF, CAP, KEEP_HDD, FPS, ...     harness settings, passed through (see sdk/harness/README.md)
#
# The native Linux lane. The Windows-compatible executable is cross-built by scripts/cross-build.sh
# (scripts/container.sh cross-build), see cross/README.md; build.bat builds it on Windows.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

. scripts/game.env

die() { echo "container: $*" >&2; exit 1; }

ENGINE=${CONTAINER_ENGINE:-}
if [ -z "$ENGINE" ]; then
    # the runner's service PATH can miss where the engine is installed (linuxbrew, rootless, /usr/local)
    for dir in "$(dirname "$(command -v docker podman 2>/dev/null | head -1)" 2>/dev/null)" \
              "$HOME/.local/bin" "$HOME/linuxbrew/.linuxbrew/bin" /home/linuxbrew/.linuxbrew/bin \
              /usr/local/bin /usr/bin /snap/bin; do
        [ -n "$dir" ] && [ -x "$dir/docker" ] && { ENGINE="$dir/docker"; break; }
        [ -n "$dir" ] && [ -x "$dir/podman" ] && { ENGINE="$dir/podman"; break; }
    done
    if [ -z "$ENGINE" ]; then
        {
            echo "container: no docker or podman in PATH or the usual install locations; install one, or set CONTAINER_ENGINE to its absolute path"
            echo "container: PATH=$PATH" >&2
            echo "container: HOME=$HOME user=$(id -un) host=$(hostname)" >&2
        } >&2
        exit 1
    fi
fi
IMAGE=${IMAGE:-outrun2-xbe-tools:24.04}

# a "docker" command may be a podman shim (common on immutable distros); its user mapping differs
ENGINE_KIND=docker
engine_version=$("$ENGINE" --version 2>&1 || true)
if grep -qi podman <<< "$engine_version"; then
    ENGINE_KIND=podman
fi

# extra -v arguments for a game outside the repository (a removable disc image, another asset folder)
EXTRA_MOUNTS=()

# GAME for the harness is either relative to the repository (already under the /work mount) or an absolute path
# outside it: mount that path read-only at the same absolute path, so the GAME value means the same in the container.
add_game_mount() {
    local game=${GAME:-} path
    [ -n "$game" ] || return 0
    case "$game" in
        /*) path=$game ;;
        *) path=$ROOT/$game ;;
    esac
    path=$(realpath -m -- "$path")
    [ -e "$path" ] || die "GAME=$game does not exist ($path)"
    case "$path" in
        "$ROOT"|"$ROOT"/*)
            # the repository mount already covers it; an absolute host path becomes its /work path
            case "$game" in
                /*) GAME=/work${path#"$ROOT"} ;;
            esac
            return 0
            ;;
        /) die "GAME=/ is not a game folder" ;;
    esac
    case "$path" in
        *:*) die "GAME path contains ':' which container volume syntax cannot express: $path" ;;
    esac
    EXTRA_MOUNTS+=(-v "$path:$path:ro")
    GAME=$path
    export GAME
    echo "container: mounting $path read-only at the same path"
}

ensure_sdk() {
    [ -f sdk/cmake/XbeRecomp.cmake ] && return 0
    [ -e .git ] || die "sdk/ is missing and this is not a git checkout to fetch it from"
    echo "container: fetching the pinned SDK submodule"
    git submodule update --init sdk
}

ensure_image() {
    [ "${DRY_RUN:-0}" = 1 ] && return 0
    $ENGINE info >/dev/null 2>&1 ||
        die "$ENGINE is not usable by this user (add yourself to its group; see the README)"
    if [ "${REBUILD:-0}" != 1 ] && $ENGINE image inspect "$IMAGE" >/dev/null 2>&1; then
        return 0
    fi
    echo "container: building $IMAGE (first run, a few minutes)"
    $ENGINE build -t "$IMAGE" "$ROOT/scripts/container"
}

# build/linux records an absolute source path: a host build and a container build cannot share it.
ensure_own_build_dir() {
    local cache=build/linux/CMakeCache.txt src
    if [ -f "$cache" ]; then
        src=$(sed -n 's/^CMAKE_HOME_DIRECTORY:INTERNAL=//p' "$cache" | head -1)
        [ "$src" = "/work" ] ||
            die "build/linux was configured at '$src'; remove build/linux to build in the container"
    fi
}

ensure_game() {
    [ -f "assets/$GAME_XBE" ] ||
        die "assets/$GAME_XBE is missing: extract your own legally acquired disc there first"
}

ensure_exe() {
    [ -x build/linux/xbe_symbols ] ||
        die "build/linux/xbe_symbols is missing: run scripts/container.sh tools first"
}

quote_args() { printf '%q ' "$@"; }

run_cmd() {
    local -a envs=() tty=() user=()
    if [ "${1:-}" = "--tty" ]; then
        tty=(-it)
        shift
    fi
    # rootless Podman maps container root to the host user; keep-id makes the mount writable by the process
    if [ "$ENGINE_KIND" = podman ] && [ "$(id -u)" -ne 0 ]; then
        user=(--userns=keep-id)
    else
        user=(--user "$(id -u):$(id -g)")
    fi
    local name
    for name in GAME REF CAP FPS OUTPUT KEEP_HDD WAV AUDIT PROBES TRACE SNAP_FRAMES \
                XBE_PERF XBE_FRAMELOG JOBS RAW RT_THREAD GEN_OPT HOST_FLAGS SMOKE_SECS REF_DRAWLOG; do
        if [ -n "${!name-}" ]; then
            envs+=(-e "$name=${!name}")
        fi
    done
    if [ "${DRY_RUN:-0}" = 1 ]; then
        printf '%q ' "$ENGINE" run --rm "${tty[@]}" "${user[@]}" "${envs[@]}" \
            -v "$ROOT:/work" "${EXTRA_MOUNTS[@]}" -w /work -e HOME=/tmp \
            "$IMAGE" bash -lc "$1"
        printf '\n'
        return 0
    fi
    $ENGINE run --rm "${tty[@]}" "${user[@]}" "${envs[@]}" \
        -v "$ROOT:/work" "${EXTRA_MOUNTS[@]}" -w /work -e HOME=/tmp \
        "$IMAGE" bash -lc "$1"
}

cmd=${1:-}
if [ $# -gt 0 ]; then
    shift
fi

case "$cmd" in
    tools)
        ensure_sdk
        ensure_image
        ensure_own_build_dir
        run_cmd "scripts/linux-tools.sh"
        ;;
    symbols)
        ensure_sdk
        ensure_image
        ensure_game
        ensure_exe
        run_cmd "build/linux/xbe_symbols assets/$GAME_XBE sdk/xdk --library $GAME_TARGET.dll --out config/game.toml"
        ;;
    recompile)
        ensure_sdk
        ensure_image
        ensure_own_build_dir
        ensure_exe
        run_cmd "scripts/recompile.sh"
        ;;
    cross-build)
        # own container image (scripts/container/Dockerfile.cross) and scripts; see cross/README.md
        exec "$ROOT/scripts/cross-build.sh" "$@"
        ;;
    harness)
        ensure_sdk
        add_game_mount
        ensure_image
        if [ "${DRY_RUN:-0}" != 1 ] && [ ! -d generated/game ]; then
            die "generated/game is missing: run scripts/container.sh bootstrap first"
        fi
        run_cmd "scripts/harness.sh $(quote_args "$@")"
        ;;
    bootstrap)
        ensure_sdk
        ensure_game
        add_game_mount
        ensure_image
        ensure_own_build_dir
        steps="set -e; scripts/linux-tools.sh"
        if [ "${FORCE:-0}" = 1 ] || ! grep -q '^\[symbols\]' config/game.toml 2>/dev/null; then
            steps="$steps; build/linux/xbe_symbols assets/$GAME_XBE sdk/xdk --library $GAME_TARGET.dll --out config/game.toml"
        fi
        steps="$steps; scripts/recompile.sh; scripts/harness.sh $(quote_args "$@")"
        run_cmd "$steps"
        ;;
    shell)
        ensure_sdk
        ensure_image
        run_cmd --tty bash
        ;;
    ""|-h|--help|help)
        sed -n '2,22p' "$0"
        ;;
    *)
        die "unknown command '$cmd' (try scripts/container.sh help)"
        ;;
esac
