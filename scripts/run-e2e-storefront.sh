#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
web_root=${E2E_WEB_ROOT:-"$root/../terrahorse-web-e2e"}
runtime_env=${E2E_RUNTIME_ENV_FILE:-"$root/../terrahorse-web/.env.preview"}
secret_env=${E2E_SECRET_ENV_FILE:-"$root/../terrahorse-web/.env.e2e"}
revision=06a106e712bfabe8d731c582493c12c58415e44a

missing=''
for file in "$runtime_env" "$secret_env"; do
  test -r "$file" || missing="$missing ${file##*/}"
done
if test -n "$missing"; then
  printf 'Missing required files:%s\n' "$missing" >&2
  exit 1
fi

set -a
. "$runtime_env"
. "$secret_env"
set +a
for name in SALEOR_API_URL SALEOR_E2E_ADMIN_TOKEN SALEOR_PAYMENT_GATEWAY_ID SALEOR_PAYMENT_APP_ID SALEOR_PAYMENT_WEBHOOK_SECRET MONTONIO_ACCESS_KEY MONTONIO_SECRET_KEY COMMERCE_EVENT_HMAC_KEY SALEOR_VENIPAK_PARCEL_LOCKER_METHOD_ID SALEOR_VENIPAK_COURIER_METHOD_ID; do
  eval "value=\${$name-}"
  test -n "$value" || missing="$missing $name"
done
if test -n "$missing"; then
  printf 'Missing required names:%s\n' "$missing" >&2
  exit 1
fi

export NUXT_PUBLIC_SITE_URL=https://e2e.terrahorse.lt
export SALEOR_CHANNEL=terrahorse-e2e
export SALEOR_COMMERCE_APP_TOKEN="$SALEOR_E2E_ADMIN_TOKEN"
export APP_VERSION="$revision"

cd "$web_root"
test "$(git rev-parse HEAD)" = "$revision" || { printf '%s\n' 'Unexpected E2E web revision.' >&2; exit 1; }
compose="docker compose --project-name terrahorse-web-e2e --env-file $runtime_env --env-file $secret_env -f compose.yml -f compose.preview.yml -f $root/compose.e2e.yml"
$compose config --quiet
$compose up -d --build --wait --wait-timeout 90
