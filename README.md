# TerraHorse Infrastructure

This repository owns environment-level TerraHorse operations. Its first scoped capability is the non-production E2E boundary at `e2e.terrahorse.lt`.

Changes require a reviewed pull request. Scripts must be idempotent, must not print secret values, and must document their precise resources and rollback scope.

Application runtime contracts remain in the sibling `terrahorse-web` repository.

## E2E boundary

The retained non-production boundary is `terrahorse-e2e` / `e2e.terrahorse.lt`. It runs the exact storefront revision `06a106e712bfabe8d731c582493c12c58415e44a` in Compose project `terrahorse-web-e2e`, loopback port `4100`, behind its dedicated named tunnel. The isolated Saleor scope contains only the E2E channel, warehouse, LT shipping zone, test delivery method, product and variant. No payment was created.

Owner-only `.env.e2e`, Cloudflared credentials and config remain outside Git. Start with `scripts/run-e2e-storefront.sh`; verify with `scripts/verify-e2e-boundary.sh` and `scripts/verify-e2e-saleor.mjs`; stop with `E2E_STOP_CONFIRM=terrahorse-e2e scripts/stop-e2e-storefront.sh`.

`scripts/rollback-e2e-boundary.sh` refuses broad deletion and refuses Saleor cleanup by design. It checks the exact named tunnel and hostname before it can act; Saleor removal must be explicit and run-scoped.
