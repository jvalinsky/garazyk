---
title: Objective-J UI Migration - Phase 1 Architecture Lock
---

# Objective-J UI Migration - Phase 1 Architecture Lock

## Purpose
Lock the route model, fallback behavior, and cutover strategy so Phase 2 implementation can proceed without routing/API-scope decisions.

## Locked Decisions
1. Backend API strategy is **reuse existing surfaces** (`/api/pds`, `/admin`, `/api/mst`, `/oauth-demo`, `/xrpc`, `/oauth/*`).
2. No new `/api/v2/ui` backend namespace is introduced in migration phases.
3. Objective-J app will be served from **`/ui` and `/ui/*`** during migration.
4. Legacy web UI remains default until final cutover.
5. Full parity gate is mandatory for cutover: Explore + Admin + MST Viewer + OAuth Demo.

## Current Route Baseline (As Implemented)
Source of truth: `Garazyk/Sources/Network/PDSHttpServerBuilder.m`.

- OAuth routes are registered first.
- XRPC routes are registered under `/xrpc`.
- Explore routes include `/api/pds/:endpoint` and static assets via wildcard fallback handler.
- OAuth demo routes are under `/oauth-demo` and `/oauth-demo/*`.
- MST viewer routes are under `/mst-viewer` and `/api/mst`.
- Admin API routes are under `/admin*`; admin static modules are under `/admin-ui/*`.
- Wildcard `GET /*` to `ExploreHandler` is registered last.

## Target Route Model for Phase 2+
The following model is locked for implementation:

1. Add explicit Objective-J static routes:
- `GET /ui`
- `GET /ui/*`

2. Keep existing routes unchanged during migration:
- `/api/pds/*`, `/admin*`, `/admin-ui/*`, `/api/mst/*`, `/mst-viewer*`, `/oauth-demo*`, `/xrpc/*`, `/oauth/*`, `/.well-known/*`.

3. Keep wildcard legacy fallback until cutover:
- `GET /*` remains mapped to `ExploreHandler` until final switch.

## Route Precedence Table (Locked)
| Precedence | Route family | Handler | Rationale |
|---|---|---|---|
| 1 | `/oauth/*` | `OAuth2Handler` | Auth protocol routes must remain deterministic and never depend on wildcard fallback. |
| 2 | `/xrpc*` | `XrpcDispatcher` + WebSocket handlers | Core ATProto API surface; must not be shadowed by UI routes. |
| 3 | `/api/pds/*` | `ExploreHandler` API branch | Existing Explore API consumers depend on this path. |
| 4 | `/api/mst/*` | `MSTViewerHandler` API branch | Existing MST clients depend on this path. |
| 5 | `/admin*` | `PDSAdminHandler` | Admin auth and admin API must remain isolated from UI shell routes. |
| 6 | `/admin-ui/*` | Static AdminUI assets | Dynamic import paths in legacy Explore UI depend on this exact route. |
| 7 | `/oauth-demo*` | `OAuthDemoHandler` | OAuth demo flow and callback path must remain explicit. |
| 8 | `/mst-viewer*` | `MSTViewerHandler` static assets | Standalone MST app remains functional during migration. |
| 9 | `/ui` + `/ui/*` | New Objective-J static handler | New migration target route; explicit and non-breaking. |
| 10 | `/*` | `ExploreHandler` fallback | Preserves legacy default UX until parity and cutover criteria are met. |

## Wildcard and Conflict Rules
1. `/ui/*` must be registered before `/*`.
2. `/ui/*` must not consume `/xrpc`, `/admin`, `/api/*`, `/oauth*`, `/mst-viewer*`, `/oauth-demo*`.
3. Existing `/css/*` and `/js/*` legacy paths stay owned by `ExploreHandler` until cutover.
4. Objective-J static paths are namespaced under `/ui/*` to avoid collisions with legacy root-relative assets.

## Fallback and Cutover Policy
1. Migration state (default):
- `/` continues to render legacy Explore shell via wildcard `ExploreHandler`.
- Objective-J UI is available at `/ui` for parity validation.

2. Cutover state (future, post-parity):
- `/` will route to Objective-J shell.
- Legacy Explore shell moves behind explicit legacy route or is removed after soak period.

3. Removal state (future):
- Legacy wildcard behavior and legacy web assets are removed only after full parity verification and soak criteria are met.

## Open Routing Conflicts
None. The `/ui` namespace is disjoint from current specific route families.

## Acceptance Checklist
1. Route precedence table exists and is explicit.
2. `/ui` integration rule is locked without replacing existing families.
3. Legacy default behavior is documented and preserved until cutover.
4. No unresolved path conflict remains for implementation handoff.

## Phase 1 Sign-off Record (Required Before Phase 2)
1. Architecture reviewer confirms no unresolved route/API namespace decisions remain.
2. UI migration implementer confirms parity/API/routing docs are sufficient to begin coding without clarification questions.
3. Sign-off is recorded in PR/thread with explicit statement: "Phase 1 lock accepted for Phase 2 implementation."
