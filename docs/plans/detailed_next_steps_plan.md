# Detailed Next Steps Plan (Post Re-Review, 2026-02-18)

## Objective

Close production blockers for small selfhosters in the shortest safe sequence, then move to broader architecture cleanup.

---

## Phase 0 — Stabilize Security Test Signal (P0)

**Goal:** Make admin auth suites reflect the current admin JWT model.

### Tasks
- [ ] Update `AdminAuthXrpcTests` to mint/use admin-scope JWTs instead of account `accessJwt`.
- [ ] Update `AdminAuthApplicationXrpcTests` similarly.
- [ ] Keep existing negative coverage for issuer/audience/scope mismatch.

### Acceptance Criteria
- [ ] `AdminAuthXrpcTests` passes without bulk 403 regressions.
- [ ] `AdminAuthApplicationXrpcTests` admin-success paths use valid admin token flow.

### Evidence Targets
- `ATProtoPDS/Tests/Network/AdminAuthXrpcTests.m`
- `ATProtoPDS/Tests/Network/AdminAuthApplicationXrpcTests.m`
- `ATProtoPDS/Sources/Admin/PDSAdminAuth.m`

---

## Phase 1 — Firehose Conformance Fix (P0)

**Goal:** Make stream frames lexicon-conformant and pass conformance tests.

### Tasks
- [ ] `EventFormatter`: include `blocks` in commit payload.
- [ ] `EventFormatter`: always emit `since` key (nullable behavior).
- [ ] `EventFormatter`: identity payload emits `seq`, `did`, `time` (+ optional `handle`).
- [ ] `EventFormatter`: account payload emits required `seq`, `did`, `time`, `active`.
- [ ] `EventFormatter`: info payload uses `name` (not `info`).
- [ ] `SubscribeReposHandler`: populate required fields for identity/account/info events before encoding.

### Acceptance Criteria
- [ ] `FirehoseConformanceTests` green.
- [ ] Replay/backfill still works for existing persisted events.

### Evidence Targets
- `ATProtoPDS/Sources/Sync/EventFormatter.m`
- `ATProtoPDS/Sources/Sync/SubscribeReposHandler.m`
- `ATProtoPDS/Tests/Sync/FirehoseConformanceTests.m`
- `ATProtoPDS/Resources/lexicons/com/atproto/sync/subscribeRepos.json`

---

## Phase 2 — Close Remaining Core XRPC Gaps (P1)

**Goal:** Reach 100% `com.atproto.*` endpoint registration coverage for current in-scope set.

### Tasks
- [ ] Implement `com.atproto.identity.resolveHandle`.
- [ ] Implement `com.atproto.identity.resolveIdentity`.
- [ ] Implement `com.atproto.identity.getRecommendedDidCredentials`.
- [ ] Implement `com.atproto.sync.notifyOfUpdate` (or explicit no-op/deprecation response per policy).
- [ ] Implement/register `com.atproto.admin.getAccountTakedown`.
- [ ] Keep compatibility route strategy explicit for `takeDownAccount` naming drift.

### Acceptance Criteria
- [ ] Coverage report shows 0 missing in-scope methods for `com.atproto.*`.
- [ ] Add/adjust tests for each new endpoint path.

### Evidence Targets
- `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
- `ATProtoPDS/Resources/lexicons/com/atproto/**`
- `/tmp/objpds_xrpc_coverage_*.md`

---

## Phase 3 — OAuth/Session Protocol Correctness (P1)

**Goal:** Remove known auth interop gaps before external client onboarding.

### Tasks
- [ ] Align `com.atproto.server.refreshSession` request handling to refresh JWT auth semantics.
- [ ] Implement XRPC DPoP nonce challenge behavior (`DPoP-Nonce` on nonce-required failures).
- [ ] Add tests for nonce-required + retry-with-nonce success flow.

### Acceptance Criteria
- [ ] Refresh flow matches lexicon contract.
- [ ] DPoP nonce dance is test-covered and deterministic.

### Evidence Targets
- `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
- `ATProtoPDS/Sources/Auth/OAuth2.m`
- `ATProtoPDS/Resources/lexicons/com/atproto/server/refreshSession.json`

---

## Phase 4 — Public URL and Issuer Consistency (P1)

**Goal:** Ensure one canonical external identity/issuer source across auth and identity outputs.

### Tasks
- [ ] Use `config.issuer`/`PDS_ISSUER` consistently for JWT mint/verify.
- [ ] Remove localhost fallback from runtime builder path when issuer is configured.
- [ ] Update PLC service endpoint defaults to HTTPS/public issuer semantics.

### Acceptance Criteria
- [ ] Issuer values are consistent in JWT claims, NodeInfo, and identity service descriptors.

### Evidence Targets
- `ATProtoPDS/Sources/App/PDSApplication.m`
- `ATProtoPDS/Sources/Network/PDSHttpServerBuilder.m`
- `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`

---

## Phase 5 — Operations Hardening for Selfhosters (P1)

**Goal:** Ensure backup/restore and startup docs/scripts match current runtime layout.

### Tasks
- [ ] Fix `scripts/backup_pds.sh` duplicated body and stale DB filenames.
- [ ] Update backup restore instructions in `README.md`.
- [ ] Update deployment backup examples in `docs/guides/DEPLOYMENT.md`.
- [ ] Update `scripts/start_server.sh` default binary (`atprotopds-cli` vs `september`) or document explicit override.

### Acceptance Criteria
- [ ] Backup script dry-run works against real local data layout.
- [ ] Restore doc steps match actual database file locations.

### Evidence Targets
- `scripts/backup_pds.sh`
- `README.md`
- `docs/guides/DEPLOYMENT.md`
- `scripts/start_server.sh`

---

## Phase 6 — Hygiene and Reliability (P2)

**Goal:** Remove avoidable operational noise and reduce long-run failure risk.

### Tasks
- [ ] Remove tracked build/test artifacts (`build-dd`, `test_output*.txt`).
- [ ] Extend `.gitignore` to prevent recurrence.
- [ ] Add graceful test skip/failure handling when network bind is unavailable (for sandbox/CI portability).
- [ ] Wire optional firehose event retention policy to config (if enabled).

### Acceptance Criteria
- [ ] Clean repo status without generated artifacts.
- [ ] Test suites do not crash on environment network restrictions.

### Evidence Targets
- `.gitignore`
- `ATProtoPDS/Tests/Services/CoverageGapTests.m`
- `ATProtoPDS/Sources/Database/Service/ServiceDatabases.m`

---

## Recommended Execution Order

1. Phase 0 (test signal)
2. Phase 1 (firehose conformance)
3. Phase 2 (endpoint coverage closure)
4. Phase 3 (auth protocol correctness)
5. Phase 4 (issuer/public URL consistency)
6. Phase 5 (operations/scripts/docs)
7. Phase 6 (hygiene/reliability)

This order minimizes risk by first restoring trustworthy security/conformance signal, then closing external interoperability blockers, then polishing operations.
