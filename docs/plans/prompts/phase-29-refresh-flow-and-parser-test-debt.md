---
phase: 29
title: Refresh-flow regression and parser test debt
status: complete
agent: worker
depends_on: []
---

# Phase 29: Refresh-flow regression and parser test debt

## Progress

All four slices closed 2026-07-29.

- **Slice 1 (P0)** — fixed in `bab8bbf2`. Chose option (b): migrated the
  session flow to JWT refresh tokens via `mintRefreshTokenForDID:`, no
  migration path needed (no live production servers to preserve
  compatibility for). The two named regressions had a different root cause
  than this prompt's diagnosis: `verifyRefreshToken:` was never in the
  session-flow call path at all (it belongs to the OAuth2 flow only) — the
  real bugs were in §4.3's family/tombstone mechanism itself
  (`tombstoneRefreshTokenFamily:` killed the sibling token minted in the
  same rotation it was reacting to; `accountDidForRefreshToken:` never
  checked `rotated_at`/`tombstoned_at`). Replaced the family/tombstone
  model with the reference AT Protocol PDS's grace-period design
  (shortened expiry + `next_token` pointer + idempotent reissue on
  in-window replay) rather than either option this prompt originally
  posed — confirmed by reading `packages/pds/src/account-manager/` in
  `bluesky-social/atproto`. Added
  `testRefreshTokenReuseAfterGracePeriodIsRejected` and rewrote
  `testRefreshTokenRotation`'s final assertion for the new semantics.
  Full `AllTests --gated=run`: 4885 tests, only the 6 pre-existing failures
  unrelated to this phase remain (DPoP nonce challenge, CommitChain/
  Firehose CAR, X-Forwarded-For proxy parsing — confirmed pre-existing via
  `git stash` against the same HEAD).
- **Slice 2 (P1, STAR fixture)** — already landed by `fcbd15c3` before this
  session picked up the phase. `STARPreorderTests` 15/15 green, product
  code untouched.
- **Slice 3 (P2, CBOR canonical exploit tests)** — already landed by
  `fea378c9`/`14279b3c` before this session. `CBORCanonicalFormExploitTests`
  deleted; `CBORParserExploitTests` 6/6, `CARParserExploitTests` 2/2,
  `ParserRecursionExploitTests` 1/1 all green.
- **Slice 4 (P3, remote-issuer token_use/alg)** — product fix already
  landed by `b77de70d` (alg) and `c2bc66d1` (token_use/typ) before this
  session. Neither had a dedicated test; added both in `5da73c4e`
  (`AuthVerifierParityTests.m`): a remote-issued refresh token rejected at
  the access-token boundary, and a token with a disallowed header `alg`
  (genuinely signed, otherwise fully valid claims) rejected on the remote
  path. Broader `--filter '*Auth*'`/`--category Security` runs: 751 tests,
  0 failures.

## Mission

Two commits from the 2026-07-28 security review — `aa0482f5` (§4.1 `token_use`
enforcement) and `631b92bb` (§4.3 refresh reuse detection) — hardened the refresh
**verifier** without migrating every refresh **minter**. The result is a live
regression: refreshing a session returns 401, and rotation no longer revokes the
old token, which is the precise property §4.3 was added to guarantee.

Then clear the parser test debt left behind by the same review, so the suite goes
green and stops signalling a fix that must not be applied.

Baseline for this phase: **4662 tests, 8 failures** on a clean build.
Target: **0 failures**.

## Read first

- `docs/plans/security-review-2026-07-28.md` § "Status revision 2" (authoritative
  for this phase; if this prompt disagrees, that document wins)
- `docs/adr/0013-claim-type-rejection-at-json-boundaries.md` — the boundary
  principle §4.1 was extending
- `Garazyk/Sources/Services/PDS/PDSAccountService.m:690-735` — the rotation branch
- `Garazyk/Sources/Auth/JWT.m:784-802` — the *correct* JWT refresh minter
- `Garazyk/Sources/Auth/PDS/PDSAuth.m` — `verifyRefreshToken:` as changed by `aa0482f5`

## What is already correct — do not "fix" it

- `mintRefreshTokenForDID:` (`JWT.m:784`) already sets `token_use = @"refresh"`
  (`:795`) and `header.typ = @"refresh+jwt"` (`:802`). The JWT scheme is fine.
- The §4.1 check itself (`JWT.m:501-533`) is correct and correctly opt-in.
- The `Repository/CBOR.m` trailing-data rejection is **correct and load-bearing**.
  It is not the cause of the STAR failures. Do not remove or relax it — doing so
  re-opens a CID-malleability hole.
- `ATProtoDagCBOR` canonical-form enforcement and its `ATProtoDagCBOREdgeCaseTests`
  coverage are correct and stay.

## Slice 1 — Refresh flow (P0)

Two failures, both regressions (absent from the pre-`aa0482f5` baseline run):

- `NetworkSecurityHardeningTests/testRefreshTokenRotation`
  (`SecurityHardeningTests.m:172`) — new refresh token returns **401**, expected 200.
- `PDSAccountServiceTests/testRefreshAccessToken_RotatesRefreshToken`
  (`PDSAccountServiceTests.m:315`) — old refresh token still resolves after rotation.

**Cause.** Two coexisting refresh-token schemes. The live session flow mints an
**opaque UUID** (`PDSAccountService.m:713`, `[[NSUUID UUID] UUIDString]`) — no
header, no claims, no signature. §4.1 made `verifyRefreshToken:` parse the token
as a JWT and require `token_use`/`typ`, which an opaque UUID can never satisfy.
Three further legacy mint paths (`JWT.m:572`, `:602`, `:671`) stamp the generic
`typ = @"JWT"` with no `token_use` and fail the same check.

**Decision required before coding.** Pick one and record it in the workstream:

- **(a) Keep opaque refresh tokens (default if no sign-off is available).**
  Scope §4.1's JWT checks to the JWT scheme; make `verifyRefreshToken:` resolve
  opaque tokens through the session store with the family/tombstone check from
  §4.3. Smaller blast radius, no token-format change, no migration.
- **(b) Migrate the session flow to JWT refresh tokens** from
  `mintRefreshTokenForDID:`. One scheme, §4.1 applies uniformly — but it changes
  the token format and needs a migration path for tokens already issued.
  **Do not start (b) without explicit sign-off**: it invalidates live sessions.

Then fix revocation separately — it is a distinct defect from the 401. The
rotation branch at `PDSAccountService.m:690` falls back to "legacy DELETE-based
rotation" for tokens without `family_id`. Establish which branch the failing test
takes, and confirm both the account row and the session row are updated in the
same store: the assertion observes an account lookup by `refresh_jwt`
(`PDSDatabase+Accounts.m:157`).

**Exit:** both named tests green. Add a case asserting that a *rotated* token is
rejected **and** that presenting it revokes the family — reuse detection, not just
rotation.

## Slice 2 — STAR test fixtures (P1)

Four failures in `STARPreorderTests`. **These are fixture bugs, not product bugs.**

`testRecordDataForKey:` (`STARPreorderTests.m:83`) synthesizes record bytes as
`0xA1` followed by the raw UTF-8 key. `0xA1` is a CBOR `map(1)` header and what
follows is not CBOR — this data was never valid. `classifyChunk:` (`:147`)
CBOR-decodes each chunk and labels anything that is not a map `"other"`; all four
assertions route through it (`:332`, `:336`, `:492`, `:674`). The old lenient
decoder parsed the `map(1)` prefix and ignored the trailing bytes, so the fixture
classified as `"record"`. The trailing-data check now correctly rejects it.

Real MST nodes still classify correctly (5 nodes, as expected) — only the
synthetic records fail, which is the signature of a fixture problem.

**Fix:** make `testRecordDataForKey:` emit a valid canonical CBOR map (e.g.
`{"k": "<key>"}`) and let the CIDs follow from those bytes. Test-only change.

**Exit:** `STARPreorderTests` green with the product code untouched.

## Slice 3 — Delete the misaimed canonical tests (P2)

`CBORCanonicalFormExploitTests/testDuplicateMapKeysAreRejected` and
`.../testNonMinimalIntegerEncodingIsRejected` assert that `Repository/CBOR.m`
enforces canonical form. Under the §3.4 decision that decoder stays generic — it
also serves WebAuthn attestation parsing (`WebAuthnVerifier.m:65`), and CTAP2
canonical CBOR is a different profile from DAG-CBOR. The property is owned by
`ATProtoDagCBOR` and is already covered in `ATProtoDagCBOREdgeCaseTests`.

Delete both, and state the reason in the commit message: they were written before
the §3.4 decision and encode the rejected option. Leaving them red is how the
wrong fix gets applied.

Keep every other test in that file.

**Exit:** `CBORCanonicalFormExploitTests` green or removed; the parser exploit
suites (`CBORParserExploitTests` 6/6, `CARParserExploitTests` 2/2,
`ParserRecursionExploitTests` 1/1) stay green.

## Slice 4 — Remote-issuer `token_use` and `alg` (P3)

`AuthVerifier.m:289-296` (local issuer) sets `expectedTokenUse`/`expectedTyp`
correctly. `AuthVerifier.m:369-373` (remote issuer) builds `claimsVerifier` with
issuer, audience, and `allowedAlgorithms` but **not** `expectedTokenUse`/
`expectedTyp` — so a remote-issued refresh token is still accepted as an access
token. The same three lines assign `allowedAlgorithms` and then call
`validateClaims:`, which never reads `jwt.header.alg`; enforce the allowlist there
too. Both fixes land in one function.

Severity note: the `alg` gap is currently contained because
`AuthCryptoJWK.m:579` rejects any `kty != "EC"`, making HS256/ES256 confusion
structurally impossible. Fix it as hygiene, not as an emergency — and do not
weaken that `kty` check.

**Exit:** a test asserting a remote-issued refresh token is rejected at the
access-token boundary, and one asserting a token whose header `alg` is outside the
allowlist is rejected on the remote path.

## Verification gates

Run in this order; do not report success on a partial run:

```bash
cmake --build build --target AllTests -- -j4
```

Bound the build at `-j4` — a bare `--parallel` OOMs a 16 GB machine. Capture the
real exit code; the wrapper's code is not the compiler's.

```bash
./build/tests/AllTests --gated=run
```

Baseline is 4662 tests / 8 failures. Every slice must reduce that count and
introduce none. A full run is the gate — per-suite filters missed both Slice 1
regressions during the review.

If a new test file is added, re-run `cmake -S . -B build` (the `GLOB` has no
`CONFIGURE_DEPENDS`) **and** register the class in `Garazyk/Tests/test_main.m`,
or it silently runs zero tests.

## Out of scope

Do not start these here; they are tracked in
`docs/plans/security-review-2026-07-28.md`:

- §2.1 typed-accessor sweep (171 remaining raw `body[@"..."]` sites) — its own phase
- §4.2 DPoP `ath`, §4.6 `htu` host validation
- §5 data layer (blob ownership, `stringValue` crash, unclamped limit, LIKE ESCAPE)
- §6 blob CRLF, handle-resolver ambient SSRF bypass
- §7 unaudited surfaces (PLC, MST/commit integrity, Registration, AdminUI, Email,
  MediaCore/Video, password KDF)
- N1 `encodeCount:` 2³² truncation, N2 S19 encode/decode asymmetry, N3 `setUsage:`
