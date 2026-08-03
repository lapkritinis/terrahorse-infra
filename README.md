# TerraHorse Infrastructure

This repository owns the non-production E2E boundary at `e2e.terrahorse.lt`. It uses only the `terrahorse-e2e` Saleor app, channel, catalogue, warehouse, shipping zone and delivery method. It never changes `terrahorse.lt`, `www`, a production tunnel or production Saleor resources.

Compose project `terrahorse-web-e2e` owns both the production-built storefront on loopback port `4100` and the dedicated Cloudflared connector. Cloudflare adds `X-Robots-Tag: noindex, nofollow` for this hostname. Provisioning creates no Montonio Order or payment.

## Protected inputs

Keep both env files, the dedicated tunnel config and its credentials outside Git as owner-only `0600` files:

```sh
export E2E_STOREFRONT_SOURCE_REPO=/absolute/path/to/terrahorse-web
export E2E_STOREFRONT_REF=origin/main
export E2E_RUNTIME_ENV_FILE=/protected/path/runtime.env
export E2E_SECRET_ENV_FILE=/protected/path/secrets.env
export E2E_TUNNEL_CONFIG_FILE=/protected/path/terrahorse-e2e.yml
export E2E_TUNNEL_CREDENTIALS_FILE=/protected/path/terrahorse-e2e.json
```

The tunnel config is intentionally exact and contains no other ingress:

```yaml
tunnel: <dedicated-tunnel-uuid>
credentials-file: /etc/cloudflared/credentials.json
loglevel: info
ingress:
  - hostname: e2e.terrahorse.lt
    service: http://host.docker.internal:4100
  - service: http_status:404
```

## Start, verify and stop

Start resolves the friendly storefront ref once, reuses a clean detached ignored worktree, derives the authenticated E2E Saleor app ID, installs and rereads the permanent webhook, and writes one ignored owner record before Compose starts both services:

```sh
E2E_WEBHOOK_INSTALL_CONFIRM=terrahorse-e2e scripts/run-e2e-storefront.sh
```

Standalone verification uses that record:

```sh
export E2E_STOREFRONT_SHA=$(sed -n '1p' .e2e-run)
scripts/verify-e2e-boundary.sh
```

The read-only verifier requires an active connector, exact public revision/environment, route-specific status and noindex headers, and a matching storefront access-log request ID for the empty callback rejection. It makes no callback-authentication claim.

Stop removes both services as one project and deletes the owner record only after Compose succeeds:

```sh
E2E_STOP_CONFIRM=terrahorse-e2e scripts/stop-e2e-storefront.sh
```

After stop, remove only the exact detached worktree with `E2E_STOREFRONT_SHA=<full-sha> E2E_WORKTREE_CLEANUP_CONFIRM=terrahorse-e2e scripts/cleanup-e2e-storefront-worktree.sh`.

If start is interrupted, run the same project-scoped stop and retry:

```sh
E2E_STOP_CONFIRM=terrahorse-e2e scripts/stop-e2e-storefront.sh
```

The local identity cannot read the exact Cloudflare DNS record, so automatic rollback is unavailable. Approved removal remains an owner dashboard action: confirm the exact UUID, delete only the `e2e.terrahorse.lt` record targeting it, then delete only the `terrahorse-e2e` tunnel. Saleor audit records remain unless a separate resource-ID-scoped task authorizes removal.
