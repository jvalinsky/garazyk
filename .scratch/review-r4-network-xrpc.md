# R4 Network / XRPC Security Review

Scope: `Garazyk/Sources/Network/*` with emphasis on XRPC dispatch, auth, and proxying.

## Findings

### 1) Critical: `tools.ozone.*` admin endpoints skip auth failures if any Authorization header is present

`XrpcToolsOzonePack.m` repeatedly calls `XrpcAuthHelper extractDIDFromAuthHeader:...` but then only checks whether `authHeader` is non-nil:

- `if (!authHeader) return;`
- not `if (!adminDid) return;`

That means any request with a syntactically non-empty `Authorization` header continues down the privileged code path even if token parsing/verification failed and the helper already set a 401 response. The handler later overwrites the response with success, so invalid auth still reaches the endpoint logic.

This affects many admin-only moderation and configuration methods, including but not limited to:

- `tools.ozone.moderation.getRecord`
- `tools.ozone.moderation.getRecords`
- `tools.ozone.moderation.getRepo`
- `tools.ozone.moderation.getRepos`
- `tools.ozone.moderation.searchRepos`
- `tools.ozone.team.listMembers`
- `tools.ozone.set.getValues`
- `tools.ozone.verification.listVerifications`
- `tools.ozone.safelink.queryRules`
- `tools.ozone.safelink.queryEvents`
- `tools.ozone.setting.listOptions`
- `tools.ozone.signature.findRelatedAccounts`
- `tools.ozone.signature.findCorrelation`

Observed pattern in the file is repeated many times, e.g. at lines 138-141, 163-166, 189-192, 214-217, 240-243, and onward.

**Impact:** authentication bypass for a large set of Ozone admin endpoints, including read and write operations.

**Recommended fix:** check the return value from `extractDIDFromAuthHeader` and return immediately on failure. Centralizing the auth gate in a helper would prevent this class of mistake from recurring.

---

### 2) High/Critical: attacker-controlled `atproto-proxy` values can force SSRF and bypass local method protection

`XrpcProxyInterceptor.m` honors the inbound `atproto-proxy` header directly from the client:

- `explicitProxyTarget = [request headerForKey:@"atproto-proxy"]`
- if present, it immediately proxies using that descriptor
- the descriptor can be either a DID reference or an absolute URL (`proxyBaseURLFromDescriptor` accepts direct URLs)

There is no trust boundary check that the caller is a verified internal service. As a result, a public request can cause the PDS to fetch attacker-chosen URLs, including internal/private destinations, and the proxy code forwards most inbound headers to the upstream target.

This is especially problematic because the interceptor runs before normal dispatch, so it can override the dispatcher’s protected-method handling. Only two methods are forcibly kept local (`com.atproto.identity.resolveDid` and `com.atproto.identity.updateHandle`); every other method can be redirected if `atproto-proxy` is present.

Relevant code paths:

- `XrpcProxyInterceptor.m:464-480` — explicit `atproto-proxy` header is honored
- `XrpcProxyInterceptor.m:99-118` — absolute URLs are accepted as proxy targets
- `XrpcProxyInterceptor.m:260-333` — upstream request is built and headers are forwarded
- `XrpcHandler.m:216-247` / protected-method logic is bypassable because the request interceptor handles the request first

**Impact:** SSRF against internal services and arbitrary upstream redirection, plus potential leakage of client headers/tokens to attacker-controlled endpoints.

**Recommended fix:** only honor `atproto-proxy` from trusted internal sources, reject absolute URLs from untrusted requests, and ensure protected/local methods cannot be overridden by client-supplied proxy headers.

---

## Notes

- I did not find a comparable SSRF issue in the lexicon resolver path; `XrpcLexiconResolver.m` includes a public-IP validation step before fetching authority-hosted records.
- No code changes were made as part of this review.
