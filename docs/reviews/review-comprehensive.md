# Garazyk ATProto PDS — Comprehensive Code Review

**Date:** 2026-05-06
**Scope:** Full PDS codebase (~360 headers, ~283 test files) plus WASM kernel (light review)
**Method:** 7 parallel research agents → 4 cross-cutting synthesis agents → this integration

---

## Executive Summary

A deep code review of the Garazyk ATProto PDS identified 5 critical, 12 high, and 20+ medium-severity issues across authentication, firehose/sync, repository encoding, and AppView services. The three most urgent concerns are: (1) multiple authentication bypass paths that allow unauthenticated admin access and remote-issuer token forgery, (2) a protocol-breaking firehose bug where sequence numbers are never assigned to events, rendering cursor-based replay non-functional, and (3) a systemic schema mismatch in AppView where services reference tables that don't exist in the database. The codebase has solid architectural instincts — modular domain separation, validation infrastructure, and correct high-level patterns — but boundary enforcement is uneven, and several "plumbing exists, safety check missing" gaps undermine otherwise sound design.

---

## Critical Findings (Must Fix Immediately)

### C1. Ozone admin auth gate checks header presence, not auth result
- **File:** `Garazyk/Sources/Network/XrpcToolsOzonePack.m` (lines 138-141, 163-166, 189-192, and onward)
- **Description:** `XrpcToolsOzonePack` calls `XrpcAuthHelper extractDIDFromAuthHeader:...` but then checks `if (!authHeader) return;` instead of `if (!adminDid) return;`. Any request with a non-empty `Authorization` header passes the auth gate, even if token parsing/verification failed and the helper already set a 401 response. The handler then overwrites the 401 with success.
- **Impact:** Authentication bypass for 12+ admin-only `tools.ozone.*` endpoints, including read and write moderation operations.
- **Fix:** Check the returned DID/token result, not the header presence. Centralize the auth gate in a helper to prevent recurrence.

### C2. Remote-issuer JWTs are not signature-verified
- **File:** `Garazyk/Sources/Auth/Verifier/AuthVerifier.m`
- **Description:** When a token comes from a non-local issuer, `AuthVerifier` fetches JWKS but never uses the returned keys to verify the JWT signature. The local issuer path correctly verifies; the remote path does not.
- **Impact:** Any forged JWT with an allowed remote `iss` can pass as long as the claims look valid. This is arbitrary token forgery for any trusted remote issuer.
- **Fix:** After JWKS retrieval, instantiate a verifier with the fetched keys and require a successful signature check before continuing.

### C3. Firehose sequence numbers are never assigned to events
- **File:** `Garazyk/Sources/Sync/Firehose/FirehoseProtocolSession.m:23-35`
- **Description:** `encodeCommitEvent:` increments `_sequenceNumber` and captures it into local `seq`, but never assigns `event.seq = seq` before encoding. The same bug exists in `encodeIdentityEvent:`, `encodeAccountEvent:`, and `encodeInfoEvent:`. Events go out with `seq=0` or stale values.
- **Impact:** All firehose events are broadcast with broken sequence numbers. Cursor-based replay, resume, deduplication, and gap detection are completely non-functional. This is a protocol-breaking bug.
- **Fix:** Add `event.seq = seq;` before encoding in each encode method.

### C4. Client-controlled `atproto-proxy` header enables SSRF
- **File:** `Garazyk/Sources/Network/XrpcProxyInterceptor.m:464-480, 99-118`
- **Description:** `XrpcProxyInterceptor` honors the `atproto-proxy` header directly from client requests, including absolute URLs as proxy targets. There is no trust boundary check. The interceptor runs before normal dispatch, so it can override protected-method handling for all but two methods.
- **Impact:** External attackers can cause the PDS to fetch arbitrary URLs (including internal services), forwarding most inbound headers to the upstream target. Combined with C1, this yields full internal network access without valid credentials.
- **Fix:** Only honor `atproto-proxy` from trusted internal sources. Reject absolute URLs from untrusted requests. Ensure protected/local methods cannot be overridden by client-supplied proxy headers.

### C5. AppView services reference PDS tables that don't exist
- **File:** `Garazyk/Sources/AppView/Server/AppViewRuntime.m`, `AppViewDatabase.m`
- **Description:** `AppViewRuntime` wires several services to `AppViewDatabase`, but many services (`DraftService`, `ContactService`, `NotificationService`, `ActorService` preferences, `GraphService` mutes/starter packs, `BookmarkService`) issue SQL against PDS-style tables that don't exist in the AppView DB.
- **Impact:** Large chunk of the AppView read/write surface will fail at runtime with `no such table` errors.
- **Fix:** Align the service layer with the actual AppView schema, or split AppView/PDS data access cleanly.

---

## High Findings (Fix Before Production)

### H1. Firehose client silently drops `#account`, `#sync`, and `#info` events
- **File:** `Garazyk/Sources/Sync/Firehose/Firehose.m:120-176`
- **Description:** `#account` events are constructed but never dispatched to subscriptions. `#sync` and `#info` events have no handler at all. The `FirehoseEventKind` enum is missing `FirehoseEventKindAccount`.
- **Impact:** Firehose subscribers miss account status events (takedowns, deactivations), sync fallback events, and info events (cursor adjustments). Consumers relying on these for moderation or gap recovery will miss them entirely.
- **Fix:** Add `FirehoseEventKindAccount` to the enum, add corresponding delegate methods, and dispatch all event types in `handleMessage:`.

### H2. WebSocket heartbeat epoch mismatch — dead connections never detected
- **File:** `Garazyk/Sources/Sync/WebSocket/WebSocketConnection.m:432` vs `WebSocketProtocolSession.m:75`
- **Description:** `handlePongFrame:` records pong timestamps using `timeIntervalSince1970`, but the heartbeat policy tracks ping times using `timeIntervalSinceReferenceDate`. These are ~978 million seconds apart. The `waitingForPong` flag is immediately cleared, so heartbeat timeouts never fire.
- **Impact:** Dead WebSocket connections are never cleaned up by the heartbeat mechanism. They linger until TCP reset, accumulating stale state and memory.
- **Fix:** Use the same time base consistently (either `timeIntervalSinceReferenceDate` or `timeIntervalSince1970`) for both ping and pong tracking.

### H3. Refresh tokens are stateless JWTs with no revocation; access tokens accepted at refresh endpoint
- **File:** `Garazyk/Sources/Auth/OAuthProvider/OAuthProvider.m`, `Garazyk/Sources/Auth/PDS/PDSAuth.m`
- **Description:** `PDSAuthTokenSigner verifyRefreshToken:` delegates to `verifyAccessToken:forAudience:`. There is no token-type claim, and no server-side lookup for revocation. Refresh tokens cannot be revoked without key rotation.
- **Impact:** Token-type confusion (access tokens work at refresh endpoint) and irrevocable refresh tokens make token theft much more damaging.
- **Fix:** Store refresh tokens server-side, add a `token_use` claim, and reject anything not explicitly marked as a refresh token.

### H4. Expired refresh tokens are still accepted
- **File:** `Garazyk/Sources/Core/Repositories/PDSSQLiteSessionRepository.m:46-63`
- **Description:** `accountDidForRefreshToken:` never checks the `expires_at` column. Expired tokens remain usable indefinitely.
- **Impact:** Session replay and account takeover through expired refresh tokens.
- **Fix:** Add `expires_at > now` to the lookup query.

### H5. DPoP replay protection is not enforced
- **File:** `Garazyk/Sources/Auth/Verifier/AuthVerifier.m`, `Garazyk/Sources/Auth/Crypto/AuthCryptoDPoP.m`
- **Description:** `AuthVerifier` calls `verifyProof:... replayChecker:nil`. Replay prevention only happens when a checker is provided.
- **Impact:** Captured DPoP proofs can be replayed within the validity window.
- **Fix:** Pass a real replay cache to all DPoP verification calls.

### H6. AppView admin endpoints open when `APPVIEW_ADMIN_SECRET` is unset
- **File:** `Garazyk/Sources/AppView/Server/Admin/AppViewAdminRoutePack.m`
- **Description:** Default deployments allow open admin access when the environment variable is not set.
- **Impact:** Any request to admin endpoints is accepted without authentication.
- **Fix:** If `APPVIEW_ADMIN_SECRET` is missing, admin routes should refuse to start.

### H7. Disk blob retrieval capped at 5 MB while validator allows 50-100 MB
- **File:** `Garazyk/Sources/Blob/PDSDiskBlobProvider.m:67-88`
- **Description:** `retrieveBlobDataForCID:` caps in-memory reads at 5 MB, but `MimeTypeValidator` allows up to 50 MB (video) and 100 MB (models). Blobs above 5 MB can be stored successfully but fail on every read.
- **Impact:** Large blobs become permanently unreadable despite successful upload.
- **Fix:** Use streaming or file-handle-based retrieval for large blobs, or raise the in-memory cap to match validation limits.

### H8. WebSocket `startReading` re-entry creates recursive read loop
- **File:** `Garazyk/Sources/Sync/WebSocket/WebSocketConnection.m:269-305`
- **Description:** The completion handler for `receiveWithMinimumLength:` calls `startReading` directly (not dispatched to main queue), potentially causing overlapping reads.
- **Impact:** Double-read or read-after-cancel on the underlying connection.
- **Fix:** Ensure `startReading` is only called from a single dispatch context, or add a guard against re-entrancy.

### H9. WebSocket `closeWithCode:reason:` has race with `sendFrame:`
- **File:** `Garazyk/Sources/Sync/WebSocket/WebSocketConnection.m:439-466`
- **Description:** Close sets state on the main thread but clears the message queue on `writeQueue`. A `sendFrame:` already queued on `writeQueue` can execute between the state change and the queue clear.
- **Impact:** Out-of-order close/frame writes, or a frame written after the queue was "cleared."
- **Fix:** Perform all close-related state transitions on `writeQueue` to ensure ordering.

### H10. Non-HTTPS client IDs accepted
- **File:** `Garazyk/Sources/Auth/PDS/PDSAuth.m`
- **Description:** `PDSAuthClientRegistry` accepts both `http://` and `https://` client IDs.
- **Impact:** Enables downgrade or MITM attacks against client metadata retrieval.
- **Fix:** Require HTTPS client IDs in production, with loopback exceptions for development.

### H11. WASM kernel `isKindOfClass:`/`isMemberOfClass:` can dereference invalid pointer
- **File:** `objc-jupyter-wasm/kernel/objc_interp_messages.c`
- **Description:** Fallback to `object_getClass((id)obj_deref(...))` for non-class arguments can dereference an invalid pointer when a user passes a non-object interpreter handle.
- **Impact:** WASM runtime crash from user code — denial of service in the Jupyter kernel.
- **Fix:** Only accept known class markers or verified runtime class objects in the fallback path.

### H12. NotificationService uses read API for write operations
- **File:** `Garazyk/Sources/AppView/Services/NotificationService.m`
- **Description:** `markNotificationsAsReadForActor:` and `putPreferencesForActor:` use the query API instead of the update API.
- **Impact:** Write operations silently fail or have no effect.
- **Fix:** Switch to the correct update/write API for mutation operations.

---

## Medium Findings (Fix in Next Sprint)

### Repository & Encoding
- **M1.** MST key prefix handling mixes character counts with UTF-8 byte offsets — non-ASCII keys corrupted on save/load (`MST.m:232-286, 754-813`)
- **M2.** DAG-CBOR CID tag-42 marker byte not verified — malformed CIDs accepted (`MSTPersistence.m:195-238`)
- **M3.** RepoCommit parsing doesn't enforce `version == 3` or require `sig` — unsigned commits accepted (`RepoCommit.m:135-221`)
- **M4.** AT URI parsing accepts malformed paths, skips component validation (`ATURI.m:12-30`)

### Blob & Storage
- **M5.** Magic-number validation skipped for blobs under 12 bytes — MIME type spoofing bypass (`BlobStorage.m:328-340`)
- **M6.** Upload deduplication trusts stale metadata — missing provider data unrepaired (`BlobStorage.m:83-97`)

### Auth & Crypto
- **M7.** PKCE verifier optional in legacy OAuth session flow — code exchange without PKCE proof (`OAuthSession.m`)
- **M8.** ContactService hashes phone numbers without salt — rainbow table attacks feasible (`ContactService.m`)

### Sync & WebSocket
- **M9.** SubscribeReposHandler replay doesn't check backpressure — memory exhaustion via cursor=0 (`SubscribeReposHandler.m:824-831`)
- **M10.** WebSocket handshake doesn't validate `Sec-WebSocket-Accept` header — MITM can inject fake 101 (`WebSocketConnection.m:352-380`)
- **M11.** Firehose cursor not passed in WebSocket URL — replay never works (`Firehose.m:61-78`)
- **M12.** WebSocketCodec doesn't reject reserved opcodes — should close with code 1003 (`WebSocketCodec.m:119-157`)
- **M13.** RelayEventBuffer `eventsAfterCursor:` is O(n) linear scan — should use binary search (`RelayEventBuffer.m:73-86`)
- **M14.** RelayEventBuffer `pruneExpired` is O(n) and not called automatically (`RelayEventBuffer.m:125-145`)

### WASM Kernel
- **M15.** Float values serialized as literal "0.0" regardless of actual value (`objc_interp_messages.c`)
- **M16.** JSON string emission doesn't escape control characters — invalid JSON output (`objc_interp_messages.c`)
- **M17.** Integer negation of INT_MIN is undefined behavior (`objc_interp_format.c`)

### PLC & Identity
- **M18.** PLCServer `handleExport:` doesn't validate `after` cursor format — nil cursor returns all data (`PLCServer.m:682-686`)

### AppView
- **M19.** FeedService has broken reply-count URI parse and ignores feed generator URI (`FeedService.m`)
- **M20.** AppViewGroupIndexer writes rows using schema that doesn't match AppViewDatabase (`AppViewGroupIndexer.m`)

---

## Architecture & Quality Assessment

The codebase is organized into clear domain-specific subsystems (core, repository, database, blob, auth, network, XRPC, sync, AppView, chat, PLC), and that separation is a real strength. The project has the right architectural instincts: validation infrastructure exists at boundaries, provider abstractions separate storage backends, and the sync subsystem models cursors, sequences, and backpressure as first-class concepts.

The main architectural weakness is **uneven boundary enforcement**. The codebase frequently has the right plumbing but the wrong safety check — or the check exists but is in the wrong place:

- Auth gates check header presence instead of auth result (C1)
- JWKS is fetched but never used for verification (C2)
- Sequence numbers are incremented but never assigned (C3)
- Proxy headers are honored without trust boundary checks (C4)
- Refresh token expiry is written but never checked on lookup (H4)
- DPoP replay checker is plumbed but passed `nil` (H5)
- Blob size limits exist in validation but not in retrieval (H7)
- Heartbeat timestamps use different epochs in the same comparison (H2)

This pattern — "plumbing exists, safety check missing" — is the dominant quality issue. It suggests the codebase was built with correct high-level understanding but needs stricter execution at the boundaries.

**Schema drift** is the second major architectural concern. AppView services reference PDS tables that don't exist in the AppView database, indexers write to columns that don't exist, and blob validation/retrieval disagree on size limits. This drift suggests the service layer and schema layer have evolved independently.

**Dual-path complexity** adds maintenance burden: legacy vs modern WebSocket paths, local vs remote token verification, client vs server firehose event handling, and PDS-style vs AppView-style persistence. These dual paths increase the surface for bugs and make it harder to reason about correctness.

---

## Security Assessment

The PDS has a **high-risk security posture** due to multiple independently exploitable authentication bypass paths that compound into critical attack chains.

### Attack Surface Map

| Boundary | Entry Point | Auth Mechanism | Current State |
|----------|-------------|----------------|---------------|
| Public XRPC | HTTP/XRPC endpoints | Bearer token / OAuth2 | Multiple bypass paths |
| Admin XRPC | `tools.ozone.*` | Admin DID extraction | Effectively open |
| WebSocket | `/xrpc/com.atproto.sync.subscribeRepos` | Optional cursor | No handshake validation |
| Blob Upload | `com.atproto.repo.uploadBlob` | Bearer + MIME sniffing | Magic-number bypass |
| AppView Admin | AppView admin routes | `APPVIEW_ADMIN_SECRET` | Open when unset |

### Critical Attack Chains

**Chain 1: SSRF + Ozone Auth Bypass → Internal Admin Access**
An attacker sends `Authorization: Bearer anything` (passes C1's header-presence check) with `atproto-proxy: http://internal-service:8080/` (triggers C4's SSRF). The PDS proxies the request to internal services with the PDS's own identity. Combined severity: CRITICAL.

**Chain 2: Remote Issuer Forgery + Ozone Auth Bypass → Admin Impersonation**
An attacker forges a JWT with an allowed remote `iss` (passes C2's unverified-remote path) and sends it to `tools.ozone.*` (passes C1's header-presence check). The admin DID from the forged JWT's claims is used for authorization. Combined severity: CRITICAL.

**Chain 3: DPoP Replay + Token Type Confusion → Persistent Access**
An attacker captures a DPoP proof (H5 — no replay checker), replays it to get an access token, then uses that access token at the refresh endpoint (H3 — no token-type distinction) to obtain an irrevocable refresh token. Combined severity: HIGH.

### Prioritized Security Remediation

1. **P0:** Fix Ozone auth gate (C1) — one-line fix per method
2. **P0:** Verify remote-issuer JWT signatures (C2) — use fetched JWKS
3. **P0:** Restrict `atproto-proxy` handling (C4) — trusted-internal-only
4. **P1:** Enforce admin secret requirement (H6)
5. **P1:** Check refresh token expiration (H4) — one-line SQL fix
6. **P1:** Bind refresh tokens server-side (H3) — add token-type claim
7. **P1:** Wire DPoP replay checker (H5) — pass real cache
8. **P2:** Remove magic-number size gate (M5)
9. **P2:** Require HTTPS client IDs (H10)
10. **P2:** Mandate PKCE verifier (M7)
11. **P2:** Validate Sec-WebSocket-Accept (M10)
12. **P2:** Salt phone number hashes (M8)

---

## Protocol Compliance Assessment

The implementation diverges from ATProto specifications in several critical areas:

### Firehose / Sync (Most Broken)
- **Sequence numbers:** Events are emitted with `seq=0` instead of monotonically increasing values. This breaks the core ATProto sync contract — consumers cannot resume, replay, or detect gaps.
- **Event types:** `#account`, `#sync`, and `#info` events are silently dropped by the client. The ATProto spec requires all event types to be surfaced.
- **Cursor handling:** The cursor is not passed in the WebSocket URL, making cursor-based subscriptions non-functional.
- **Backpressure:** Replay events are sent without backpressure checking, which can cause memory exhaustion.

### Repository / MST / CAR
- **MST encoding:** Non-ASCII keys are corrupted due to character-count/byte-offset confusion. The ATProto spec requires consistent UTF-8 byte handling.
- **DAG-CBOR CID tags:** The tag-42 `0x00` marker is not verified, allowing malformed CID links.
- **Commit structure:** Commits without `version=3` or without signatures are accepted, contradicting the spec.
- **AT URI validation:** Malformed `at://` references are normalized instead of rejected.

### Auth / OAuth
- **Remote issuer verification:** JWTs from remote issuers are trusted without signature verification, violating the OAuth trust model.
- **Refresh tokens:** Not revocable, not type-bound, and access tokens are accepted at the refresh endpoint.
- **DPoP:** Replay protection is disabled, violating the DPoP specification.

### Identity / PLC
- **PLC signature pre-validation:** Too weak — only checks that `sig` is a string not ending with `=`.
- **Export cursors:** Invalid `after` values silently fall back to the beginning.

---

## Concurrency & Memory Assessment

### Thread Safety Issues
- **WebSocket close/send race:** `closeWithCode:reason:` and `sendFrame:` can interleave on different dispatch contexts (H9). State transitions span the main thread and `writeQueue` without a unified state machine.
- **Recursive read loop:** `startReading` re-enters from its own completion handler without a guard against overlapping reads (H8).
- **RelayEventFilter setters:** Not synchronized — concurrent modification while reading can yield partially-updated sets (R6 LOW-7).
- **Queue confinement assumed but not enforced:** Several subsystems rely on serial queue discipline for correctness, but the discipline is not enforced by the API.

### Memory Lifecycle Issues
- **Unbounded subscription set:** Cancelled `FirehoseSubscription` objects remain in the owning set, growing without bound (R6 LOW-1).
- **Relay event buffer:** Retains up to 100k events, prunes only by count (not by time), and `pruneExpired` is never called automatically (R6 MED-7).
- **Replay without backpressure:** `SubscribeReposHandler` replay sends events directly without backpressure checking, potentially exceeding memory limits (M9).
- **No upstream flow control:** The relay pipeline has no mechanism to pause upstream consumption when downstream consumers are slow (R6 ARCH-3).

### Performance Issues
- **O(n) linear scan** in `RelayEventBuffer eventsAfterCursor:` — should use binary search on the sorted array (M13).
- **O(n) linear scan** in `RelayUpstreamManager urlForClient:` — should use a reverse mapping dictionary (R6 MED-4).
- **O(n) prune** in `RelayEventBuffer pruneExpired` — should use a more efficient data structure (M14).
- **Empty rate limiter:** The `eventRateLimiter` timer handler does nothing — events are processed as fast as they arrive (R6 LOW-6).

### Epoch Confusion
- The heartbeat system mixes `timeIntervalSinceReferenceDate` and `timeIntervalSince1970`, which are ~978 million seconds apart. This is not just a timestamp bug — it defeats the entire liveness detection mechanism (H2). Audit other time-based comparisons for the same class of bug.

---

## Positive Patterns

Several patterns are worth preserving because they give the codebase a solid foundation:

1. **Domain modularity** — The codebase is cleanly separated into domain-specific subsystems (core, repository, database, blob, auth, network, XRPC, sync, AppView, chat, PLC). This makes it possible to tighten boundaries without a full rewrite.

2. **Validation infrastructure** — Dedicated validators exist for DIDs, handles, AT URIs, CIDs, JWTs, PKCE, TOTP, and WebAuthn. The architecture is already thinking about boundary validation.

3. **Provider abstractions** — Blob storage uses a provider pattern (`PDSBlobProvider` protocol) with disk and cloud implementations. This makes it feasible to add safety checks in one place.

4. **Sync concept awareness** — The firehose and relay subsystems model cursors, sequences, and backpressure as first-class concepts. The architecture is correct; the implementation just needs to follow through.

5. **Newer paths are better** — The newer `OAuthProvider` authorization-code path correctly enforces PKCE when a code challenge is present. The modern HTTP upgrade path for WebSocket is cleaner than the legacy standalone server. This shows the codebase is improving.

6. **secp256k1 and TOTP implementations** — Use fixed-size inputs, deterministic patterns, and standard truncation/time-window logic. These are well-implemented.

7. **WebAuthn verifier** — Includes sign-count checks and signature format handling. Correct implementation of the spec.

8. **XrpcLexiconResolver** — Includes a public-IP validation step before fetching authority-hosted records. Shows the codebase can do SSRF prevention when it's top of mind.

---

## Prioritized Remediation Roadmap

### P0 — Fix Now (Active Exploit Risk)

| # | Issue | Effort | Impact |
|---|-------|--------|--------|
| 1 | Fix Ozone auth gate: check `adminDid` not `authHeader` | Small (1-line per method) | Eliminates most exploitable auth bypass |
| 2 | Verify remote-issuer JWT signatures with fetched JWKS | Medium | Closes arbitrary token forgery |
| 3 | Restrict `atproto-proxy` to trusted-internal-only, reject absolute URLs | Medium | Removes SSRF vector |
| 4 | Assign firehose `event.seq` before encoding | Small (1-line per method) | Restores core ATProto sync contract |
| 5 | Add `FirehoseEventKindAccount` enum, dispatch `#account`/`#sync`/`#info` events | Medium | Restores full event stream |

### P1 — Fix This Week (High Risk)

| # | Issue | Effort | Impact |
|---|-------|--------|--------|
| 6 | Enforce admin secret requirement for AppView | Small | Prevents default-open admin access |
| 7 | Check `expires_at` in refresh-token lookup | Small (1-line SQL) | Prevents expired-token reuse |
| 8 | Store refresh tokens server-side, add `token_use` claim | Medium | Enables revocation, prevents type confusion |
| 9 | Wire DPoP replay checker (pass real cache, not nil) | Small | Enables DPoP anti-replay |
| 10 | Unify heartbeat epoch (use one time base) | Small | Restores dead-connection detection |
| 11 | Fix WebSocket `startReading` re-entrancy guard | Small | Prevents double-read |
| 12 | Fix WebSocket close/send race (unify on writeQueue) | Small | Prevents out-of-order writes |
| 13 | Fix disk blob retrieval cap (stream or raise limit) | Medium | Makes large blobs readable |
| 14 | Align AppView services with AppViewDatabase schema | Large | Eliminates runtime `no such table` errors |

### P2 — Fix This Month (Medium Risk)

| # | Issue | Effort | Impact |
|---|-------|--------|--------|
| 15 | Remove magic-number 12-byte size gate | Small | Closes MIME-type spoofing bypass |
| 16 | Require HTTPS client IDs | Small | Prevents client metadata downgrade |
| 17 | Mandate PKCE verifier when challenge was issued | Small | Prevents code exchange without PKCE |
| 18 | Validate Sec-WebSocket-Accept header | Small | Prevents MITM WebSocket injection |
| 19 | Fix MST UTF-8 byte offset handling | Medium | Prevents non-ASCII key corruption |
| 20 | Enforce CID tag-42 `0x00` marker byte | Small | Rejects malformed DAG-CBOR links |
| 21 | Enforce RepoCommit `version=3` and `sig` presence | Small | Rejects malformed commits |
| 22 | Validate AT URI components | Small | Prevents malformed reference normalization |
| 23 | Add backpressure to replay path | Small | Prevents memory exhaustion via cursor=0 |
| 24 | Pass cursor in Firehose WebSocket URL | Small | Enables cursor-based replay |
| 25 | Salt phone number hashes in ContactService | Small | Prevents rainbow table reversal |
| 26 | Fix NotificationService write API usage | Small | Makes write operations effective |
| 27 | Fix AppViewGroupIndexer schema mismatch | Medium | Makes group indexing functional |
| 28 | Fix FeedService reply-count URI parse | Small | Corrects reply counts |
| 29 | Harden WASM kernel class-check fallback | Small | Prevents kernel crash from user input |
| 30 | Fix kernel float serialization (write actual value) | Small | Prevents silent data corruption |

### P3 — Next Quarter (Hardening & Debt Reduction)

| # | Issue | Effort | Impact |
|---|-------|--------|--------|
| 31 | Replace ad hoc kernel JSON encoder with proper escaping | Medium | Prevents invalid JSON output |
| 32 | Handle INT_MIN negation in kernel format helpers | Small | Eliminates undefined behavior |
| 33 | Verify blob provider on dedup hit | Small | Repairs missing provider data |
| 34 | Harden PLC sig pre-validation (base64url + length) | Small | Defense-in-depth for PLC operations |
| 35 | Validate PLC export cursor format | Small | Prevents silent fallback to full export |
| 36 | Reject reserved WebSocket opcodes with close 1003 | Small | RFC 6455 compliance |
| 37 | Replace RelayEventBuffer linear scan with binary search | Small | O(log n) instead of O(n) for backfill |
| 38 | Add reverse mapping to RelayUpstreamManager | Small | O(1) instead of O(n) per delegate callback |
| 39 | Auto-prune RelayEventBuffer on timer or append | Small | Prevents unbounded time-based retention |
| 40 | Remove cancelled FirehoseSubscriptions from set | Small | Prevents unbounded set growth |
| 41 | Remove or compile-flag legacy WebSocket server path | Medium | Reduces dual-path complexity |
| 42 | Remove or compile-flag deprecated RelayDownstreamHandler formatters | Small | Reduces dead code |
| 43 | Fix Linux WebSocketServer accept source | Small | Makes WS server functional on GNUstep |
| 44 | Wire event rate limiter timer handler | Small | Enables actual rate limiting |
| 45 | Synchronize RelayEventFilter setters | Small | Thread safety for filter mutation |
| 46 | Fix FirehoseCommitEvent.blobs type mismatch | Small | Type declaration matches runtime |
| 47 | Remove duplicate PLCServer alsoKnownAs validation | Small | Reduces dead code |
| 48 | Fix MST node content-type label | Small | Metadata accuracy |
