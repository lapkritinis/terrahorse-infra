#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
web_root=${E2E_WEB_ROOT:-"$root/../terrahorse-web-e2e"}
test "${E2E_STOP_CONFIRM:-}" = terrahorse-e2e || { echo 'Set E2E_STOP_CONFIRM=terrahorse-e2e.' >&2; exit 1; }
cd "$web_root"
docker compose --project-name terrahorse-web-e2e -f compose.yml -f compose.preview.yml -f "$root/compose.e2e.yml" down --remove-orphans
pkill -f 'cloudflared.*terrahorse-e2e' 2>/dev/null || true
