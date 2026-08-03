#!/bin/sh
set -eu

fail() { printf '%s\n' "$1" >&2; exit 1; }

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
state_dir="$root/.e2e-run"
runtime_env=${E2E_RUNTIME_ENV_FILE:?E2E_RUNTIME_ENV_FILE is required}
secret_env=${E2E_SECRET_ENV_FILE:?E2E_SECRET_ENV_FILE is required}
config=${E2E_TUNNEL_CONFIG_FILE:?E2E_TUNNEL_CONFIG_FILE is required}
credentials=${E2E_TUNNEL_CREDENTIALS_FILE:?E2E_TUNNEL_CREDENTIALS_FILE is required}
pid_file=${E2E_TUNNEL_PID_FILE:?E2E_TUNNEL_PID_FILE is required}
launch_label=terrahorse-e2e-cloudflared

# This mkdir is both the first mutation and the single-run ownership lock.
umask 077
mkdir "$state_dir" 2>/dev/null || fail 'Active or stale E2E run state exists; refusing ownership.'
chmod 700 "$state_dir"

compose_owned=false
tunnel_owned=false
launched_pid=''
web_root=''
cleanup_state() {
  rm -f "$state_dir/owner-pid" "$state_dir/status" "$state_dir/revision" \
    "$state_dir/web-root" "$state_dir/runtime-env" "$state_dir/secret-env" \
    "$state_dir/tunnel-config" "$state_dir/tunnel-credentials" \
    "$state_dir/tunnel-pid-file" "$state_dir/tunnel-pid" "$state_dir/tunnel-uuid" \
    "$state_dir/payment-app-id" "$state_dir/runtime-env-sha256" \
    "$state_dir/secret-env-sha256"
  rmdir "$state_dir" 2>/dev/null || true
}
compose() {
  docker compose --project-name terrahorse-web-e2e \
    --env-file "$runtime_env" --env-file "$secret_env" \
    -f "$web_root/compose.yml" -f "$web_root/compose.preview.yml" \
    -f "$root/compose.e2e.yml" "$@"
}
owned_cloudflared() {
  test -n "$launched_pid" && kill -0 "$launched_pid" 2>/dev/null || return 1
  command=$(ps -p "$launched_pid" -o command= 2>/dev/null) || return 1
  printf '%s\n' "$command" | grep -Fq 'cloudflared' &&
    printf '%s\n' "$command" | grep -Fq -- "--config $config" &&
    printf '%s\n' "$command" | grep -Fq -- "run $uuid"
}
connector_active() {
  cloudflared tunnel info "$uuid" 2>/dev/null | \
    awk 'seen && NF { found=1; exit } /^CONNECTOR ID/ { seen=1 } END { exit(found ? 0 : 1) }'
}
cleanup() {
  code=$?
  trap - EXIT INT TERM
  if test "$tunnel_owned" = true && test -f "$pid_file" && test "$(cat "$pid_file")" = "$launched_pid"; then
    if owned_cloudflared; then
      kill "$launched_pid" 2>/dev/null || true
      wait "$launched_pid" 2>/dev/null || true
    fi
    rm -f "$pid_file"
  fi
  if test "$tunnel_owned" = true; then
    launchctl remove "$launch_label" >/dev/null 2>&1 || true
  fi
  if test "$compose_owned" = true; then
    compose down --remove-orphans >/dev/null 2>&1 || true
  fi
  cleanup_state
  exit "$code"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
printf '%s\n' "$$" > "$state_dir/owner-pid"

protected_file() {
  file=$1
  label=$2
  test -f "$file" && test ! -L "$file" || fail "$label must be a regular, non-symlink file."
  test "$(stat -f '%u' "$file")" = "$(id -u)" || fail "$label must be owned by the current user."
  test "$(stat -f '%Lp' "$file")" = 600 || fail "$label must be mode 0600."
  file_repo=$(git -C "$(dirname -- "$file")" rev-parse --show-toplevel 2>/dev/null || true)
  if test -n "$file_repo" && git -C "$file_repo" ls-files --error-unmatch -- "$file" >/dev/null 2>&1; then
    fail "$label must not be tracked by Git."
  fi
  return 0
}

missing=''
for file in "$runtime_env" "$secret_env" "$config" "$credentials"; do
  test -e "$file" || missing="$missing ${file##*/}"
done
test -z "$missing" || fail "Missing required files:$missing"
protected_file "$runtime_env" 'Runtime environment file'
protected_file "$secret_env" 'Secret environment file'
protected_file "$config" 'Tunnel configuration file'
protected_file "$credentials" 'Tunnel credentials file'
test ! -e "$pid_file" && test ! -L "$pid_file" || fail 'Tunnel PID file already exists; refusing ownership.'
launchctl print "gui/$(id -u)/$launch_label" >/dev/null 2>&1 && fail 'Managed Cloudflared launch job already exists.'
test -z "$(docker ps -aq --filter label=com.docker.compose.project=terrahorse-web-e2e)" || \
  fail 'Compose project already exists; refusing to disturb it.'

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

uuid=$(node -e 'const fs=require("fs");const x=JSON.parse(fs.readFileSync(process.argv[1],"utf8")).TunnelID;if(!/^[0-9a-f-]{36}$/i.test(x))process.exit(1);process.stdout.write(x)' "$credentials")
cloudflared tunnel ingress validate "$config" >/dev/null
grep -Eq "^tunnel:[[:space:]]*$uuid[[:space:]]*$" "$config" || fail 'Tunnel configuration UUID mismatch.'
grep -Fq "credentials-file: $credentials" "$config" || fail 'Tunnel credentials path mismatch.'
grep -Eq "^[[:space:]]*-[[:space:]]*hostname:[[:space:]]*['\"]?e2e\\.terrahorse\\.lt['\"]?[[:space:]]*$" "$config" || fail 'Tunnel hostname mismatch.'
grep -Eq "^[[:space:]]*service:[[:space:]]*['\"]?http://127\\.0\\.0\\.1:4100['\"]?[[:space:]]*$" "$config" || fail 'Tunnel origin mismatch.'
grep -Eq "^[[:space:]]*-[[:space:]]*service:[[:space:]]*['\"]?http_status:404['\"]?[[:space:]]*$" "$config" || fail 'Tunnel catch-all mismatch.'
if connector_active; then
  fail 'Tunnel already has an active connector; refusing ownership.'
fi
printf '%s\n' "$revision" > "$state_dir/revision"
printf '%s\n' "$web_root" > "$state_dir/web-root"
printf '%s\n' "$runtime_env" > "$state_dir/runtime-env"
printf '%s\n' "$secret_env" > "$state_dir/secret-env"
shasum -a 256 "$runtime_env" | awk '{ print $1 }' > "$state_dir/runtime-env-sha256"
shasum -a 256 "$secret_env" | awk '{ print $1 }' > "$state_dir/secret-env-sha256"
printf '%s\n' "$config" > "$state_dir/tunnel-config"
printf '%s\n' "$credentials" > "$state_dir/tunnel-credentials"
printf '%s\n' "$pid_file" > "$state_dir/tunnel-pid-file"
printf '%s\n' "$uuid" > "$state_dir/tunnel-uuid"
printf '%s\n' "$SALEOR_PAYMENT_APP_ID" > "$state_dir/payment-app-id"
printf '%s\n' starting > "$state_dir/status"

export E2E_STOREFRONT_PAYMENT_OPERATION="$web_root/server/data/saleor/graphql/operations/payment-ownership.graphql"
node "$root/scripts/install-e2e-payment-webhook.mjs"

compose config --quiet
compose_owned=true
compose up -d --build --wait --wait-timeout 90
curl -fsS --max-time 10 http://127.0.0.1:4100/health | node -e 'let s="";process.stdin.on("data",x=>s+=x);process.stdin.on("end",()=>{const x=JSON.parse(s);process.exit(x.status==="ok"&&x.service==="storefront"&&x.environment==="preview"&&x.version===process.env.APP_VERSION?0:1)})'

cloudflared_bin=$(command -v cloudflared)
launchctl submit -l "$launch_label" -o /dev/null -e /dev/null -- \
  "$cloudflared_bin" tunnel --config "$config" --pidfile "$pid_file" run "$uuid"
tunnel_owned=true
ready=false
for attempt in 1 2 3 4 5 6 7 8 9 10; do
  if test -f "$pid_file"; then
    launched_pid=$(cat "$pid_file")
    case "$launched_pid" in *[!0-9]*|'') fail 'Cloudflared wrote an invalid PID.';; esac
    if owned_cloudflared && connector_active; then
      ready=true
      break
    fi
  fi
  sleep 1
done
test "$ready" = true || fail 'E2E tunnel connector did not become ready.'
printf '%s\n' "$launched_pid" > "$state_dir/tunnel-pid"
chmod 600 "$pid_file"
protected_file "$pid_file" 'Tunnel PID file'
"$root/scripts/verify-e2e-boundary.sh"
printf '%s\n' active > "$state_dir/status"
trap - EXIT INT TERM
printf '%s\n' 'E2E storefront and tunnel started.'
