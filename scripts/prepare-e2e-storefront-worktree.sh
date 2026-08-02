#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source=${E2E_STOREFRONT_SOURCE_REPO:?E2E_STOREFRONT_SOURCE_REPO is required}
sha=${E2E_STOREFRONT_SHA:?E2E_STOREFRONT_SHA is required}
case "$sha" in [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;; *) echo 'E2E_STOREFRONT_SHA must be a full lowercase SHA.' >&2; exit 1;; esac
git -C "$source" cat-file -e "$sha^{commit}"
target="$root/.tmp/worktrees/storefront-$sha"
if test -e "$target"; then
  test "$(git -C "$target" rev-parse HEAD)" = "$sha" || { echo 'Managed worktree SHA mismatch.' >&2; exit 1; }
else
  mkdir -p "$root/.tmp/worktrees"
  git -C "$source" worktree add --detach "$target" "$sha"
fi
printf '%s\n' "$target"
