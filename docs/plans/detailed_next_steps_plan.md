# Detailed Next Steps Plan (Updated 2026-02-18)

## Objective

Close remaining production blockers for small selfhosters while preserving the security hardening that has already landed.

---

## Completed Since Last Plan Revision

### Phase 0 — Security Signal Stabilization (Done)

Completed:
- Admin auth test setup now mints real admin JWTs via `PDSAdminAuth`.
- `AdminAuthXrpcTests` is green.
- `AdminAuthApplicationXrpcTests` is green except environment-specific socket skips.

Evidence:
- `ATProtoPDS/Tests/Network/AdminAuthXrpcTests.m`
- `ATProtoPDS/Tests/Network/AdminAuthApplicationXrpcTests.m`

---

## Phase 1 — Firehose Lexicon Conformance (P0)

**Goal:** Make emitted `subscribeRepos` frames strictly conformant.

### Tasks
- [ ] Add required `blocks` to commit payload emission in `EventFormatter`.
- [ ] Always emit `since` key for commits (nullable semantics).
- [ ] Emit required `seq/time` for identity/account events.
- [ ] Rename info payload key from `info` to `name`.
- [ ] Ensure `SubscribeReposHandler` populates all required fields before encoding.

### Acceptance Criteria
- [ ] `./build/tests/AllTests -XCTest FirehoseConformanceTests` passes.
- [ ] Replay/backfill behavior remains functional (no regressions in subscribe flow).

### Evidence Targets
- `ATProtoPDS/Sources/Sync/EventFormatter.m`
- `ATProtoPDS/Sources/Sync/SubscribeReposHandler.m`
- `ATProtoPDS/Tests/Sync/FirehoseConformanceTests.m`

---

## Phase 2 — XRPC OAuth/Session Protocol Correctness (P0/P1)

**Goal:** Fix interoperability gaps for standards-compliant OAuth clients.

### Tasks
- [ ] Implement XRPC DPoP nonce challenge handling with `DPoP-Nonce` response header.
- [ ] Thread nonce issuance/validation through XRPC auth path (not just OAuth token endpoint).
- [ ] Align `com.atproto.server.refreshSession` with lexicon (refresh JWT auth, no body `refreshToken` dependency).
- [ ] Add focused tests for nonce retry dance and refreshSession contract.

### Acceptance Criteria
- [ ] DPoP nonce-required failure returns recoverable challenge semantics.
- [ ] Refresh session request/response is lexicon-compliant.

### Evidence Targets
- `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
- `ATProtoPDS/Sources/Auth/OAuth2.m`
- `ATProtoPDS/Resources/lexicons/com/atproto/server/refreshSession.json`

---

## Phase 3 — Close Remaining `com.atproto.*` Coverage Gaps (P1)

**Goal:** Raise in-scope coverage from 94.79% to 100%.

### Tasks
- [ ] Implement/register `com.atproto.identity.resolveHandle`.
- [ ] Implement/register `com.atproto.identity.resolveIdentity`.
- [ ] Implement/register `com.atproto.identity.getRecommendedDidCredentials`.
- [ ] Implement/register `com.atproto.sync.notifyOfUpdate`.
- [ ] Implement/register `com.atproto.admin.getAccountTakedown`.

### Acceptance Criteria
- [ ] Coverage report shows 0 in-scope missing endpoints.
- [ ] New endpoints have happy/error-path tests.

### Evidence Targets
- `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
- `/tmp/objpds_xrpc_coverage_*.md`

---

## Phase 4 — Selfhoster Operations Alignment (P1)

**Goal:** Make backup/restore/startup workflows match real runtime layout.

### Tasks
- [ ] Remove duplicated second body in `scripts/backup_pds.sh`.
- [ ] Update backup script to actual DB paths (`service/service.db`, DID-keyed user DB files).
- [ ] Update restore instructions in `README.md` and `docs/guides/DEPLOYMENT.md`.
- [ ] Update `scripts/start_server.sh` default binary to current executable.

### Acceptance Criteria
- [ ] Backup script succeeds on real local layout.
- [ ] Restore docs are executable as written.

### Evidence Targets
- `scripts/backup_pds.sh`
- `README.md`
- `docs/guides/DEPLOYMENT.md`
- `scripts/start_server.sh`

---

## Phase 5 — Issuer/Public URL Consistency (P1)

**Goal:** Ensure one canonical public issuer/base URL across outputs and metadata.

### Tasks
- [ ] Use configured issuer for builder/nodeinfo instead of localhost fallback.
- [ ] Remove `http://host:port` fallback for PLC endpoint when issuer exists.
- [ ] Ensure any service-auth audience derivation uses public issuer host semantics.

### Acceptance Criteria
- [ ] JWT issuer, NodeInfo issuer, and PLC endpoint resolve to same public origin.

### Evidence Targets
- `ATProtoPDS/Sources/App/PDSApplication.m`
- `ATProtoPDS/Sources/Network/PDSHttpServerBuilder.m`
- `ATProtoPDS/Sources/App/Services/PDSAccountService.m`
- `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`

---

## Phase 6 — Reliability and Hygiene (P2)

**Goal:** Reduce avoidable operational/test noise.

### Tasks
- [ ] Harden network-dependent tests to skip/fail gracefully when bind is unavailable (avoid crash).
- [ ] Remove tracked generated artifacts (for example `build-dd/*`) and add ignore coverage.
- [ ] Wire event retention (`pruneEventsBefore`) to a configurable runtime policy.

### Acceptance Criteria
- [ ] `CoverageGapTests` no longer crashes in restricted environments.
- [ ] Repository stays clean after normal build/test loops.
- [ ] Event storage growth can be bounded by configuration.

### Evidence Targets
- `ATProtoPDS/Tests/Services/CoverageGapTests.m`
- `.gitignore`
- `ATProtoPDS/Sources/Database/Service/ServiceDatabases.m`
- `ATProtoPDS/Sources/Sync/SubscribeReposHandler.m`

---

## Recommended Execution Order

1. Phase 1 — Firehose conformance
2. Phase 2 — OAuth/session correctness
3. Phase 3 — Endpoint coverage closure
4. Phase 4 — Ops/script/doc alignment
5. Phase 5 — Issuer consistency cleanup
6. Phase 6 — Reliability/hygiene

This keeps external protocol correctness first, then closes remaining interoperability and operability gaps.
