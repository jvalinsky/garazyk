# Production Readiness Re-Review (2026-02-18)

## Executive Summary

**Current verdict:** **NOT production-ready** for internet-exposed small selfhosters.

What is strong:
- Core build works (`xcodebuild -scheme AllTests ...` succeeded).
- Core auth/repo suites still pass (`ProductionSecurityTests`, `OAuthConformanceTests`, `RepoAuthXrpcTests`).
- XRPC coverage is high at **94.79%** for `com.atproto.*` scope.

What blocks production:
- Firehose encoding is not lexicon-conformant.
- Admin XRPC test suites are red due auth model drift.
- 5 `com.atproto.*` endpoints are still missing.
- XRPC DPoP nonce flow is incomplete for standards-compliant clients.
- Operational scripts/docs still reference old DB/binary layout.

---

## Scope and Evidence

### Commands executed
- `node scripts/generate_xrpc_coverage_report.js --source-only --fail-on-duplicates ...`
- `node scripts/generate_xrpc_next_steps.js --coverage-path ...`
- `/Users/jack/.codex/skills/atproto-endpoint-stub-finder/scripts/run_all.sh ...`
- `/Users/jack/.codex/skills/oauth-jwt-security-audit/scripts/run_all.sh ...`
- `/Users/jack/.codex/skills/websocket-firehose-conformance/scripts/run_all.sh ...`
- `xcodebuild build -scheme AllTests -destination 'platform=macOS,arch=arm64' -derivedDataPath ./build-dd`
- Targeted test runs for `ProductionSecurityTests`, `OAuthConformanceTests`, `RepoAuthXrpcTests`, `FirehoseConformanceTests`, `AdminAuthXrpcTests`, `AdminAuthApplicationXrpcTests`, `CoverageGapTests`

### Snapshot results
- **XRPC coverage (`com.atproto.*`)**: 91/96 = **94.79%**
- **Missing endpoints**:
  - `com.atproto.admin.getAccountTakedown`
  - `com.atproto.identity.getRecommendedDidCredentials`
  - `com.atproto.identity.resolveHandle`
  - `com.atproto.identity.resolveIdentity`
  - `com.atproto.sync.notifyOfUpdate`
- Stub scan (`not_implemented`, `TODO/FIXME`): **0 critical markers** in source scan output

---

## Blocking Findings (Must Fix Before Production)

### P0 — Firehose event schema drift

**Impact:** Relay consumers and strict clients can reject stream frames.

Evidence:
- `ATProtoPDS/Sources/Sync/EventFormatter.m:15` does not emit commit `blocks` even though lexicon requires it.
- `ATProtoPDS/Sources/Sync/EventFormatter.m:26` only emits `since` when non-nil, but field is required+nullable.
- `ATProtoPDS/Sources/Sync/EventFormatter.m:54` identity payload omits required `seq` + `time`.
- `ATProtoPDS/Sources/Sync/EventFormatter.m:84` info payload uses `info` instead of required `name`.
- Lexicon contract: `ATProtoPDS/Resources/lexicons/com/atproto/sync/subscribeRepos.json:31`.
- Failing test: `ATProtoPDS/Tests/Sync/FirehoseConformanceTests.m:101`.

### P0 — Admin auth test suites no longer validate current security model

**Impact:** CI signal is unreliable; admin path regressions are harder to detect confidently.

Evidence:
- Tests seed `adminJwt` from normal account access token:
  - `ATProtoPDS/Tests/Network/AdminAuthXrpcTests.m:44`
  - `ATProtoPDS/Tests/Network/AdminAuthApplicationXrpcTests.m:50`
- Production admin auth now requires `scope=admin`:
  - `ATProtoPDS/Sources/Admin/PDSAdminAuth.m:243`
- Expected admin claims during mint:
  - `ATProtoPDS/Sources/Admin/PDSAdminAuth.m:391`
- Result: large 403 failure sets in admin success-path tests.

---

## High Priority Gaps (Fix Next)

### P1 — Missing `com.atproto.*` endpoint coverage

Evidence:
- Coverage report identifies 5 missing in-scope methods (see list above).
- Registration scan shows only `resolveDid` implemented among resolver family:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m:5245`
- Admin method typo/mismatch also contributes:
  - registered `com.atproto.admin.takeDownAccount` at `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m:2688`
  - missing lexicon method `com.atproto.admin.getAccountTakedown`.

### P1 — XRPC DPoP nonce challenge flow is incomplete

Evidence:
- XRPC verifier requires nonce but passes `nonce:nil`:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m:5130`
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m:5134`
- OAuth DPoP verifier expects nonce contract (`use_dpop_nonce` path):
  - `ATProtoPDS/Sources/Auth/OAuth2.m:810`
- No `DPoP-Nonce` response handling found in network layer for XRPC failures.

### P1 — `refreshSession` shape does not match lexicon contract

Evidence:
- Handler reads `refreshToken` from JSON body:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m:3791`
- Lexicon expects auth via refresh JWT and defines no input body:
  - `ATProtoPDS/Resources/lexicons/com/atproto/server/refreshSession.json:6`

### P1 — Issuer/public URL consistency risk

Evidence:
- JWT minter issuer defaults to env-only fallback:
  - `ATProtoPDS/Sources/App/PDSApplication.m:233`
- HTTP builder issuer hardcoded to localhost URL:
  - `ATProtoPDS/Sources/App/PDSApplication.m:429`
- PLC service endpoint default uses `http://host:port`:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m:1587`

---

## Operational Readiness Gaps

### P1 — Backup/docs mismatch with current DB layout

Evidence:
- Actual layout uses `service/service.db` and DID-keyed user DB files:
  - `ATProtoPDS/Sources/Database/Service/ServiceDatabases.m:105`
  - `ATProtoPDS/Sources/Database/Pool/DatabasePool.m:63`
- Backup script still targets `service.sqlite` and `data.sqlite`, and contains duplicated script blocks:
  - `scripts/backup_pds.sh:88`
  - `scripts/backup_pds.sh:116`
  - duplicate second script body starts at `scripts/backup_pds.sh:165`
- Docs still reference old paths:
  - `README.md:435`
  - `docs/guides/DEPLOYMENT.md:91`

### P2 — Firehose retention not operationalized

Evidence:
- Retention primitive exists:
  - `ATProtoPDS/Sources/Database/Service/ServiceDatabases.m:904`
- No caller wiring found in runtime path (only declaration/implementation references).

### P2 — Repository hygiene

Evidence:
- Tracked build artifacts and test outputs are present (`build-dd/*`, `test_output*.txt`).
- `.gitignore` does not currently exclude these classes:
  - `.gitignore:1`

---

## Environment-Specific Test Limitation (Not a Product Bug by itself)

- `CoverageGapTests` and two socket-stream tests fail/skip in this sandbox due bind/start restriction (`NSPOSIXErrorDomain Code=1 Operation not permitted`), then crash from nil JSON handling.
- Relevant failure points:
  - `ATProtoPDS/Tests/Services/CoverageGapTests.m:25`
  - `ATProtoPDS/Tests/Network/AdminAuthApplicationXrpcTests.m:945`
  - `ATProtoPDS/Tests/Network/AdminAuthApplicationXrpcTests.m:1014`

This should still be hardened so tests fail gracefully when networking is unavailable.

---

## Production Go/No-Go Criteria

### Must pass before go-live
1. Firehose encoder is lexicon-conformant for `commit`, `identity`, `account`, `info`.
2. Admin auth tests are updated to mint real admin-scope JWTs and pass.
3. Missing 5 `com.atproto.*` endpoints are implemented or explicitly marked out-of-scope with policy.
4. XRPC DPoP nonce challenge/response flow is standards-compliant.
5. `refreshSession` request handling aligns with lexicon.
6. Backup script + docs match actual database paths and are validated in restore drill.

### Should pass in the same hardening window
1. Issuer/public URL logic uses one canonical source (`config.issuer`/`PDS_ISSUER`) everywhere.
2. Firehose replay retention policy is configurable and enforced.
3. Build/test artifacts are removed from version control and ignored going forward.

---

## Linked Plan

Implementation sequencing is updated in:
- `docs/plans/detailed_next_steps_plan.md`
