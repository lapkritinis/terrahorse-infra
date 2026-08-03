#!/bin/sh
set -eu

fail() { printf '%s\n' "$1" >&2; exit 1; }
test "${E2E_DIAGNOSTIC_CONFIRM:-}" = terrahorse-e2e || \
  fail 'Set E2E_DIAGNOSTIC_CONFIRM=terrahorse-e2e.'
config=${E2E_TUNNEL_CONFIG_FILE:?E2E_TUNNEL_CONFIG_FILE is required}
credentials=${E2E_TUNNEL_CREDENTIALS_FILE:?E2E_TUNNEL_CREDENTIALS_FILE is required}
test -f "$config" && test ! -L "$config" || fail 'Invalid protected tunnel configuration.'
test -f "$credentials" && test ! -L "$credentials" || fail 'Invalid protected tunnel credentials.'
test "$(stat -f '%u' "$config")" = "$(id -u)" && test "$(stat -f '%Lp' "$config")" = 600 || fail 'Tunnel configuration must be owner-only mode 0600.'
test "$(stat -f '%u' "$credentials")" = "$(id -u)" && test "$(stat -f '%Lp' "$credentials")" = 600 || fail 'Tunnel credentials must be owner-only mode 0600.'
uuid=$(node -e 'const fs=require("fs");const x=JSON.parse(fs.readFileSync(process.argv[1],"utf8")).TunnelID;if(!/^[0-9a-f-]{36}$/i.test(x))process.exit(1);process.stdout.write(x)' "$credentials")
cloudflared tunnel ingress validate "$config" >/dev/null
grep -Eq "^tunnel:[[:space:]]*$uuid[[:space:]]*$" "$config" || fail 'Tunnel configuration UUID mismatch.'
grep -Eq "^[[:space:]]*-[[:space:]]*hostname:[[:space:]]*['\"]?e2e\\.terrahorse\\.lt['\"]?[[:space:]]*$" "$config" || fail 'Tunnel configuration hostname mismatch.'
grep -Eq "^[[:space:]]*service:[[:space:]]*['\"]?http://127\\.0\\.0\\.1:4100['\"]?[[:space:]]*$" "$config" || fail 'Tunnel origin mismatch.'
grep -Eq "^[[:space:]]*-[[:space:]]*service:[[:space:]]*['\"]?http_status:404['\"]?[[:space:]]*$" "$config" || fail 'Tunnel catch-all mismatch.'
cloudflared tunnel info "$uuid" 2>/dev/null | grep -q 'NAME:[[:space:]]*terrahorse-e2e' || \
  fail 'Named tunnel identity mismatch.'
printf '%s\n' 'Ownership diagnostic passed; no resource was changed.'
printf '%s\n' 'Owner cleanup only: in Cloudflare DNS, delete only e2e.terrahorse.lt after confirming its target is this UUID.cfargotunnel.com; then in Zero Trust > Networks > Tunnels, delete only terrahorse-e2e after confirming the same UUID.'
printf '%s\n' 'Saleor resources are retained for audit; remove them only through a separately reviewed, resource-ID-scoped task.'
