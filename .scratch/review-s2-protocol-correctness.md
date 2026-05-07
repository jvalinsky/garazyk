# S2: Protocol Correctness Synthesis

## Themes

Across the PDS codebase, the highest-risk protocol problems cluster around three contracts that ATProto depends on for correctness: **ordered sync delivery**, **canonical repository encoding**, and **trust-bound authentication/identity**.

### Firehose / sync transport
The firehose implementation is the most protocol-breaking area. The server-side encoder increments sequence numbers but never writes them onto the event payload, so downstream consumers see `seq=0` or stale values instead of a monotonic cursor (`R6 BUG-1`). That alone breaks replay, resume, deduplication, and gap detection. The client side compounds this by silently dropping `#account` events and never dispatching `#sync` or `#info` events (`R6 BUG-2`, `BUG-3`, `MED-1`), while the subscription URL path omits the cursor parameter entirely (`R6 MED-9`). In ATProto terms, that means consumers cannot reliably recover a stream after disconnect or cursor advancement.

### XRPC dispatch and method trust
The network layer has two distinct correctness failures: privileged methods are reachable even after auth parsing fails, and client-controlled proxy headers can reroute requests to arbitrary upstreams (`R4 finding 1`, `finding 2`). The first is an authorization gate bug: the code checks that an `Authorization` header exists, not that it produced a valid DID, so admin-only `tools.ozone.*` routes can continue on invalid credentials. The second violates the trust boundary for XRPC proxying by honoring `atproto-proxy` from untrusted requests and even accepting absolute URLs, which can bypass local dispatch rules and leak headers to attacker-chosen targets. Both issues diverge from the expected XRPC model where dispatch should enforce local auth and only trust proxy routing from internal, authenticated infrastructure.

### Repository / MST / CAR / DAG-CBOR correctness
Repository encoding is also drifting from the ATProto wire model. The MST serializer/deserializer mixes UTF-16 character counts with UTF-8 byte slicing, which corrupts any non-ASCII key and can break tree ordering and proof generation (`R2 finding 3`). The persistence layer strips the tag-42 CID prefix without checking for the required `0x00` marker, admitting malformed DAG-CBOR links as if they were valid (`R2 finding 4`). Commit parsing is similarly permissive: it accepts commits without enforcing `version == 3` or requiring `sig` (`R2 finding 5`). At the boundary, malformed `at://` references are normalized without full validation of DID / collection / rkey components (`R2 finding 2`). Taken together, these issues mean the repository layer can ingest objects that are not canonical ATProto repository data, then emit or persist structures that downstream sync and proof code cannot safely trust.

### Auth / OAuth / DPoP / session handling
The authentication stack has multiple protocol-level trust failures. Remote issuer JWTs are not actually verified against the fetched JWKS, so any forged token from an allowed issuer can pass claims checks (`R5 CRITICAL`). Refresh-token handling is effectively stateless and revocation-free, and the refresh endpoint will accept access tokens if they satisfy the same JWT checks (`R5 HIGH`). DPoP replay protection is disabled because no replay checker is wired in, and legacy PKCE exchange can proceed without a verifier when one should be mandatory (`R5 HIGH`, `MEDIUM`). Separately, the repository session table accepts refresh tokens even after their expiry date because the lookup ignores `expires_at` (`R2 finding 1`), extending the lifetime of credentials well past the intended session window.

### Identity / PLC operations
The PLC server and DID-related paths show weaker, but still protocol-relevant, validation gaps. PLC signature validation is superficial: it checks for a string-like `sig` and base64 padding behavior, but does not meaningfully validate the structure or length before deeper verification (`R6 HIGH-5`). Export cursors are also weakly checked; an invalid `after` value can silently fall back to the beginning of the export stream (`R6 MED-6`). These issues are less immediately catastrophic than the firehose and auth gaps, but they still diverge from the DID/PLC expectation that operations be validated at the boundary and that cursors / checkpoints be treated as authoritative protocol state.

## Critical Findings

1. **Firehose sequence numbers are not emitted at all** (`R6 BUG-1`)  
   This is the most dangerous correctness failure in the entire set. A sync stream without correct `seq` values cannot support cursor-based replay, consumer resumption, or reliable moderation backfill. Once `seq` is wrong, every downstream consumer that depends on monotonic ordering is effectively broken.

2. **Firehose event classes do not faithfully round-trip the protocol event set** (`R6 BUG-2`, `BUG-3`, `MED-1`, `MED-9`)  
   `#account` events are dropped, `#sync` and `#info` are not dispatched, and the cursor is not threaded into the subscription URL. This means even when the stream is live, clients miss state changes and cannot recover gaps the way ATProto consumers expect.

3. **Remote auth and replay protections are not enforcing the protocol trust model** (`R5 CRITICAL`, `R5 HIGH`, `R4 finding 1`)  
   Remote JWTs are trusted without signature verification, refresh tokens are not revocable in practice, DPoP replay checking is absent, and admin XRPC endpoints continue when auth parsing fails. This is a compound protocol break: the server cannot distinguish legitimate token holders from forged or replayed credentials.

4. **XRPC proxying lets untrusted clients steer request routing** (`R4 finding 2`)  
   The `atproto-proxy` header is honored from the public request path, including absolute URLs. That makes it possible to bypass local method protection and send protocol traffic to arbitrary upstreams, which is not compatible with the intended XRPC trust boundary.

5. **Repository objects are accepted even when they are non-canonical or malformed** (`R2 finding 3`, `4`, `5`, `2`)  
   Non-ASCII MST keys can be corrupted, CID tags can lose their marker byte, commits can arrive without the expected version/signature structure, and malformed AT URIs can be normalized instead of rejected. These issues threaten repository integrity and make replicated data diverge from the canonical ATProto shape.

6. **Identity/PLC validation is too weak at the boundary** (`R6 HIGH-5`, `R6 MED-6`)  
   PLC operations are not being validated as strictly as the protocol requires, which raises the chance of accepting malformed DID operations or exporting inconsistent state.

## Priority Recommendations

1. **Fix firehose sequence emission and event dispatch first** (`R6 BUG-1`, `BUG-2`, `BUG-3`, `MED-1`, `MED-9`)  
   Assign the computed sequence back onto each encoded event, then ensure `#account`, `#sync`, and `#info` are surfaced to clients and that cursor handling is wired into the subscription URL. This restores the core ATProto sync contract and prevents silent data loss.

2. **Close the auth trust gaps in the XRPC and OAuth stack** (`R5 CRITICAL`, `R5 HIGH`, `R4 finding 1`)  
   Verify remote issuer signatures with JWKS, enforce token type and revocation for refresh tokens, require DPoP replay tracking, and stop Ozone admin routes when auth parsing fails. These are the most dangerous account-takeover and authorization-bypass paths.

3. **Lock down client-controlled proxy routing** (`R4 finding 2`)  
   Treat `atproto-proxy` as trusted-internal-only, reject absolute URLs from public requests, and ensure proxy logic cannot override protected local methods. This removes the SSRF and dispatch-bypass surface.

4. **Make repository encoding canonical and strict** (`R2 finding 2`, `3`, `4`, `5`)  
   Enforce exact AT URI shape, use UTF-8 byte offsets consistently in MST code, require the DAG-CBOR CID marker byte, and reject commits that do not match the expected version/signature shape. This prevents malformed repository state from entering the system.

5. **Enforce expiry and revocation in session storage** (`R2 finding 1`)  
   Add expiry checks to refresh-token lookup so dead tokens cannot be reused indefinitely. This should be treated as part of the auth boundary, not just a database cleanup issue.

6. **Tighten PLC / DID boundary validation** (`R6 HIGH-5`, `MED-6`)  
   Treat PLC signatures and export cursors as protocol inputs that must be strictly validated. Fail closed on malformed data instead of falling back to permissive behavior.

7. **After protocol fixes, add round-trip tests for sync and repository contracts**  
   Add tests that verify monotonic firehose seqs, presence of all event types, replay from cursor, CID tag canonicalization, commit version/signature enforcement, and JWT/DPoP negative cases. The current failures are protocol-shaped, so regression tests should be protocol-shaped too.