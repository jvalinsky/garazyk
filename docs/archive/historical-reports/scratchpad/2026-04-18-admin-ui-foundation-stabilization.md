# Admin UI Foundation Stabilization (2026-04-18)

## Scope
- Normalize admin route/action handling through `PDSHttpAdminRoutePack` + `PDSAdminHandler`.
- Consolidate `/admin/partials/*` behavior around `AdminPartialHandler`.
- Preserve query semantics and deterministic route matching for admin actions.

## Decisions
- Route matching in `PDSAdminHandler` now uses a query-stripped `routePath` while preserving full request path for handlers that parse query params.
- `/admin/partials/*` remains centralized in `AdminPartialHandler`, with `AdminUIHandler` used as a shell/fallback path.

## Actions Implemented
- Route pack now forwards path + query into admin handler for all admin and partial routes.
- Added/normalized route coverage for wildcard and admin action paths.
- Reordered bulk user routes before generic `/admin/users/*` matching.

## Outcome
- Admin route dispatch is deterministic for query-bearing paths and wildcard user action paths.

## Linked Deciduous Nodes
- `468` goal: Stabilize admin foundation routing and partial dispatch
- `469` decision: How should admin handlers process query-bearing paths?
- `470` option (rejected): Route strictly on raw request path (including query string)
- `471` option (chosen): Route on normalized path while preserving full path for query-aware handlers
- `472` action: Forward query strings from route pack into admin handler
- `474` action: Normalize admin route matching and fallback flow
- `473` outcome: Admin foundation routes are deterministic for wildcard and query-bearing paths
