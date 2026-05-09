# Phase 2 - Service UI Removal

Date: 2026-04-26

## Scope

- Remove service-side Admin/Explore/HTMX/static UI traces.
- Keep metrics APIs.
- Keep protocol/XRPC behavior.

## Node Links

- Action node: 412
- Related decisions: 402, 405, 407

## Notes

- `PDSHttpServerBuilder` no longer registers explore/admin UI route packs.
- `PDSHttpServerBuilder` no longer wires design-system static UI routes.
- `AppViewRuntime` no longer registers `AppViewAdminRoutePack`.
- `PLCServer` setup no longer registers `/static`, `/index.html`, `/css/*`,
  `/js/*` routes.
- Service binaries now avoid serving admin HTML surfaces directly.
