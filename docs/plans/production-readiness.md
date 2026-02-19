# Production Readiness Re-Review (2026-02-19, Updated)

## Executive Summary

**Current verdict:** **NOT production-ready yet** for internet-exposed small selfhosters.

### What improved since prior pass
- Firehose schema fixes implemented:
  - Commit payload and event fields corrected in `ATProtoPDS/Sources/Sync/EventFormatter.m` at lines 19, 54, 67, and 81.
  - Publisher fields correctly set in `ATProtoPDS/Sources/Sync/SubscribeReposHandler.m` at lines 347 and 379.
- Core test suites are now passing:
  - `FirehoseConformanceTests`: 2/2 passed.
  - `EventFormatterTests`: 10/10 passed.
  - `AdminAuthXrpcTests`: 34/34 passed.
  - `AdminAuthApplicationXrpcTests`: 17 run, 0 failed, 2 skipped.
- Admin auth hardening remains active and verified.
- Account creation hardening remains active and verified.

### What still blocks production
- **Refresh-token security model is weak/incomplete**:
  - Expiry is ignored during token lookup: `ATProtoPDS/Sources/Database/Service/ServiceDatabases.m:275`.
  - Refresh does not rotate or revoke old tokens: `ATProtoPDS/Sources/App/Services/PDSAccountService.m:304`.
  - `refreshSession` returns only an access token: `ATProtoPDS/Sources/App/Services/PDSAccountService.m:333`.
- **XRPC DPoP nonce challenge flow remains incomplete**:
  - Requesting nonce (`requireNonce:YES`) but passing `nil`: `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m:5130`.
- **Lexicon mismatch in `refreshSession`**:
  - Expects `refreshToken` in body, violating lexicon: `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m:3790`.
- **Coverage Gap**: `com.atproto.*` coverage remains at 94.79% (5 missing) in `reports/xrpc_coverage.md`.
- **Public URL Consistency**: Localhost hardcoding in `PDSApplication.m:429` and HTTP fallback in `PDSAccountService.m:458` still break production flows.

---

## Scope and Evidence

### Commands executed in this re-review
- `./scripts/archive/stub_find.sh .`
- `node scripts/generate_xrpc_coverage_report.js --source-only --fail-on-duplicates --out-json /tmp/objpds_xrpc_coverage_20260218.json --out-md /tmp/objpds_xrpc_coverage_20260218.md`
- `node scripts/generate_xrpc_next_steps.js --coverage-path /tmp/objpds_xrpc_coverage_20260218.json --plan-path /tmp/objpds_xrpc_next_steps_20260218.md --issues-path /tmp/objpds_xrpc_issue_candidates_20260218.md --top 30`
- `./build/tests/AllTests -XCTest AdminAuthXrpcTests`
- `./build/tests/AllTests -XCTest AdminAuthApplicationXrpcTests`
- `./build/tests/AllTests -XCTest FirehoseConformanceTests`
- `./build/tests/AllTests -XCTest ProductionSecurityTests`
- `./build/tests/AllTests -XCTest OAuthConformanceTests`
- `./build/tests/AllTests -XCTest RepoAuthXrpcTests`
- `./build/tests/AllTests -XCTest CoverageGapTests` (sandbox-bounded; startup/bind failure + crash path observed)

### Snapshot results
- **XRPC coverage (`com.atproto.*`)**: 91/96 = **94.79%**
- **Missing endpoints**:
  - `com.atproto.admin.getAccountTakedown`
  - `com.atproto.identity.getRecommendedDidCredentials`
  - `com.atproto.identity.resolveHandle`
  - `com.atproto.identity.resolveIdentity`
  - `com.atproto.sync.notifyOfUpdate`
- Stub scan (server source): no actionable `TODO/FIXME/not implemented/stub` markers in `ATProtoPDS/Sources`.

---

## Blocking Findings (Must Fix Before Production)

### P0 — Refresh-token lifecycle security
**Impact:** Stolen refresh tokens can be used indefinitely; non-compliance with ATProto security specs.
Evidence:
- Token lookup ignores expiry: `ATProtoPDS/Sources/Database/Service/ServiceDatabases.m:275`.
- No rotation/revocation on use: `ATProtoPDS/Sources/App/Services/PDSAccountService.m:304`.
- Missing refresh token in refresh response: `ATProtoPDS/Sources/App/Services/PDSAccountService.m:333`.

### P0 — XRPC DPoP nonce flow incomplete
**Impact:** Standards-compliant nonce retry clients cannot access protected XRPC routes.
Evidence:
- XRPC auth path verifies DPoP with `requireNonce:YES` but passes `nonce:nil`: `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m:5130`.
- Challenge response headers are not yet implemented.

---

## High Priority Gaps

### P1 — `refreshSession` request/response contract mismatch

Evidence:
- Handler expects body `refreshToken`: `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m:3791`.
- Lexicon expects auth via refresh JWT and no input body:
  - `ATProtoPDS/Resources/lexicons/com/atproto/server/refreshSession.json:6`.

### P1 — Missing core `com.atproto.*` routes

Evidence:
- Coverage output (`/tmp/objpds_xrpc_coverage_20260218.md`) still reports 5 in-scope missing methods.
- Resolver family currently has `resolveDid` wired, but not `resolveHandle`/`resolveIdentity`:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m:5245`.
- Admin takedown route is still registered as `takeDownAccount`, not lexicon `getAccountTakedown`:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m:2688`.

### P1 — Public issuer/base URL consistency still incomplete

Evidence:
- Startup enforces `PDS_ISSUER` in production and sets minter issuer:
  - `ATProtoPDS/Sources/App/PDSApplication.m:230`
  - `ATProtoPDS/Sources/App/PDSApplication.m:233`
- But HTTP builder issuer is hardcoded to localhost:
  - `ATProtoPDS/Sources/App/PDSApplication.m:429`
  - `ATProtoPDS/Sources/Network/PDSHttpServerBuilder.m:277`
- PLC registration still falls back to `http://host:port`:
  - `ATProtoPDS/Sources/App/Services/PDSAccountService.m:458`.

---

## Operational Readiness Gaps

### P1 — Backup tooling/docs do not match runtime database layout
Evidence:
- Runtime layout uses `service/service.db`: `ATProtoPDS/Sources/Database/Pool/DatabasePool.m:63`.
- Backup script has duplicated body and incorrect pathing:
  - `scripts/backup_pds.sh:88`
  - `scripts/backup_pds.sh:165`
- Docs still reference legacy paths in `README.md` and `DEPLOYMENT.md`.

### P2 — Reliability and Crash Resilience
Evidence:
- `CoverageGapTests` crashes on nil-data path in restricted environments: `ATProtoPDS/Tests/Services/CoverageGapTests.m:192`.
- WebSocket connection/backpressure lifecycle needs tighter management.

---

## Environment-Specific Test Limitation (Still Needs Hardening)

- `CoverageGapTests` cannot bind sockets in this sandbox (`NSPOSIXErrorDomain Code=1`) and then crashes on nil JSON serialization path.
- Primary failure location:
  - `ATProtoPDS/Tests/Services/CoverageGapTests.m:25`.

This is environment-triggered, but test code should fail/skip gracefully rather than crash.

---

## Previously Blocking Items Now Closed

1. **Admin auth test drift**: fixed and green (with environment-specific socket skips only).
2. **Arbitrary DID injection in `createAccount`**: now rejected.
3. **Invite-only enforcement gap**: now enforced when config requires invites.
4. **JWKS endpoint availability**: `OAuthConformanceTests` `testJWKSResponse` passes.

---

## Updated Go/No-Go Criteria

### Must pass before go-live
1. **Refresh-token lifecycle**: Expiry enforcement, rotation, and revocation implemented.
2. **XRPC DPoP nonce challenge**: `DPoP-Nonce` header + retry semantics implemented and tested.
3. `refreshSession` aligns to lexicon contract (body and response).
4. Missing 5 `com.atproto.*` methods are implemented.
5. Backup script/docs matched to current `service.db` layout and de-duplicated.

### Should pass in same hardening window
1. Canonical issuer/public URL source is used across JWT, NodeInfo, and PLC endpoint generation.
2. Event retention policy is configurable and executed in runtime path.
3. Build artifacts and generated outputs are untracked/ignored consistently.

---

## Linked Plan

Implementation sequencing is updated in:
- `docs/plans/detailed_next_steps_plan.md`
