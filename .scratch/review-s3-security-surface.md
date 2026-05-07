# S3: Security Surface Synthesis

## Attack Surface Map

The Garazyk PDS exposes four primary trust boundaries:

| Boundary | Entry Point | Auth Mechanism | Current State |
|----------|-------------|----------------|---------------|
| **Public XRPC** | HTTP/XRPC endpoints | Bearer token / OAuth2 | Multiple bypass paths |
| **Admin XRPC** | `tools.ozone.*` endpoints | Admin DID extraction | Effectively open |
| **WebSocket** | `/xrpc/com.atproto.sync.subscribeRepos` | Optional cursor auth | No handshake validation |
| **Blob Upload** | `com.atproto.repo.uploadBlob` | Bearer token + MIME sniffing | Magic-number bypass |
| **AppView Admin** | AppView admin routes | `APPVIEW_ADMIN_SECRET` env var | Open when unset |

Secondary surfaces:

| Boundary | Entry Point | Risk |
|----------|-------------|------|
| **PLC Server** | HTTP API on 127.0.0.1 | Weak signature pre-validation |
| **WASM Kernel** | Jupyter notebook input | DoS via invalid pointer deref |
| **Relay** | Upstream WebSocket connections | No flow control, backpressure bypass |

---

## Threat Categories

### 1. Authentication Bypass (5 findings)

| ID | Source | Severity | Exploitability | Impact | Description |
|----|--------|----------|----------------|--------|-------------|
| AUTH-1 | R4 | CRITICAL | **High** — any HTTP client can send a header | **Critical** — full admin access | `tools.ozone.*` endpoints check `authHeader != nil` instead of `adminDid != nil`. Any non-empty `Authorization` header passes the auth gate. Affects 12+ admin endpoints. |
| AUTH-2 | R5 | CRITICAL | **High** — forge a JWT with any allowed remote `iss` | **Critical** — arbitrary token forgery | `AuthVerifier` fetches JWKS for remote issuers but never uses the keys to verify the JWT signature. Any forged JWT with a valid-looking remote issuer passes. |
| AUTH-3 | R7 | HIGH | **Medium** — requires missing env var | **High** — full admin access | AppView admin routes allow open access when `APPVIEW_ADMIN_SECRET` is unset. Default deployments are vulnerable. |
| AUTH-4 | R2 | HIGH | **Medium** — requires expired token | **High** — session takeover | `PDSSQLiteSessionRepository` never checks `expires_at` when looking up refresh tokens. Expired tokens remain usable indefinitely. |
| AUTH-5 | R5 | HIGH | **Medium** — requires token theft | **High** — long-lived token misuse | Refresh tokens are stateless JWTs with no server-side revocation. Access tokens can be replayed at the refresh endpoint because there's no token-type claim distinction. |

### 2. Server-Side Request Forgery (1 finding)

| ID | Source | Severity | Exploitability | Impact | Description |
|----|--------|----------|----------------|--------|-------------|
| SSRF-1 | R4 | HIGH/CRITICAL | **High** — single HTTP header | **Critical** — internal network access | `XrpcProxyInterceptor` honors client-supplied `atproto-proxy` headers without trust boundary checks. Accepts absolute URLs as proxy targets. Runs before protected-method dispatch, so it can override local method handling. Forwards most inbound headers to the upstream target. |

### 3. Crypto & Protocol Weaknesses (4 findings)

| ID | Source | Severity | Exploitability | Impact | Description |
|----|--------|----------|----------------|--------|-------------|
| CRYPTO-1 | R5 | HIGH | **Medium** — requires captured proof | **Medium** — replay within validity window | DPoP replay protection is not enforced because `AuthVerifier` passes `replayChecker:nil`. A captured DPoP proof can be replayed. |
| CRYPTO-2 | R5 | HIGH | **Low** — requires MITM position | **Medium** — client metadata downgrade | Dynamic client ID handling accepts `http://` client IDs, violating the OAuth client metadata security model. |
| CRYPTO-3 | R5 | MEDIUM | **Medium** — requires code interception | **Medium** — code exchange without PKCE | Legacy OAuth session flow allows PKCE verifier omission. If `codeVerifier` is absent, the exchange still proceeds. |
| CRYPTO-4 | R7 | MEDIUM | **Low** — requires DB access | **Medium** — privacy breach | `ContactService` hashes phone numbers without a salt, making rainbow table attacks feasible. |

### 4. Input Validation Gaps (5 findings)

| ID | Source | Severity | Exploitability | Impact | Description |
|----|--------|----------|----------------|--------|-------------|
| VAL-1 | R2 | MEDIUM | **Medium** — crafted AT URI | **Medium** — reference ambiguity | AT URI parsing accepts malformed paths. `did`, `collection`, and `rkey` are never validated. Extra path segments are silently ignored. |
| VAL-2 | R2 | MEDIUM | **Low** — requires crafted CBOR | **Medium** — invalid CID acceptance | `cidFromTaggedValue:` strips the first byte unconditionally without checking for the required `0x00` marker. Malformed CID tags are accepted. |
| VAL-3 | R2 | MEDIUM | **Low** — requires crafted CAR data | **Medium** — unsigned commits accepted | `RepoCommit.fromCARData:` doesn't enforce `version == 3` and accepts commits without signatures. |
| VAL-4 | R3 | MEDIUM-HIGH | **High** — upload a <12 byte blob | **Medium** — MIME type spoofing | Magic-number validation is skipped for blobs under 12 bytes. A malicious upload can claim any MIME type while avoiding signature checks. |
| VAL-5 | R6 | MEDIUM | **Low** — requires MITM position | **Medium** — fake WebSocket upgrade | WebSocket handshake doesn't validate `Sec-WebSocket-Accept` header. A MITM could inject a fake 101 response. |

### 5. Denial of Service (3 findings)

| ID | Source | Severity | Exploitability | Impact | Description |
|----|--------|----------|----------------|--------|-------------|
| DOS-1 | R1 | HIGH | **High** — any notebook user | **Medium** — kernel crash | `isKindOfClass:`/`isMemberOfClass:` can dereference invalid pointers in the WASM kernel, trapping the runtime. |
| DOS-2 | R6 | MEDIUM | **High** — connect with cursor=0 | **Medium** — memory exhaustion | SubscribeReposHandler replay sends events without backpressure checking. A slow consumer with cursor=0 can cause memory pressure. |
| DOS-3 | R6 | LOW | **High** — any firehose consumer | **Low** — no rate limiting | The event rate limiter timer handler is empty — events are processed as fast as they arrive. |

### 6. Defense-in-Depth Gaps (2 findings)

| ID | Source | Severity | Exploitability | Impact | Description |
|----|--------|----------|----------------|--------|-------------|
| DEEP-1 | R6 | MEDIUM | **Low** — requires crafted PLC op | **Low** — PLCAuditor catches it | PLCServer `sig` field check only verifies the value is a string not ending with `=`. A 1-character string passes. Actual crypto verification happens in PLCAuditor, so this is defense-in-depth. |
| DEEP-2 | R3 | MEDIUM | **Low** — requires partial failure | **Medium** — blob unavailability | Upload deduplication trusts stale metadata. If provider data was lost, re-upload returns success without repairing the missing blob. |

---

## Attack Chains

### Chain 1: SSRF + Ozone Auth Bypass → Internal Admin Access

**Steps:**
1. Attacker sends a request to any `tools.ozone.*` endpoint with:
   - `Authorization: Bearer anything` (passes the `authHeader != nil` check in AUTH-1)
   - `atproto-proxy: http://internal-service:8080/` (triggers SSRF-1)
2. The proxy interceptor redirects the request to the internal service, forwarding the `Authorization` header
3. The internal service receives an authenticated-looking request from the PDS itself

**Risk:** An external attacker can reach internal services through the PDS, with the PDS's own identity as the source. The Ozone auth bypass means no valid credentials are needed.

**Combined severity:** CRITICAL — two independent bypasses compound into a full internal network access vector.

### Chain 2: Remote Issuer Forgery + Ozone Auth Bypass → Admin Account Takeover

**Steps:**
1. Attacker forges a JWT with `iss: "allowed-remote-issuer.example.com"` and arbitrary claims (AUTH-2 — signature never verified)
2. Sends the forged JWT to any `tools.ozone.*` endpoint (AUTH-1 — only checks header presence)
3. The admin DID extracted from the forged JWT's claims is used for authorization decisions

**Risk:** An attacker can impersonate any admin user by forging a remote-issuer JWT and passing it through the Ozone auth gate.

**Combined severity:** CRITICAL — two independent auth failures allow complete admin impersonation.

### Chain 3: DPoP Replay + Token Type Confusion → Persistent Access

**Steps:**
1. Attacker captures a DPoP proof from a legitimate request (CRYPTO-1 — no replay checker)
2. Replays the proof within the validity window to obtain a new access token
3. Uses the access token at the refresh endpoint (AUTH-5 — no token-type distinction)
4. Obtains a refresh token that cannot be revoked (AUTH-5 — stateless JWT, no server-side tracking)

**Risk:** A single captured request can be escalated into persistent, irrevocable access.

**Combined severity:** HIGH — requires initial token capture but yields persistent access.

### Chain 4: WebSocket MITM + Firehose Manipulation

**Steps:**
1. Attacker in MITM position intercepts WebSocket upgrade (VAL-5 — no Sec-WebSocket-Accept validation)
2. Injects a fake 101 response to establish a controlled WebSocket connection
3. Sends crafted firehose events to the client (e.g., fake `#identity` events to change DID mappings)

**Risk:** A network-level attacker can inject fake events into the firehose consumer, potentially causing incorrect DID resolution or record processing.

**Combined severity:** MEDIUM — requires MITM position, but impact is data integrity corruption.

---

## Priority Recommendations

### P0 — Fix Immediately (Active Exploit Risk)

1. **Fix Ozone auth gate (AUTH-1)** — Check `adminDid` not `authHeader`. This is a one-line fix per method that eliminates the most exploitable auth bypass. Centralize the auth gate in a helper to prevent recurrence.

2. **Verify remote-issuer JWT signatures (AUTH-2)** — After JWKS retrieval, instantiate a verifier with the fetched keys and require a successful signature check. This closes the most critical crypto gap.

3. **Restrict `atproto-proxy` handling (SSRF-1)** — Only honor the header from trusted internal sources. Reject absolute URLs from untrusted requests. Ensure protected/local methods cannot be overridden by client-supplied proxy headers.

### P1 — Fix Before Production (High Risk)

4. **Enforce admin secret requirement (AUTH-3)** — If `APPVIEW_ADMIN_SECRET` is unset, admin routes should refuse to start rather than allowing open access.

5. **Check refresh token expiration (AUTH-4)** — Add `expires_at > now` to the `accountDidForRefreshToken:` query. One-line SQL fix.

6. **Bind refresh tokens server-side (AUTH-5)** — Store refresh tokens in the database, add a `token_use` claim, and reject access tokens at the refresh endpoint.

7. **Wire DPoP replay checker (CRYPTO-1)** — Pass a real replay cache to `AuthCryptoDPoP.verifyProof:...` instead of `nil`.

### P2 — Fix Before Public Beta (Medium Risk)

8. **Remove magic-number size gate (VAL-4)** — Let the sniffer validate whatever bytes are available. Fail closed for blob categories that require signature validation.

9. **Require HTTPS client IDs (CRYPTO-2)** — Reject `http://` client IDs in production, with only loopback exceptions for development.

10. **Mandate PKCE verifier (CRYPTO-3)** — Treat `code_verifier` as mandatory whenever `code_challenge` was issued.

11. **Validate Sec-WebSocket-Accept (VAL-5)** — Compute the expected hash and compare against the response header per RFC 6455 section 4.2.2.

12. **Salt phone number hashes (CRYPTO-4)** — Add a server-side salt to `ContactService` hashing. Add rate limiting for contact lookup endpoints.

13. **Validate AT URI components (VAL-1)** — Require exactly three path components and validate each with existing DID/NSID/rkey validators.

14. **Enforce CID tag marker (VAL-2)** — Require the first byte of tag-42 values to be exactly `0x00`.

15. **Enforce RepoCommit structure (VAL-3)** — Hard-fail when `version != 3` and when signature is missing.

### P3 — Hardening (Defense in Depth)

16. **Harden PLC sig pre-validation (DEEP-1)** — Verify the `sig` field is valid base64url and decodes to a reasonable length.

17. **Verify blob provider on dedup (DEEP-2)** — Check provider presence before treating existing metadata as a complete hit.

18. **Add backpressure to replay (DOS-2)** — Use `sendEventData:toConnectionWithBackpressureCheck:` during replay.

19. **Harden WASM kernel class checks (DOS-1)** — Only accept known class markers in `isKindOfClass:`/`isMemberOfClass:` fallback.
