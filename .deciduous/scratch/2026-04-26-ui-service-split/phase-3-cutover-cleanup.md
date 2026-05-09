# Phase 3 - Cutover and Cleanup

Date: 2026-04-26

## Scope

- ASCII service roots.
- Legacy `/admin*` transition behavior.
- Final cleanup and test/docs alignment.

## Node Links

- Action node: 413
- Related decisions: 401, 403, 407

## Notes

- Enforced `text/plain; charset=utf-8` one-line service banners on:
  - PDS (`kaszlak 1.0.0`)
  - PLC (`campagnola 1.0.0`)
  - Relay (`zuk 1.0.0`)
  - AppView (`syrena 1.0.0`)
- Added legacy `/admin` and `/admin/*` redirects in service runtimes to preserve
  transition compatibility and path/query forwarding.
- Updated `PDSHttpServerBuilderTests` for new banner + redirect contract.
