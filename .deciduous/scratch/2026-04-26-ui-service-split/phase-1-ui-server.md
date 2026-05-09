# Phase 1 - UI Server

Date: 2026-04-26

## Scope

- New dedicated UI server binary.
- HTMX shell and partial APIs.
- Backend adapter clients and service indicator lights.

## Node Links

- Action node: 411
- Related decisions: 401, 404, 405, 406, 408, 409, 410

## Notes

- Implemented `garazyk-ui` dedicated binary and startup command handling.
- Added `UIServiceConfig` for env-driven host/port and backend service URLs.
- Added `UIAuthManager` for cookie/bearer-backed admin sessions.
- Added `UIBackendClient` XRPC-first probes and key PDS admin operations.
- Added `UIServerRuntime` routes:
  - `/admin/login`, `/admin/logout`, `/admin`
  - `/admin/partials/overview`, `/admin/partials/accounts`,
    `/admin/partials/invites`
  - `/admin/actions/disable-invites`
- Added service indicator lights and periodic HTMX refresh in shell UI.
