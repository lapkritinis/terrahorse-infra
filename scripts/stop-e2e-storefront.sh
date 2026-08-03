#!/bin/sh
set -eu

fail() { printf '%s\n' "$1" >&2; exit 1; }
read_state() {
  file="$state_dir/$1"
  test -f "$file" && test ! -L "$file" || fail "Invalid E2E run-state file: $1."
  test "$(stat -f '%u' "$file")" = "$(id -u)" && test "$(stat -f '%Lp' "$file")" = 600 || \
    fail "Unsafe E2E run-state permissions: $1."
  sed -n '1p' "$file"
}
protected_file() {
  file=$1
  label=$2
  test -f "$file" && test ! -L "$file" || fail "$label must be a regular, non-symlink file."
  test "$(stat -f '%u' "$file")" = "$(id -u)" && test "$(stat -f '%Lp' "$file")" = 600 || \
    fail "$label must be owner-only mode 0600."
  file_repo=$(git -C "$(dirname -- "$file")" rev-parse --show-toplevel 2>/dev/null || true)
  if test -n "$file_repo" && git -C "$file_repo" ls-files --error-unmatch -- "$file" >/dev/null 2>&1; then
    fail "$label must not be tracked by Git."
  fi
}

test "${E2E_STOP_CONFIRM:-}" = terrahorse-e2e || fail 'Set E2E_STOP_CONFIRM=terrahorse-e2e.'
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
state_dir="$root/.e2e-run"
launch_label=terrahorse-e2e-cloudflared
test -d "$state_dir" && test ! -L "$state_dir" || fail 'No managed E2E run state exists.'
test "$(stat -f '%u' "$state_dir")" = "$(id -u)" && test "$(stat -f '%Lp' "$state_dir")" = 700 || \
  fail 'Unsafe E2E run-state directory permissions.'
test "$(read_state status)" = active || fail 'E2E run state is not active; refusing cleanup.'

revision=$(read_state revision)
web_root=$(read_state web-root)
runtime_env=$(read_state runtime-env)
secret_env=$(read_state secret-env)
runtime_env_sha256=$(read_state runtime-env-sha256)
secret_env_sha256=$(read_state secret-env-sha256)
config=$(read_state tunnel-config)
credentials=$(read_state tunnel-credentials)
pid_file=$(read_state tunnel-pid-file)
pid=$(read_state tunnel-pid)
uuid=$(read_state tunnel-uuid)
payment_app_id=$(read_state payment-app-id)
case "$revision" in *[!0-9a-f]*|'') fail 'Invalid persisted storefront revision.';; esac
test "${#revision}" -eq 40 || fail 'Invalid persisted storefront revision.'
case "$pid" in *[!0-9]*|'') fail 'Invalid persisted tunnel PID.';; esac
test -n "$payment_app_id" || fail 'Invalid persisted payment app identity.'
protected_file "$runtime_env" 'Runtime environment file'
protected_file "$secret_env" 'Secret environment file'
protected_file "$config" 'Tunnel configuration file'
protected_file "$credentials" 'Tunnel credentials file'
test "$(shasum -a 256 "$runtime_env" | awk '{ print $1 }')" = "$runtime_env_sha256" || fail 'Runtime environment changed after start.'
test "$(shasum -a 256 "$secret_env" | awk '{ print $1 }')" = "$secret_env_sha256" || fail 'Secret environment changed after start.'
actual_uuid=$(node -e 'const fs=require("fs");const x=JSON.parse(fs.readFileSync(process.argv[1],"utf8")).TunnelID;if(!/^[0-9a-f-]{36}$/i.test(x))process.exit(1);process.stdout.write(x)' "$credentials")
test "$actual_uuid" = "$uuid" || fail 'Tunnel credentials no longer match run state.'
test -f "$pid_file" && test ! -L "$pid_file" && test "$(cat "$pid_file")" = "$pid" || fail 'Tunnel PID file does not match run state.'
protected_file "$pid_file" 'Tunnel PID file'
test "$(git -C "$web_root" rev-parse HEAD)" = "$revision" || fail 'Managed worktree revision no longer matches run state.'
test "$(git -C "$web_root" status --porcelain)" = '' || fail 'Managed worktree is not clean.'
command=$(ps -p "$pid" -o command= 2>/dev/null) || fail 'Recorded Cloudflared process is not running.'
printf '%s\n' "$command" | grep -Fq 'cloudflared' &&
  printf '%s\n' "$command" | grep -Fq -- "--config $config" &&
  printf '%s\n' "$command" | grep -Fq -- "run $uuid" || fail 'Recorded PID is not the owned Cloudflared process.'
launchctl print "gui/$(id -u)/$launch_label" 2>/dev/null | grep -Eq "^[[:space:]]*pid = $pid$" || \
  fail 'Managed Cloudflared launch job does not own the recorded PID.'

set -a
. "$runtime_env"
. "$secret_env"
set +a
export NUXT_PUBLIC_SITE_URL=https://e2e.terrahorse.lt
export PAYMENT_CALLBACK_ORIGIN=https://e2e.terrahorse.lt
export SALEOR_CHANNEL=terrahorse-e2e
export SALEOR_COMMERCE_APP_TOKEN=${SALEOR_E2E_ADMIN_TOKEN:?SALEOR_E2E_ADMIN_TOKEN is required}
export SALEOR_PAYMENT_APP_ID="$payment_app_id"
export APP_VERSION="$revision"
compose() {
  docker compose --project-name terrahorse-web-e2e \
    --env-file "$runtime_env" --env-file "$secret_env" \
    -f "$web_root/compose.yml" -f "$web_root/compose.preview.yml" \
    -f "$root/compose.e2e.yml" "$@"
}
compose config --quiet
compose down --remove-orphans
kill "$pid"
waited=false
for attempt in 1 2 3 4 5 6 7 8 9 10; do
  kill -0 "$pid" 2>/dev/null || { waited=true; break; }
  sleep 1
done
test "$waited" = true || fail 'Cloudflared did not stop; run state retained.'
launchctl remove "$launch_label" >/dev/null 2>&1 || true
rm -f "$pid_file"
rm -f "$state_dir/owner-pid" "$state_dir/status" "$state_dir/revision" \
  "$state_dir/web-root" "$state_dir/runtime-env" "$state_dir/secret-env" \
  "$state_dir/tunnel-config" "$state_dir/tunnel-credentials" \
  "$state_dir/tunnel-pid-file" "$state_dir/tunnel-pid" "$state_dir/tunnel-uuid" \
  "$state_dir/payment-app-id" "$state_dir/runtime-env-sha256" \
  "$state_dir/secret-env-sha256"
rmdir "$state_dir"
printf '%s\n' 'E2E storefront and tunnel stopped.'
