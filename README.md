# TerraHorse Infrastructure

This repository owns environment-level TerraHorse operations. Its first scoped capability is the non-production E2E boundary at `e2e.terrahorse.lt`.

Changes require a reviewed pull request. Scripts must be idempotent, must not print secret values, and must document their precise resources and rollback scope.

Application runtime contracts remain in the sibling `terrahorse-web` repository.
