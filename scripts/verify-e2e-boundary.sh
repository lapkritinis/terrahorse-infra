#!/bin/sh
set -eu

fail() { printf '%s\n' "$1" >&2; exit 1; }
expected=${E2E_STOREFRONT_SHA:?E2E_STOREFRONT_SHA is required}
credentials=${E2E_TUNNEL_CREDENTIALS_FILE:?E2E_TUNNEL_CREDENTIALS_FILE is required}
test -f "$credentials" && test ! -L "$credentials" || fail 'Invalid protected tunnel credentials.'
test "$(stat -f '%u' "$credentials")" = "$(id -u)" && test "$(stat -f '%Lp' "$credentials")" = 600 || \
  fail 'Tunnel credentials must be owner-only mode 0600.'
uuid=$(node -e 'const fs=require("fs");const x=JSON.parse(fs.readFileSync(process.argv[1],"utf8")).TunnelID;if(!/^[0-9a-f-]{36}$/i.test(x))process.exit(1);process.stdout.write(x)' "$credentials")

# The local tunnel identity cannot read the DNS control plane. This verifier is
# deliberately read-only: it checks the connector and public application only.
cloudflared tunnel info "$uuid" 2>/dev/null | \
  awk 'seen && NF { found=1; exit } /^CONNECTOR ID/ { seen=1 } END { exit(found ? 0 : 1) }' || \
  fail 'The expected E2E tunnel has no active connector.'

body=$(mktemp)
trap 'rm -f "$body"' EXIT INT TERM
health_code=$(curl -sS --max-time 10 -o "$body" -w '%{http_code}' https://e2e.terrahorse.lt/health)
test "$health_code" = 200 || fail 'Public health did not return HTTP 200.'
node -e 'const fs=require("fs");const x=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));process.exit(x.status==="ok"&&x.service==="storefront"&&x.environment==="preview"&&x.version===process.env.E2E_STOREFRONT_SHA?0:1)' "$body" || \
  fail 'Public health identity does not match the exact E2E revision.'
rm -f "$body"
trap - EXIT INT TERM

check_noindex() {
  url=$1
  expected_code=$2
  method=${3:-GET}
  headers=$(mktemp)
  trap 'rm -f "$headers"' EXIT INT TERM
  code=$(curl -sS --max-time 10 -X "$method" -D "$headers" -o /dev/null -w '%{http_code}' "$url")
  test "$code" = "$expected_code" || fail "Unexpected public response status for $url."
  grep -Eiq '^x-robots-tag:[[:space:]]*noindex, nofollow\r?$' "$headers" || \
    fail "Missing exact noindex header for $url."
  if grep -Eiq '^set-cookie:.*domain=' "$headers"; then
    fail "Domain-scoped cookie returned by $url."
  fi
  rm -f "$headers"
  trap - EXIT INT TERM
}
check_noindex https://e2e.terrahorse.lt/ 302
check_noindex https://e2e.terrahorse.lt/lt 200
check_noindex https://e2e.terrahorse.lt/health 200

request_id="e2e-boundary-$(node -e 'process.stdout.write(require("node:crypto").randomBytes(12).toString("hex"))')"
headers=$(mktemp)
trap 'rm -f "$headers"' EXIT INT TERM
code=$(curl -sS --max-time 10 -X POST -H 'Content-Length: 0' -H "X-Request-Id: $request_id" \
  -D "$headers" -o /dev/null -w '%{http_code}' https://e2e.terrahorse.lt/api/payments/montonio/callback)
test "$code" = 415 || fail 'Callback path did not return the exact application rejection.'
grep -Eiq '^x-robots-tag:[[:space:]]*noindex, nofollow\r?$' "$headers" || \
  fail 'Callback rejection is missing the exact noindex header.'
if grep -Eiq '^set-cookie:.*domain=' "$headers"; then
  fail 'Domain-scoped cookie returned by callback rejection.'
fi
rm -f "$headers"
trap - EXIT INT TERM

container=$(docker ps --filter label=com.docker.compose.project=terrahorse-web-e2e \
  --filter label=com.docker.compose.service=storefront --format '{{.ID}}')
test -n "$container" && test "$(printf '%s\n' "$container" | wc -l | tr -d ' ')" = 1 || \
  fail 'Expected exactly one running E2E storefront container.'
docker logs --since 2m "$container" 2>&1 | \
  grep -F "\"requestId\":\"$request_id\"" | \
  grep -Fq '"path":"/api/payments/montonio/callback"' || \
  fail 'Callback rejection was not observed in the matching storefront access log.'

printf '%s\n' 'E2E public boundary verified.'
