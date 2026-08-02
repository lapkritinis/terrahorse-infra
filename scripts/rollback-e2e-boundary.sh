#!/bin/sh
set -eu
test "${E2E_ROLLBACK_CONFIRM:-}" = terrahorse-e2e || { echo 'Set E2E_ROLLBACK_CONFIRM=terrahorse-e2e.' >&2; exit 1; }
uuid=$(node -e 'const fs=require("fs");const x=JSON.parse(fs.readFileSync(process.argv[1],"utf8")).TunnelID;if(!/^[0-9a-f-]{36}$/i.test(x))process.exit(1);process.stdout.write(x)' "$HOME/.cloudflared/terrahorse-e2e.json")
cloudflared tunnel info "$uuid" 2>/dev/null | grep -q 'NAME:     terrahorse-e2e'
echo 'Refusal-only diagnostic: remove only the exact e2e.terrahorse.lt record and terrahorse-e2e tunnel in the Cloudflare Dashboard after confirming their UUID; retain Saleor audit records and use explicit run-scoped cleanup only.' >&2
exit 1
