#!/bin/sh
set -eu
test "${E2E_WORKTREE_CLEANUP_CONFIRM:-}" = terrahorse-e2e || { echo 'Set E2E_WORKTREE_CLEANUP_CONFIRM=terrahorse-e2e.' >&2; exit 1; }
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source=${E2E_STOREFRONT_SOURCE_REPO:?E2E_STOREFRONT_SOURCE_REPO is required}
ref=${E2E_STOREFRONT_REF:-HEAD}
sha=$(git -C "$source" rev-parse --verify "$ref^{commit}")
target="$root/.tmp/worktrees/storefront-$sha"
test -d "$target" && test "$(git -C "$target" rev-parse HEAD)" = "$sha" || { echo 'Exact managed worktree not found.' >&2; exit 1; }
git -C "$source" worktree remove "$target"
