---
title: Objective-J UI Migration - Phase 1 Implementation Backlog
---

# Objective-J UI Migration - Phase 1 Implementation Backlog

## Backlog Goal
Provide implementation-ready Phase 2+ work packages with locked dependencies, acceptance criteria, and test expectations.

## Priority Order
1. `WP-01` Objective-J shell and route integration.
2. `WP-02` Explore parity (read workflows).
3. `WP-03` Explore auth + composer parity.
4. `WP-04` Admin parity.
5. `WP-05` MST parity.
6. `WP-06` OAuth demo parity.
7. `WP-07` CI/test hardening and cutover checks.

## Work Packages

### WP-01 - Objective-J Shell and Route Integration (P0)
**Subsystem:** Objective-J shell/routing

**Entry criteria**
- Phase 1 docs are merged.
- Contract IDs and parity matrix are available.

**Implementation tasks**
1. Add server routes for `GET /ui` and `GET /ui/*` to serve `CappuccinoUI` distribution assets.
2. Ensure `/ui/*` routes are registered before wildcard `/*` fallback.
3. Keep legacy `GET /` default on Explore while migration is in progress.
4. Refactor `UIAPIClient` base strategy to multi-endpoint adapters (no `/api/v2/ui` backend dependency).
5. Add a minimal Objective-J boot smoke path that confirms app shell render and tab host initialization.

**Dependencies**
- None (foundation package).

**Test expectations**
- Route tests: `/ui`, `/ui/index.html`, and static JS/CSS return correct status/content-type.
- Conflict tests: `/xrpc/*`, `/admin*`, `/api/pds/*`, `/api/mst/*`, `/oauth-demo*` unchanged.
- Smoke: Objective-J app boots without runtime exceptions.

**Done criteria**
- `/ui` is usable in dev/runtime.
- No route precedence regressions.
- Legacy `/` behavior unchanged.

---

### WP-02 - Explore Parity (Read Workflows) (P0)
**Subsystem:** Explore parity

**Entry criteria**
- `WP-01` complete.
- Endpoint adapters for `EXP-*` contracts available.

**Implementation tasks**
1. Implement Explore account browser: accounts load, DID/handle lookup, account selection.
2. Implement DID + PLC + collections parallel load flow using `EXP-03/04/05`.
3. Implement records browser and record detail rendering path with `$type`-based render modes.
4. Implement feed views (`posts/likes/reposts`) and graph/profile views.
5. Implement utility parity for CID decode and API docs navigation.
6. Implement local view-state transitions matching `LOCAL-01/02` contracts.

**Dependencies**
- `WP-01`.

**Test expectations**
- Integration tests for each `EXP-*` adapter mapping and error handling.
- UI tests for account select -> three-pane data load transition.
- UI tests for record list/detail and feed/profile toggles.

**Done criteria**
- Rows `E-00` through `E-23` (except auth/poster rows) reach `implemented` and pass target tests.

---

### WP-03 - Explore Auth and Composer Parity (P0)
**Subsystem:** Explore parity (auth/posting)

**Entry criteria**
- `WP-02` complete.
- Session adapter abstractions for `AUTH-*` available.

**Implementation tasks**
1. Implement login dialog + handle resolution status flow (`AUTH-01`).
2. Implement OAuth start and callback token exchange path (`AUTH-02/03`) with DPoP proof handling.
3. Implement session fetch for admin detection (`AUTH-04`) and session-driven menu state changes.
4. Implement poster flow: load recent posts, test session, create post with optional reply (`AUTH-06`, `AUTH-04`, `AUTH-05`).
5. Implement logout state reset and session cleanup behavior.

**Dependencies**
- `WP-02`.

**Test expectations**
- Adapter tests for OAuth/token/session/createRecord/listRecords.
- UI tests for login -> callback -> authenticated state transition.
- UI tests for post success/failure UX, including retry path.

**Done criteria**
- Rows `E-24` through `E-30` reach `implemented` and pass target tests.

---

### WP-04 - Admin Parity (P0)
**Subsystem:** Admin parity

**Entry criteria**
- `WP-01` complete.
- Admin adapter layer for `ADM-*` and admin XRPC contracts exists.

**Implementation tasks**
1. Implement admin login/token lifecycle and 401 re-auth behavior.
2. Implement unified admin panel tabs: overview, accounts, reports, system.
3. Implement account actions (enable/disable invites), report actions (resolve/dismiss), and audit preview/modal flows.
4. Implement invite management flows (list/create/disable).
5. Preserve legacy admin windows during migration window as fallback surface.

**Dependencies**
- `WP-01`; can proceed in parallel with `WP-02/03` once adapter layer is stable.

**Test expectations**
- API tests for all `ADM-*` and report/account moderation actions.
- UI tests for each tab load and major action path.
- Session-expiry tests (401 -> prompt/recovery).

**Done criteria**
- Rows `A-01` through `A-19` reach `implemented` and pass target tests.

---

### WP-05 - MST Parity (P1)
**Subsystem:** MST parity

**Entry criteria**
- `WP-01` complete.
- MST adapter contracts (`MST-*`) integrated.

**Implementation tasks**
1. Implement standalone MST page parity: account search/select, tree/list modes, stats panel.
2. Implement export actions for JSON/DOT/SVG contract behavior.
3. Implement zoom and local interaction parity.
4. Implement embedded MST utility parity in main Objective-J Explore shell.

**Dependencies**
- `WP-01`; can run in parallel with `WP-04`.

**Test expectations**
- API adapter tests for `MST-01..04` including invalid format path.
- UI tests for account selection, render mode switch, export triggers.

**Done criteria**
- Rows `M-01` through `M-06` and `E-21..E-23` reach `implemented` and pass target tests.

---

### WP-06 - OAuth Demo Parity (P1)
**Subsystem:** OAuth demo parity

**Entry criteria**
- `WP-03` complete (shared OAuth/token/DPoP primitives).

**Implementation tasks**
1. Implement standalone OAuth demo shell parity under `/oauth-demo`.
2. Implement callback exchange, session test, post creation, record listing, and logout flow.
3. Preserve debug log/status messaging behavior expected by existing operator workflows.

**Dependencies**
- `WP-03`.

**Test expectations**
- UI tests for login/callback/session/post/records/logout lifecycle.
- DPoP nonce retry path tests and token persistence behavior tests.

**Done criteria**
- Rows `O-01` through `O-07` reach `implemented` and pass target tests.

---

### WP-07 - CI, Verification, and Cutover Readiness (P0)
**Subsystem:** CI/test hardening + release gating

**Entry criteria**
- `WP-01` through `WP-06` at least `implemented`.

**Implementation tasks**
1. Add Objective-J build to CI as required check.
2. Add UI smoke tests covering Explore/Admin/MST/OAuth key flows.
3. Add parity-matrix test harness mapping each row to an automated/manual verification artifact.
4. Enforce cutover rule: all parity rows must be `verified` before default route switch.
5. Produce migration verification report with pass/fail per row ID.

**Dependencies**
- All prior work packages.

**Test expectations**
- CI green with Objective-J build and smoke suite.
- No route regressions for existing API families.
- Parity matrix row coverage report generated in CI artifacts.

**Done criteria**
- All rows in parity matrix reach `verified`.
- Cutover checklist complete and explicitly approved.

## Cross-Package Rules (Locked)
1. No package is allowed to introduce `/api/v2/ui` backend endpoints.
2. Backend shape changes require explicit backlog item and contract update.
3. Route precedence from `phase-1-architecture-lock.md` is non-negotiable.
4. Any discovered mismatch must be recorded against matrix row ID and contract ID.

## Verification Artifacts Required
1. Per-package test output or report.
2. Updated parity matrix status for affected rows.
3. Contract deltas (only if explicit backend change approved).
