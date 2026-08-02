#!/bin/sh
set -eu
uuid=$(node -e 'const fs=require("fs");const x=JSON.parse(fs.readFileSync(process.argv[1],"utf8")).TunnelID;if(!/^[0-9a-f-]{36}$/i.test(x))process.exit(1);process.stdout.write(x)' "$HOME/.cloudflared/terrahorse-e2e.json")
cloudflared tunnel route dns terrahorse-e2e e2e.terrahorse.lt >/dev/null
cloudflared tunnel info "$uuid" 2>/dev/null | grep -q '^CONNECTOR ID'
test "$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 https://e2e.terrahorse.lt/health)" = 200
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 -X POST -H 'Content-Length: 0' https://e2e.terrahorse.lt/api/payments/montonio/callback || true)
case "$code" in 4*) ;; *) exit 1;; esac
echo 'E2E public boundary verified.'
