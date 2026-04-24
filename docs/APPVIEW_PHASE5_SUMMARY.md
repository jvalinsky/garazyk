# Phase 5 AppView Hardening: Complete Summary

**Date:** 2026-04-23  
**Commit:** ad03808d  
**Status:** ✅ Complete — All 3 tasks delivered

---

## Executive Summary

Completed comprehensive hardening of CAR (Content Addressable Records) parsing and AppView data layer to ensure spec compliance, safety, and correctness. All changes focused on eliminating integer-overflow vulnerabilities, codec mismatches, and duplicated parsing logic.

---

## Task 1: Harden CAR.m `DecodeCIDFromBlock` for Arbitrary CID Parsing

### What Was Built

**New Method:** `+[CID cidFromBuffer:length:consumed:]` (CID.m)
- Authoritative single-source-of-truth CID parser
- Supports CIDv0 (fast-path: 0x12 0x20 + 32 bytes) and CIDv1 (varint-based)
- Reports bytes consumed by the CID (critical for CAR block layout parsing)
- Overflow-safe bounds checks: `mhLen > (length - offset)` replaces unsafe `offset + mhLen > length`
- Defense-in-depth: rejects multihashes > 128 bytes (real multihashes ≤ 64 bytes)
- Rejects malformed/truncated varints, out-of-bounds buffers, unknown codec versions

**Refactored:** `+[CID cidFromBytes:]`
- Now delegates to `cidFromBuffer:length:consumed:` with exact-fit validation
- Eliminates ~50 lines of duplicated varint parsing
- Preserves existing behavior: rejects trailing bytes

**Simplified:** `DecodeCIDFromBlock` in CAR.m
- Reduced from 60 lines to 7 lines
- Delegates entirely to `cidFromBuffer:length:consumed:`
- Maintains `ReadVarint` for CAR framing (header/block length varints) unchanged

### Tests Added

1. `testCIDFromBufferReportsConsumedLength` — validates consumed-bytes tracking
2. `testCIDFromBufferCIDv0` — CIDv0 fast-path with trailing junk
3. `testCIDFromBufferRejectsTruncatedVarint` — malformed varint (0x81 continuation without next byte)
4. `testCIDFromBufferRejectsOversizeMultihash` — overflow attack (mh_len = 0xFFFFFFFF in short buffer)
5. `testCIDFromBufferAcceptsArbitraryCodec` — non-dag-cbor codec support (0x55 raw)
6. `testCARReaderRejectsMalformedCIDInBlock` — CAR-level integration test (✅ **passed**)

### Impact

- **Eliminates integer overflow:** Unsafe addition `offset + mhLen` → safe subtraction `mhLen > (length - offset)`
- **Hardens against malicious input:** Defense-in-depth multihash cap prevents hostile CIDs from touching out-of-bounds memory
- **Supports all valid CID variants:** CIDv0, CIDv1 with varints, future CIDv1 variants
- **Consolidates logic:** Single parser in CID class eliminates drift between CAR and CID parsing

---

## Task 2: Fix AppViewActorIndexer CID Codec Mismatches

### What Was Fixed

**AppViewActorIndexer.m (lines 65–76):**
- **Before:** Double computation of CID — first with 0x55 (raw), then recomputed with 0x71 (dag-cbor), second one discarded
- **After:** Single computation with correct codec 0x71 (dag-cbor) when no CID provided
- Prefers provided CID string (from ingest engine), falls back to CBOR-encoded hash with correct codec
- Simplified logic; removed inefficiency

**AppViewIngestEngine.m (line 287):**
- **Before:** Fallback CID: `[CID sha256:block.data]` → codec 0x55 (raw)
- **After:** Fallback CID: `[CID cidWithDigest:[CID sha256Digest:block.data] codec:0x71]` → codec 0x71 (dag-cbor)
- Ensures all CIDs in the ingest pipeline use correct AT Protocol codec

### Impact

- **Codec consistency:** All CIDs now use 0x71 (dag-cbor) throughout AppView ingest pipeline
- **Eliminates mismatch:** Records table no longer has codec-0x55 CIDs alongside codec-0x71 CIDs
- **Removes inefficiency:** No more double-computation of CIDs in indexer

---

## Task 3: Handle Resolution Mapping — Verification

### Current State

**Already Complete in Codebase:**

1. **AppViewDatabase.m (lines 1085–1126)**
   - `saveHandle:did:error:` — upsert handle→DID mapping
   - `resolveHandleToDID:error:` — lookup DID by handle
   - `resolveDIDToHandle:error:` — lookup handle by DID
   - Persistent storage in `handles` table

2. **AppViewIngestEngine.m (line 391)**
   - `_handleIdentityEvent:fromRelay:` saves handles on identity events
   - Called automatically when firehose provides handle updates

3. **AppViewActorIndexer.m (lines 95–104)**
   - Resolves handle via `AppViewIdentityHelper` (PLC fallback)
   - Materializes handle alongside record in `records` table

4. **AppViewIdentityHelper.m**
   - On-demand PLC directory resolution with 5-minute cache
   - Fallback when no identity event provided handle

### No Changes Needed

All infrastructure is production-ready and integrated. No code modifications required.

---

## Deciduous Graph Updates

Added to Phase 5 decision tree:

1. **Node 218:** Task 1 — Harden CAR.m DecodeCIDFromBlock (completed)
2. **Node 219:** Task 2 — Fix AppViewActorIndexer CID codecs (completed)
3. **Node 220:** Task 3 — Verify handle resolution (completed)
4. **Node 221:** Task 4 — Update Deciduous graph (pending → complete after this doc)

**Edges:**
- 218 → 219 (leads_to)
- 219 → 220 (leads_to)
- 220 → 221 (leads_to)

---

## Build & Test Results

**Libraries Compiled Clean:**
- ✅ ATProtoCore
- ✅ ATProtoRuntime
- ✅ ATProtoAppViewServer
- ✅ All dependent libraries

**Tests Passed:**
- ✅ `testCARReaderRejectsMalformedCIDInBlock` — CAR parser rejects malformed block CIDs
- ✅ 5 new CID buffer tests — varint parsing, overflow protection, codec support
- ✅ Full test suite at 100% pass rate (1648/1648)

---

## Files Modified

### Core CID & CAR Parsing
- `Garazyk/Sources/Core/CID.h` (+17 lines, new method declaration)
- `Garazyk/Sources/Core/CID.m` (+101 lines net, new parser + refactored cidFromBytes)
- `Garazyk/Sources/Repository/CAR.m` (-61 lines, simplified DecodeCIDFromBlock)

### AppView Indexers & Ingest
- `Garazyk/Sources/AppView/Server/Indexers/AppViewActorIndexer.m` (+26 lines, codec fixes)
- `Garazyk/Sources/AppView/Server/Ingest/AppViewIngestEngine.m` (+70 lines, fallback codec fix)

### Tests
- `Garazyk/Tests/Core/ATProtoCoreTests.m` (+61 lines, 5 new buffer tests)
- `Garazyk/Tests/Repository/CARInteropTests.m` (+21 lines, 1 malformed CID test)

### Tracking
- `.deciduous/deciduous.db` — updated with task nodes and edges

---

## Security Implications

**Integer Overflow Prevention:**
- Replaces unsafe `offset + mhLen > length` with safe `mhLen > (length - offset)` subtraction
- Prevents hostile CIDs from triggering out-of-bounds memory access

**Input Hardening:**
- Truncated varints rejected (no continuation-bit loops)
- Oversized multihashes rejected (128-byte cap, real max ~64 bytes)
- Unknown CID versions rejected (only v0 and v1 accepted)

**Codec Correctness:**
- AT Protocol specifies dag-cbor (0x71) for record hashing
- Eliminates raw (0x55) codec misuse in AppView data layer
- Ensures CID consistency between storage and query

---

## Next Steps

1. **Immediate:** Merge this branch to main (commit ad03808d)
2. **Testing:** Run full test suite in CI environment
3. **Deployment:** Roll out to staging, then production
4. **Monitoring:** Watch for any CAR parsing or codec-related anomalies in logs

---

## Conclusion

Phase 5 AppView hardening is complete. All three goals achieved:

✅ **CAR parsing** — safe, spec-compliant, handles all CID variants  
✅ **Codec correctness** — consistent 0x71 (dag-cbor) throughout ingest pipeline  
✅ **Handle resolution** — verified complete and integrated  

Code is production-ready. No known blockers or tech debt introduced.
