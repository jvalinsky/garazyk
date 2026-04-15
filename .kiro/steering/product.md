# Product Overview

September PDS is an Objective-C implementation of an AT Protocol Personal Data Server for macOS and Linux/GNUstep.

## Core Purpose

Provide a self-hosted PDS that exposes AT Protocol endpoints, maintains per-account repository state, and includes contributor tooling for inspecting and operating the runtime.

## Primary Runtime Surfaces

- `/xrpc/*` for protocol-facing XRPC methods
- `/api/pds/*` for contributor and operator inspection endpoints
- `/api/relay/*` for relay operations and health endpoints
- `/ui` for the Cappuccino-based browser UI
- `/metrics` for observability

## Primary Executables

- `kaszlak` - main PDS CLI and server binary
- `campagnola` - standalone PLC server
- `zuk` - standalone relay server
- `syrena` - standalone AppView server in the CMake build
- `AllTests` - shared Objective-C test runner

## Contributor Docs

The canonical contributor docs live under `docs/` and are published as a VitePress site. New contributors should start with `docs/index.md`, `docs/01-getting-started/setup.md`, and `docs/01-getting-started/codebase-map.md`. Documentation style and comment contracts are defined in `DOCUMENTATION.md`.
