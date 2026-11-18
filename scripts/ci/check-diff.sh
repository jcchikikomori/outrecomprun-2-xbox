#!/usr/bin/env bash
# Whitespace and conflict-marker check over the pushed range.
#
# BASE_SHA     github.event.before (push only; all-zero on branch creation)
# PR_BASE_SHA  github.event.pull_request.base.sha (pull_request only)
#
# git diff --check is skipped when no base commit is available or the base is not present
# in this clone (a force push, or the all-zero "new branch" sentinel).
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

base=${BASE_SHA:-}
if [ -z "$base" ] || [ "$base" = 0000000000000000000000000000000000000000 ]; then
    base=${PR_BASE_SHA:-}
fi

if [ -n "$base" ] && git cat-file -e "$base^{commit}" 2>/dev/null; then
    echo "diff: whitespace check over $base..HEAD"
    git diff --check "$base" HEAD
    echo "diff: no whitespace errors"
else
    echo "diff: no usable base commit (initial push, force push or pull request); skipping git diff --check"
fi

# Conflict markers in tracked text files. git grep exits 1 when nothing matches.
if git grep -n -E '^(<<<<<<< |=======$|>>>>>>> )' -- . ':(exclude)sdk'; then
    echo "diff: FAILED: conflict markers found (see above)" >&2
    exit 1
fi
echo "diff: no conflict markers"
