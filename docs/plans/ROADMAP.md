# ATProto PDS Implementation Roadmap

## Current Status: Spec-Compliant & Verified (Feb 2026)

The project has successfully reached **Phase 10**, achieving full AT Protocol specification compliance with native implementation and comprehensive verification.

### Completed Milestones

#### Phase 0: Lock The Spec Source And Gates
- [x] Locked spec source (`SPEC_VERSION`)
- [x] CI gates for lexicon drift detection (`scripts/generate_xrpc_coverage_report.js`)
- [x] Conformance test entry point (`scripts/run_conformance.sh`)
- [x] Validated baseline: **901 passing tests**

#### Phase 1: Canonical Encodings (DAG-CBOR/CID)
- [x] `ATProtoDagCBOR` implementation (strict map ordering, float rejection)
- [x] CID-link encoding (tag 42)
- [x] `$link` and `$bytes` handling
- [x] Consolidated commit building (`RepoCommit` refactor)

#### Phase 2: subscribeRepos Compliance
- [x] `FirehoseCommitEvent` with all spec fields
- [x] Correct CAR v1 generation
- [x] Full event stream verification

#### Phase 3: Repo State & Sync
- [x] Commit chain semantics verification
- [x] `updateRepo` implementation with revisions
- [x] `com.atproto.sync.*` endpoint compliance

#### Phase 4: OAuth & Security
- [x] `GET /oauth/jwks` implementation
- [x] DPoP support (nonces, binding)
- [x] Protected resource metadata
- [x] JTI replay cache

#### Phase 5: Firehose Client Update
- [x] Spec-compliant `Firehose.m` (DAG-CBOR decoding)
- [x] Proper cursor handling (`seq`)

#### Phase 6: Verification & Fixes
- [x] Fixed binary path resolutions
- [x] Resolved Keychain access issues
- [x] Achieved 100% test pass rate (901/901)

#### Phase 7: Polish
- [x] Optimized MST rebuilds
- [x] Wipe-and-rebuild utilities

#### Phase 9: PLC Server Compliance
- [x] `PLCStore` protocol updates
- [x] `GET /export` and `GET /{did}/log/last`
- [x] `GET /{did}/data`

#### Phase 10: E2E Verification
- [x] Native integration test suite (`scripts/run_e2e.sh`)
- [x] Confirmed PDS+PLC interoperability

---

## Future Work & Improvements

### Phase 11: Production Hardening
- [ ] **Manual Client Review**: Verify with real Bluesky client (iOS/Web)
- [ ] **Performance Tuning**: Analyze MST rebuild performance (currently O(N) on writes)
- [ ] **Database Optimization**: Review SQLite indexing for scale

### Phase 12: Architecture Refinement
- [ ] **PDSController Refactor Completion**:
  - `PDSController.m` is evolving into a facade (~700 lines).
  - Continue extracting logic into `PDSApplication`, `PDSAdminController`, etc.
  - Target: `PDSController` < 200 lines (delegation only).
- [ ] **Service Isolation**: Ensure strict boundaries between Account, Repo, and Blob services.

### Phase 13: Advanced Features
- [ ] **Federation Expansion**: Enhanced relay integration
- [ ] **Moderation Tooling**: Admin UI for moderation actions
- [ ] **Backup & Restore**: User-facing export/import tools

---
*Last Updated: 2026-02-17*
