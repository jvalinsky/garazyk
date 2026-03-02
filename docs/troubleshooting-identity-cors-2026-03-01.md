# Troubleshooting: Identity Resolution & CORS — 2026-03-01

## Overview

This session covered two major areas: (1) fixing `com.atproto.identity.updateHandle`
to match the AT Protocol reference implementation, and (2) implementing dynamic CORS
headers across all PDS HTTP handlers.

---

## Part 1: updateHandle Spec Compliance

### Background

A code review comparing `XrpcIdentityMethods.m` against the reference TypeScript
implementation (`packages/pds/src/api/com/atproto/identity/updateHandle.ts` in
`bluesky-social/atproto`) found six spec deviations.

### Issue 1: Missing Per-Endpoint Rate Limiting (HIGH)

**Spec requirement:** 10 requests per 5 minutes + 50 per day, per DID.

**What existed:** Only global per-IP rate limiting (3000 req/5min) via `RateLimiter`.
No per-endpoint or per-DID limits.

**Fix:** Added a generic `checkRateLimitForKey:limit:windowSeconds:` method to
`RateLimiter` that accepts an arbitrary composite key, limit, and window duration.
The `updateHandle` handler now checks two keys before processing:

```objc
// 10 requests per 5 minutes per DID
RateLimitResult *shortLimit = [[RateLimiter sharedLimiter]
    checkRateLimitForKey:[NSString stringWithFormat:@"identity.updateHandle:5m:%@", did]
                   limit:10
           windowSeconds:300];

// 50 requests per day per DID
RateLimitResult *longLimit = [[RateLimiter sharedLimiter]
    checkRateLimitForKey:[NSString stringWithFormat:@"identity.updateHandle:1d:%@", did]
                   limit:50
           windowSeconds:86400];
```

**Files:** `RateLimiter.h`, `RateLimiter.m`, `XrpcIdentityMethods.m`

### Issue 2: Same-Handle Ownership Case (MEDIUM)

**Spec requirement:** When the requester already owns the requested handle, skip PLC
update and DB write but still emit an `#identity` firehose event.

**What existed:** The code performed the full PLC update + DB write even when the user
re-claimed their own handle.

**Fix:** Added a `needsUpdate` flag after the uniqueness check:

```objc
BOOL needsUpdate = YES;
if (existingAccount && [existingAccount.did isEqualToString:did]) {
    needsUpdate = NO;  // Already owns this handle, just re-sequence
} else if (existingAccount) {
    // 409 HandleAlreadyTaken
    return;
}

if (needsUpdate) {
    // PLC update, DB update
}

// ALWAYS broadcast identity event
[subscribeReposHandler broadcastIdentityChange:did handle:normalizedHandle];
```

**File:** `XrpcIdentityMethods.m`

### Issue 3: alsoKnownAs Preservation (MEDIUM)

**Spec requirement:** When updating PLC, preserve existing non-`at://` entries in
`alsoKnownAs` and only replace the `at://` handle entry.

**What existed:** The code overwrote all `alsoKnownAs` entries with just the new handle:
```objc
op[@"alsoKnownAs"] = @[@"at://handle"];  // destroyed other aliases
```

**Fix:** Read existing aliases from the current PLC state, filter out old `at://`
entries, prepend the new handle:

```objc
NSMutableArray *newAlsoKnownAs = [NSMutableArray array];
NSString *newAtHandle = [NSString stringWithFormat:@"at://%@", normalizedHandle];
for (NSString *aka in currentState.alsoKnownAs) {
    if (![aka hasPrefix:@"at://"]) {
        [newAlsoKnownAs addObject:aka];
    }
}
[newAlsoKnownAs insertObject:newAtHandle atIndex:0];
op[@"alsoKnownAs"] = newAlsoKnownAs;
```

**File:** `XrpcIdentityMethods.m`

### Issue 4: Identity Event Always Sequenced (MEDIUM)

**Spec requirement:** An `#identity` firehose event must always be emitted after
`updateHandle`, even when the user already owns the handle.

**What existed:** The broadcast call was gated on the DB update path, so the
same-handle case returned early without emitting any event.

**Fix:** Moved the `broadcastIdentityChange:` call outside the `needsUpdate` guard
so it always runs. See Issue 2 code above.

**File:** `XrpcIdentityMethods.m`

### Issue 5: Takedown Check (FALSE POSITIVE)

Initial review flagged missing takedown check. On closer inspection,
`XrpcAuthHelper.extractDIDFromAuthHeader:` at line 307–317 already calls
`[adminController isAccountTakedownActive:did]` and returns `nil` (401) if active.
No code change needed.

### Issue 6: Admin updateHandle Documentation (LOW)

Added a clarifying comment to `PDSAdminService.m` noting the admin `updateHandle:`
method intentionally bypasses PLC and firehose:

```objc
// Direct DB update only — does NOT update PLC directory or emit firehose identity events.
// For full protocol-compliant updates, use com.atproto.identity.updateHandle XRPC endpoint.
```

**File:** `PDSAdminService.m`

### Tests

Added two new test cases to `RepoAuthIdentityTests.m`:
- `testIdentityUpdateHandleRateLimiting` — verifies 429 after exceeding 10 req/5min
- `testIdentityUpdateHandleSameHandleStillBroadcasts` — verifies identity event is
  emitted even when re-claiming own handle

All 8 `RepoAuthIdentityTests` pass with 0 failures.

**Commits:** `b092b24` (initial spec fixes), then follow-up for robust PLC parsing.

---

## Part 1b: VM Handle Update Debugging

### Symptom

After deploying the spec fixes, handle updates via the web UI still failed on the
production VM. The PDS returned success but the PLC directory wasn't updated.

### Debugging Steps

1. **`docker logs nspds | grep updateHandle`** — found the handler was called
   but PLC operation submission failed silently.
2. **`curl -s https://plc.directory/did:plc:.../log/audit | jq .`** — confirmed
   no new operations were appearing in PLC.
3. **Code review of PLC audit log parsing** — found the `PLCOperation` parser
   was silently returning `nil` for certain operation formats without logging.
4. **Added diagnostic logging** to the PLC operation parse loop and the signing
   code path.

### Root Cause

The PLC audit log response format had fields that the parser didn't handle
robustly. Certain dictionary keys were expected in a specific format but the
real PLC directory returned slightly different structures.

### Fix

Updated `XrpcIdentityMethods.m` and `PLCOperation.m` with more robust JSON
parsing and better error logging for PLC operation construction failures.

### Additional Build Fix

The Linux/GNUstep Docker build failed because `PDSAppleKeyManager.m` (which uses
`Security.framework`) was included in the CMake source list unconditionally.

**Fix:** Excluded `PDSAppleKeyManager.m` on non-Apple platforms in `CMakeLists.txt`.

**Commit:** `b092b24` (CMakeLists fix)

---

## Part 2: Dynamic CORS Headers

### Background

Browser console errors when using `witchsky.app` (Bluesky web client) pointed at
`pds.garazyk.xyz`:

```
Access to fetch at 'https://pds.garazyk.xyz/xrpc/com.atproto.server.createSession'
from origin 'https://witchsky.app' has been blocked by CORS policy:
No 'Access-Control-Allow-Origin' header is present on the requested resource.
```

The previous CORS fix (2026-02-27, see `troubleshooting-cors-ratelimit-2026-02-27.md`)
used hardcoded `Access-Control-Allow-Origin: *` everywhere. This needed to be replaced
with dynamic origin-reflecting CORS to support credentialed requests and configurable
allowed origins.

### Changes

Replaced all hardcoded CORS headers with a shared `setCorsHeaders:forRequest:` method
in each handler layer:

| File | What Changed |
|------|-------------|
| `XrpcHandler.m` | Added `setCorsHeaders:` that reads `cors.allowed_origins` from config, reflects `Origin` header when wildcard is configured |
| `OAuth2Handler.m` | Added same `setCorsHeaders:` pattern; applied to `/oauth/token`, `/oauth/revoke`, `/.well-known/oauth-*`, `/oauth/jwks`, `/oauth/par`, and preflight handlers |
| `PDSHttpServerBuilder.m` | Added `setCorsHeaders:` using existing `getCorsAllowedOrigins` helpers; applied to OPTIONS `/xrpc`, `/xrpc/:method`, prefix handler, and subscribeRepos |
| `NodeInfoHandler.m` | Added `setCorsHeaders:` for NodeInfo discovery/2.0/2.1 endpoints (previously hardcoded `*`) |
| `PDSConfiguration.h/.m` | Added `arrayForKey:` method to support reading `cors.allowed_origins` as an array from config.json |

### CORS Header Behavior

```
Origin: https://witchsky.app
→ Access-Control-Allow-Origin: https://witchsky.app  (reflected)
→ Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS, HEAD
→ Access-Control-Allow-Headers: DPoP, Authorization, Content-Type, *
→ Access-Control-Max-Age: 86400
→ Access-Control-Expose-Headers: DPoP-Nonce, WWW-Authenticate
→ Vary: Origin
```

All values are configurable via `config.json`:
```json
{
  "cors": {
    "allowed_origins": ["*"],
    "allowed_methods": "GET, POST, PUT, DELETE, OPTIONS, HEAD",
    "allowed_headers": "DPoP, Authorization, Content-Type, *",
    "max_age": 86400
  }
}
```

Default is `["*"]` (allow all origins with reflection).

### Additional: `com.atproto.identity.resolveDid` Endpoint

Added the missing `com.atproto.identity.resolveDid` XRPC endpoint in
`XrpcIdentityMethods.m`. Accepts a `did` query parameter, resolves via
`XrpcIdentityHelper`, returns the DID document or 404.

### Verification

**PDS direct (localhost:2583):** ✅ CORS headers present on all responses
```bash
ssh crimson-comet.exe.xyz "curl -v -X POST http://localhost:2583/xrpc/com.atproto.server.createSession \
  -H 'Origin: https://witchsky.app' -H 'Content-Type: application/json' \
  -d '{\"identifier\":\"test\", \"password\":\"test\"}'"
# → Access-Control-Allow-Origin: https://witchsky.app ✅
```

**Through nginx (localhost:3000):** ✅ Headers pass through
```bash
ssh crimson-comet.exe.xyz "curl -v -X POST http://localhost:3000/xrpc/com.atproto.server.createSession \
  -H 'Host: pds.garazyk.xyz' -H 'Origin: https://witchsky.app' ..."
# → Access-Control-Allow-Origin: https://witchsky.app ✅
```

**Through exe.dev TLS proxy (HTTPS):** ❌ POST+Origin blocked (see Known Issue)
```bash
curl -v -X POST https://pds.garazyk.xyz/xrpc/com.atproto.server.createSession \
  -H 'Origin: https://witchsky.app' ...
# → 403 "cross-origin request denied" (from exe.dev proxy, not PDS)
```

### Known Issue: exe.dev TLS Proxy Blocks Cross-Origin POST

The exe.dev platform's TLS termination proxy (at `s001.exe.xyz`, upstream of the VM)
actively blocks non-GET/non-OPTIONS requests that include an `Origin` header. This is
a platform-level security feature, not a PDS or nginx issue.

**Evidence:**
- `OPTIONS + Origin` → passes through ✅ (preflight works)
- `GET + Origin` → passes through ✅ (CORS headers visible)
- `POST + Origin` → blocked with `403 "cross-origin request denied"` ❌
- `POST` without `Origin` → passes through ✅ (returns 401 with CORS headers)
- Response body is `"cross-origin request denied"` (plain text, not JSON — not from PDS)

**Workaround options:**
1. Contact exe.dev support to whitelist cross-origin POST for `pds.garazyk.xyz`
2. Use a different TLS terminator (Cloudflare, self-hosted reverse proxy)
3. Move the PDS to hosting without platform-level CORS enforcement

**Commit:** `d631877`

---

## Pre-existing Test Failures (Not Related)

> [!NOTE]
> **Update 2026-03-01 (Stabilization):** All failures listed below, along with over 1200 other transient/pre-existing issues, have been resolved. See the [Test Suite Stabilization Report](test-suite-stabilization-report-2026-03-01.md) for details.

| Test | Failure | Notes |
|------|---------|-------|
| `PLCServerTests.testPostDID` | 400 instead of 200 | PLC server test infrastructure issue |
| `XrpcMethodRegistryTests.testExtractDIDFromAuthHeaderDPoPNonceChallengeAndRetry` | Missing nonce challenge headers | DPoP nonce flow not fully wired |
| `XrpcProxyTests.testAtprotoProxyHeaderOverridesLocalHandler` | Proxy not returning expected JSON | Proxy test infrastructure issue |
| `XrpcProxyTests.testUnknownAppBskyMethodFallsBackToConfiguredProxy` | 404 instead of 200 | Fallback proxy routing not configured in test |

---

## Debugging Methodology

1. **Spec comparison**: Read the reference TypeScript `updateHandle.ts` from `bluesky-social/atproto` and compared line-by-line with the Objective-C implementation
2. **Formal code review**: Used structured code review to systematically identify all 6 deviations
3. **Layer-by-layer curl testing**: Tested CORS at each network layer (PDS:2583 → nginx:3000 → exe.dev HTTPS) to isolate where headers were lost
4. **Docker logs + grep**: `docker logs nspds 2>&1 | grep -i 'updateHandle'` to trace PLC operation failures on the VM
5. **PLC directory API**: `curl -s https://plc.directory/did:plc:.../log/audit | jq .` to verify operations were/weren't reaching the directory
6. **git stash comparison**: Stashed changes, ran tests, confirmed all 4 failures were pre-existing

## Files Modified

| File | Change |
|------|--------|
| `RateLimiter.h` / `.m` | Added generic `checkRateLimitForKey:limit:windowSeconds:` |
| `XrpcIdentityMethods.m` | Per-endpoint rate limiting, same-handle early return, alsoKnownAs preservation, identity event always sequenced, `resolveDid` endpoint, robust PLC parsing |
| `PDSAdminService.m` | Clarifying comment on admin `updateHandle:` |
| `RepoAuthIdentityTests.m` | Two new test cases |
| `XrpcHandler.m` | Dynamic CORS via `setCorsHeaders:` |
| `OAuth2Handler.m` | Dynamic CORS for all OAuth endpoints |
| `PDSHttpServerBuilder.m` | Dynamic CORS for XRPC OPTIONS and prefix handlers |
| `NodeInfoHandler.m` | Dynamic CORS for NodeInfo endpoints |
| `PDSConfiguration.h` / `.m` | Added `arrayForKey:` for config array access |
| `CMakeLists.txt` | Excluded `PDSAppleKeyManager.m` on non-Apple platforms |

---

## Part 3: Handle Resolution CORS (.well-known)

### Background

After fixing the main RPC CORS headers, handle resolution on `pdsls.dev` for subdomains (e.g., `newvmtest.garazyk.xyz`) was still failing. 

Browser behavior on `pdsls.dev`:
1. Attempts to fetch `https://newvmtest.garazyk.xyz/.well-known/atproto-did`.
2. Sends an `OPTIONS` preflight request.
3. PDS returned `404 Not Found` for `OPTIONS /.well-known/atproto-did`.

### Root Cause

In `PDSHttpServerBuilder.m`, the `.well-known` routes were registered using method-specific `addRoute:path:handler:` calls (GET/HEAD). While the XRPC layer had catch-all CORS handling, the `.well-known` endpoints were outside that dispatcher and lacked an `OPTIONS` handler.

Initial attempt to add a specific `OPTIONS` route via `addRoute:@"OPTIONS" ...` failed because the router's exact matching logic sometimes conflicted with how the PDS handles subdomains vs main domains.

### Fix: Method-Agnostic Path Handler

Changed the registration from method-specific routes to a method-agnostic path handler using `addHandlerForPath:`. This mirrors the robust pattern used for the `/xrpc` prefix.

**File:** `PDSHttpServerBuilder.m`

```objc
[server addHandlerForPath:@"/.well-known/atproto-did"
                  handler:^(HttpRequest *request, HttpResponse *response) {
                    [self setCorsHeaders:response forRequest:request];
                    NSString *method = request.methodString.uppercaseString;
                    if ([method isEqualToString:@"OPTIONS"]) {
                      response.statusCode = HttpStatusOK;
                    } else {
                      handleWellKnownAtprotoDid(request, response,
                                                [method isEqualToString:@"GET"]);
                    }
                  }];
```

This ensures:
1. `OPTIONS` requests are caught and return 200 OK + CORS headers.
2. `GET`/`HEAD` requests continue to serve the DID, but now with proper CORS headers.
3. The `setCorsHeaders:` helper matches the origin against `config.json` allowed origins.

---

## Deployment & Build Orchestration

### Workflow Refinement

Deploying these fixes to the production VM required several steps and surfaced some environmental nuances:

1. **Git Workflow**: Local changes were committed and pushed, then pulled on the server.
2. **Docker Rebuild**: Because the fix involved Objective-C source code, a simple container restart was insufficient. A full rebuild was required:
   ```bash
   docker compose up --build -d
   ```
3. **Container Conflict Resolution**: Encountered issues where `docker compose` would fail if a container with the same name (`nspds`) already existed but wasn't part of the current compose state. 
   **Fix**: Manually removed the conflicting container: `docker rm -f nspds`.
4. **Command Transition**: Noted that the server uses modern `docker compose` (V2) rather than the legacy `docker-compose` (Python).

### Verification

Final verification using `curl` confirmed success for both XRPC and `.well-known` endpoints:

```bash
# Verify Handle Resolution OPTIONS
curl -v -X OPTIONS https://newvmtest.garazyk.xyz/.well-known/atproto-did \
  -H "Origin: https://pdsls.dev"
# -> HTTP 200 OK
# -> access-control-allow-origin: https://pdsls.dev ✅
```

**Commits:** `1af4d9d` (initial OPTIONS route), `bd3c9a4` (final `addHandlerForPath` fix).
