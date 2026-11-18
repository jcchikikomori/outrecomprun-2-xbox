#!/usr/bin/env bash
# The recompiler is a pinned Git submodule. Fail when sdk/ is absent, points at another
# commit, or when .gitmodules no longer describes the hk21x fork the build was tested with.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

expected_commit=b908ae7f05908ff335f94037c673e4b437c7c1d6
expected_path=sdk
expected_url=https://github.com/hk21x/XboxXBERecomp.git

status=0
fail() { printf 'submodule: %s\n' "$*" >&2; status=1; }

path=$(git config -f .gitmodules --get submodule.sdk.path 2>/dev/null || true)
url=$(git config -f .gitmodules --get submodule.sdk.url 2>/dev/null || true)

if [ "$path" != "$expected_path" ]; then
    fail ".gitmodules submodule.sdk.path is '${path:-<unset>}', expected '$expected_path'"
fi
if [ "$url" != "$expected_url" ]; then
    fail ".gitmodules submodule.sdk.url is '${url:-<unset>}', expected '$expected_url'"
fi

# HEAD:sdk is the gitlink recorded in the superproject. It works whether or not the
# submodule is checked out, so this is the authoritative pin.
actual=$(git rev-parse -q --verify 'HEAD:sdk' 2>/dev/null || true)
if [ -z "$actual" ]; then
    fail "HEAD does not record a gitlink at '$expected_path'"
elif [ "$actual" != "$expected_commit" ]; then
    fail "sdk/ is pinned at $actual, expected $expected_commit"
else
    echo "submodule: sdk/ is pinned at $actual"
fi

# git submodule status is the human-readable view: '-' means not initialized, '+' means
# the checkout differs from the gitlink.
echo "submodule: git submodule status reports:"
git submodule status -- sdk || fail "git submodule status failed"

if [ ! -f "$expected_path/cmake/XbeRecomp.cmake" ]; then
    fail "$expected_path/cmake/XbeRecomp.cmake is missing; check out submodules (git submodule update --init sdk)"
else
    echo "submodule: sdk/cmake/XbeRecomp.cmake is present"
fi

if [ "$status" -ne 0 ]; then
    echo "submodule: FAILED" >&2
    exit 1
fi
echo "submodule: passed"
