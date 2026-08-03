#!/bin/sh
set -eu

fail() { printf '%s\n' "$1" >&2; exit 1; }
test "${E2E_STOP_CONFIRM:-}" = terrahorse-e2e || fail 'Set E2E_STOP_CONFIRM=terrahorse-e2e.'
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
state="$root/.e2e-run"
test -d "$state" && test ! -L "$state" || fail 'No safe E2E ownership directory exists.'
test "$(stat -f '%u' "$state")" = "$(id -u)" && test "$(stat -f '%Lp' "$state")" = 700 || \
  fail 'E2E ownership directory must be owner-only mode 0700.'
for file in owner saleor.env runtime.env; do
  test -f "$state/$file" && test ! -L "$state/$file" && \
    test "$(stat -f '%u' "$state/$file")" = "$(id -u)" && \
    test "$(stat -f '%Lp' "$state/$file")" = 600 || fail "Invalid E2E $file state."
done
test "$(wc -l < "$state/owner" | tr -d ' ')" = 6 || fail 'Invalid E2E ownership record.'
revision=$(sed -n '1p' "$state/owner")
web_root=$(sed -n '2p' "$state/owner")
runtime_env=$(sed -n '3p' "$state/owner")
secret_env=$(sed -n '4p' "$state/owner")
E2E_TUNNEL_CONFIG_FILE=$(sed -n '5p' "$state/owner")
E2E_TUNNEL_CREDENTIALS_FILE=$(sed -n '6p' "$state/owner")
export E2E_TUNNEL_CONFIG_FILE E2E_TUNNEL_CREDENTIALS_FILE
test "$(git -C "$web_root" rev-parse HEAD)" = "$revision" || fail 'Managed storefront worktree identity changed.'

set -a
. "$runtime_env"
. "$secret_env"
. "$state/saleor.env"
. "$state/runtime.env"
set +a
export NUXT_PUBLIC_SITE_URL=https://e2e.terrahorse.lt PAYMENT_CALLBACK_ORIGIN=https://e2e.terrahorse.lt
docker compose --project-name terrahorse-web-e2e \
  --env-file "$runtime_env" --env-file "$secret_env" \
  --env-file "$state/saleor.env" --env-file "$state/runtime.env" \
  -f "$web_root/compose.yml" -f "$web_root/compose.preview.yml" -f "$root/compose.e2e.yml" \
  --profile tunnel --profile setup --profile verify down --volumes --remove-orphans
remaining_containers=$(docker ps -aq --filter label=com.docker.compose.project=terrahorse-web-e2e)
test -z "$remaining_containers" || \
  fail 'E2E project containers remain after stop.'
remaining_volumes=$(docker volume ls -q --filter label=com.docker.compose.project=terrahorse-web-e2e)
test -z "$remaining_volumes" || \
  fail 'E2E project volumes remain after stop.'
find "$state" -mindepth 1 -maxdepth 1 -type f ! -name owner ! -name saleor.env ! -name runtime.env | grep -q . && \
  fail 'Unexpected generated state file; refusing removal.'
rm -f "$state/owner" "$state/saleor.env" "$state/runtime.env"
rmdir "$state"
printf '%s\n' 'E2E storefront, disposable Saleor project and volumes stopped.'
