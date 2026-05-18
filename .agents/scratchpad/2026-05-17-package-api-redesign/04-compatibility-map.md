# Compatibility Map

Date: 2026-05-17

## Laweta

- Old: `import { startLocalNetwork } from "@garazyk/laweta"`
- New: `import { startLocalNetwork } from "@garazyk/hamownia/atproto-network"`

- Old: `import { initRunDir, neededPorts, serviceUrl } from "@garazyk/laweta"`
- New: `import { initRunDir, neededPorts, serviceUrl } from "@garazyk/laweta/atproto-runtime"`

Generic Docker imports remain on `@garazyk/laweta`.

## Gruszka

- Old: `import { AccountsClient } from "@garazyk/gruszka"`
- New: `import { AccountsClient } from "@garazyk/gruszka/legacy-clients"`

- Old: full generated types from root
- New: full generated types from `@garazyk/gruszka/lexicons`

- Root `GeneratedClient`, `QueryParams`, `QueryOutput`, `ProcedureInput`, and `ProcedureOutput` are documentation-safe proxy aliases. Use `@garazyk/gruszka/lexicons` when exact generated method shapes are required.

Primary client imports remain on `@garazyk/gruszka`.

## Schemat

- Old: `import { initRunDir, repoRoot, serviceUrl, neededPorts } from "@garazyk/schemat"`
- New: `import { initRunDir, repoRoot, serviceUrl, neededPorts } from "@garazyk/schemat/runtime"`

Pure topology and schema imports remain on `@garazyk/schemat`.

## Hamownia

- Old: `import { PDS1, SERVICE_URLS } from "@garazyk/hamownia"`
- New: `import { PDS1, SERVICE_URLS } from "@garazyk/hamownia/config"`

- Old: runner/orchestration helpers from root
- New: explicit subpaths such as `@garazyk/hamownia/run-loop`, `@garazyk/hamownia/diagnostics`, `@garazyk/hamownia/otel`, and `@garazyk/hamownia/mock-twilio`

Scenario authoring imports remain on `@garazyk/hamownia`.
