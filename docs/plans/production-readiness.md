# Production Readiness Re-Review (2026-02-18, Updated)

## Executive Summary

**Current verdict:** **NOT production-ready yet** for internet-exposed small selfhosters.

### What improved since prior pass
- Admin auth hardening landed in request path:
  - Prefix-based admin escalation is disabled in `ATProtoPDS/Sources/Security/PDSAuthzManager.m:168`.
  - Admin routes enforce `PDSAdminAuth` token checks in `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m:79`.
- Account creation hardening landed:
  - Arbitrary `did` input is rejected in `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m:3686`.
  - Invite code enforcement is now active when configured in `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m:3694`.
- Admin auth test suites now pass with real admin token flow:
  - `AdminAuthXrpcTests`: 34 passed, 0 failed.
  - `AdminAuthApplicationXrpcTests`: 17 executed, 0 failed, 2 skipped (socket unavailable in sandbox).

### What still blocks production
- Firehose frame encoding remains lexicon-nonconformant.
- `com.atproto.*` endpoint coverage is still **94.79%** (5 missing).
- XRPC DPoP nonce challenge flow is incomplete.
- `com.atproto.server.refreshSession` remains lexicon-mismatched.
- Backup/restore scripts and docs are still out of sync with actual on-disk DB layout.

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

### P0 — Firehose schema nonconformance

**Impact:** Strict consumers/relays can reject frames; interoperability and replay safety remain at risk.

Evidence:
- Commit encoder does not emit required `blocks`: `ATProtoPDS/Sources/Sync/EventFormatter.m:15`.
- `since` is only emitted when non-nil (required+nullable field): `ATProtoPDS/Sources/Sync/EventFormatter.m:26`.
- Identity event omits required `seq` and `time`: `ATProtoPDS/Sources/Sync/EventFormatter.m:54`.
- Account event omits required `seq`: `ATProtoPDS/Sources/Sync/EventFormatter.m:65`.
- Info event uses `info` key instead of required `name`: `ATProtoPDS/Sources/Sync/EventFormatter.m:84`.
- Conformance test still fails: `ATProtoPDS/Tests/Sync/FirehoseConformanceTests.m:101`.

### P0 — XRPC DPoP nonce flow incomplete

**Impact:** Standards-compliant nonce retry clients can fail on protected XRPC routes.

Evidence:
- XRPC auth path verifies DPoP with `requireNonce:YES` but passes `nonce:nil`:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m:5130`
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m:5133`
- Failure path returns `nil DID` only; no `DPoP-Nonce` response header is emitted in XRPC layer.
- OAuth DPoP verifier explicitly supports `use_dpop_nonce` semantics: `ATProtoPDS/Sources/Auth/OAuth2.m:808`.

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
- Runtime layout uses `service/service.db` plus DID-keyed user DB files:
  - `ATProtoPDS/Sources/Database/Service/ServiceDatabases.m:105`
  - `ATProtoPDS/Sources/Database/Pool/DatabasePool.m:63`
- Backup script still targets `service.sqlite` and `data.sqlite`, and is duplicated in the same file:
  - `scripts/backup_pds.sh:88`
  - `scripts/backup_pds.sh:116`
  - duplicate second script body starts at `scripts/backup_pds.sh:165`.
- Docs still reference legacy paths:
  - `README.md:435`
  - `docs/guides/DEPLOYMENT.md:91`.

### P2 — Event retention primitive not wired into runtime policy

Evidence:
- Prune method exists: `ATProtoPDS/Sources/Database/Service/ServiceDatabases.m:904`.
- No runtime caller currently invokes it in sync/event flow.

### P2 — Script/repo hygiene

Evidence:
- Default start script still points at legacy binary path:
  - `scripts/start_server.sh:17`.
- Build artifacts remain tracked (`build-dd/*`) and are not ignored by `.gitignore`.

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
1. Firehose encoder fully matches `subscribeRepos` lexicon for `#commit/#identity/#account/#info`.
2. XRPC DPoP nonce challenge/retry behavior is implemented and test-covered.
3. `refreshSession` aligns to lexicon contract.
4. Missing 5 `com.atproto.*` methods are implemented (or explicitly policy-excluded).
5. Backup script/docs are corrected and validated via restore drill.

### Should pass in same hardening window
1. Canonical issuer/public URL source is used across JWT, NodeInfo, and PLC endpoint generation.
2. Event retention policy is configurable and executed in runtime path.
3. Build artifacts and generated outputs are untracked/ignored consistently.

---

## Linked Plan

Implementation sequencing is updated in:
- `docs/plans/detailed_next_steps_plan.md`
