#!/usr/bin/env bash
# Markdown sanity for tracked .md files: no skipped heading levels, balanced code fences.
#
# Headings inside fenced code blocks are ignored. A fenced block opens and closes on a line
# whose first non-space characters are three backticks.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

files=$(git ls-files '*.md')
if [ -z "$files" ]; then
    echo "markdown: no tracked .md files"
    exit 0
fi

status=0
checked=0
while IFS= read -r file; do
    [ -n "$file" ] || continue
    checked=$((checked + 1))
    if ! awk -v file="$file" '
        BEGIN { fence = 0; last = 0; bad = 0 }
        {
            line = $0
            if (line ~ /^[[:space:]]*```/) { fence = !fence; next }
            if (fence) next
            if (match(line, /^#+/)) {
                level = RLENGTH
                if (last > 0 && level > last + 1) {
                    printf "%s:%d: heading level jumps from %d to %d\n", file, FNR, last, level
                    bad = 1
                }
                last = level
            }
        }
        END {
            if (fence) { printf "%s: unbalanced code fence (still open at EOF)\n", file; bad = 1 }
            exit bad
        }
    ' "$file"; then
        status=1
    fi
done <<< "$files"

if [ "$status" -ne 0 ]; then
    echo "markdown: FAILED" >&2
    exit 1
fi
echo "markdown: $checked file(s) checked, headings and fences are consistent"
