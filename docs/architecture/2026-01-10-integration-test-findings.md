# PDS Integration Test Results - Findings Report

> **Status (2026-02-19):** Items 1 (JWT tokens) and 4 (session persistence) are resolved. Access tokens are now signed JWTs. Sessions persist to SQLite. Items 2-3 remain as documented.

## Executive Summary

Integration tests verified PDS interaction session behavior. **All 7 tests pass**, documenting expected behavior and implementation differences from ATProto specification.

## Test Results

| Test | Status | Key Finding |
|------|--------|-------------|
| Complete Session Lifecycle | ✓ PASS | Tokens are UUIDs, not JWTs |
| Record CRUD with Value Retrieval | ✓ PASS | getRecord missing `value` field |
| CID Format Compliance | ✓ PASS | CID uses non-standard format |
| Token Validation | ✓ PASS | UUID-based opaque tokens |
| Session Persistence Limitation | ✓ PASS | In-memory only (documented) |
| Record Value Field Analysis | ✓ PASS | Only 4 fields returned |
| Authentication Required | ✓ PASS | UUID-based session lookup |

## Critical Findings

### 1. Tokens Are UUIDs, Not JWTs

> **RESOLVED (Phase 2):** Access tokens are now signed JWTs via `JWTMinter`. Refresh tokens remain opaque.

**Expected (ATProto Spec):**
- Access/refresh tokens should be signed JWTs with cryptographic claims
- JWT structure: `header.payload.signature`
- Claims include: `iss`, `sub`, `aud`, `iat`, `exp`

**Historical Implementation (pre-Phase 2):**
```
Access token: 87CB3C9A-0922-4DA8-A3C2-8E50CD7400B8
Refresh token: 5A15252D-A080-41F7-89E7-477FB5B5A54B
```

Tokens were opaque UUID strings with no cryptographic verification.

### 2. getRecord Returns Incomplete Data

**Expected Response:**
```json
{
  "uri": "at://did/collection/rkey",
  "cid": "bafyre...",
  "collection": "app.bsky.feed.post",
  "rkey": "rkey",
  "value": {...},           // MISSING
  "createdAt": "2026-01-10T12:00:00Z"  // MISSING
}
```

**Actual Response:**
```json
{
  "uri": "at://did/collection/rkey",
  "cid": "bafyre...",
  "collection": "app.bsky.feed.post",
  "rkey": "rkey"
}
```

**Impact:**
- Clients must make separate requests to fetch CAR block for record value
- `createdAt` is set but not returned
- Additional round-trip required for complete record data

### 3. CID Format is Non-Standard

**Expected (IPLD CIDv1):**
- Multibase format with proper codec identification
- Example: `bafyreicyslcncdgxabkz6o2oxejqtrweod7suwa`

**Actual:**
```
bafyreid6ygzb2pn6vypl4phtpn56w6q7lvjukfcsek3kupo3zkks4xgmdy
```

Uses `bafyre` prefix with base64url-encoded SHA-256 (59 chars).

**Positive:** CID generation is deterministic - same content produces same CID.

### 4. Session Persistence

> **RESOLVED (Phase 5):** Sessions now persist to SQLite via `SessionStore`.

**Historical Status:** Sessions were stored in-memory in `SessionStore` NSMutableDictionary.

**Impact (resolved):**
- Sessions lost on server restart
- Users must re-authenticate after restart
- No session recovery mechanism

## Comparison: Expected vs Actual

| Aspect | Expected | Actual | Impact |
|--------|----------|--------|--------|
| Token Format | Signed JWT | UUID | Lower security |
| Token Claims | Cryptographic | None | No verification |
| getRecord value | Included | Missing | Extra round-trip |
| CID Format | IPLD v1 | bafyre + SHA-256 | Non-standard |
| Session Storage | Database/Persistent | In-memory | Lost on restart |

## Test Files

- **Integration Tests:** `ATProtoPDS/Tests/Network/PDSIntegrationTests.m`
- **Test Command:** `./build/tests/AllTests`
- **Test Count:** 7 tests covering session lifecycle, records, tokens, and authentication

## Recommendations

### High Priority

1. **~~Implement JWT Token Generation~~** ✓ DONE
   - ~~Replace UUID tokens with signed JWTs~~
   - Implemented via `JWTMinter` in Phase 2

2. **Fix getRecord Response**
   - Include `value` field with record content
   - Include `createdAt` timestamp
   - Or document as separate CAR block fetch

### Medium Priority

3. **Implement IPLD CID Generation**
   - Use proper CIDv1 multicodec format
   - Consider using a proper CID library

4. **~~Persist Sessions to Database~~** ✓ DONE
   - Sessions now persist to SQLite
   - Implemented in Phase 5

### Low Priority

5. **Add Token Rotation on Refresh**
   - Current: New tokens generated, old discarded
   - Recommended: Track refresh token rotation for security

## Conclusion

The PDS implementation works correctly for basic operations (account creation, login, record CRUD). Remaining deviations from ATProto specification:

1. **Record Retrieval:** Missing value field
2. **CID Format:** Non-standard encoding

Resolved items:
- Authentication: Now JWT-based (Phase 2)
- Session persistence: Now SQLite-backed (Phase 5)
