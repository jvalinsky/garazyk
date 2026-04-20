# AT Protocol Adherence Deep Dive - Executive Summary

**Date**: 2026-04-20
**Project**: garazyk (ATProtoPDS)
**Version**: Main branch (db5ee972+)

---

## Overview

This report documents AT Protocol specification compliance across the garazyk codebase. The audit examined 8 protocol areas against reference implementations and official specifications.

**Overall Assessment**: **94% Compliant** with documented gaps.

---

## Compliance by Area

| Protocol Area | Status | Coverage | Critical Issues |
|----------------|--------|----------|------------------|
| **Repository** (MST, CAR, CBOR) | ✅ | 100% | 0 |
| **Sync** (Firehose) | ✅ | 98% | 0 |
| **Identity** (DID, PLC) | ✅ | 95% | 0 |
| **XRPC/Lexicon** | ✅ | 94.6% | 0 |
| **OAuth/Auth** | ⚠️ | 85% | 5 |
| **PLC Directory Server** | ✅ | 95% | 0 |
| **Blob Storage** | ✅ | 95% | 0 |

---

## 🔴 Critical Issues (5)

All in OAuth/Auth subsystem - documented in existing report:

### OAuth Critical Issues

1. **No Dynamic Client Metadata Fetching** - Third-party clients cannot authenticate
2. **`plain` PKCE Method Allowed** - Weakens security
3. **DPoP Nonce TTL Exceeds Spec** - 10 min vs 5 min max
4. **DPoP Nonces One-Time Use** - Forces retry cycles
5. **Confidential Client JWT Not Verified** - Token endpoint auth incomplete

**Impact**: OAuth flow incomplete for standard clients. Works for pre-registered apps.

**Full Details**: `docs/archive/planning/oauth2-spec-compliance-report.md`

---

## ⚠️ Gaps (15)

### Repository
- MST key validation could be stricter

### Sync
- `ConsumerTooSlow` error emission not verified
- `ops[].prev` field tracking for inductive firehose

### Identity
- DID:web resolver needs verification
- Handle-DID bidirectional validation incomplete

### XRPC
- `tools.ozone.*` endpoints deferred (16 endpoints)
- `app.bsky.graph.getListMutes` missing
- `app.bsky.graph.getListBlocks` missing
- `chat.bsky.*` DM endpoints partial

### PLC Server
- Legacy `create` operation format handling

### Blob Storage
- CDN redirect behavior verification
- Orphaned blob cleanup

### OAuth (8 additional moderate issues)
- See full report

---

## ✅ Compliant Highlights

### Repository Protocol
- MST key-depth algorithm verified against reference
- CAR v1 format matches spec
- DAG-CBOR encoding correct (tag 42 CID-links)
- TID generation spec-compliant

### Sync Protocol
- All 5 event types implemented
- Monotonic sequence numbers
- Serial dispatch queue for ordering
- `FutureCursor` and `OutdatedCursor` errors correct
- Sync event fallback for oversized commits

### Identity Protocol
- PLC operation chain validation complete
- 72-hour recovery window enforced
- Operation rate limiting (10/h, 30/d, 100/w)
- Handle resolution with HTTPS + DNS TXT fallback
- SSRF protection in handle resolution

### XRPC Coverage
- `com.atproto.server.*`: 100% (25/25)
- `com.atproto.repo.*`: 100% (11+2)
- `com.atproto.sync.*`: 93% (14/15)
- `com.atproto.identity.*`: 100% (9/9)
- `com.atproto.label.*`: 100% (4/4)

---

## Documentation

### Generated Reports
All reports in `docs/protocol-audit-2026-04-20/`:

| File | Topic |
|------|-------|
| `01-repository.md` | MST, CAR, CBOR, TID |
| `02-sync.md` | Firehose, subscribeRepos |
| `03-identity.md` | DID, PLC, Handles |
| `04-xrpc-lexicon.md` | XRPC endpoint coverage |
| `05-oauth-summary.md` | OAuth critical issues |
| `06-plc-server.md` | PLC directory server |
| `07-blob-storage.md` | Blob CID, storage |

### Existing Documentation
- OAuth Full Report: `docs/archive/planning/oauth2-spec-compliance-report.md`
- XRPC Coverage: `docs/xrpc-coverage-analysis-2026-04-17.md`
- Firehose Docs: `docs/08-sync-firehose/` (12 files)

---

## Prioritized Action Items

### Immediate (Security)
1. Fix DPoP nonce TTL (600 → 300 seconds)
2. Make DPoP nonces reusable until expiry
3. Reject `plain` PKCE method

### High Priority (Interop)
4. Implement dynamic client metadata fetching
5. Add `atproto` scope enforcement

### Medium Priority (Completeness)
6. Verify DID:web resolution
7. Implement bidirectional handle validation
8. Add missing AppView endpoints (getListMutes, getListBlocks)

### Low Priority (Nice to have)
9. Ozone API (tools.ozone.*)
10. Chat/DM endpoints (chat.bsky.*)

---

## References

### Source Code
- `Garazyk/Sources/Repository/` - MST, CAR
- `Garazyk/Sources/Sync/` - Firehose
- `Garazyk/Sources/Identity/` - DID, handles
- `Garazyk/Sources/PLC/` - PLC server
- `Garazyk/Sources/Auth/` - OAuth
- `Garazyk/Sources/Blob/` - Blob storage

### Reference Implementations
- `reference/atproto/` - Official TypeScript PDS
- `reference/did-method-plc/` - PLC spec + implementation

### Specifications
- atproto.com/specs/repository
- atproto.com/specs/sync
- atproto.com/specs/identity
- atproto.com/specs/oauth
- atproto.com/specs/handle

---

## Conclusion

Garazyk is a highly spec-compliant AT Protocol PDS implementation with strong coverage across core protocol areas. The only critical issues are in OAuth authentication, which is a work-in-progress area with known gaps documented in a prior detailed report.

**Recommended Path Forward**:
1. Address DPoP nonce issues (small fix, high impact)
2. Complete dynamic client fetching for OAuth interop
3. Continue Ozone API work when resources allow
