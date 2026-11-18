#!/usr/bin/env bash
# Preflight the container entry points without building anything.
#
# Both scripts validate their inputs before honouring DRY_RUN; cross-build.sh requires
# assets/default.xbe to exist, so a zero-byte placeholder is used when the checkout has no
# user media. It is never read by the dry run, never uploaded, and removed on exit.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

if [ ! -f sdk/cmake/XbeRecomp.cmake ]; then
    echo "preflight: sdk/ is not initialized; run 'git submodule update --init sdk'" >&2
    exit 1
fi

echo "preflight: DRY_RUN=1 scripts/cross-build.sh"
scripts/ci/with-placeholder-xbe.sh env DRY_RUN=1 scripts/cross-build.sh

echo "preflight: DRY_RUN=1 scripts/container.sh harness 5"
scripts/ci/with-placeholder-xbe.sh env DRY_RUN=1 scripts/container.sh harness 5

echo "preflight: passed (both dry runs exited 0; no container was started)"
