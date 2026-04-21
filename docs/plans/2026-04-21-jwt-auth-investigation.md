# JWT Auth Investigation Plan

**Date**: 2026-04-21
**Git Hash**: c5bc73162
**Issue**: JWT verification failing when accessing authenticated endpoints after successful session creation

## Root Cause Identified ✅

**The Problem**: JWT tokens are minted with `iss: http://localhost:8080` (default port) but verified expecting the actual server port (2583).

**Why**: 
1. `PDSConfiguration._serverPort` defaults to **8080** (line 134 of PDSConfiguration.m)
2. `PDSApplication` creates `JWTMinter` with `issuer = [configuration canonicalIssuerWithPortHint:_httpPort]`
3. `_httpPort` comes from `_configuration.serverPort` → defaults to 8080
4. CLI `--port` flag sets the HTTP server port, but **never updates** `JWTMinter.issuer`
5. Verification uses `jwtMinter.issuer` which is wrong

**Call Chain**:
```
CLI --port 2583
  → PDSCLIServeCommand creates PDSController
    → PDSController creates PDSApplication
      → PDSApplication._httpPort = _configuration.serverPort (8080!)
      → JWTMinter.issuer = canonicalIssuerWithPortHint:8080 → "http://localhost:8080"
  → serverBuilder.issuer = canonicalIssuerWithPortHint:2583 ✓ (correct, but unused)
  → JWTMinter.issuer still "http://localhost:8080" ✗
```

**The CLI sets `serverBuilder.issuer` but never updates `controller.jwtMinter.issuer`!**

## Fix Applied ✅

**Commit**: `33710a03`

**Changes in PDSCLIServeCommand.m**:
1. Set `PDSConfiguration.serverPort` before creating PDSController
2. Explicitly update `controller.jwtMinter.issuer` after creation

```objc
// CRITICAL: Set serverPort BEFORE creating PDSController so that
// PDSApplication uses the correct port for JWT issuer calculation.
// Without this, JWT minter defaults to port 8080 while server runs on --port.
[[PDSConfiguration sharedConfiguration] setServerPort:port];

// ... create controller ...

// Calculate canonical issuer with the actual port
NSString *canonicalIssuer = [[PDSConfiguration sharedConfiguration] canonicalIssuerWithPortHint:port];
serverBuilder.issuer = canonicalIssuer;

// Ensure JWT minter issuer matches the server port (belt and suspenders)
controller.jwtMinter.issuer = canonicalIssuer;
```

## Verification ✅

```
# JWT Payload (decoded):
{
  "iss": "http://localhost:2583",  // Correct! Was 8080 before
  "did": "did:plc:nt3vjqflcoxxawfsn2rq3sxi",
  ...
}

# Authenticated endpoints now work:
$ curl -s "http://localhost:2583/xrpc/app.bsky.graph.getListMutes" \
  -H "Authorization: Bearer $ACCESS_TOKEN"
{"lists": []}
```

## Summary

| Issue | Root Cause | Fix |
|-------|------------|-----|
| JWT verification failing | Issuer mismatch (8080 vs 2583) | Set config.serverPort before PDSApplication init |
| getConfig ignored --port | PDSConfiguration default 8080 | Explicit update after controller creation |


## Evidence

```
# Session response (works):
{
  "accessJwt": "eyJhbGciOiJFUzI1NksiLCJ0eXAiOiJhdCtqd3QifQ...",
  "did": "did:plc:vi5cop6zfhvqm36ptimwn63d",
  "handle": "test.localhost"
}

# Authenticated request (fails):
curl -s "http://localhost:2583/xrpc/app.bsky.graph.getListBlocks" \
  -H "Authorization: Bearer $ACCESS_TOKEN"
# Returns: {"error": "AuthRequired", "message": "Authentication required"}

# Server logs:
[WARN] JWT verification failed for request from IP: ::1
```

## Investigation Steps

### Phase 1: Understand JWT Flow

- [ ] **Read `XrpcAuthHelper.m`** - Find the JWT verification logic at line 257
- [ ] **Read JWT creation in session handler** - Find where `accessJwt` is minted
- [ ] **Compare issuer (`iss`) claim** - Session creates with one issuer, verification expects another?
- [ ] **Compare audience (`aud`) claim** - Same potential mismatch

### Phase 2: Trace Configuration

- [ ] **Check PDSConfiguration issuer setting** - What is `PDS_HOSTNAME` vs configured issuer?
- [ ] **Check JWT issuer configuration** - Where does JWT minting get its `iss` claim?
- [ ] **Check JWT verifier configuration** - Where does verification get expected `iss`?
- [ ] **Check for environment variable fallbacks** - Are we using `PDS_HOSTNAME` or `issuer` config?

### Phase 3: Identify Mismatch

Hypothesis: JWT is minted with `iss: http://localhost:8080` (default?) but verified expecting `iss: http://localhost:2583`

Evidence supporting this:
- Access token payload shows: `"iss":"http:\/\/localhost:8080"`
- Server is running on port 2583

### Phase 4: Fix Options

**Option A: Fix JWT minting** - Use actual server URL when minting tokens
**Option B: Fix JWT verification** - Accept the issuer that's being minted
**Option C: Fix configuration** - Ensure consistent configuration between minting and verification

## Files to Examine

| File | Purpose | Lines |
|------|---------|-------|
| `Garazyk/Sources/Network/XrpcAuthHelper.m` | JWT verification logic | ~257 |
| `Garazyk/Sources/Auth/JWTMinter.m` | JWT creation | All |
| `Garazyk/Sources/Auth/JWTVerifier.m` | JWT verification | All |
| `Garazyk/Sources/Network/XrpcServerMethods.m` | createSession handler | All |
| `Garazyk/Sources/Core/PDSConfiguration.m` | Configuration loading | All |

## Expected Findings

1. JWT minting uses a hardcoded or default issuer URL
2. JWT verification uses PDS_HOSTNAME or configured issuer
3. These two values don't match in E2E test environment
4. Fix involves ensuring consistency

## Success Criteria

- [ ] Session creation sets correct `iss` claim
- [ ] JWT verification accepts the `iss` from minted tokens
- [ ] `getListBlocks` and `getListMutes` return successfully with auth
- [ ] Unit tests pass for JWT scenarios

## Implementation Approach

1. **Don't compile mid-investigation** - Understand fully first
2. **Document root cause** - Write findings to this file
3. **Make minimal fix** - One targeted change
4. **Test comprehensively** - Verify E2E before committing
