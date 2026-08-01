# Infrastructure Agent Instructions

This repository owns environment-level operations for TerraHorse.

- Keep secrets, credentials, Cloudflare tunnel JSON, resolved environment files, and test artifacts outside Git.
- Do not change production DNS, tunnels, Saleor scopes, or cloud resources while working on E2E support.
- E2E resources must use the `terrahorse-e2e` / `e2e.terrahorse.lt` names and have an explicit, narrow rollback.
- Use small, reviewable scripts with preflight checks and fail closed on an unexpected target.
- Do not add Terraform, AWS, or production deployment structure unless a separately approved task requires it.
