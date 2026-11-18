#!/usr/bin/env bash
# Preflight the container entry points without building anything.
#
# Both scripts validate their inputs before honouring DRY_RUN; cross-build.sh requires
# assets/default.xbe to exist, so a zero-byte placeholder is created when the checkout has no
# user media. It is never read by the dry run, never uploaded, and removed on exit.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

if [ ! -f sdk/cmake/XbeRecomp.cmake ]; then
    echo "preflight: sdk/ is not initialized; run 'git submodule update --init sdk'" >&2
    exit 1
fi

placeholder=0
if [ ! -f assets/default.xbe ]; then
    mkdir -p assets
    : > assets/default.xbe
    placeholder=1
    echo "preflight: created a zero-byte assets/default.xbe placeholder for the dry runs (removed on exit)"
fi
trap 'if [ "$placeholder" = 1 ]; then rm -f assets/default.xbe; fi' EXIT

echo "preflight: DRY_RUN=1 scripts/cross-build.sh"
DRY_RUN=1 scripts/cross-build.sh

echo "preflight: DRY_RUN=1 scripts/container.sh harness 5"
DRY_RUN=1 scripts/container.sh harness 5

echo "preflight: passed (both dry runs exited 0; no container was started)"
