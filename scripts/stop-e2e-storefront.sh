#!/bin/sh
set -eu

fail() { printf '%s\n' "$1" >&2; exit 1; }
test "${E2E_STOP_CONFIRM:-}" = terrahorse-e2e || fail 'Set E2E_STOP_CONFIRM=terrahorse-e2e.'
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
state="$root/.e2e-run"
test -f "$state" && test ! -L "$state" && test "$(stat -f '%Lp' "$state")" = 600 || fail 'No safe E2E ownership record exists.'
test "$(wc -l < "$state" | tr -d ' ')" = 7 || fail 'Invalid E2E ownership record.'
revision=$(sed -n '1p' "$state")
web_root=$(sed -n '2p' "$state")
runtime_env=$(sed -n '3p' "$state")
secret_env=$(sed -n '4p' "$state")
E2E_TUNNEL_CONFIG_FILE=$(sed -n '5p' "$state")
E2E_TUNNEL_CREDENTIALS_FILE=$(sed -n '6p' "$state")
SALEOR_PAYMENT_APP_ID=$(sed -n '7p' "$state")
export E2E_TUNNEL_CONFIG_FILE E2E_TUNNEL_CREDENTIALS_FILE SALEOR_PAYMENT_APP_ID
set -a
. "$runtime_env"
. "$secret_env"
set +a
export NUXT_PUBLIC_SITE_URL=https://e2e.terrahorse.lt PAYMENT_CALLBACK_ORIGIN=https://e2e.terrahorse.lt SALEOR_CHANNEL=terrahorse-e2e
export SALEOR_COMMERCE_APP_TOKEN=${SALEOR_E2E_ADMIN_TOKEN:?SALEOR_E2E_ADMIN_TOKEN is required} APP_VERSION="$revision"
docker compose --project-name terrahorse-web-e2e --env-file "$runtime_env" --env-file "$secret_env" \
  -f "$web_root/compose.yml" -f "$web_root/compose.preview.yml" -f "$root/compose.e2e.yml" \
  --profile tunnel down --remove-orphans
rm -f "$state"
printf '%s\n' 'E2E storefront and tunnel stopped.'
