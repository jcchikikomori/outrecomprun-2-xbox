#!/usr/bin/env bash
# Run a command with a placeholder assets/default.xbe when the checkout has no user media.
#
# The shared SDK scripts guard on assets/default.xbe existing, but the tools that are built
# without game code (xbe_symbols, xbe_recomp) never read it. This wrapper creates an empty
# placeholder for the duration of the command and removes it afterwards. An existing
# assets/default.xbe is never touched.
#
#   scripts/ci/with-placeholder-xbe.sh scripts/container.sh tools
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

placeholder=0
if [ ! -f assets/default.xbe ]; then
    mkdir -p assets
    : > assets/default.xbe
    placeholder=1
    trap 'if [ "$placeholder" = 1 ]; then rm -f assets/default.xbe; fi' EXIT
    echo "with-placeholder-xbe: created an empty assets/default.xbe for this command (removed on exit)"
fi

"$@"
