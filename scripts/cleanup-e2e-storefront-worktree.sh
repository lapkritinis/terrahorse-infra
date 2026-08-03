#!/bin/sh
set -eu
test "${E2E_WORKTREE_CLEANUP_CONFIRM:-}" = terrahorse-e2e || { echo 'Set E2E_WORKTREE_CLEANUP_CONFIRM=terrahorse-e2e.' >&2; exit 1; }
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source=${E2E_STOREFRONT_SOURCE_REPO:?E2E_STOREFRONT_SOURCE_REPO is required}
sha=${E2E_STOREFRONT_SHA:?E2E_STOREFRONT_SHA is required}
case "$sha" in *[!0-9a-f]*|'') echo 'E2E_STOREFRONT_SHA must be a full lowercase SHA.' >&2; exit 1;; esac
test "${#sha}" -eq 40 || { echo 'E2E_STOREFRONT_SHA must be a full lowercase SHA.' >&2; exit 1; }
git -C "$source" cat-file -e "$sha^{commit}"
target="$root/.tmp/worktrees/storefront-$sha"
test -d "$target" && test "$(git -C "$target" rev-parse HEAD)" = "$sha" || { echo 'Exact managed worktree not found.' >&2; exit 1; }
git -C "$source" worktree remove "$target"
