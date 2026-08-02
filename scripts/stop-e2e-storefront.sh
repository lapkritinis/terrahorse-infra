#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
runtime_env=${E2E_RUNTIME_ENV_FILE:?E2E_RUNTIME_ENV_FILE is required}
secret_env=${E2E_SECRET_ENV_FILE:?E2E_SECRET_ENV_FILE is required}
web_root=$("$root/scripts/prepare-e2e-storefront-worktree.sh")
test "${E2E_STOP_CONFIRM:-}" = terrahorse-e2e || { echo 'Set E2E_STOP_CONFIRM=terrahorse-e2e.' >&2; exit 1; }
cd "$web_root"
docker compose --project-name terrahorse-web-e2e --env-file "$runtime_env" --env-file "$secret_env" -f compose.yml -f compose.preview.yml -f "$root/compose.e2e.yml" down --remove-orphans
test -r "${E2E_TUNNEL_PID_FILE:?E2E_TUNNEL_PID_FILE is required}" && kill "$(cat "$E2E_TUNNEL_PID_FILE")" && rm "$E2E_TUNNEL_PID_FILE" || true
