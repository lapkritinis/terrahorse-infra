#!/bin/sh
set -eu
uuid=$(node -e 'const fs=require("fs");const x=JSON.parse(fs.readFileSync(process.argv[1],"utf8")).TunnelID;if(!/^[0-9a-f-]{36}$/i.test(x))process.exit(1);process.stdout.write(x)' "$HOME/.cloudflared/terrahorse-e2e.json")
# cloudflared exposes no read-only DNS-record query. This verifier intentionally
# refuses to repair DNS; the owner must confirm the exact route in Cloudflare.
cloudflared tunnel info "$uuid" 2>/dev/null | grep -q '^CONNECTOR ID'
expected=${E2E_STOREFRONT_SHA:?E2E_STOREFRONT_SHA is required}
curl -sS --max-time 10 https://e2e.terrahorse.lt/health | node -e 'let s="";process.stdin.on("data",x=>s+=x);process.stdin.on("end",()=>{const x=JSON.parse(s);process.exit(x.environment==="preview"&&x.version===process.env.E2E_STOREFRONT_SHA?0:1)})'
for url in https://e2e.terrahorse.lt/ https://e2e.terrahorse.lt/lt https://e2e.terrahorse.lt/health; do curl -sSIL --max-time 10 "$url" | grep -qi '^x-robots-tag: noindex, nofollow'; done
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 -X POST -H 'Content-Length: 0' https://e2e.terrahorse.lt/api/payments/montonio/callback || true)
test "$code" = 415
echo 'E2E public boundary verified.'
