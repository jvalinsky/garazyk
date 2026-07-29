---
title: Security Review Remediation — 2026-07-28
status: proposed
last_verified: 2026-07-28
---

# Security Review Remediation — 2026-07-28

## Objective

Close the findings from the 2026-07-28 parallel security audit (six surfaces:
auth/crypto, HTTP+XRPC transport, SQL/data layer, binary parsers, blob/media,
identity/PLC), and close the audit gaps the review did not reach.

Sections are sized to land independently. Each states its own exit criterion.
Fold into `workstreams/01-security-and-protocol-correctness.md` as S18+ if this
survives review.

## Evidence status

Findings carry one of three labels, used consistently below:

- **PROVEN** — a failing test in this repository reproduces it.
- **CONFIRMED** — the whole code path was read; no test written yet.
- **PLAUSIBLE** — the defect is real in the code read, but a file that decides
  its severity or reachability was not read. Listed with the file that resolves it.

Nothing below is speculative. Findings the audit could not substantiate were dropped.

## Working agreement

1. **One finding, one commit, one green test.** Land the exploit test and its
   fix together so `main` is never knowingly red. The suites in
   `Garazyk/Tests/Security/ParserExploitTests.m` and
   `ParserRecursionExploitTests.m` are currently **red on `main`** — Section 1
   is what turns them green. If Section 1 slips, quarantine them rather than
   leaving a red build.
2. **Bound the build.** `cmake --build build --target AllTests -- -j4`, never a
   bare `--parallel`. Capture the real rc; the wrapper's exit code lies.
3. **Reconfigure after adding test files.** The CMake `GLOB` has no
   `CONFIGURE_DEPENDS`; a new suite also needs its class registered in
   `test_main.m` or it silently runs zero tests.

---

## Status revision — 2026-07-29

Re-verified against a clean build (`BUILD_RC=0`) and a full default run:
**4660 tests, 9 failures.** Of those 9: 4 are this plan's known-open exploit
tests, 4 are a **new regression** (§R1), and 1 is a pre-existing test-isolation
flake (§R4). Everything below is measured, not inferred, except where stated.

### Landed since the plan was written

| Item | State | Evidence |
|---|---|---|
| §1.1 bounds wrap | **DONE** — all 4 sites | `CBOR.m:516,532` and `CAR.m:186,258` now use `length > data.length - offset`. `CARParserExploitTests` **fully green** (2/2). |
| §1.2 depth cap | **DONE** | `kCBORMaxDecodeDepth = 64`, threaded via `decodeInternal:offset:depth:`. `ParserRecursionExploitTests` exits **0** — was SIGSEGV/139. |
| §3.1 type-7 desync | **DONE** | `decodeSimpleOrFloat:` now consumes 1/2/4/8 payload bytes for additional-info 24–27. |
| §3.4 canonical form | **DONE, in the right place** | `ATProtoDagCBOR.m` now rejects trailing data (`:54`), non-minimal lengths (`:590`), and duplicate keys + enforces sort order (`:737`). `ATProtoDagCBOREdgeCaseTests.m` gained 125 lines covering all four additional-info levels. This is option (c) executed as chosen. |
| §2.1 part 1 (guard parity) | **DONE** | `HttpRequestDispatcher.m:77` wraps `handler(request, response)` in `@try/@catch`. |
| §2.1 part 2 (typed accessors) | **NOT DONE** | No `stringForKey:`/`numberForKey:` on `HttpRequest`. The plan warned these are not substitutes: the guard converts crashes to 500s but leaves the type confusion, and does not cover throws from `dispatch_async` frames. |
| §3.3 negative integers | **NOT DONE** | 2 tests still failing. |
| §4–§8 | **Untouched** | |

### R1 — REGRESSION (P0): STAR round-trip decodes 0 records

Four failures in `STARPreorderTests` — `testSTARL0RoundTripViaVerifyingReader`
and `testSTARLiteHasNoMSTNodesAndUsesVersionTwo` both assert 8 records and get
**0**; `testEmitsSTARL0FixtureForComparison` fails twice.

**Mechanism (confirmed by reading):** `CBORDecoder decode:` (`CBOR.m:439-444`)
now ends with `if (offset != data.length) return nil;`. `[CBORValue decode:]`
(`CBOR.m:216`) forwards straight to it. `STAR.m` calls `[CBORValue decode:]` at
`:705` (`parseCommit:`) and `:838` (wire node). Neither `STAR.m` nor
`STARPreorderTests.m` is modified — only decoder behavior changed.

**Root cause is architectural, not a typo.** The trailing-data check was added
to `Repository/CBOR.m` — the *generic* decoder that the §3.4 decision
(option (c)) says must stay lenient, because it also serves WebAuthn
attestation parsing at `WebAuthnVerifier.m:65`. Strictness belongs in
`ATProtoDagCBOR`, where it has correctly landed. This is option-(a) drift into
a decoder that was deliberately excluded from strictness.

Two candidate fixes:
- **(i) Remove the trailing check from `CBOR.m`.** Aligned with the chosen
  architecture; strictness stays in `ATProtoDagCBOR`, which already has it and
  already has better test coverage. Preferred.
- **(ii) Leave the check; migrate `STAR.m` to `decode:offset:`** and have it
  validate the residual offset itself. Keeps CBOR.m strict but re-opens the
  WebAuthn question and contradicts the §3.4 decision.

**Honest caveat:** the full suite was never run *before* these changes, so it is
not proven that `STARPreorderTests` was green beforehand. The causal chain is
clear and STAR is unmodified, but that is inference — confirm with a `git stash`
of the two decoder files before treating it as settled.

### R2 — Two exploit tests now assert the wrong contract (P1)

`CBORCanonicalFormExploitTests/testDuplicateMapKeysAreRejected` and
`.../testNonMinimalIntegerEncodingIsRejected` assert that
**`Repository/CBOR.m`** enforces canonical form. Under option (c) it must not:
it is the generic decoder, and CTAP2 canonical CBOR is a different profile from
DAG-CBOR. Equivalent coverage now correctly exists in
`ATProtoDagCBOREdgeCaseTests` against the decoder that owns the property.

These tests were written before the §3.4 decision and encode option (a)'s
expectations. Leaving them red is actively dangerous: the obvious way to make
them pass is to make `CBOR.m` fully strict, which is exactly what caused §R1 and
would push further into WebAuthn's parse path.

**Action:** delete all three assertions from `CBORCanonicalFormExploitTests`
(including the trailing-data one, which is the §R1 cause), and rely on
`ATProtoDagCBOREdgeCaseTests`. Record the reason in the deletion commit so the
coverage is not "restored" later by someone reading only the test name.

### R3 — Negative integers: scope narrowed (P2)

The defect is confined to `Repository/CBOR.m`. `ATProtoDagCBOR.m:624` is
**already correct** and is a ready reference implementation:

```objc
if (value > (uint64_t)INT64_MAX) {
    [self _setDecodingError:error message:@"Negative integer exceeds int64 range"];
    return nil;
}
return @( -1 - (int64_t)value );
```

This is **not** a canonicalization-policy question and does not wait on §3.4:
it is a correctness and signed-overflow-UB bug, and COSE — i.e. WebAuthn — uses
negative integers heavily for key parameters (`-1` crv, `-2` x, `-3` y). Port
the `ATProtoDagCBOR` form into `CBOR.m`.

### R4 — Not a regression

`PDSBlobAuditOperationTests/testBaseClassMainSetsProgressToComplete` fails in the
full run but **passes 8/8 in isolation on two consecutive runs**. That is
order-dependent shared state, pre-existing and unrelated to this work. Worth its
own ticket; do not let it block this plan.

### R5 — Hygiene

The legacy CAR parser still uses the unsafe idiom at `CAR.m:325`, `:352`, `:361`
(`offset + X > data.length`). The audit established these are safe on 64-bit
builds because the lengths are `uint32_t` and cannot wrap an `NSUInteger`. They
are not a vulnerability — but leaving two idioms in one file is a trap for the
next edit. Apply the same helper for consistency.

Separately: the working tree carries **64 modified files with nothing
committed**. The green parts (§1.1, §1.2, §3.1, §3.4, §2.1 part 1) should be
committed before the P0 work starts, so a bisect can distinguish them.

### Revised order

**P0** §R1 STAR regression → **P1** §R2 retarget tests → **P2** §R3 negative
integers → **P3** §2.1 part 2 typed accessors → then Sections 4–8 unchanged.

---

## Section 0 — Verification spikes (completed 2026-07-28)

Five findings were **PLAUSIBLE** only because the audit ran out of budget
before reading one specific file. Each spike was a single-file read that
either promoted a finding to critical or deleted it. All five resolved within
a single read pass.

| Spike | Verdict | Deciding line / reason |
|---|---|---|
| 0.1 | **DOWNGRADED → hardening** | `AuthCryptoJWK.m:579` rejects any `kty != "EC"`; `JWT.m` has no HMAC signing or verification branch. HS256/ES256 confusion is structurally impossible. §4.4 stays as code hygiene (still no `alg` allowlist on the remote-issuer path; still `kid`-less tokens default to first JWKS key). |
| 0.2 | **CONFIRMED-dormant; dead code** | Grep `[OAuthProvider ` and `id<OAuthProvider>` across `Garazyk/Sources/` returns zero hits. `PDSAuth.m:187` is not reached by the live boot wiring. Spike 0.6 confirmed the live OAuth authorization path is handled securely by `OAuth2Handler`, which bypasses the vulnerable `OAuthProvider` stack entirely. The dormant code is strictly dead and slated for deletion (§4.5). |
| 0.3 | **CONFIRMED-high** | `OAuthProvider.m:512` `-revokeToken:` is RFC 7009 single-token only. No `family`, no reuse-detection plumbing. Combined with §4.3's finding that `PDSAuth.m:126` rotates by delete without tombstone — replay of a stolen rotated token fails one request but raises no alarm and revokes nothing. §4.3 stands at **high**. |
| 0.4 | **WITHDRAWN (unauthenticated path); admin path stays by-design** | `validateHost:` (`Garazyk/Sources/Sync/Relay/RelayUpstreamManager.m`) routes through `ATProtoSafeHTTPClient` with `followRedirects=NO`, a 64 KB cap, and a mandatory 200 from `/xrpc/com.atproto.server.describeServer`. A metadata endpoint does not satisfy that liveness probe — the unauthenticated SSRF claim was unfounded. The admin-gated `handleAdminRequestCrawl` path deliberately bypasses `validateHost:`; capture that as a §7 follow-up. |
| 0.5 | **CONFIRMED-high** | `ATProtoSafeHTTPClient.m defaultOptions` sets `allowHTTP=NO`, `allowPrivateHosts=NO`. The latter gates two distinct defenses: `validateHostResolvesToPublicIP:` (line 220) AND `resolvePinnedAddressesForHost:` (line 261, the ADR 0016 pinned-egress DNS-rebinding protection). §6.4's ambient `XCTestCase != nil` predicate in `HandleResolver.m:58` flips both off simultaneously. §6.4 is **high**. |

### Spike 0.6 — OAuth2Handler authorize flow verification (resolved 2026-07-28)

Spike 0.2's negative result asked: does whatever serves the live OAuth
authorize/token endpoints mitigate the §4.5 synthesizer defect, or recreate
it independently?

Reading the live code revealed the auditor's framing was itself wrong: the
live endpoint is **not** `AuthVerifier.m` (which is purely a token verifier
with no client concept), nor the `OAuthProvider` protocol adapter (no instance
exists). It is `OAuth2Handler`, wired via `PDSController`, split across
`OAuth2Handler+Authorization.m`, `+TokenEndpoint.m`, `+ClientValidation.m`,
`+ClientMetadataFetch.m`, `+PAR.m`, `+DPoP.m`. The central client resolution
function, `validateClient:completion:`, gates client lookup by, in order:

1. Database lookup via `[self.database getClientWithID:clientID:]` — requires
   the client to be registered.
2. Operator allowlist policy via `ATProtoServiceConfiguration.oauthClientPolicy
   == "allowlist"`.
3. Request-supplied `client_metadata` validated through `validateClientMetadata:`
   against the ATProto spec — HTTPS-only `client_id`, mandatory
   `dpop_bound_access_tokens: true`, allowlisted `token_endpoint_auth_method`,
   `response_types: code`, etc.
4. Dynamic URL discovery for `https://` clients or loopback, via SSRF-protected
   `ATProtoSafeHTTPClient`.

`OAuth2Handler+ClientValidation.m:validateRedirectURI:forClient:error:` does
exact-match against the registered URI list with RFC 8252 loopback port-
wildcard. Production requires HTTPS; HTTP only for localhost. The live
authorize endpoint requires `request_uri` (PAR), then enforces `state`, CSRF,
and PKCE (`code_challenge` for public clients) before serving a consent screen
— no auto-authorization.

**Verdict:** §4.5 is dead code, not a live attack. Disposition: **delete** *(gated on S18 — see `docs/plans/workstreams/01-security-and-protocol-correctness.md`)*
`OAuthProvider.m`, `OAuthProviderProtocols.h`, and the adapter classes in
`PDSAuth.m` (lines 165–225). No new tests required; existing suite passing
post-deletion is the verification per the plan's working-agreement.

---

## Section 1 — Parser memory safety (highest priority)

**PROVEN.** Unauthenticated, remote, sub-10-byte inputs. Both parsers sit on
remote paths: `CARReader` is reached from `com.atproto.repo.importRepo`
(`XrpcRepoPack+Import.m`), `AppViewIngestEngine`, `AppViewBackfillWorker`, and
`RelayDownstreamHandler`; the CBOR decoder is reached via
`ATProtoCBORSerialization` from `XrpcSyncPack`, `PDSRepoImportValidator`, and
`PLCOperation`.

### 1.1 Integer-overflow bounds checks

Three sites share one defect: `offset + length > data.length` is unsigned
64-bit arithmetic, so a near-`UINT64_MAX` length wraps the sum and the guard
passes. `subdataWithRange:` then raises an uncaught `NSRangeException`.

- `Repository/CBOR.m:486` — byte string. Attack: `5B FF FF FF FF FF FF FF FF` (9 bytes).
- `Repository/CBOR.m:502` — text string. Attack: `7B FF FF FF FF FF FF FF FF`.
- `Repository/CAR.m:186` — header varint. Attack: `FF FF FF FF FF FF FF FF FF 01` (10 bytes).
- `Repository/CAR.m:258` — per-block varint, same shape, reachable after a valid header.

**Fix:** rewrite as `length > data.length - offset`, valid because
`offset <= data.length` holds on every path. Introduce one shared helper
(`PDSRangeIsWithin(offset, length, total)`) rather than four hand-written
comparisons, and use it at every length-prefixed read.

**Risk:** low. Pure tightening; no valid input changes behavior.

**Exit:** `CBORParserExploitTests` and `CARParserExploitTests` green. The CAR
control test (`testCarHeaderLengthBeyondBufferIsRejectedCleanly`) already passes
and must stay passing — it is what isolates the wrap from a missing check.

### 1.2 Recursion depth cap

`CBOR.m:527`/`:548` recurse with no depth counter. One byte per level
(`0x81`); 200 KB of input exhausts the 8 MB stack. Verified: **SIGSEGV, exit
139**, no XCTest summary — the process dies, so there is no exception to catch
and no graceful-degradation path.

**Fix:** thread a depth parameter through `decode:offset:` with a documented cap.
Reject beyond it rather than truncating — a silently truncated record is worse
than a rejected one for content-addressed data.

**Open question for §1.2's fix (not for §3.4's ADR).** The cap value for
`Repository/CBOR.m` itself. ATProto records nest shallowly in practice; a cap
in the low hundreds is generous. Pick a number, name the constant, and state
the rationale — do not leave it as a magic literal. The depth cap from §3.4's
chosen path (route DAG-CBOR through `ATProtoDagCBOR` and harden it) reuses
that decoder's existing `kMaxDecodeDepth = 64`, so the content-addressed cap
is already named and justified; this section's fix is for `Repository/CBOR.m`,
which still needs its own value.

**Exit:** `ParserRecursionExploitTests` green (currently aborts the runner).

### 1.3 Audit the second CBOR decoder — **complete 2026-07-28**

`Core/ATProtoDagCBOR.m` (778 lines) is an **independent** decoder that shares
no code with `Repository/CBOR.m`. The §1.3 audit ran the same three
defect-class probes used against `Repository/CBOR.m` (bounds wrap, recursion
depth, canonical-form gaps) plus two bonus checks (CID decode bounds and
integer-handling UB). All line citations verified empirically on 2026-07-28
via `rg -n` against `Garazyk/Sources/Core/ATProtoDagCBOR.m`.

**Class #1 — bounds wrap on length-prefixed reads:** **verified-clean.**
The decoder was written with the overflow-proof comparison `len > length -
*index` everywhere — byte-string read around line 608, `_decodeArray:` at
line 634, `_decodeMap:` at line 659. It does not use the unsafe form
`*index + len > length` that breaks `Repository/CBOR.m:486/502`. **Not
vulnerable.**

**Class #2 — recursion depth cap:** **verified-clean.** `kMaxDecodeDepth = 64`
(line 10) is threaded through `_decodeFromBytes:index:depth:` and incremented
on each recursive call (into `_decodeArray:` at line 628 and `_decodeMap:` at
line 659). **Not vulnerable** — §1.2's fix is for `Repository/CBOR.m` only.

**Class #3a — trailing data after complete item:** **PROVEN.** The top-level
`+decodeData:error:` around line 35 calls `_decodeFromBytes:` and returns its
output without checking the resulting `index` against `data.length`. Attack
bytes: `01 FF` parses as integer `1` and silently discards `FF`. Same defect
as `Repository/CBOR.m:426`.

**Class #3b — duplicate map keys and out-of-order keys:** **CONFIRMED.**
`_decodeMap:` at line 696 does `dict[key] = value` with last-write-wins
collision handling; no duplicate-key rejection. DAG-CBOR also requires map
keys to be lexicographically sorted by their *encoded byte form* on ingest;
the decoder has no such check. The duplicate-key half mirrors
`Repository/CBOR.m:557`; the sort-order half is unique to DagCBOR.

**Class #3c — non-minimal length encodings accepted:** **CONFIRMED.**
`_decodeLength:` (declared at line 521, body spans lines 521–568) accepts
larger encodings than DAG-CBOR permits. Same defect as `Repository/CBOR.m:456`.

**Bonus — CID decode path:** **verified-clean.** The empty-input guard at
line 727 shields the `subdataWithRange:NSMakeRange(1, cidData.length - 1)`
at line 743 from integer underflow on empty input.

**Bonus — `INT64_MIN` UB on negative-integer decode:** **CONFIRMED.**
`_decodeNegativeInteger:` at line 580 evaluates `-(int64_t)(value + 1)`.
When `value == INT64_MAX`, `value + 1` invokes signed-overflow UB. Sibling
of `Repository/CBOR.m:472` (covered in §3.3).

**Audit verdict:** **three confirmed canonical-form bugs (3a, 3b, 3c) plus
the `INT64_MIN` sibling, all in `ATProtoDagCBOR.m`.** §3.4 (option c) is
**gated on landing these four fixes** in §1.5. No bounds bugs were found,
so the option-(a) fallback is not currently justified: §3.4 stays on
option (c).

**Exit.** Each of the four findings lands as its own one-commit fix in
§1.5. Parser-exploit tests are extended (or a new
`Garazyk/Tests/Security/ATProtoDagCBORSecurityTests.m` is added) per the
working-agreement ("one finding, one commit, one green test").

All line citations above were verified empirically on 2026-07-28 via `rg -n`
against `Garazyk/Sources/Core/ATProtoDagCBOR.m`.

### 1.4 Fuzzing

`fuzzing/harness/FuzzCBORDecoder.m` exists but contains no depth or length-wrap
coverage (grep for `depth|MAX|recurs` returns zero hits). Extend the corpus with
the byte sequences from §1.1–1.2 and add a CAR harness. These bugs are exactly
what a fuzzer finds in minutes; that it did not is a harness gap worth closing.

### 1.5 DagCBOR canonical-form hardening (unlocks §3.4)

The four confirmed bugs surfaced by §1.3 form the work for this section.
Each lands as one commit per the working-agreement ("one finding, one commit,
one green test"); DagCBOR's existing parser-exploit tests are extended, and
the working tree stays compilable throughout.

1. **Trailing-data check** (`+decodeData:error:` around line 35). **Complete
   2026-07-28.** Pin the final `index` returned by `_decodeFromBytes:` and
   reject if `index != data.length`. Otherwise-changed: zero. Risk: low.
   Test pair: input `01 FF` → reject with `DecodingFailed`. One new test
   `testTrailingDataAfterCompleteItemIsRejected` in
   `Garazyk/Tests/Core/ATProtoDagCBOREdgeCaseTests.m` under `#pragma mark -
   Structural Rejection` (see §4.5 amendment).

2. **Duplicate-key rejection + sort-order enforcement** (`_decodeMap:` around
   line 696). **Complete 2026-07-28.** Track the previously decoded key's
   *encoded byte form* (the raw CBOR bytes of the key, not the post-decoded
   dictionary representation) and reject if equal (duplicate) or `< 0`
   (out-of-order comparison). Helper signature
   `_dagCBORCompareEncodedKeys(const uint8_t *a, NSUInteger aLen, const
   uint8_t *b, NSUInteger bLen)` returning NSInteger — length-first then
   unsigned-byte `memcmp`, mirroring the encoder's `_canonicallySortedKeys:`
   exactly so canonical encodings round-trip cleanly. Five new tests in
   `Garazyk/Tests/Core/ATProtoDagCBOREdgeCaseTests.m` under `#pragma mark -
   Structural Rejection`: `testDuplicateMapKeyIsRejected`,
   `testOutOfOrderMapKeysAreRejected`, `testCanonicalMapKeysAccepted`,
   `testMapKeyLengthFirstBoundary`, `testThreeEntryCanonicalMapAccepted`.
   Otherwise-changed: zero (no callers pass intentionally-out-of-order or
   duplicate keys; the encoder's sort guarantees canonical form for valid
   encodings). Risk: medium as planned — full DagCBOR suite
   (`ATProtoDagCBOREdgeCaseTests` + `ATProtoDagCBORTests`, including
   `testRoundTripIdentity` and `testNullValuesInMapsAndArrays`) is the
   verification standard per the working-agreement.

3. **Non-minimal length encoding rejection** (`_decodeLength:` declared at
   line 521, body spans lines 521–568). **Complete 2026-07-28.** After
   decoding the payload, assert the value is at or above the natural floor
   for the parsed `additionalInfo`. Floors indexed by
   `additionalInfo - 24`: `24 → 24`, `25 → 256`, `26 → 65536`,
   `27 → 4294967296` — anything below fits in a smaller additionalInfo, so
   the wider encoding is non-minimal. The check is gated by
   `additionalInfo >= 24 && additionalInfo <= 27` so the `additionalInfo -
   24` array index is always in-range; the `static const` array is declared
   inside the conditional block, qualified `static` so it persists across
   calls. Two new tests in
   `Garazyk/Tests/Core/ATProtoDagCBOREdgeCaseTests.m` (placed at the end
   of `#pragma mark - Structural Rejection`, before `#pragma mark - Round
   Trip and Value Boundaries`):
   `testNonMinimalLengthEncodingRejectedForAllAdditionalInfoLevels` (four
   attack vectors — `0x18 0x05`, `0x19 0x00 0x05`, `0x1A 0x00 0x00 0x00
   0x05`, `0x1B 0x00 ... 0x05` — one per additionalInfo level, all
   encoding integer 5 in wider-than-canonical form) and
   `testCanonicalLengthEncodingAcceptedAtFloor` (positive controls `0x18
   0x18` and `0x19 0x01 0x00` decode cleanly). Otherwise-changed: zero
   (the encoder uses additionalInfo directly when `value < 24`, so
   canonical encodings produced by Garazyk pass the decoder's floor check
   unchanged). Risk: low as planned — the fix is mechanical and
   universally applicable to every `_decodeLength:` call site (text-string
   length, byte-string length, array count, map count, tag value, integer
   value).

4. **(Sibling to §3.3.) `INT64_MIN` UB fix** (`_decodeNegativeInteger:`
   around line 635 — line was 580 in §1.3 audit, shifted by §1.5 item 3's
   floor-check block). **Complete 2026-07-28.** Replace
   `-(int64_t)(value + 1)` with `@( -1 - (int64_t)value )`. The pre-fix
   expression invoked signed-overflow UB at the exact boundary case
   where `value == INT64_MAX` (negative-integer payload
   `0x7F FF FF FF FF FF FF FF` decodes to `INT64_MIN`); the new
   expression is `-1 - (int64_t)value = -1 - INT64_MAX = INT64_MIN`,
   well-defined for all `value ≤ INT64_MAX`. The upstream
   `value > (uint64_t)INT64_MAX` guard is preserved, so the cast itself
   is safe. One new test `testNegativeIntegerEdgeAtInt64MaxPayloadDecodesToInt64Min`
   (placed before `#pragma mark - Width Defects (workstream 01 S11)`)
   uses the `0x3B 0x7F FF ...` boundary bytes as a positive control;
   the existing `testLargeIntegerEdgeCases` and
   `testNegativeIntegerEdgeAtTwoPow64MinusOneRejected` also turn green
   with the fix (the former would otherwise have crashed the runner on
   UB at the boundary, the latter would otherwise have wrapped to 0 on
   overflow at `value == UINT64_MAX`). Otherwise-changed: zero for any
   `value < INT64_MAX` (the fix produces the same result as the buggy
   code); the two edge cases both change behavior — pre-fix UB
   (`value == INT64_MAX`) and wrong-result wrap (`value == UINT64_MAX`
   yielding 0); post-fix correct decode (`INT64_MIN`) and correct
   rejection (via the existing `value > (uint64_t)INT64_MAX` guard).
   Risk: low as planned — identical fix shape to §3.3 sibling.

**§3.4 gate NOW satisfied.** All four §1.5 hardening items are complete
(Complete 2026-07-28): trailing-data check (item 1), duplicate-key +
sort-order (item 2), non-minimal length encoding rejection (item 3),
and `INT64_MIN` UB fix (item 4). §3.4's recorded chosen path
(option c — route DAG-CBOR through `ATProtoDagCBOR` and harden it)
is fully unlocked with no further ADR amendment required.

**Exit:** all four test pairs green; the count of redundant
`Repository/CBOR.m` canonical-form tests stays as-is. **Then** §3.4's
ADR-recorded chosen path (option c, recorded 2026-07-28) is fully
unlocked, no further ADR amendment required.

**Relationship to §3.4.** §3.4 already records "Routing and hardening
happen together, gated on §1.3." With §1.3 complete, the newer gate is
this section: §3.4 lands when §1.5 lands. The decision itself
(option c) does not need to change.

## Section 2 — Transport crash-safety

### 2.1 Complete ADR 0013 at the HTTP boundary

**CONFIRMED, unauthenticated, process kill.**

ADR 0013 ("Claim Type Mismatches Rejected at JSON Parse Boundaries", Accepted
2026-07-27) already establishes the policy and the mechanism (`AuthTypedValue`
at the parse boundary, not at each consumer). It was applied to the **auth**
boundaries. It was never extended to **XRPC request bodies**. This section
finishes the accepted decision rather than making a new one.

Live sink: `Network/RelayXrpcRoutePack.m:698`

```objc
NSString *hostname = body[@"hostname"];
if (!hostname || hostname.length == 0)
```

`POST /xrpc/com.atproto.sync.requestCrawl` with `{"hostname":null}` yields
`-[NSNull length]` → `NSInvalidArgumentException`. The route is registered at
`RelayXrpcRoutePack.m:158` with no auth and no rate limiting.

Same pattern, admin-gated: `PDSHttpPDSAdminRoutePack.m:99`, `:165`, `:198`;
`RelayXrpcRoutePack.m:866`.

**Two-part fix — both parts are required:**

1. **Guard parity.** `HttpRequestDispatcher.m:63` calls `handler(request, response)`
   bare, while `XrpcHandler.m:372` wraps the equivalent call in `@try/@catch` → 500.
   Handlers registered via `addRoute:` therefore have no net; handlers registered
   via `registerMethod:` do. Add the same guard at the dispatcher. This converts
   crashes to 500s but does **not** fix the type confusion.
2. **Typed accessors.** Add `-stringForKey:` / `-numberForKey:` / `-arrayForKey:`
   to the request-body boundary per ADR 0013, and sweep the `addRoute:` packs.
   This fixes the confusion but does not protect the ~35 pack files not yet audited.

**Caveat on part 1:** an exception thrown inside a `dispatch_async` block runs on
a different frame and escapes the `@try` regardless. Handlers that defer work
need the typed accessors, not the guard. Do not treat the guard as sufficient.

**Exit:** table-driven test posting `null`/`1`/`[]`/`{}`/`true` for each
`(route, field)` pair, asserting no throw and a status in {400, 401, 403}.
Audit of the remaining `addRoute:` packs recorded.

### 2.2 Path normalization

**CONFIRMED as a latent defect; impact unverified.**

`Http1Parser.m:320` takes `NSURL.path`, which is already percent-decoded, so
`%2e%2e` arrives as `..`. `HttpRouter.m:143` then branches on
`containsString:@".."` into `normalizePath:` (`:264`), which only strips leading
slashes and **never resolves `..`** — the branch is decorative.

Impact needs one more read: no consumer was found that joins `request.path` onto
a filesystem root, and the blob path was separately shown to be safe (§6.3). Fix
the normalizer regardless; it is a trap primed for the next handler that trusts
`request.path`.

Related: `HttpRouteTrie splitPath:` discards empty components, so `//xrpc//foo`
and `/xrpc/foo` route identically. Any middleware that prefix-matches
`request.path` for an authorization decision would disagree with the router.

### 2.3 X-Forwarded-For leftmost element

**CONFIRMED.** `HttpRequest.m:130` takes `ips.firstObject` — the leftmost XFF
entry, which is entirely client-supplied. A proxy appends the real client on the
right.

The *gating* is sound (`PDSHttpRequestIsTrustedProxyAddress` requires both a
loopback/RFC1918 peer and `PDS_TRUST_PROXY_HEADERS`), so this only bites in the
normal behind-a-proxy production deployment. `RateLimitMiddleware`
(`XrpcMiddleware.m:240`) keys directly off `remoteAddress`, so rotating XFF
yields a fresh bucket per request and also poisons every audit log line.

**Fix:** take the rightmost untrusted entry, or make the trusted-hop count
explicit configuration.

---

## Section 3 — Record integrity and canonical form

These do not crash anything. They let two parties disagree about what a record
says while agreeing on its CID — which is worse, because there is no symptom.

### 3.1 Type-7 payload not consumed

**PROVEN.** `CBOR.m:570` returns a simple value without advancing `offset` past
its payload, so the payload byte is re-read as the next item's header.

Test evidence: `A2 61 61 F8 62 61 62 01` must decode to `{"a": simple(98), "b": 1}`.
Garazyk yields `{"a": simple(24), "ab": 1}` — different keys, identical bytes,
identical CID. Additional values 25/26/27 (half/float/double) leave 2/4/8 bytes.

**Fix:** advance by the payload width; reject the reserved additional values.

**Risk:** medium — this changes decode output for inputs currently accepted.
Run the full suite, not just the security filter.

### 3.2 CAR blocks trust their declared CID

**CONFIRMED in `CARReader`; end-to-end PLAUSIBLE** (the `importRepo` caller was
not read and may re-verify).

`CAR.m:270-284` parses the CID out of each block's own prefix and stores it
verbatim. There is **no `sha256(blockData)` compared against the declared
multihash digest**. Three defects in one loop:

- Declared CID trusted → block substitution: submit a block whose declared CID is
  a legitimate record's and whose payload is arbitrary.
- Duplicate CIDs silently last-wins (`index[blockCID.stringValue] = block`).
- No reachability check from `roots` → unreferenced blocks retained (storage
  exhaustion, block poisoning).

Also `CAR.m:281`: `blockBytes.length - cidLength` underflows if
`cidFromBuffer:length:consumed:` can report `consumed > length` — verify that
postcondition.

**Fix:** recompute and compare every block CID before admission; reject
duplicates; drop blocks unreachable from the declared roots.

**Verify first:** whether `PDSRepoImportValidator` already does this. If so,
downgrade to defense-in-depth on the reader.

### 3.3 Negative-integer wrap

**PROVEN.** `CBOR.m:472`: `-(NSInteger)(u + 1)`.

- `3B FF…FF` → `+1` wraps to 0 → decodes as **0** (test observed `0`).
- `3B 80 00…00` → negation of `INT64_MIN+1` → **`INT64_MAX`** (test observed
  `9223372036854775807`). Sign flip. Negating `INT64_MIN` is signed-overflow UB
  and traps under `-fsanitize=undefined`.

Exploitability depends on which protocol fields accept negative integers
(firehose `seq`, `rev`, limits) — `SubscribeReposHandler.m` was not read.

Same defect class is present in `ATProtoDagCBOR.m:_decodeNegativeInteger:`
around **line 580** (confirmed by §1.3 audit) with the same
`-(int64_t)(value + 1)` shape. The fix shape is identical
(`@( -1 - (int64_t)value )`) and is captured as §1.5 item 4.

### 3.4 ADR — strict DAG-CBOR decode mode

**Decision recorded 2026-07-28: option (c).** Routing and hardening happen
together, gated on §1.3.

Three canonical-form gaps are **PROVEN** (all three tests currently fail):
duplicate map keys last-wins (in both decoders — `Repository/CBOR.m:557` and
`Core/ATProtoDagCBOR.m:696`, both reduce to `dict[key] = value`), non-minimal
integer encodings accepted (`CBOR.m:456`), trailing data after a complete item
ignored (`CBOR.m:426`; `ATProtoDagCBOR.m +decodeData:error:` at line 35 returns
the value without checking the final `index`). Map key ordering is also
unvalidated on ingest though the encoder sorts.

Each means one logical record has more than one valid encoding, or one
encoding has more than one reading. For content-addressed, signed data that is
a malleability bug.

**Why not (a).** `WebAuthnVerifier.m:65` decodes `attestationObject` through
`Repository/CBOR.m`. CTAP2 canonical CBOR uses negative-integer keys
(`-1 = crv`, `-2 = x`, `-3 = y`) for COSE parameters. DAG-CBOR forbids them.
Unconditionally making `CBOR.m` strict would either reject authentic
attestation objects or — worse — silently drop the negative-int keys,
producing the wrong `authData`. The dep is registration-time only: any PDS that
offers security-key enrollment would fail. Option (a) requires an explicit
lenient opt-out for WebAuthn, either by parameter or by always using
`Repository/CBOR.m` for attestation and only routing *signed AT data* through
strictness. That makes (a) a non-trivial change in its own right, not a
simplification.

**Why not (b).** Silent lenient default. The failure mode is the worst kind —
malleability accepted, no alarm, downstream CID becomes non-canonical. A
forgotten `isStrict:YES` is invisible until the day somebody exploits it.

**Why (c).** `ATProtoDagCBOR`'s consumer set is *exactly* the content-addressed
set (15 files: `RepoCommit.m`, `Firehose.m`, `EventFormatter.m`,
`PDSSpaceStore.m`, `AppViewIngestEngine.m`, `STAR.m`, four
`PDSRecordService`/`PDSRepositoryService` files, plus a handful of others). The
generic-CBOR consumers keep doing CTAP2-style things. Boundary matches the
profile boundary. `ATProtoDagCBOR` also already has `kMaxDecodeDepth = 64`
threaded through and an overflow-aware count guard with an explanatory
comment — it has been better hardened than `Repository/CBOR.m`. The depth-cap
constant from §1.2's fix moves into DagCBOR's already-used scaffolding rather
than being invented in CBOR.m.

**Disposition.** ADR recorded, migration plan catalogued (§S19),
one migration commit pending. §1.3 and §1.5 are both **complete**;
option (a)'s fallback remains unjustified; §3.4 stays on option (c). The
DAG-CBOR-routing migration (option c — payload-vs-decoder split between
`ATProtoDagCBOR` for content-addressed callers and `Repository/CBOR.m`
for CTAP2/WebAuthn) is now tracked as §S19 in
`docs/plans/workstreams/01-security-and-protocol-correctness.md`; this
ADR remains recorded, not amended.

**Recurring risk under any option.** `WebAuthnVerifier.m` keeps a path through
the still-vulnerable `Repository/CBOR.m`. Even if DAG-CBOR strictness is fully
delivered, attestation-object parsing stays exposed to §1.1/§1.2 bugs until the
memory-safety fixes in §1 land. Treat WebAuthn attestation parsing as a
follow-up audit after §1 closes.

### 3.5 Repository commit integrity — UNAUDITED

`MST.m`, `MSTWalker.m`, `MSTPersistence.m`, `RepoCommit.m`, `STAR.m` were **not
reached**. Open questions, all unanswered:

- Is the commit signature verified **before** blocks are persisted, or after?
- Is the commit's `did` checked against the repo being written (repo spoofing)?
- Is `prev`/`rev` monotonicity enforced (rollback/replay of an old commit)?
- Are MST key-ordering invariants checked? Is there cycle detection?

This is the densest remaining risk surface in the repository layer.

---

## Section 4 — Authentication and tokens

### 4.1 Refresh tokens accepted as access tokens

**CONFIRMED, high.** `JWT.m:746` mints refresh tokens with the same issuer,
audience, subject, and signing key as access tokens (`JWT.m:690`). The only
discriminators are `token_use` and `typ`. `AuthVerifier.m:259-264` reads neither.
`PDSAuth.m:307` makes it bidirectional:

```objc
- (nullable NSDictionary *)verifyRefreshToken:(NSString *)token error:(NSError **)error {
    return [self verifyAccessToken:token forAudience:self.issuer error:error];
}
```

A client sends its 30-day refresh token as `Authorization: Bearer` to any
protected endpoint and is authorized. Access-token expiry (1 h) and any
access-level revocation become unenforceable.

**Fix:** enforce `token_use` and `typ` at the verifier, ADR-recorded alongside
0013's boundary principle. Give the two token types distinct audiences as
defense in depth.

**Exit:** `verifyAccessToken:` returns nil for a refresh token and vice versa.

### 4.2 DPoP proof not bound to the access token

**CONFIRMED, medium.** `AuthCryptoDPoP.m:190-204` reads `htm`, `htu`, `iat`,
`jti`, `nonce` — never `ath`. RFC 9449 §4.3 requires `ath` =
`base64url(SHA-256(token))` when a proof accompanies an access token.
`AuthVerifier.m:394` completes binding on the key thumbprint alone, so any two
tokens under one DPoP key are interchangeable from the proof's perspective.

Bounded by the replay cache (one use per proof), which is correctly implemented.
Also `iat` uses `fabs(now - iat) > 300`, accepting proofs up to 5 minutes in the
future.

### 4.3 Refresh-token reuse detection

**CONFIRMED-high.** `PDSAuth.m:126` rotates by deleting the predecessor with
no tombstone and no family id. Replaying a stolen rotated token fails that
one request but revokes nothing and raises no alarm — the condition OAuth 2.1
§4.14.2 requires detection for. Spike 0.3 confirmed `OAuthProvider.m:512` has
only single-token RFC 7009 revocation: no family tracking anywhere above the
PDS adapter.

Secondary, same file: PARs, authorization codes, refresh tokens, and consent
grants live in plain `NSMutableDictionary` ivars keyed by the raw secret, so they
do not survive restart; and the injected `PDSDatabase` is stored but never used.

### 4.4 Remote-issuer JWKS: `alg` never enforced

**CONFIRMED-low (hardening).** Spike 0.1 ruled out the cross-algorithm forgery
(mint a JWKS with `kty:oct`, register the symmetric secret, sign HS256 tokens
that the verifier tries to validate). Safety on the remote branch now rests
entirely on `AuthCryptoJWK publicKeyFromJWK:` rejecting non-EC keys — that gate
is structurally solid.

What remains: `AuthVerifier.m:367` assigns
`claimsVerifier.allowedAlgorithms = @[@"ES256", @"RS256"]` and then only calls
`validateClaims:`, which inspects `exp`/`nbf`/`iss`/`aud`/`sub` and never reads
`jwt.header.alg`. The allowlist is enforced only on the *local*-issuer branch
(`JWT.m:336`). A remote-issuer token whose header advertises `none`/`PS256`
still passes if the JWKS-loading path accepted a key the verifier will use.

Also `AuthVerifier.m:320`: a token with **no `kid`** selects the JWKS's first key
regardless of purpose. And `claimsVerifier.expectedIssuer = issuer` compares the
issuer to itself — tautological, though gated upstream by `isIssuerAllowed:`.

These are defense-in-depth: apply the algorithm allowlist at the JWKS-merging
step, reject `kid`-less tokens, and delete the tautological assignment.

### 4.5 OAuth client auto-registration

**CONFIRMED-dormant; dead code.**

`PDSAuth.m:187` returns a synthesized client for *any* `client_id`: never nil
(no registration gate), `token_endpoint_auth_method` hard-coded `"none"` for
every client (confidential clients collapse to public), and `redirect_uris`
derived from the client_id itself with `http://` accepted. `validateRedirectURI:`
(`PDSAuth.m:205`) does correct exact matching — it is simply matching against a
set the attacker just dictated.

Spike 0.6 confirmed this defect belongs to a completely unreachable adapter —
**dead code**. Grep `[OAuthProvider ` and `id<OAuthProvider>` across
`Garazyk/Sources/` returns zero hits, so nothing in the running code path ever
instantiates the synthesizer. The live OAuth authorize/token endpoints live in
`OAuth2Handler` (wired via `PDSController`), which implements robust client
validation: explicit database lookup, operator allowlists, strict
ATProto-spec-validated request metadata via `validateClientMetadata:`
(`OAuth2Handler+ClientValidation.m`), and SSRF-protected dynamic
client-metadata discovery via `ATProtoSafeHTTPClient`
(`OAuth2Handler+ClientMetadataFetch.m`). The vulnerable `OAuthProvider` and
`PDSAuthClientRegistry` adapter stack is dormant and bypassed by every live
path.**Fix:** **dead code; remove.** Delete `OAuthProvider.m`,
`OAuthProviderProtocols.h`, and `PDSAuthClientRegistry` in `PDSAuth.m` —
the `#pragma mark - PDSAuthClientRegistry` block, `@interface` at line 173
through the closing `@end` of `@implementation` at line 217, ending immediately
before `#pragma mark - PDSAuthTokenSigner` at line 220. Delete ranges are
anchored to those structural boundaries (verified 2026-07-28 via `rg -n`), not
to approximate line ranges, to avoid cutting into `PDSAuthTokenSigner`. The
existing suite passing post-deletion is its own verification per the plan's
working-agreement ("one finding, one commit, one green test").Version control preserves the option. **Gated on S18** — see `docs/plans/workstreams/01-security-and-protocol-correctness.md`.

**Amendment 2026-07-28 (recorded after a failed §1.5 commit attempt):** The
file-level deletion above was over-aggressive. `OAuthProviderProtocols.h`
also declares three live protocols that `AuthVerifier.m` depends on —
`AccountPolicy`, `TokenKeyResolver`, `DPoPNonceStore` (typed `id<Protocol>`
properties on `AuthVerifier.m:63–65`, with methods called at lines 227,
229, 305, 307, 420, 432, 434). The original verification grep
(`[OAuthProvider ` and `id<OAuthProvider>`) checked usage of the
`OAuthProvider` class instance only, which correctly returned zero hits.
That the protocols live in the same file as the dead class was missed.
Attempting the §1.5 commit that included removing the import in
`AuthVerifier.m` and the deletion of the `PDSAuthClientRegistry` block in
`PDSAuth.m` produced seven compile errors against `AuthVerifier.m`.
Recovery: full revert of the §4.5 file-level deletion (the three files and
the `PDSAuth.m` block restored via `git checkout HEAD`). The dead-class
analysis at the instance level stands — `OAuth2Handler` (wired via
`PDSController`) is the live OAuth path and bypasses the entire
`OAuthProvider` adapter stack. The right path to a clean §4.5 is a
refactor: extract the three live protocols
(`AccountPolicy`, `TokenKeyResolver`, `DPoPNonceStore`) to a dedicated
`AuthVerifierProtocols.h`, update `AuthVerifier.m` to import the new
header, then re-attempt the file-level deletion on the now-empty
`OAuthProvider*` files. Future work item, recorded here so a follow-up
audit does not re-do the same over-aggressive delete.

### 4.6 DPoP `htu` from unvalidated Host

**CONFIRMED, deployment-dependent.** `AuthVerifier.m:446` builds the expected
`htu` from the `Host` and `X-Forwarded-Proto` headers with no host allowlist and
no trusted-proxy check, so the requester chooses the value their proof is
compared against. Behind a proxy that overwrites both headers this is not
reachable; combined with §2.3 it is worth fixing together. `hostHeader` is also
used with no nil-guard (yields the literal `https://(null)/path`).

### 4.7 JWKS advertises secp256k1 as P-256

**CONFIRMED, low (interop).** `PDSAuth.m:242` publishes secp256k1 coordinates
with `crv: P-256`; `JWT.m:787` publishes the same key correctly as
`secp256k1`/`ES256K`. `JWT.m:516` also stamps `alg: ES256` on tokens actually
signed with secp256k1. A conformant peer fails closed, so this is a correctness
bug, but mislabelled curve metadata is raw material for cross-curve confusion in
a lenient relying party.

---

## Section 5 — Data layer and multi-tenancy

**Lead with the negative result:** every dynamic-SQL site enumerated in the audit
was traced and **no SQL injection was found**. `ORDER BY` is allowlisted
(`XrpcAdminPack.m:282`), identifiers come from schema introspection filtered
through literal allowlists, `IN` clauses interpolate only generated `?,?,?` runs,
and values are bound. `ActorStore` `WHERE uri = ?` queries are not IDOR because
the actor store is per-DID sharded. That surface is genuinely well defended and
should be recorded as verified, not re-audited next quarter.

The real issues are elsewhere:

### 5.1 Blob ownership rewrite

**CONFIRMED (schema precondition verified).** Schema is `cid BLOB PRIMARY KEY`
(`Schema.m:117`) — uniqueness on `cid` alone. `PDSDatabase+Blobs.m:21` upserts
`ON CONFLICT(cid) DO UPDATE SET did=excluded.did`, and `:60` deletes by `cid`
with no `AND did`. Sibling accessors scope correctly
(`PDSActorStore+Blob.m:101`, `PDSSQLiteBlobRepository.m:114`).

CIDs are content hashes, so re-uploading a victim's bytes collides deliberately:
the row's owner is rewritten to the attacker (quota accounting follows `did`),
and a later delete removes it for the victim.

**Still to verify:** which upload path actually reaches `PDSDatabase+Blobs`
versus the scoped store. `BlobStorage.m:152` is the candidate. The missing
predicate is a defect regardless.

### 5.2 `stringValue` sent to `NSString`

**CONFIRMED (column types verified as TEXT).** `ModerationService.m:415` and
`:459` call `-stringValue` on a value read from a TEXT column, i.e. an
`NSString`, which has no such method. The `?: @""` fallback never runs — the
message raises first. Triggered by any `limit` reaching a full page (e.g.
`limit=1` on a non-empty set).

### 5.3 Unclamped limit

`ModerationService.m:392` binds `limit` unclamped; SQLite treats a **negative**
LIMIT as unlimited. The guard `rows.count >= (NSUInteger)limit` cannot catch it —
casting a negative `NSInteger` yields a huge value, so it is always false.
A shared validator exists (`GZXrpcRouteSupport.m:50`); confirm which routes skip it.

### 5.4 LIKE without ESCAPE

`ModerationService.m:427` interpolates `namePrefix` raw into a `LIKE` pattern.
`%` defeats the prefix filter (enumeration on a moderation endpoint); a
`%a%b%c%…` pattern forces superlinear matching. The correct idiom already exists
at `AppViewDatabase.m:956` (`LIKE ? || '%' ESCAPE '\'`).

Unverified sibling sites: `GroupService.m:291,418`, `GraphService.m:771`,
`ActorService.m:497,539`, `FeedService.m:672-694`.

### 5.5 Not reached

Record write-path IDOR (`PDSRecordService`, `AppViewGenericIndexer.m:187`,
`AppViewIngestEngine.m:902`); handle/account uniqueness TOCTOU (does
`accounts.handle` carry a UNIQUE constraint, or is the check application-level?);
secrets at rest — `PDSDatabase+Accounts.m:157` selects by `refresh_jwt = ?`,
implying refresh tokens are stored in directly-comparable form; `PRAGMA %@ = %@`
construction at `ATProtoConnectionPool.m:19`.

---

## Section 6 — Blob, media, and identity

### 6.1 CRLF / open redirect via unvalidated `cid`

**CONFIRMED (open-redirect half); CRLF half PLAUSIBLE.** `XrpcSyncPack.m:898`
checks `cid` only for emptiness, never parses it, then interpolates it into a
302 `Location`. `HttpResponse.m:279` serializes headers with raw `\r\n` and no
stripping. Same pattern at `XrpcRepoPack+Blobs.m:312`.

The open-redirect variant (`cid=@evil.example.com`) needs no decoding and is
confirmed. The CRLF variant depends on whether `%0d%0a` survives query decoding —
one read of `queryParamForKey:` settles it.

**Fix:** parse through `CID cidFromString:` before use (the validated path
already exists), and strip CR/LF in `setHeader:forKey:` as defense in depth.

### 6.2 Active-content MIME denylist is route-only

**CONFIRMED as a latent gap.** `MimeTypeValidator` still lists `text/html` and
`image/svg+xml` as supported (`:64`, `:124`), and `BlobStorage.uploadBlob` applies
no active-content check — the denylist lives only at the route
(`XrpcRepoPack+Blobs.m:164`). `nosniff` does not stop a correctly-declared
`image/svg+xml` from executing script on top-level navigation.

No network-reachable bypass was found, so this is a regression risk rather than
an open hole. `XrpcSpacePack.m:301` does it correctly (attachment + nosniff +
`CSP: default-src 'none'; sandbox`) — adopt that CSP on the repo/sync paths.

### 6.3 Verified clean — blob path traversal

Recorded so it is not re-audited: `PDSDiskBlobProvider.blobURLForCID:` shards on
`CID.stringValue`, which **re-encodes** from the parsed binary multihash
(`CID.m:245`). The attacker's original string never becomes a path component.
`cidFromString:` caps length at 256 and requires full consumption. Both read and
write paths use it. Also clean: cross-user `repo.getBlob` (403), takedown checks
on both paths, deleted-record blobs gated on `state == Referenced`, tiered size
caps with overflow-safe quota arithmetic, and Range header parsing.

### 6.4 Handle resolver — SSRF control plane disabled by ambient state

**CONFIRMED-high.** Spike 0.5 confirmed `ATProtoSafeHTTPClient.m defaultOptions`
sets `allowHTTP=NO` and `allowPrivateHosts=NO`. The latter gates two distinct
defenses — `validateHostResolvesToPublicIP:` (line 220) and
`resolvePinnedAddressesForHost:` (line 261, ADR 0016 pinned-egress DNS-rebinding
protection). Both flip off together. `HandleResolver.m:58`:

```objc
return NSClassFromString(@"XCTestCase") != Nil;
```

Both `allowHTTP` and `allowPrivateHosts` are switched off by this predicate
(`HandleResolver.m:242`). The third clause is not an opt-in — it is a
**linkage side effect**. Any binary shipping with XCTest linked, or any
process inheriting `PDS_RUNNING_TESTS`, resolves handles over cleartext HTTP
to loopback and link-local addresses — and, per spike 0.5, the same flip
disables the public-IP allowlist *and* the ADR 0016 pinned-egress check, so
any caller can request a private or loopback address directly (no DNS
rebind required).

**Fix:** replace the ambient check with an injected seam so the default is
secure and tests opt in explicitly.

### 6.5 DNS TXT path performs no validation

**CONFIRMED.** `HandleResolver.m:507` returns everything after `did=` verbatim —
no `did:` prefix check, no trim, no length bound, unlike the HTTPS path (`:310`,
which does all three). Segments are concatenated across 255-byte chunks, so the
value can be kilobytes. Reached by simply not serving `/.well-known/atproto-did`.

### 6.6 Resolution is one-way

**CONFIRMED for the resolver; exploitability depends on callers.**
`HandleResolver` never fetches a DID document and has no `alsoKnownAs`
cross-check, so whoever controls a domain can assert any DID — including a
victim's — and it is cached for 300 s. **Next step:** enumerate `resolveHandle:`
callers and check whether any performs the reverse verification. This is the
highest-value follow-up in the identity slice.

### 6.7 Failure-cache key mismatch

**CONFIRMED, low-medium.** Failures are read pre-normalization
(`HandleResolver.m:103`) and written post-normalization (`:172`), so backoff only
ever fires for already-lowercase handles. `Victim.example` vs `victim.example`
bypasses it; the success cache is correctly keyed.

---

## Section 7 — Unaudited surfaces

**Not clean — unexamined.** No claim either way is supported for these. Roughly
priority-ordered:

1. **`Sources/PLC/`** (~5.5k LOC) — operation signature verification, `prev`
   chaining, rotation-key authority and priority ordering, genesis hash,
   replay, tombstones. Densest remaining risk surface overall.
2. **Repository commit integrity** — see §3.5.
3. **`MediaCore/`, `Video/`** — the ffmpeg shell-out question. `FFmpegTranscoder.m`,
   `VideoThumbnailGenerator.m`, `VideoHLSGenerator.m`, `JelczCLI.m`: argv array
   (safe) vs shell string (injectable), and argument injection via a leading `-`.
4. **`AdminUIServer/`** — XSS in `UITemplateEngine.m` / `UIServerRuntime+Renderers.m`,
   `innerHTML` in `Assets/js/admin-ui.js`, CSRF tokens, cookie flags, per-route
   auth. Note the mega-plan claims AdminUIServer already enforces session+CSRF on
   POST mutations — verify rather than assume.
5. **`Registration/`, `PhoneVerification/`** — invite-code check-vs-consume race,
   handle-squatting TOCTOU, OTP attempt caps and entropy.
6. **`Email/`** — CRLF header injection, template interpolation.
7. **Password KDF** — never located during the audit. Find it and assess.
8. **Service auth** — `getServiceAuth` `aud` restriction, `lxm` binding, `exp`;
   Ozone label/takedown ingestion authentication.
9. **`did:web` resolution** — implementation never located; path traversal and
   port smuggling unassessed.
10. **Relay `requestCrawl` admin-path SSRF bypass** — `handleAdminRequestCrawl`
    in `Network/RelayXrpcRoutePack.m` deliberately bypasses `validateHost:` and
    connects without SSRF validation. Operator-authenticated only; capture the
    operator-only caveat and decide whether an explicit
    `PDS_TRUST_OPERATOR_UPSTREAMS=` gate is needed before admin-crawled hosts
    are allowed to skip validation. Spike 0.4 resolved.

---

## Section 8 — Test-suite integrity

Two existing suites assert security properties they do not test. Both are worse
than no coverage, because their names imply the opposite.

- `Tests/Security/CBORSecurityTests.m` — `testDeeplyNestedArraysDoesNotCrash`
  has body `XCTAssertTrue(YES, @"Survived deep nesting")`. It passes whether or
  not a depth limit exists, and if the stack does blow it kills the runner rather
  than failing the case. Replace with the §1.2 assertion.
- `Tests/Security/HandleResolverSecurityTests.m` — allocates `self.resolver` in
  `setUp` and **never uses it**. Both tests call `SSRFValidator` as pure
  functions. Nothing exercises the resolver's URL construction, options wiring,
  redirects, or the §6.4 bypass. The range coverage it does have is real and
  adequate; the resolver coverage is absent.

Also run `PDSRunRegistrationAudit` (`--audit`) in CI to catch suites that link
but are unregistered and silently run zero tests.

---

## Section 9 — Repository hygiene

Two pre-existing build breaks were fixed during the review and should be
reviewed and committed:

1. `Sources/Database/PDSDatabase.h` — the uncommitted doc-comment pass deleted
   the `executeParameterizedQuery:params:modelClass:error:` **declaration** while
   its implementation (`PDSDatabase.m:1212`) and 21 call sites remained.
   Declaration restored; no behavior change.
2. `Tests/AppView/AppViewIndexerTests.m` — merge `6cebf219` duplicated three
   test methods. **This is committed on `main`, so `main` does not compile.**
   One copy of each removed; each block's unique test preserved.

Worth a follow-up: `main` was in a non-compiling state and this was not caught.
Check whether CI builds `AllTests` on every push, and whether the gate is
capturing the real build exit code.

## Proposed ADRs

| ADR | Subject | Blocks |
|---|---|---|
| new | Bounds-check idiom for untrusted length fields; shared range helper | §1.1 |
| new | DAG-CBOR canonical strictness lives in `ATProtoDagCBOR`; depth cap reuses `kMaxDecodeDepth = 64`; `Repository/CBOR.m` stays lenient with explicit `WebAuthn` opt-out (option c recorded 2026-07-28) | §1.2, §1.3, §3.1, §3.4 |
| amend 0013 | Extend claim-type rejection to XRPC request bodies; dispatcher guard parity | §2.1 |
| new | Access/refresh token separation — `token_use` + `typ` enforcement, distinct audiences | §4.1 |

## Suggested order

Section 0 (cheap, reprioritizes everything) → §1.1/§1.2 (proven, remote,
sub-10-byte bounds + depth in `Repository/CBOR.m`) → §1.3 (audit
`ATProtoDagCBOR` — **complete 2026-07-28**) → §1.4 Fuzzing → §1.5
(`ATProtoDagCBOR` canonical-form hardening, four fixes; unblocks §3.4) →
§2.1 (unauthenticated process kill) → §4.1 (token confusion) → §4.5
(delete dead `OAuthProvider*` files; **gated on S18** — see`docs/plans/workstreams/01-security-and-protocol-correctness.md`) →
(option c — DAG-CBOR routing migration catalogued in §S19) → Section 3
(integrity; canonical-form experiments already in §1.5) → Sections 5–6 →
Section 7 (new audits) → Section 8.
