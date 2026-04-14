---
title: Objective-J Service Ops UI - Phase 2 Implementation Backlog
---

# Objective-J Service Ops UI - Phase 2 Implementation Backlog

## Backlog Goal
Convert the reviewed findings and service split strategy into implementation-ready tickets for:
- PDS ops app
- Relay ops app
- AppView ops app
- PLC ops app

The backlog is dependency-locked and decision-complete for execution.

## Critical Findings Addressed
1. Relay upstream URL canonicalization mismatch (`wss://` double-prefix risk).
2. Explorer UI depends on `/api/pds` while Explore route pack can be disabled.
3. Admin route list includes endpoints without handler implementation.
4. Admin APIs serialize errors but still return HTTP 200.
5. AppView status endpoint requires bearer auth, but dashboard status load is unauthenticated.

## Execution Order
1. Stabilize API contracts and auth behavior.
2. Resolve route capability mismatches and URL canonicalization.
3. Extract service-specific apps.
4. Run service-by-service verification and cutover.

---

## Ticket Index

| ID | Priority | Owner | Title | Depends On |
|---|---|---|---|---|
| `OPS-001` | P1 | Backend-PDS | Fix admin HTTP status propagation | None |
| `OPS-002` | P2 | Backend-PDS | Align admin route list with handler support | `OPS-001` |
| `OPS-003` | P1 | Backend-AppView + Frontend-Ops | Fix AppView status auth flow | None |
| `OPS-004` | P1 | Backend-Relay + Frontend-Ops | Canonicalize relay upstream URL format | None |
| `OPS-005` | P2 | Backend-PDS + Frontend-Ops | Make Explorer tab conditional on route capability | None |
| `OPS-006` | P1 | Security + Backend | Define per-service auth/session contract | `OPS-001`, `OPS-003` |
| `OPS-007` | P1 | Frontend-Ops | Shared ops shell for separate service apps | `OPS-006` |
| `OPS-008` | P1 | Frontend-Ops + Backend-PDS | Extract `pds-ops` app | `OPS-007` |
| `OPS-009` | P1 | Frontend-Ops + Backend-Relay | Extract `relay-ops` app | `OPS-004`, `OPS-007` |
| `OPS-010` | P1 | Frontend-Ops + Backend-AppView | Extract `appview-ops` app | `OPS-003`, `OPS-007` |
| `OPS-011` | P2 | Frontend-Ops + Backend-PLC | Extract `plc-ops` app | `OPS-006`, `OPS-007` |
| `OPS-012` | P1 | QA + SRE | Contract, e2e, and cutover verification | `OPS-008`..`OPS-011` |

---

## Ticket Details

### OPS-001 - Fix Admin HTTP Status Propagation
**Priority:** P1  
**Owner:** Backend-PDS

**Problem**
Admin endpoints currently return logical error bodies with transport status `200`, which breaks UI error semantics and monitoring.

**File touchpoints**
- `Garazyk/Sources/Network/PDSHttpAdminRoutePack.m`
- `Garazyk/Sources/Admin/PDSAdminHandler.m`
- `Garazyk/Tests/Admin/*` (new/update)

**Implementation tasks**
1. Change admin handler contract to return both status and payload (instead of string-only body).
2. Set `HttpResponse.statusCode` from handler result, not hardcoded `200`.
3. Remove raw HTTP string formatting from `textResponseWithStatus:` or route it through proper response object handling.
4. Preserve JSON body schema for existing clients.

**Acceptance checks**
1. Invalid token returns transport `401` with error JSON body.
2. Handler-level failures return `4xx/5xx`, not `200`.
3. Existing successful paths still return `200`.
4. New regression tests validate status/body pairs for `/admin/login`, `/admin/users`, `/admin/stats`.

---

### OPS-002 - Align Admin Route List With Handler Support
**Priority:** P2  
**Owner:** Backend-PDS

**Problem**
Routes include `/admin/capabilities` and `/admin/audit/receipts` without corresponding handler branches.

**File touchpoints**
- `Garazyk/Sources/Network/PDSHttpAdminRoutePack.m`
- `Garazyk/Sources/Admin/PDSAdminHandler.m`
- `Garazyk/Sources/Services/PDS/PDSAdminService.m` (if receipt lookup is implemented)

**Implementation tasks**
1. Choose one path per endpoint: implement now or remove from route pack.
2. If implementing:
   1. Add explicit handler branches and stable response schemas.
   2. Add authorization behavior consistent with other admin endpoints.
3. Publish endpoint capability in API docs used by ops UI.

**Acceptance checks**
1. No registered admin route returns framework-level 404 due to missing handler branch.
2. `/admin/capabilities` returns schema used by frontend feature gating.
3. `/admin/audit/receipts` either works end-to-end or is not registered.

---

### OPS-003 - Fix AppView Status Auth Flow
**Priority:** P1  
**Owner:** Backend-AppView + Frontend-Ops

**Problem**
Dashboard status polling is unauthenticated while backend requires bearer auth.

**File touchpoints**
- `Garazyk/Sources/App/CappuccinoUI/AppViewBackfillController.j`
- `Garazyk/Sources/AppView/Server/Admin/AppViewAdminRoutePack.m`
- `Garazyk/Sources/App/CappuccinoUI/SessionState.j`

**Implementation tasks**
1. Add authenticated status request path in frontend (Authorization header support for status fetch).
2. Normalize AppView admin token/session handling in one client utility path.
3. Add explicit unauthorized UX state (no noisy retry loop).
4. Add optional short-lived session endpoint (recommended) to reduce raw token copy/paste usage.

**Acceptance checks**
1. With valid credentials, status panel refresh succeeds and renders metrics.
2. Without credentials, UI shows actionable auth prompt and does not spin with repeated generic errors.
3. `401` and network failures are visually distinct in status messaging.

---

### OPS-004 - Canonicalize Relay Upstream URL Format
**Priority:** P1  
**Owner:** Backend-Relay + Frontend-Ops

**Problem**
UI/API allow full `ws(s)://` URLs while upstream manager assumes host-like values in websocket URL construction.

**File touchpoints**
- `Garazyk/Sources/Sync/Relay/RelayUpstreamManager.m`
- `Garazyk/Sources/Sync/Relay/RelayAPIHandler.m`
- `Garazyk/Sources/App/CappuccinoUI/RelayUpstreamsController.j`
- `Garazyk/Sources/Sync/Relay/RelayConfiguration.m`

**Implementation tasks**
1. Define one canonical persisted format (`wss://host[:port]` recommended).
2. Normalize inbound values in API handler before storing.
3. Update upstream manager connection builder to consume canonical format directly.
4. Update UI validation and help text to match canonical format.
5. Backfill existing stored/configured upstream values on startup.

**Acceptance checks**
1. Adding `wss://example.com` connects successfully.
2. Adding `example.com` either normalizes correctly or is rejected with clear error.
3. No generated websocket URL contains duplicated scheme.
4. Reconnect/disconnect/remove actions work for normalized entries.

---

### OPS-005 - Explorer Tab and Route Capability Alignment
**Priority:** P2  
**Owner:** Backend-PDS + Frontend-Ops

**Problem**
Explorer tab assumes `/api/pds` availability while Explore route registration is togglable.

**File touchpoints**
- `Garazyk/Sources/Network/PDSHttpServerBuilder.m`
- `Garazyk/Sources/Network/PDSHttpExploreRoutePack.m`
- `Garazyk/Sources/App/CappuccinoUI/AppController.j`
- `Garazyk/Sources/App/CappuccinoUI/UIAPIClient.j`

**Implementation tasks**
1. Expose runtime capability payload for enabled UI/API surfaces.
2. Gate Explorer tab render and navigation by backend capability.
3. Choose and document default behavior:
   1. Enable Explore routes by default when Explorer UI is enabled.
   2. Or keep disabled and hide Explorer tab.

**Acceptance checks**
1. Explorer tab is never shown if `/api/pds/*` routes are unavailable.
2. If Explorer tab is shown, all core Explorer requests return non-404 expected responses.
3. Startup logs clearly indicate Explore capability state.

---

### OPS-006 - Per-Service Auth/Session Contract
**Priority:** P1  
**Owner:** Security + Backend

**Problem**
Service auth patterns differ and are not consistently consumable by separate internet-exposed ops apps.

**File touchpoints**
- `Garazyk/Sources/Admin/PDSAdminAuth.m`
- `Garazyk/Sources/AppView/Server/Admin/AppViewAdminRoutePack.m`
- `Garazyk/Sources/PLC/PLCServer.m`
- `Garazyk/Sources/Sync/Relay/RelayAPIHandler.m` (if auth added/expanded)

**Implementation tasks**
1. Define common auth expectations for ops apps:
   1. token issuance/login,
   2. request auth header behavior,
   3. token TTL/expiry semantics,
   4. unauthorized error schema.
2. Add missing middleware paths for services not currently aligned.
3. Add rate-limit/lockout behavior for login endpoints.

**Acceptance checks**
1. Each service app has documented, tested auth behavior.
2. Unauthorized responses are consistent enough for shared frontend handling.
3. Session expiry and re-auth flows pass e2e checks.

---

### OPS-007 - Shared Ops Shell for Separate Apps
**Priority:** P1  
**Owner:** Frontend-Ops

**Problem**
Four separate apps need consistent operator ergonomics and navigation while remaining independently deployable.

**File touchpoints**
- `Garazyk/Sources/App/CappuccinoUI/*` (new shared shell modules)
- `Garazyk/Sources/App/CappuccinoUI/UIAPIClient.j`
- `Garazyk/Sources/App/CappuccinoUI/SessionState.j`

**Implementation tasks**
1. Extract shared components: top bar, environment badge, session status, error banner, action confirmation modal.
2. Standardize status line and audit receipt rendering components.
3. Add shared client wrappers for pagination, error envelope parsing, and request-id display.

**Acceptance checks**
1. All service apps use shared shell components.
2. Error states look and behave consistently across apps.
3. High-risk action modal behavior is uniform.

---

### OPS-008 - Extract `pds-ops` App
**Priority:** P1  
**Owner:** Frontend-Ops + Backend-PDS

**File touchpoints**
- `Garazyk/Sources/App/CappuccinoUI/AdminController.j`
- `Garazyk/Sources/App/CappuccinoUI/ExplorerController.j`
- `Garazyk/Sources/App/CappuccinoUI/MSTController.j`
- `Garazyk/Sources/Network/PDSHttpCappuccinoUIRoutePack.m` (routing split)

**Implementation tasks**
1. Split PDS sub-tabs into dedicated app entrypoint and route.
2. Keep account/admin/moderation/investigate workflows intact.
3. Integrate guarded write confirmations and audit receipt surfaces.

**Acceptance checks**
1. `pds-ops` supports existing operator workflows without dependency on other service tabs.
2. Route-level smoke tests pass for new app path/subdomain mapping.

---

### OPS-009 - Extract `relay-ops` App
**Priority:** P1  
**Owner:** Frontend-Ops + Backend-Relay

**File touchpoints**
- `Garazyk/Sources/App/CappuccinoUI/RelayDashboardController.j`
- `Garazyk/Sources/App/CappuccinoUI/RelayUpstreamsController.j`
- `Garazyk/Sources/App/CappuccinoUI/RelayEventsController.j`
- `Garazyk/Sources/Network/PDSHttpRelayAPIRoutePack.m`

**Implementation tasks**
1. Create standalone relay shell with dashboard/upstreams/events.
2. Add capability-driven feature gating for mutate actions.
3. Add high-risk bulk action guardrails (typed confirmation for reconnect-all/disconnect-all).

**Acceptance checks**
1. All upstream lifecycle actions work from standalone app.
2. Events stream and metrics remain stable under reconnect churn.

---

### OPS-010 - Extract `appview-ops` App
**Priority:** P1  
**Owner:** Frontend-Ops + Backend-AppView

**File touchpoints**
- `Garazyk/Sources/App/CappuccinoUI/AppViewBackfillController.j`
- `Garazyk/Sources/AppView/Server/Admin/AppViewAdminRoutePack.m`
- `Garazyk/Sources/AppView/Server/AppViewRuntime.m`

**Implementation tasks**
1. Create standalone appview shell for backfill and ingest operations.
2. Integrate authenticated status, enqueue, and scope rebuild workflows.
3. Add queue triage views (pending/processing/failed) and batch-safe controls.

**Acceptance checks**
1. Authenticated status panel, enqueue, and rebuild all work in app.
2. Unauthorized and degraded ingest states are clearly distinguished.

---

### OPS-011 - Extract `plc-ops` App
**Priority:** P2  
**Owner:** Frontend-Ops + Backend-PLC

**File touchpoints**
- `Garazyk/Sources/App/CappuccinoUI/PLCDirectoryController.j`
- `Garazyk/Sources/App/CappuccinoUI/PLCDetailController.j`
- `Garazyk/Sources/App/CappuccinoUI/PLCTimelineController.j`
- `Garazyk/Sources/App/CappuccinoUI/PLCMetricsController.j`
- `Garazyk/Sources/PLC/PLCServer.m`

**Implementation tasks**
1. Create standalone PLC app for directory/detail/timeline/metrics.
2. Keep write/admin endpoints behind auth and add explicit high-risk confirmations.
3. Ensure public endpoints remain intentional and documented for internet exposure.

**Acceptance checks**
1. Read workflows function without requiring mixed-service shell.
2. Admin-only operations are protected by auth checks.
3. Security tests confirm no sensitive admin path exposure without auth.

---

### OPS-012 - Verification and Cutover Gates
**Priority:** P1  
**Owner:** QA + SRE

**File touchpoints**
- `Garazyk/Tests/*` (new contract + e2e coverage)
- `docs/plans/objective-j-ui/phase-1-parity-matrix.md` (status tracking updates)
- CI workflow files (`.github/workflows/*`) as needed

**Implementation tasks**
1. Add contract tests for status codes, auth errors, and capabilities payloads.
2. Add e2e tests for critical operator paths in each app.
3. Add cutover checklist proving each app can run independently.
4. Add rollback procedure for app routing/subdomain cutover.

**Acceptance checks**
1. CI passes with new contract/e2e suites.
2. Cutover checklist signed off with no P1/P2 open defects.
3. Rollback plan verified in staging.

---

## Definition of Done (Backlog-Level)
1. All `P1` tickets complete and verified in CI/staging.
2. Each service app is independently usable for core operator workflows.
3. Auth + status code + capabilities contracts are stable and documented.
4. Remaining `P2` items are either complete or explicitly deferred with risk owner and target date.

