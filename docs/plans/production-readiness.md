---
title: Production Readiness Deep-Dive (2026-02-19)
---

# Production Readiness Deep-Dive (2026-02-19)

> **Status Cross-Check**: As of AGENTS.md, Phases 1-6 are documented. The P0/P1 blockers below remain open - none are marked resolved in the current project status. See AGENTS.md for latest completed milestones.

## Verdict

**No-Go** for internet-exposed personal selfhosters.

The codebase has materially improved on ATProto endpoint coverage and several previously reported protocol gaps, but new critical regressions and security/reliability defects still block production readiness.

## Audit Scope (Skills + Checks)

This pass used:
- `xrpc-schema-sync`
- `oauth-jwt-security-audit`
- `websocket-firehose-conformance`
- `objc-memory-audit`
- `objc-concurrency-bug-audit`
- `objc-locking-queue-audit`
- `objc-network-timeout-retry-audit`
- `objc-service-boundary-audit`
- `atproto-expert`

Primary generated artifacts:
- `/private/tmp/objpds_xrpc_coverage_20260219.md`
- `/private/tmp/objpds_oauth_audit_20260219/auth_hotspots.json`
- `/private/tmp/objpds_oauth_audit_20260219/jwt_claims.json`
- `/private/tmp/objpds_firehose_audit_20260219/firehose_events.json`
- `/private/tmp/objpds_firehose_audit_20260219/backpressure.json`
- `/private/tmp/objc-concurrency-audit-20260219/summary.md`
- `/private/tmp/objc-locking-queue-audit-20260219/summary.md`
- `/private/tmp/objc-network-timeout-retry-audit-20260219/summary.md`
- `/private/tmp/objc-service-boundary-audit-20260219/summary.md`

## Confirmed Improvements Since Prior Report

1. `com.atproto.*` in-scope endpoint coverage is now **100%** (`96/96`):
   - `reports/xrpc_coverage.md:13`
   - `reports/xrpc_coverage.md:25`
2. Refresh-token lifecycle is substantially improved:
   - Expiry enforced in lookup query: `Garazyk/Sources/Database/Service/ServiceDatabases.m:278`
   - Rotation + revocation in refresh path: `Garazyk/Sources/App/Services/PDSAccountService.m:323`
   - Refresh response returns both tokens: `Garazyk/Sources/App/Services/PDSAccountService.m:343`
3. `refreshSession` contract now uses bearer auth header (not JSON body):
   - `Garazyk/Sources/Network/XrpcMethodRegistry.m:3903`
   - Lexicon reference: `Garazyk/Resources/lexicons/com/atproto/server/refreshSession.json:7`
4. XRPC DPoP nonce challenge behavior exists:
   - `requireNonce:YES`: `Garazyk/Sources/Network/XrpcMethodRegistry.m:5284`
   - `DPoP-Nonce` header on challenge: `Garazyk/Sources/Network/XrpcMethodRegistry.m:5290`

## Current Blocking Findings

### P0 — Admin auth runtime regression (unimplemented selector)

**Impact:** Admin XRPC paths throw `unrecognized selector`, breaking privileged routes and risking process-level exceptions.

Evidence:
- Call site invokes 4-arg selector: `Garazyk/Sources/Network/XrpcMethodRegistry.m:85`
- 4-arg selector declared in header: `Garazyk/Sources/Network/XrpcMethodRegistry.h:65`
- Implemented method is 5-arg variant (`...request:response:`): `Garazyk/Sources/Network/XrpcMethodRegistry.m:5226`
- Broad admin surface depends on this helper: `Garazyk/Sources/Network/XrpcMethodRegistry.m:1719`

Test evidence:
- `AdminAuthXrpcTests`: 34/34 failed with `unrecognized selector`
- `AdminAuthApplicationXrpcTests`: 17 run, 2 skipped, 8 failed with same selector issue

### P1 — Password KDF input-length bug + reduced salt entropy

**Impact:** Non-ASCII passwords are truncated at PBKDF2 input length, creating unintended collisions and weaker credential handling.

Evidence:
- PBKDF2 uses UTF-8 pointer with UTF-16 length: `Garazyk/Sources/App/Services/PDSAccountService.m:402` and `Garazyk/Sources/App/Services/PDSAccountService.m:403`
- Salt buffer is 32 bytes but only first 16 bytes are populated from UUID bytes: `Garazyk/Sources/App/Services/PDSAccountService.m:388`

### P1 — Base64URL decode padding bug in auth primitives

**Impact:** Valid JWT/DPoP tokens can fail decoding for certain segment lengths, causing interoperability failures.

Evidence:
- Incorrect padding math in JWT decode: `Garazyk/Sources/Auth/JWT.m:210`
- Incorrect padding math in DPoP util decode: `Garazyk/Sources/Auth/DPoPUtil.m:354`

### P1 — Issuer/public URL consistency still broken

**Impact:** External identity metadata can publish localhost/http-derived values incompatible with production federation.

Evidence:
- HTTP server builder issuer hardcoded to localhost from app startup path: `Garazyk/Sources/App/PDSApplication.m:427`
- Builder fallback still defaults to localhost when issuer not supplied: `Garazyk/Sources/Network/PDSHttpServerBuilder.m:277`
- PLC endpoint fallback still permits plain `http://host:port`: `Garazyk/Sources/App/Services/PDSAccountService.m:470`

### P1 — Backup script does not match runtime DB naming

**Impact:** Backups may omit critical service DB state in real deployments.

Evidence:
- Backup script targets `service.sqlite`: `scripts/backup_pds.sh:88`
- Runtime DB path uses `service.db`: `Garazyk/Sources/Database/Pool/DatabasePool.m:63`

### P2 — WebSocket backpressure remains unbounded

**Impact:** Slow consumers can accumulate unbounded outbound queue memory under firehose load.

Evidence:
- Writes enqueue without byte/queue cap: `Garazyk/Sources/Sync/WebSocketConnection.m:401`
- Queue-bytes metric exists but is only observational (not enforced): `Garazyk/Sources/Sync/WebSocketConnection.m:421`

### P2 — Reliability tests still fail hard in restricted environments

Evidence:
- `CoverageGapTests` currently fail in restricted socket environments (port bind denied at setup path): `Garazyk/Tests/Services/CoverageGapTests.m:25`

## Targeted Test Snapshot (This Audit)

- `FirehoseConformanceTests`: 2/2 pass
- `EventFormatterTests`: 10/10 pass
- `OAuthConformanceTests`: 2/2 pass
- `ProductionSecurityTests`: 2/2 pass
- `AdminAuthXrpcTests`: 34/34 fail (selector regression)
- `AdminAuthApplicationXrpcTests`: 17 run, 2 skipped, 8 fail (selector regression)
- `CoverageGapTests`: 3 tests, 11 failures in restricted environment (socket bind denied)
- `SecurityHardeningTests`: 0 discovered in current `-XCTest` filter run (coverage gap in test targeting)

## Go/No-Go Criteria

Go-live requires all of the following:
1. P0 admin auth selector regression fixed and admin auth suites green.
2. Password derivation/salt defects fixed with migration-safe handling for existing credentials.
3. Base64URL decode defects fixed for JWT and DPoP paths.
4. Canonical production issuer/public URL used consistently across JWT, NodeInfo, and PLC outputs.
5. Backup tooling validated against current `service.db` + user DB layout.
6. WebSocket backpressure limits enforced and tested under slow-client scenarios.

Until these are complete: **No-Go**.

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
