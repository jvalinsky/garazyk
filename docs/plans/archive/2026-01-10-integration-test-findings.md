# PDS Integration Test Results - Findings Report

## Executive Summary

Integration tests were written and executed to verify the behavior of a normal PDS interaction session. **All 7 tests pass**, documenting both expected behavior and several significant implementation differences from ATProto specification.

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

**Expected (ATProto Spec):**
- Access/refresh tokens should be signed JWTs with cryptographic claims
- JWT structure: `header.payload.signature`
- Claims include: `iss`, `sub`, `aud`, `iat`, `exp`

**Actual Implementation:**
```
Access token: 87CB3C9A-0922-4DA8-A3C2-8E50CD7400B8
Refresh token: 5A15252D-A080-41F7-89E7-477FB5B5A54B
```

Tokens are opaque UUID strings with no cryptographic verification.

**Security Implications:**
- No verification of token claims
- Tokens can be forged if session store is compromised
- No proof of token ownership beyond session store access
- Sessions are authenticated via in-memory lookup only

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

**Status:** Sessions are stored in-memory in `SessionStore` NSMutableDictionary.

**Impact:**
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

1. **Implement JWT Token Generation**
   - Replace UUID tokens with signed JWTs
   - Include standard claims: `iss`, `sub`, `aud`, `iat`, `exp`
   - Enable cryptographic token verification

2. **Fix getRecord Response**
   - Include `value` field with record content
   - Include `createdAt` timestamp
   - Or document as separate CAR block fetch

### Medium Priority

3. **Implement IPLD CID Generation**
   - Use proper CIDv1 multicodec format
   - Consider using a proper CID library

4. **Persist Sessions to Database**
   - Store sessions in SQLite for persistence
   - Implement session recovery on restart

### Low Priority

5. **Add Token Rotation on Refresh**
   - Current: New tokens generated, old discarded
   - Recommended: Track refresh token rotation for security

## Conclusion

The PDS implementation works correctly for basic operations (account creation, login, record CRUD), but has significant deviations from ATProto specification in:

1. **Authentication:** UUID-based instead of JWT-based
2. **Record Retrieval:** Missing value field
3. **CID Format:** Non-standard encoding
4. **Session Persistence:** In-memory only

These findings inform the gap between current implementation and specification compliance.

---

## Related Documentation

- [Archive Index](./README.md) - Index of all archived plans
- [Current Plans](../README.md) - Active implementation plans
- [Tests Docs](../../tests/README.md) - Testing documentation
