#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
runtime_env=${E2E_RUNTIME_ENV_FILE:?E2E_RUNTIME_ENV_FILE is required}
secret_env=${E2E_SECRET_ENV_FILE:?E2E_SECRET_ENV_FILE is required}
web_root=$("$root/scripts/prepare-e2e-storefront-worktree.sh")
revision=$(git -C "$web_root" rev-parse HEAD)

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
test "$(git rev-parse HEAD)" = "$revision" || { printf '%s\n' 'Unexpected E2E worktree revision.' >&2; exit 1; }
compose="docker compose --project-name terrahorse-web-e2e --env-file $runtime_env --env-file $secret_env -f compose.yml -f compose.preview.yml -f $root/compose.e2e.yml"
$compose config --quiet
$compose up -d --build --wait --wait-timeout 90
test "$(curl -sS --max-time 10 http://127.0.0.1:4100/health | node -e 'let s="";process.stdin.on("data",x=>s+=x);process.stdin.on("end",()=>{const x=JSON.parse(s);process.exit(x.environment==="preview"&&x.version===process.env.APP_VERSION?0:1)})" = "" || exit 1
config=${E2E_TUNNEL_CONFIG_FILE:?E2E_TUNNEL_CONFIG_FILE is required}
pid=${E2E_TUNNEL_PID_FILE:?E2E_TUNNEL_PID_FILE is required}
cloudflared tunnel --config "$config" --pidfile "$pid" run "$(node -e 'const fs=require("fs");process.stdout.write(JSON.parse(fs.readFileSync(process.argv[1])).TunnelID)' "${E2E_TUNNEL_CREDENTIALS_FILE:?E2E_TUNNEL_CREDENTIALS_FILE is required}") >/dev/null 2>&1 &
