# Troubleshooting: CORS & Rate Limiting — 2026-02-27

## Symptom

`witchsky.app` (a Bluesky client pointed at `pds.garazyk.xyz`) failed to log in or
load any data. Browser console showed a mix of errors:

- `Access-Control-Allow-Origin header contains multiple values '*, *'`
- `No 'Access-Control-Allow-Origin' header is present on the requested resource`
- `429 Too Many Requests`

---

## Architecture

```
Browser (witchsky.app)
  → HTTPS (TLS terminated at exe.dev LB, 100.20.12.135)
    → nginx (port 80/3000, keepalive 8 to upstream)
      → PDS Docker container (port 2583)
        → XrpcHandler dispatch
          → local handler (e.g. createSession)
          OR
          → AppView proxy (e.g. getPreferences → public.api.bsky.app)
```

---

## Issue 1: OPTIONS Preflight → 400

**Found by:** `curl -X OPTIONS` to `createSession` returned 400 instead of 200.

**Root cause:** `HttpServer.m` dispatches requests via prefix-matching path handlers
before the route trie. The `/xrpc` prefix handler in `PDSHttpServerBuilder.m` caught
OPTIONS requests and passed them to `XrpcDispatcher.handleRequest:response:`, which
tried to dispatch them as XRPC method calls and failed with 400.

**Fix:** Added an early return in `XrpcHandler.m` `handleRequest:response:` for
`HttpMethodOPTIONS` — returns 200 with CORS headers immediately.

```objc
// XrpcHandler.m — early return for OPTIONS
if (request.method == HttpMethodOPTIONS) {
    [response setHeader:@"*" forKey:@"Access-Control-Allow-Origin"];
    [response setHeader:@"GET, POST, OPTIONS, HEAD" forKey:@"Access-Control-Allow-Methods"];
    [response setHeader:@"Content-Type, Authorization, DPoP, *" forKey:@"Access-Control-Allow-Headers"];
    [response setHeader:@"86400" forKey:@"Access-Control-Max-Age"];
    response.statusCode = HttpStatusOK;
    return;
}
```

**File:** `ATProtoPDS/Sources/Network/XrpcHandler.m`

---

## Issue 2: Rate Limiter SQL Bug (counts never reset)

**Found by:** Even after waiting, requests continued to receive 429. Inspecting
`RateLimiter.m` showed the SQL `ON CONFLICT DO UPDATE` always incremented
`request_count` regardless of whether the time window had expired.

**Root cause:** The upsert SQL for both `rate_limits` and `blob_rate_limits` tables
used `request_count = request_count + 1` unconditionally on conflict. When the
window expired, the count should reset to 1, but it kept incrementing forever.

**Fix:** Changed the SQL to conditionally reset:

```sql
-- Before (buggy):
ON CONFLICT(ip_address) DO UPDATE SET
  request_count = request_count + 1,
  window_start = ...

-- After (fixed):
ON CONFLICT(ip_address) DO UPDATE SET
  request_count = CASE
    WHEN (strftime('%s','now') - window_start) >= ?
    THEN 1
    ELSE request_count + 1
  END,
  window_start = CASE
    WHEN (strftime('%s','now') - window_start) >= ?
    THEN strftime('%s','now')
    ELSE window_start
  END
```

Also increased defaults from 100 req/60s to 3000 req/300s.

**File:** `ATProtoPDS/Sources/Network/RateLimiter.m`

---

## Issue 3: Duplicate CORS from `applySecurityHeaders`

**Found by:** Browser showed `Access-Control-Allow-Origin: *, *`. Traced to
`HttpResponse.m` `applySecurityHeaders:` which sets CORS headers in `init`,
AND individual route handlers also setting them.

**Root cause:** `applySecurityHeaders` is called in every `HttpResponse init`,
setting `Access-Control-Allow-Origin: *`. Route handlers in
`PDSHttpServerBuilder.m` then set the same header again. While an
`NSMutableDictionary` overwrites (so this alone wouldn't duplicate), the
combination with the proxy issue (Issue 6) created `*, *`.

**Fix:** Removed CORS headers from `applySecurityHeaders`. Added explicit CORS
headers in `XrpcHandler.m` for all non-OPTIONS responses (single authoritative
source).

**File:** `ATProtoPDS/Sources/Network/HttpResponse.m`

---

## Issue 4: Nginx 502 from Keep-Alive Race

**Found by:** `curl -X POST` to `refreshSession` through HTTPS returned 502. Nginx
error log showed:

```
upstream prematurely closed connection while reading response header from upstream
```

**Root cause:** Nginx maintains `keepalive 8` connections to the PDS. The PDS
occasionally closes idle connections. When nginx reuses a connection the PDS has
already started closing, the request fails with 502. For GET requests, nginx retries
via `proxy_next_upstream error`. For POST requests, nginx does NOT retry by default
because POST is non-idempotent.

**Fix:** Added `non_idempotent` to `proxy_next_upstream` in all nginx location
blocks:

```nginx
# Before:
proxy_next_upstream error timeout http_502;

# After:
proxy_next_upstream error timeout http_502 non_idempotent;
```

**File:** `/etc/nginx/sites-enabled/garazyk.xyz` on VM

---

## Issue 5: POST with Empty Body → 411

**Found by:** After fixing the 502, `refreshSession` (a POST with no body) returned
411 Length Required. The browser sent `Content-Length: 0` which is valid HTTP.

**Root cause:** `HttpServer.m` line 548 checked
`state.expectedBodyLength == 0` to detect missing Content-Length, but
`Content-Length: 0` is parsed as `expectedBodyLength = 0` — so valid empty-body
POSTs were rejected.

**Fix:** Changed the check to look at whether the Content-Length *header* is present,
not whether its value is zero:

```objc
// Before (buggy):
if (expectsBody && !state.isChunkedEncoding &&
    state.expectedBodyLength == 0) {

// After (fixed):
if (expectsBody && !state.isChunkedEncoding &&
    contentLengthHeader.length == 0) {
```

**File:** `ATProtoPDS/Sources/Network/HttpServer.m`

---

## Issue 6: Duplicate CORS from AppView Proxy

**Found by:** After all previous fixes, browser tests showed:
- `getSession`, `refreshSession` (local handlers) → single `*` ✅
- `getPreferences`, `getProfile` (proxied to AppView) → `*, *` ❌

One failing response included `X-Powered-By: Express`, confirming it came from the
upstream AppView.

**Root cause:** `XrpcHandler.m` sets `Access-Control-Allow-Origin: *` before
dispatch (line 50). For proxied requests, `proxyXrpcRequest()` in
`XrpcMethodRegistry.m` copies ALL upstream response headers (line 644-664),
including the AppView's own `Access-Control-Allow-Origin: *`. The response now
has two values: ours + the AppView's.

**Fix:** Added CORS headers to the `isProxyHopByHopHeader` blocked set so they're
stripped from proxied responses:

```objc
blocked = [NSSet setWithArray:@[
  @"connection", @"keep-alive", @"proxy-authenticate",
  @"proxy-authorization", @"te", @"trailer", @"transfer-encoding",
  @"upgrade", @"host", @"content-length", @"atproto-proxy",
  // Strip upstream CORS headers — our XrpcHandler sets these.
  @"access-control-allow-origin", @"access-control-allow-methods",
  @"access-control-allow-headers", @"access-control-max-age",
  @"access-control-expose-headers"
]];
```

**File:** `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`

---

## Debugging Methodology

1. **Browser console** → identified the error types (CORS `*, *`, 429, missing header)
2. **`curl -v`** at each layer (PDS direct, nginx, HTTPS) → isolated where headers changed
3. **SSH + docker logs** → found nginx 502 errors and the keep-alive race
4. **Code tracing** → followed `HttpResponse.init` → `applySecurityHeaders` → serialization
5. **Browser subagent** → confirmed POST vs GET behavior difference and identified proxied
   endpoints as the remaining failure
6. **`X-Powered-By: Express`** → confirmed the `*, *` source was the upstream AppView

## Files Modified

| File | Commit | Change |
|------|--------|--------|
| `XrpcHandler.m` | `cb20c5b` | OPTIONS early return + CORS on all responses |
| `HttpResponse.m` | `cb20c5b` | Removed CORS from `applySecurityHeaders` |
| `RateLimiter.m` | `2323a74` | Fixed SQL reset + increased limits |
| `RateLimiter.m` | `d21edf7` | Increased IP rate limit defaults |
| `HttpServer.m` | `64a2277` | Allow POST with `Content-Length: 0` |
| `XrpcMethodRegistry.m` | `290402d` | Strip upstream CORS in proxy |
| nginx (VM only) | — | Added `non_idempotent` to retry config |

## Operational Notes

- **Rate limit DB**: If rate limiting persists after fixes, delete the stale database:
  ```bash
  docker exec nspds rm -f /var/lib/atprotopds/service/ratelimits.db
  docker exec nspds rm -f /var/lib/atprotopds/data/service/ratelimits.db
  docker restart nspds
  ```
- **Nginx config**: The `non_idempotent` fix is only on the VM, not in the repo's
  `deploy/nginx.conf`. Update the repo config to match if deploying elsewhere.
