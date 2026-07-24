---
title: Codebase Map
---

# Codebase Map

A tour of the Garazyk directory structure.

## Top Level

| Directory | Purpose |
|---|---|
| `Garazyk/` | Objective-C PDS server (sources, tests, Xcode project) |
| `Garazyk/Sources/` | Core server, Database, Network, Admin, Blob, Chat, AppView, Services |
| `Garazyk/Tests/` | Unit and integration tests (2,600+) |
| `Garazyk/docs-site/` | Astro-based documentation site |
| `packages/` | Deno/TypeScript packages (6 packages) |
| `scripts/` | Build scripts, scenario runner, doc tooling |
| `docs/` | Repository documentation (this tree) |
| `ops/` | Deployment configs (Caddy, nginx, systemd) |
| `docker/` | Dockerfiles for GNUstep and UI builds |
| `cmake/` | CMake toolchain files |
| `config/` | Production configuration and service files |
| `vendor/` | Vendored third-party code (secp256k1, reference impls) |

## Objective-C (`Garazyk/Sources/`)

| Directory | Responsibility |
|---|---|
| `Core/` | XRPC server, routing, auth, AT Protocol primitives |
| `Database/` | SQLite layer, actor store, connection pooling |
| `Network/` | HTTP server, WebSocket, sans-I/O networking |
| `Admin/` | AdminUI HTMX web interface |
| `AdminUIServer/` | AdminUI server and static assets |
| `Blob/` | Blob storage and serving |
| `Chat/` | Chat protocol support |
| `AppView/` | AppView indexing and query serving |
| `Services/` | PLC, relay, firehose services |

## Deno Packages (`packages/`)

| Package | Purpose |
|---|---|
| `gruszka/` | XRPC client generation from ATProto lexicons |
| `schemat/` | Topology schema, compilation, presets |
| `laweta/` | Docker Engine API client and orchestration |
| `hamownia/` | Scenario runner with assertions and mocks |
| `narzedzia/` | Developer tooling (boundary check, doc coverage) |
| `tui/` | Terminal UI framework (screen buffer, focus, theme) |

## Scripts (`scripts/`)

| Path | Purpose |
|---|---|
| `scripts/scenarios/` | Scenario definitions and authoring standards |
| `scripts/docs/` | Documentation tooling (coverage, repo index, link graph) |
| `scripts/plc/` | PLC test utilities |
| `scripts/build-all.sh` | Build ObjC binaries |

## Documentation (`docs/`)

See the [Documentation Hub](../index.md) for the full index.
