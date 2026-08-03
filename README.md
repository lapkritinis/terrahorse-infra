# TerraHorse Infrastructure

This repository owns environment-level TerraHorse operations. Its first scoped capability is the non-production E2E boundary at `e2e.terrahorse.lt`. Application runtime contracts remain in the sibling `terrahorse-web` repository.

## Retained E2E boundary

The boundary uses only the `terrahorse-e2e` Saleor channel, app, catalogue, warehouse, shipping zone and delivery method. The storefront runs as Compose project `terrahorse-web-e2e` on loopback port `4100`, behind the dedicated `terrahorse-e2e` named tunnel. Cloudflare adds `X-Robots-Tag: noindex, nofollow` for the exact `e2e.terrahorse.lt` hostname. No Montonio Order or payment is created by these scripts.

The default operational state is stopped. A successful start retains `.e2e-run` as the owner-only active-run lock and runs Cloudflared under the dedicated macOS user launch label `terrahorse-e2e-cloudflared` until the matching stop succeeds. Existing, stale or conflicting state is refused and is never removed automatically.

## Protected inputs

Keep the runtime environment, secret environment, tunnel configuration and tunnel credentials outside Git as regular, non-symlink files owned by the current user with mode `0600`. The tunnel config must name the dedicated UUID, its dedicated credentials file, `e2e.terrahorse.lt -> http://127.0.0.1:4100`, and a final `http_status:404` catch-all. Set these paths and the storefront source before running commands:

```sh
export E2E_STOREFRONT_SOURCE_REPO=/absolute/path/to/terrahorse-web
export E2E_STOREFRONT_REF=origin/main
export E2E_RUNTIME_ENV_FILE=/protected/path/runtime.env
export E2E_SECRET_ENV_FILE=/protected/path/secrets.env
export E2E_TUNNEL_CONFIG_FILE=/protected/path/config.yml
export E2E_TUNNEL_CREDENTIALS_FILE=/protected/path/terrahorse-e2e.json
export E2E_TUNNEL_PID_FILE=/protected/path/terrahorse-e2e.pid
```

The runtime and secret files together must provide the names checked by `scripts/run-e2e-storefront.sh`. Values must never be printed or copied into this repository. The launcher derives `SALEOR_PAYMENT_APP_ID` from the authenticated E2E app rather than trusting a stale configured ID. It resolves the friendly storefront ref once, creates/reuses only the clean detached `.tmp/worktrees/storefront-<sha>` worktree, verifies and rewrites the permanent Saleor webhook contract, validates Compose without rendering resolved configuration, starts the storefront, proves local health, then starts Cloudflared and proves the public boundary.

## Start, verify and stop

```sh
E2E_WEBHOOK_INSTALL_CONFIRM=terrahorse-e2e scripts/run-e2e-storefront.sh
```

While the managed boundary is active, standalone public verification uses the immutable revision retained in `.e2e-run/revision`:

```sh
export E2E_STOREFRONT_SHA=$(sed -n '1p' .e2e-run/revision)
scripts/verify-e2e-boundary.sh
set -a
. "$E2E_RUNTIME_ENV_FILE"
. "$E2E_SECRET_ENV_FILE"
set +a
case "$SALEOR_API_URL" in
  http://host.docker.internal:*) export SALEOR_E2E_API_URL="http://127.0.0.1:${SALEOR_API_URL#http://host.docker.internal:}" ;;
  *) export SALEOR_E2E_API_URL="$SALEOR_API_URL" ;;
esac
E2E_SALEOR_VERIFY=saleor-e2e node scripts/verify-e2e-saleor.mjs
```

The public verifier is read-only with respect to Cloudflare. It requires an active connector, exact public health revision/environment, exact response statuses plus the host-wide noindex header, and a request-correlated storefront access log for the empty callback rejection. It never calls `cloudflared tunnel route dns` and makes no callback-authentication claim.

Stop reads the exact persisted SHA, worktree, Compose inputs, tunnel UUID/config and PID; it does not resolve the friendly ref again:

```sh
E2E_STOP_CONFIRM=terrahorse-e2e scripts/stop-e2e-storefront.sh
```

After stop, remove only the exact detached worktree with its immutable SHA:

```sh
export E2E_STOREFRONT_SHA=<full-40-character-sha>
E2E_WORKTREE_CLEANUP_CONFIRM=terrahorse-e2e scripts/cleanup-e2e-storefront-worktree.sh
```

## Refusal-only ownership diagnostic

The local identity cannot perform an exact read-only Cloudflare DNS-record lookup, so automated rollback is intentionally unavailable. The diagnostic validates only facts it can read and never changes DNS, tunnels or Saleor:

```sh
E2E_DIAGNOSTIC_CONFIRM=terrahorse-e2e scripts/diagnose-e2e-ownership.sh
```

If removal is approved, the owner must first stop the managed runtime, then use the Cloudflare dashboard: delete only the `e2e.terrahorse.lt` DNS record after confirming it targets `<exact UUID>.cfargotunnel.com`; then delete only the `terrahorse-e2e` tunnel after confirming the same UUID. Retain Saleor audit records unless a separate reviewed, resource-ID-scoped cleanup task authorizes their removal. Never alter `terrahorse.lt`, `www`, a root/production tunnel, or production Saleor resources.
