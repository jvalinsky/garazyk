---
title: ATProto PDS Implementation Roadmap
---

# ATProto PDS Implementation Roadmap

> **Phase Numbering Note**: This document uses phases 0-10, while `AGENTS.md` uses phases 1-6. 
> The mapping is approximately: Phase 0-6 here ≈ Phase 1-4 in AGENTS.md. 
> AGENTS.md Phase 5 (Linux Support) and Phase 6 (Professional Script Development) were added after Phase 10 here was completed.

## Current Status: Spec-Compliant & Verified (Feb 2026)

The project has reached **Phase 10**, achieving AT Protocol specification compliance with native implementation and 901 passing conformance tests.

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
- [x] MST rebuilds optimized for batch writes
- [x] Wipe-and-rebuild utilities

#### Phase 9: PLC Server Compliance
- [x] `PLCStore` protocol updates
- [x] `GET /export` and `GET /{did}/log/last`
- [x] `GET /{did}/data`

#### Phase 10: E2E Verification
- [x] Native integration test suite (`scripts/run_e2e.sh`)
- [x] Confirmed PDS+PLC interoperability

#### Phase 6 (AGENTS.md): Professional Script Development - COMPLETED
- [x] Professional bash scripting standards (`set -euo pipefail`, ShellCheck compliance)
- [x] Core script upgrades: `simple_test.sh`, `start_server.sh`, `quality_gate.sh`, `run-tests.sh`
- [x] E2E test scripts: `test_social_features.sh` (6 scenarios), `test_moderation.sh` (4 scenarios)
- [x] All scripts pass ShellCheck with zero warnings

---

## Related Documentation

- [Production Readiness](production-readiness) - Current audit findings and blocking issues
- [Detailed Next Steps](detailed_next_steps_plan) - Priority execution plan for production blockers
- [Architecture Overview](../architecture/README) - System architecture decisions
- [Security Documentation](../security/README) - Security hardening guides
- [OAuth2 Documentation](../oauth2/README) - Authentication implementation details

---

*Last Updated: 2026-02-17*
