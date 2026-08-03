#!/bin/sh
set -eu

fail() { printf '%s\n' "$1" >&2; exit 1; }
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
state="$root/.e2e-run"
runtime_env=${E2E_RUNTIME_ENV_FILE:?E2E_RUNTIME_ENV_FILE is required}
secret_env=${E2E_SECRET_ENV_FILE:?E2E_SECRET_ENV_FILE is required}
config=${E2E_TUNNEL_CONFIG_FILE:?E2E_TUNNEL_CONFIG_FILE is required}
credentials=${E2E_TUNNEL_CREDENTIALS_FILE:?E2E_TUNNEL_CREDENTIALS_FILE is required}

protected_file() {
  test -f "$1" && test ! -L "$1" || fail "$2 must be a regular, non-symlink file."
  test "$(stat -f '%u' "$1")" = "$(id -u)" && test "$(stat -f '%Lp' "$1")" = 600 || \
    fail "$2 must be owned by the current user with mode 0600."
}
protected_file "$runtime_env" 'Runtime environment file'
protected_file "$secret_env" 'Secret environment file'
protected_file "$config" 'Tunnel configuration file'
protected_file "$credentials" 'Tunnel credentials file'
node "$root/scripts/verify-e2e-tunnel-config.mjs" "$config" "$credentials"

set -a
. "$runtime_env"
. "$secret_env"
set +a
missing=''
for name in SALEOR_API_URL SALEOR_E2E_ADMIN_TOKEN SALEOR_PAYMENT_GATEWAY_ID SALEOR_PAYMENT_WEBHOOK_SECRET MONTONIO_ACCESS_KEY MONTONIO_SECRET_KEY COMMERCE_EVENT_HMAC_KEY SALEOR_VENIPAK_PARCEL_LOCKER_METHOD_ID SALEOR_VENIPAK_COURIER_METHOD_ID; do
  eval "value=\${$name-}"
  test -n "$value" || missing="$missing $name"
done
test -z "$missing" || fail "Missing required names:$missing"

web_root=$("$root/scripts/prepare-e2e-storefront-worktree.sh")
revision=$(git -C "$web_root" rev-parse HEAD)
test "$(git -C "$web_root" status --porcelain)" = '' || fail 'Managed E2E worktree is not clean.'
export E2E_STOREFRONT_SHA="$revision"
export NUXT_PUBLIC_SITE_URL=https://e2e.terrahorse.lt
export PAYMENT_CALLBACK_ORIGIN=https://e2e.terrahorse.lt
export SALEOR_CHANNEL=terrahorse-e2e
export SALEOR_COMMERCE_APP_TOKEN="$SALEOR_E2E_ADMIN_TOKEN"
export APP_VERSION="$revision"
case "$SALEOR_API_URL" in
  http://host.docker.internal:*) export SALEOR_E2E_API_URL="http://127.0.0.1:${SALEOR_API_URL#http://host.docker.internal:}" ;;
  *) export SALEOR_E2E_API_URL="$SALEOR_API_URL" ;;
esac
SALEOR_PAYMENT_APP_ID=$(E2E_WEBHOOK_IDENTITY_ONLY=terrahorse-e2e node "$root/scripts/install-e2e-payment-webhook.mjs")
export SALEOR_PAYMENT_APP_ID
export E2E_STOREFRONT_PAYMENT_OPERATION="$web_root/server/data/saleor/graphql/operations/payment-ownership.graphql"

compose() {
  docker compose --project-name terrahorse-web-e2e \
    --env-file "$runtime_env" --env-file "$secret_env" \
    -f "$web_root/compose.yml" -f "$web_root/compose.preview.yml" \
    -f "$root/compose.e2e.yml" --profile tunnel "$@"
}
compose config --quiet
umask 077
(set -C; printf '%s\n' "$revision" "$web_root" "$runtime_env" "$secret_env" "$config" "$credentials" "$SALEOR_PAYMENT_APP_ID" > "$state") 2>/dev/null || \
  fail 'An E2E boundary is already owned; stop it before starting another.'
cleanup() {
  code=$?
  trap - EXIT INT TERM
  if compose down --remove-orphans >/dev/null 2>&1; then rm -f "$state"; else printf '%s\n' 'Cleanup failed; run the documented project-scoped Compose down command.' >&2; fi
  exit "$code"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

node "$root/scripts/install-e2e-payment-webhook.mjs"
compose up -d --build --wait --wait-timeout 90 --remove-orphans
curl -fsS --max-time 10 http://127.0.0.1:4100/health | node -e 'let s="";process.stdin.on("data",x=>s+=x);process.stdin.on("end",()=>{const x=JSON.parse(s);process.exit(x.environment==="preview"&&x.version===process.env.APP_VERSION?0:1)})'
ready=false
for attempt in 1 2 3 4 5 6 7 8 9 10; do
  if "$root/scripts/verify-e2e-boundary.sh" >/dev/null 2>&1; then ready=true; break; fi
  sleep 2
done
test "$ready" = true || fail 'Public E2E boundary did not become ready.'
"$root/scripts/verify-e2e-boundary.sh"
trap - EXIT INT TERM
printf '%s\n' 'E2E storefront and tunnel started.'
