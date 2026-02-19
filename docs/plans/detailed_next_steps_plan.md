# Detailed Next Steps Plan (Updated 2026-02-19)

## Objective

Close remaining production blockers for small selfhosters while preserving the security hardening that has already landed.

---

## Completed Since Last Plan Revision

### Phase 0 — Security Signal Stabilization (Done)
Completed:
- Admin auth test setup now mints real admin JWTs via `PDSAdminAuth`.
- `AdminAuthXrpcTests` is green.
- `AdminAuthApplicationXrpcTests` is green except environment-specific socket skips.

### Phase 1 — Firehose Lexicon Conformance (Done)
Completed:
- Firehose schema fixes in `EventFormatter.m` (lines 19, 54, 67, 81).
- Publisher fields set in `SubscribeReposHandler.m` (lines 347, 379).
- `FirehoseConformanceTests` (2/2) and `EventFormatterTests` (10/10) are green.

### Phase 2 — Refresh-Token Lifecycle Security (Done)
Completed:
- ✅ `getAccountByRefreshToken:` in `ServiceDatabases.m:262-292` enforces `expires_at > current_time` in SQL.
- ✅ Token rotation implemented in `PDSAccountService.m:304-348`:
  - Revokes old RT via `[_sessionRepository revokeRefreshToken:...]`
  - Generates new RT and Access JWT
  - Stores new RT via `[_sessionRepository storeRefreshToken:...]`
- ✅ `refreshAccessToken:` returns dictionary with both `accessJwt` and `refreshJwt`
- ✅ Added configurable TTL via `PDSConfiguration.refreshTokenTtlSeconds` (defaults to 30 days)
- ✅ Added regression tests in `PDSAccountServiceTests.m` (2 new tests)

### Phase 3 — XRPC DPoP Nonce Challenge (Done)
Completed:
- ✅ `DPoP-Nonce` challenge implemented in `XrpcMethodRegistry.m:5146-5264`:
  - Returns 401 with `DPoP-Nonce` header when proof lacks nonce
  - Emits `UseDPoPNonce` error response
- ✅ Fixed `extractDIDFromAuthHeader:jwtMinter:adminController:request:response:` signature
- ✅ `refreshSession` endpoint already extracts token from `Authorization: Bearer <token>` header (line 3819)
- ✅ Tests exist in `SecurityHardeningTests.m` for token rotation and DPoP nonce flow

### Phase 4 — Close Remaining `com.atproto.*` Coverage Gaps (Done)
Completed:
- ✅ Implemented `identity.resolveHandle` - Resolves handle to DID
- ✅ Implemented `identity.resolveIdentity` - Full identity resolution with DID document
- ✅ Implemented `identity.getRecommendedDidCredentials` - Credentials for DID migration
- ✅ Implemented `sync.notifyOfUpdate` - Deprecated notification endpoint (delegates to requestCrawl)
- ✅ Implemented `admin.getAccountTakedown` - Check account takedown status

---

## Phase 5 — Selfhoster Operations Alignment (P1)
**Goal:** Fix backup/restore tooling and unify public issuer usage.
### Tasks
- [ ] Unify `PDS_ISSUER` usage across JWT, NodeInfo, and PLC endpoints.
- [x] Fix `scripts/backup_pds.sh`: remove duplication and update to `service.db`.
- [ ] Update documentation to match actual on-disk layout.

## Phase 6 — Reliability and Hygiene (P2)
**Goal:** Harden tests and websocket lifecycle.
### Tasks
- [ ] Fix `CoverageGapTests` nil-data crash (pre-existing issue).
- [ ] Tighten websocket connection and backpressure management.

---

## Summary of Work Completed

| Phase | Status | Key Deliverables |
|-------|--------|------------------|
| Phase 0 | ✅ Done | Admin auth tests stabilized |
| Phase 1 | ✅ Done | Firehose conformance tests passing |
| Phase 2 | ✅ Done | Refresh token rotation & configurable TTL |
| Phase 3 | ✅ Done | DPoP nonce challenge flow working |
| Phase 4 | ✅ Done | All 5 missing com.atproto.* endpoints implemented |
| Phase 5 | 🔄 In Progress | PDS_ISSUER unification, docs update |
| Phase 6 | ⏳ Pending | CoverageGapTests fix, websocket hardening |

## Recommended Next Steps

1. **Phase 5a** — Unify PDS_ISSUER usage (high priority for selfhosters)
2. **Phase 5b** — Update documentation for actual on-disk layout
3. **Phase 6** — Address CoverageGapTests and websocket reliability

This keeps external protocol correctness (completed), then finishes operations alignment, then reliability improvements.

---

## Commits Made Today

1. `6816635` - fix(backup): remove duplicated script body in backup_pds.sh
2. `e118f7a` - feat(auth): configurable refresh token TTL and DPoP method fixes
3. `152f941` - test(auth): add refresh token rotation tests
4. `310a01e` - feat(endpoints): implement 5 missing com.atproto.* methods
