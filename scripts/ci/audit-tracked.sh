#!/usr/bin/env bash
# Fail when the repository tracks user game media, generated recompiled code, or build products,
# or when .gitignore has lost the entries that keep those files out of version control.
#
# The audit only reads the index (git ls-files); it never touches assets/ or generated/.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

status=0

fail() { printf 'audit: %s\n' "$*" >&2; status=1; }

# --- tracked paths ------------------------------------------------------------------
# assets/ (the user's XBE, ISO and extracted files), generated/ (recompiled game code),
# out/ and .local/ (build trees, xwin sysroot, playtest bundles), and loose media or
# executables anywhere in the tree.
forbidden='(^|/)(assets|generated|out|\.local)/|\.(iso|xbe|cvm|exe|dll|sav|dmp)$'
bad=0
while IFS= read -r path; do
    [ -n "$path" ] || continue
    printf 'audit: tracked path must not be committed: %s\n' "$path" >&2
    bad=$((bad + 1))
done < <(git ls-files -z | tr '\0' '\n' | grep -Ei -- "$forbidden" || true)

if [ "$bad" -eq 0 ]; then
    echo "audit: no tracked media, generated code, or build products"
else
    fail "$bad tracked path(s) match the forbidden patterns"
fi

# --- .gitignore guard ---------------------------------------------------------------
required_ignores=(/assets/ /generated/ /out/ /.local/ '*.iso' '*.xbe')
missing=0
for pattern in "${required_ignores[@]}"; do
    if grep -qxF -- "$pattern" .gitignore; then
        printf 'audit: .gitignore keeps %s\n' "$pattern"
    else
        printf 'audit: .gitignore is missing the entry %s\n' "$pattern" >&2
        missing=$((missing + 1))
    fi
done
[ "$missing" -eq 0 ] || fail ".gitignore lost $missing required entr(ies): the media and build guards are weaker"

# --- pinned XBE checksum ------------------------------------------------------------
# The build job verifies the user's copied XBE against this file. Keep it a single,
# well-formed sha1sum line; review every change to it.
pin=config/default.xbe.sha1
if [ ! -f "$pin" ]; then
    fail "$pin is missing (it pins the SHA-1 of the user's default.xbe)"
elif [ "$(wc -l < "$pin")" -ne 1 ]; then
    fail "$pin must contain exactly one line"
elif ! grep -Eqx '[0-9a-f]{40}  default\.xbe' "$pin"; then
    fail "$pin must match '<40 hex digits>  default.xbe' (two spaces, sha1sum format)"
else
    echo "audit: $pin is well formed ($(cut -d' ' -f1 "$pin"))"
fi

# --- summary ------------------------------------------------------------------------
if [ "$status" -ne 0 ]; then
    echo "audit: FAILED" >&2
    exit 1
fi
echo "audit: passed"
