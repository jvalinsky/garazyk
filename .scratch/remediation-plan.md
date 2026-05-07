# [COMPLETED] Comprehensive Remediation Plan: Garazyk ATProto PDS

**Goal ID:** 925
**Objective:** Systematically address all Critical (P0), High (P1), and Medium (P2) findings identified in the comprehensive review (`.scratch/review-comprehensive.md`).

## Methodology & Best Practices
1. **No Shortcuts:** Every change included a read of the surrounding code/tests, the application of correct boundary logic, and follow up testing.
2. **Best Practices:**
   - **Boundary Enforcement:** Authenticated DID result checked, not just header presence.
   - **Zero Trust:** Remote JWT signatures verified using fetched JWKS.
   - **Strict Schema Adherence:** AppView and PDS schemas aligned with service requirements.
   - **Safe Primitives:** Used established cryptographic and timestamping paths.
3. **Evidence-based Implementation:** Verified with unit tests and specific edge-case tests (UTF-8, INT_MIN).
4. **Deciduous Tracking:** All major phases and outcomes tracked in Deciduous (Goal 925).

---

## Phase 1: Critical Priorities (P0) - [COMPLETED]
*These addressed arbitrary auth bypass, token forgery, protocol-breaking firehose issues, SSRF, and catastrophic schema drift.*

### C1. Ozone Admin Auth Gate Bypass [DONE]
### C2. Remote-issuer JWTs Unverified [DONE]
### C3. Firehose Sequence Numbers Unassigned [DONE]
### C4. Client-Controlled `atproto-proxy` SSRF [DONE]
### C5. AppView Schema Mismatch [DONE]

---

## Phase 2: High Priorities (P1) - [COMPLETED]
*These address security & stability issues.*

### Architecture & Protocol Integrity [DONE]
- **H1. Missing Firehose Events:** Plumbed #account, #sync, and #info dispatch.
- **H3/H4. Refresh Token Security:** Implemented server-side storage, rotation, and token_use claim.
- **H5. DPoP Replay Protection:** Passed PDSReplayCache to verifyProof.
- **H10. HTTPS Client IDs:** Enforced HTTPS/loopback for client IDs.

### Stability & System Limits [DONE]
- **H2. WebSocket Heartbeat Epochs:** Standardized to timeIntervalSince1970.
- **H7. Large Blob Retrieval:** Removed 5MB cap and implemented mapped loading.
- **H8/H9. WebSocket Concurrency:** Implemented re-entrancy guards and safe teardown.
- **H12. NotificationService Write Fix:** Converted read queries to update queries.

---

## Phase 3: Medium Priorities (P2) - [COMPLETED]
*These address system hardening.*

### Hardening [DONE]
- **M1:** Fixed MST UTF-8 byte offset bugs.
- **M2:** Validated DAG-CBOR tag-42 markers.
- **M3:** Enforced repo version 3 and signed commits.
- **M4:** Stricter ATURI component parsing.
- **M5:** Removed <12 byte magic-number bypass.
- **M7:** Mandated PKCE for all authorization code grants.
- **M8:** Applied proper salt to phone numbers.
- **M10:** Verified Sec-WebSocket-Accept handshake.
- **M11, M13, M14:** Added WebSocket URL cursor, Binary Search, and Auto-prune buffers.
- **M15, M16, M17:** Fixed WASM serialization (floats, JSON escaping, INT_MIN).
