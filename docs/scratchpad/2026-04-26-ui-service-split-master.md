# UI Service Split Master Scratchpad

Date: 2026-04-26

## Goal

Split UI and HTMX surfaces out of ATProto service binaries into a dedicated UI
server, while preserving protocol and metrics behaviors on backend services.

## Decision Nodes

- Goal node: 400
- Decision nodes:
  - 401 Use staged cutover for UI split
  - 402 Remove all service HTML and HTMX UI traces
  - 403 Enforce ASCII one-line service root response
  - 404 Track PDS PLC Relay AppView and chat logical indicators
  - 405 Use XRPC-first backend API policy
  - 406 Use UI-owned admin auth model
  - 407 Provide legacy /admin redirects during transition
  - 408 Use config-driven UI server host and port
  - 409 Deliver core-first phased parity
  - 410 Scope v1 to dashboard plus key operations

## Action Nodes

- Phase 1: 411
- Phase 2: 412
- Phase 3: 413
- Phase 4: 414

## Outcome

- Outcome node: 415

## Implemented Summary

- Added dedicated UI service binary:
  - `Garazyk/Binaries/garazyk-ui/main.m`
  - `Garazyk/Sources/AdminUIServer/*`
- Added HTMX admin shell + partial endpoints + UI-owned session auth.
- Added backend adapters that prefer XRPC calls for service health and key ops.
- Enforced service root banners on backend runtimes:
  - `kaszlak 1.0.0`
  - `campagnola 1.0.0`
  - `zuk 1.0.0`
  - `syrena 1.0.0`
- Added temporary legacy `/admin` and `/admin/*` redirect shims to UI server
  base URL (configurable via `PDS_UI_SERVER_URL`, default `http://127.0.0.1:2590`).
- Preserved service metrics routes.

## Verification

- Built targets: `kaszlak`, `campagnola`, `zuk`, `syrena`, `garazyk-ui`,
  `AllTests`.
- Ran focused tests:
  - `PDSHttpServerBuilderTests`
  - `PLCServerTests`
  - `PDSCLIServeCommandTests`
