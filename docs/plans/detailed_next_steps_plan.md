---
title: Detailed Next Steps Plan (2026-04-25 Re-Audit Revision)
---

# Detailed Next Steps Plan (2026-04-25 Re-Audit Revision)

## Objective

Clear the remaining production blockers for internet-exposed personal selfhosters after the 2026-04-25 re-audit.

## Baseline (Now)

All original P0/P1/P2 blockers from the 2026-02-19 audit are **resolved**:
- ✅ Admin auth selector regression fixed; all admin auth suites green
- ✅ PBKDF2 uses UTF-8 byte length; 32-byte salt fully populated
- ✅ Base64URL decode padding correct
- ✅ Issuer/public URL derived from `canonicalIssuerWithPortHint:`
- ✅ Backup script targets `service.db` (matches runtime)
- ✅ WebSocket backpressure: 10MB cap, close code 1009
- ✅ CoverageGapTests skip gracefully; SecurityHardeningTests discoverable

New findings from 2026-04-25 re-audit require attention before high-traffic deployment.

## Priority Execution Plan

### P0 — Fix RecordLifecycleHandler retention (CRITICAL)

The handler is created and immediately discarded, breaking all AppView side effects.

1. Store `RecordLifecycleHandler` in a strong property on `PDSApplication` or `AppViewRuntime`.
2. Ensure it lives for the entire AppView subsystem lifetime.
3. Add regression test: create a record, verify notification is generated.
4. Verify starter-pack indexing fires after the fix.

**Files:** `XrpcAppBskyMethods.m:101-118`, `RecordLifecycleHandler.m:45-61`

### P1 — Fix WebSocket session queue ownership (HIGH)

WebSocket protocol session is mutated from both main queue and write queue.

1. Route all `WebSocketProtocolSession` access through a single private queue.
2. Emit delegate notifications outward from that queue.
3. Add test that verifies heartbeat/backpressure state consistency under concurrent send/receive.

**Files:** `WebSocketConnection.m`, `WebSocketProtocolSession.m`

### P1 — Fix actor store eviction lifecycle (HIGH)

Pool can close a store while a transaction is active on its serial queue.

1. Make `close` go through the store's `transactionQueue`.
2. Block until the queue drains before closing the SQLite connection.
3. Consider reference counting or lease model for stores in active use.
4. Add test: open transaction, trigger eviction, verify no crash.

**Files:** `DatabasePool.m`, `ActorStore.m`

### P1 — Replace placeholder 200 OK endpoints with 501 (HIGH)

Multiple endpoints return success with empty data, misleading clients.

1. Audit all XRPC packs for `TODO`/stub markers.
2. Return `501 Not Implemented` for unfinished endpoints.
3. Gate truly experimental endpoints behind feature flags.
4. Document which endpoints are live vs stubbed.

**Files:** `XrpcAppBskyActorPack.m`, `XrpcAppBskyGraphPack.m`, `XrpcAppBskyFeedPack.m`, `XrpcAppBskyUnspeccedPack.m`

### P2 — Move direct SQL out of XRPC handlers (HIGH, architecture)

Several handlers bypass service boundaries with raw SQL.

1. Extract `XrpcAdminMethods.m:576-596` SQL into `AdminService`.
2. Extract `XrpcVendorMethods.m:133-154` SQL into `VendorService`.
3. Extract `XrpcAppBskyGraphPack.m:671-849` SQL into `GraphService`.
4. Keep handlers as thin request/response adapters.

**Files:** `XrpcAdminMethods.m`, `XrpcVendorMethods.m`, `XrpcAppBskyGraphPack.m`

### P2 — Move admin UI to cookie-only auth (MEDIUM, security)

Admin bearer token is exposed to browser JavaScript via `sessionStorage`.

1. Stop returning `{"token": ...}` in login response body.
2. Frontend reads auth status from cookie presence (or a `/admin/session` endpoint).
3. Remove `sessionStorage` token storage from `app.js` and `admin-panel.js`.
4. Keep `Authorization: Bearer` header support for API-only clients.

**Files:** `PDSAdminHandler.m`, `app.js`, `admin-panel.js`

### P2 — Make DPoP replay cache atomic (MEDIUM, security)

Read-then-write pattern allows concurrent replays.

1. Use `BEGIN IMMEDIATE` + `INSERT OR IGNORE` in `PDSReplayCache`.
2. Or serialize with a dedicated dispatch queue.
3. Add concurrency test: two simultaneous validations of same JTI.

**Files:** `PDSReplayCache.m`, `OAuth2.m`, `OAuth2Handler.m`

### P2 — Add serialization boundary to PDSDatabase (MEDIUM, concurrency)

Shared database connection used without explicit queue.

1. Add a serial dispatch queue to `PDSDatabase`.
2. Serialize `open`, `executeQuery:`, `executeParameterizedUpdate:`, and `close`.
3. Ensure `close` waits for in-flight queries to complete.

**Files:** `PDSDatabase.m`

### P3 — Improve test teardown determinism (LOW)

Several tests use fixed delays instead of deterministic synchronization.

1. Replace `dispatch_after` waits with delegate-expectation patterns.
2. Make teardown wait for background queues to drain.
3. Add explicit queue-drain points in `SubscribeReposHandlerTests`.

**Files:** `SubscribeReposHandlerTests.m`, `WebSocketConnectionTests.m`

## Exit Criteria

### For single-operator self-hosting (current):
- ✅ All original P0/P1/P2 blockers resolved
- ✅ 2051 tests pass, 0 failures
- ✅ No critical security issues

### For multi-tenant / high-traffic deployment:
1. 🔲 RecordLifecycleHandler retained for AppView lifetime
2. 🔲 WebSocket session has single queue owner
3. 🔲 Actor store eviction coordinated with transaction queue
4. 🔲 DPoP replay cache is atomic
5. 🔲 Placeholder endpoints return 501 or are fully implemented

## Deployment Decision

**Conditional Go** for single-operator self-hosting.
**No-Go** for multi-tenant / high-traffic until P0 and P1 items above are resolved.

## Related Documentation

- [Production Readiness](production-readiness) - Full audit findings and evidence
- [Roadmap](ROADMAP) - Project milestones and future work
- [Security Hardening](../security/README) - Security analysis and hardening guides
- [OAuth2 Documentation](../oauth2/README) - Token management and DPoP implementation
- [Admin Auth Configuration](../security/ADMIN_AUTH_CONFIGURATION) - Admin authentication setup
- [DPoP Implementation](../oauth2/dpop) - DPoP proof verification details
- [Architecture Overview](../architecture/README) - System design decisions
