---
title: Production Readiness Deep-Dive (2026-04-25 Re-Audit)
---

# Production Readiness Deep-Dive

> **Re-audited**: 2026-04-25 (original audit: 2026-02-19)
> **Test suite**: 2051 tests, 0 failures
> **Audit artifacts**: `/tmp/garazyk-security-audit-2026-04-25.md`, `/tmp/garazyk-concurrency-audit-2026-04-25.md`, `/tmp/garazyk-architecture-audit-2026-04-25.md`

## Verdict

**Conditional Go** for internet-exposed personal selfhosters.

All 6 original P0/P1/P2 blockers from the 2026-02-19 audit are **resolved**. The new re-audit found no critical security issues, but identified concurrency and architecture issues that should be addressed before trusting the server under sustained multi-client load.

The server is safe for **single-operator / low-traffic self-hosting** with the caveats below. It is **not yet ready** for high-traffic or multi-tenant deployments until the HIGH concurrency issues are resolved.

---

## Original Blockers — All Resolved

| # | Original Blocker | Status | Evidence |
|---|-----------------|--------|----------|
| 1 | P0: Admin auth selector regression | ✅ Fixed | `AdminAuthXrpcTests` all pass; 4-arg, 5-arg, controller variants all exist |
| 2 | P1: PBKDF2 password length bug | ✅ Fixed | `PDSAccountService.m:558` uses `passwordData.length` (UTF-8 byte length) |
| 3 | P1: Salt entropy (16/32 bytes) | ✅ Fixed | `generateSalt` uses 32-byte `NSMutableData` with `SecRandomCopyBytes` |
| 4 | P1: Base64URL decode padding | ✅ Fixed | `AuthCryptoBase64URL.m:31-34` handles `4 - remainder` correctly |
| 5 | P1: Issuer/public URL consistency | ✅ Fixed | `PDSApplication.m:600` uses `canonicalIssuerWithPortHint:self.httpPort`; CLI fix in `33710a03` |
| 6 | P1: Backup script DB naming | ✅ Fixed | `backup_pds.sh:89` targets `service.db` (matches runtime) |
| 7 | P2: WebSocket backpressure unbounded | ✅ Fixed | `WebSocketConnection.m:496-503` enforces 10MB cap, closes with 1009 |
| 8 | P2: Reliability tests in restricted envs | ✅ Fixed | `CoverageGapTests` now use `XCTSkip` for port bind failures |

---

## New Findings (2026-04-25 Re-Audit)

### CRITICAL — RecordLifecycleHandler deallocated immediately

**Impact:** AppView record-change side effects (notification generation, starter-pack indexing) never run because the handler is deallocated before it can process any events.

**Evidence:**
- `XrpcAppBskyMethods.m:101-118` — `RecordLifecycleHandler` stored in local `__attribute__((unused))` variable
- `RecordLifecycleHandler.m:45-61` — registers with NSNotificationCenter in init, removes in dealloc
- NSNotificationCenter does not retain observers → immediate dealloc → no side effects
- `localAppViewEnabled` defaults to YES, so this breaks the default AppView path

**Recommendation:** Store `RecordLifecycleHandler` in a strong property on a long-lived object (e.g., `PDSApplication` or `AppViewRuntime`).

---

### HIGH — WebSocket protocol session mutated from multiple queues

**Impact:** Inconsistent heartbeat timers, incorrect backpressure transitions, and hard-to-reproduce connection failures under load.

**Evidence:**
- `WebSocketConnection.m` — main queue calls `feedData:` and `tick:`
- Same `WebSocketProtocolSession` instance also accessed from `writeQueue` via `didEnqueueFrameOfSize:` and `didDequeueFrameOfSize:`
- Session mutates `heartbeatPolicy` and `isUnderBackpressure` from both queues

**Recommendation:** Route all session access through a single private queue; emit delegate notifications outward only.

---

### HIGH — Actor store eviction can close SQLite while transaction is active

**Impact:** Crash or data corruption if the pool evicts a store while a transaction is in progress on that store's serial queue.

**Evidence:**
- `DatabasePool.m` — `evictStoreForDidInternal:` and `closeAll` call `[store close]` directly
- `ActorStore.m` — serializes reads/writes on `transactionQueue`
- No coordination between pool eviction and store's transaction queue

**Recommendation:** Make store closure go through the store's own synchronization domain; block until transaction queue drains.

---

### HIGH — Placeholder XRPC endpoints return 200 OK with empty data

**Impact:** Clients receive successful responses that look real but contain no meaningful data. This is misleading and can break client assumptions.

**Evidence:**
- `app.bsky.actor.getSuggestions` — returns `{"actors": []}` (TODO marker)
- `searchStarterPacks`, `getStarterPack`, `getActorStarterPacks` — return empty/partial payloads
- `sendInteractions` — returns 200 OK with empty body
- `getListFeed` — returns `{"feed": []}` without query
- Multiple `app.bsky.unspecced.*` endpoints — return empty arrays/objects

**Recommendation:** Return `501 Not Implemented` for unfinished endpoints, or gate behind feature flags.

---

### HIGH — XRPC handlers bypass service boundaries with direct SQL

**Impact:** Architecture erosion — handlers own persistence logic, making testing harder and schema changes riskier.

**Evidence:**
- `XrpcAdminMethods.m:576-596` — uses `PDSActorStore` and raw `sqlite3_*` calls
- `XrpcVendorMethods.m:133-154` — constructs SQL and calls `sqlite3_*` directly
- `XrpcAppBskyGraphPack.m:671-675, 780-849` — raw SQL via `executeParameterizedQuery:`

**Recommendation:** Move these lookups into service-layer APIs; keep handlers thin.

---

### MEDIUM — Admin bearer token exposed to browser JavaScript

**Impact:** The `HttpOnly` cookie protection is undermined because the login response also returns the raw JWT in the JSON body, which the frontend stores in `sessionStorage`.

**Evidence:**
- `PDSAdminHandler.m:390-406` — returns `{"token": ...}` in login response body
- `app.js:98-102` — stores `data.token` in `sessionStorage`
- `admin-panel.js:45-47, 59-77` — persists and reuses token from `sessionStorage`

**Recommendation:** Move admin UI to cookie-only auth; stop returning token in JSON login body.

---

### MEDIUM — DPoP replay cache check is not atomic

**Impact:** Under concurrent requests, the same DPoP proof can be accepted twice.

**Evidence:**
- `PDSReplayCache.m:69-101` — read-then-write without mutex/transaction
- Used by `OAuth2.m:445-451` and `OAuth2Handler.m:1091-1104`

**Recommendation:** Use `BEGIN IMMEDIATE` + `INSERT OR IGNORE` or serialize with a dedicated queue.

---

### MEDIUM — Shared PDSDatabase used without explicit serialization boundary

**Impact:** Connection lifecycle races during shutdown or reconfiguration.

**Evidence:**
- `PDSDatabase.m` — exposes single SQLite connection via `executeQuery:` / `executeParameterizedUpdate:`
- No dedicated queue; `close` can race with in-flight queries
- Shared widely across subsystems

**Recommendation:** Add explicit serialization queue around connection lifecycle.

---

### LOW — Test teardown doesn't wait for async work

**Impact:** Flaky CI under load; can mask real race conditions.

**Evidence:**
- `SubscribeReposHandlerTests.m` — teardown removes temp dirs without waiting for async queues
- `WebSocketConnectionTests.m` — fixed delays instead of deterministic expectations

**Recommendation:** Replace timing-based waits with deterministic expectations; wait for queue drain in teardown.

---

## Test Suite Snapshot (2026-04-25)

- **Total**: 2051 tests, 0 failures
- `AdminAuthXrpcTests`: all pass (was 34/34 fail in Feb)
- `AdminAuthApplicationXrpcTests`: all pass (was 8 fail in Feb)
- `CoverageGapTests`: skip gracefully in restricted environments
- `SecurityHardeningTests`: 11 tests, discoverable and passing
- `ProductionSecurityTests`: 2/2 pass
- `FirehoseConformanceTests`: 2/2 pass
- `OAuthConformanceTests`: 2/2 pass

## Go/No-Go Criteria (Updated)

### Required for any internet-exposed deployment:
1. ✅ ~~P0 admin auth selector regression~~ — Fixed
2. ✅ ~~P1 password derivation/salt defects~~ — Fixed
3. ✅ ~~P1 Base64URL decode defects~~ — Fixed
4. ✅ ~~P1 canonical issuer/public URL~~ — Fixed
5. ✅ ~~P1 backup tooling~~ — Fixed
6. ✅ ~~P2 WebSocket backpressure~~ — Fixed

### Required for multi-tenant / high-traffic deployment:
7. 🔲 CRITICAL: Fix RecordLifecycleHandler retention
8. 🔲 HIGH: Fix WebSocket session queue ownership
9. 🔲 HIGH: Fix actor store eviction lifecycle
10. 🔲 MEDIUM: Make DPoP replay cache atomic

### Recommended for production hardening:
11. 🔲 HIGH: Replace placeholder 200 OK endpoints with 501 or real implementations
12. 🔲 HIGH: Move direct SQL out of XRPC handlers into service layer
13. 🔲 MEDIUM: Move admin UI to cookie-only auth
14. 🔲 MEDIUM: Add serialization boundary to PDSDatabase

## Related Documentation

- [Detailed Next Steps Plan](detailed_next_steps_plan) - Priority execution plan to clear blockers
- [Roadmap](ROADMAP) - Project milestones and completed phases
- [Security Documentation](../security/README) - Security analysis and hardening guides
- [OAuth2 Documentation](../oauth2/README) - Authentication and token management
- [P0 Security Hardening Plan](2026-02-18-p0-security-hardening) - Refresh token and DPoP implementation
- [Admin Auth Configuration](../security/ADMIN_AUTH_CONFIGURATION) - Admin authentication setup
- [DPoP Implementation](../oauth2/dpop) - DPoP proof verification details
- [Token Management](../oauth2/token-management) - JWT and refresh token lifecycle
- [Architecture Overview](../architecture/README) - System design patterns
