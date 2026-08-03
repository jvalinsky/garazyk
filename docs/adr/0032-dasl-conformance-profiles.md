# ADR 0032: DASL Conformance Is a Layered Profile, Not a Global Strict Flip

**Status:** Accepted
**Date:** 2026-08-03

## Context

[DASL](https://dasl.ing/) formalises the content-addressing primitives atproto grew organically:
DRISL (deterministic CBOR), the DASL CID subset, and CAR. Garazyk implemented ad hoc versions of
all three; this work made them conformant against the upstream
[hyphacoop/dasl-testing](https://github.com/hyphacoop/dasl-testing) corpus (104 vectors) while
keeping every existing call site's behavior unchanged.

Auditing `Core/ATProtoDagCBOR.m` against the corpus found five real defects — four of them
content-addressing bugs, where a document decoded and re-encoded to *different bytes* than it
started with:

1. Unknown CBOR tags (anything but 42) were silently unwrapped, returning the tagged payload. A
   document tagged with, say, bignum (tag 2/3) or self-describing CBOR (tag 55799) decoded fine
   and re-encoded without the tag — a different CID for logically "the same" input.
2. `0xF7` (`undefined`) decoded to `NSNull` and re-encoded as `0xF6` (`null`) — same bug, one
   more byte pattern.
3. Integer map keys (`a10000`) decoded without complaint. DAG-CBOR requires text-string keys only.
4. The encoder's `_canonicallySortedKeys:` would happily encode an `NSNumber` key if one reached
   it, for the same reason.
5. All floats were rejected, unconditionally. DRISL (the general spec) permits f64; atproto's own
   profile forbids floats entirely. Both are correct, for different documents.

Straightforwardly "fixing" (5) by allowing floats everywhere would be wrong — it changes
content-addressing for every existing repository record, silently. Straightforwardly leaving it
unfixed makes the conformance suite fail on legitimate DRISL vectors that no atproto data will
ever produce (DASL's outer layers — MASL, PFP — depend on plain DRISL, not the atproto-narrowed
subset).

The DASL CID subset raises the same shape of question one layer down: DASL requires exactly one
canonical spelling per CID (SHA-256 dag-cbor, `b`-prefixed base32, no padding), but
`Garazyk/Tests/fixtures/atproto-interop-tests/syntax/cid_syntax_valid.txt` requires *accepting*
`z…`/`f…`/`m…`/`7…` multibase and dag-pb `bafybei…` CIDs — those are real atproto wire syntax, not
malformed input. Blob references inside already-signed historical records also carry non-DASL
CIDs (dag-pb, or CIDv0). Rejecting them at parse time breaks readable history for data that was
valid when it was written.

## Decision

Conformance is exposed as **profiles the caller selects**, not a single global strictness switch.

1. **`ATProtoDRISLProfile`** (`Core/ATProtoDagCBOR.h`):
   - `ATProtoDRISLProfileATProto` — the default, used by every pre-existing call site. Floats
     rejected entirely, tags/undefined/integer-keys rejected as fixed in items 1–4 above. Bit-for-
     bit identical behavior to before this change for all repository data, because nothing that
     previously round-tripped through this profile carried a float, tag ≠ 42, `undefined`, or a
     non-string key in the first place — those were exactly the cases that were broken.
   - `ATProtoDRISLProfileDRISL` — accepts f64 only (rejects f16/f32, NaN, ±Inf); `-0.0` round-trips
     distinctly from `0.0`. No production call site uses this yet; it exists for the conformance
     suite and as the entry point for Phase 7 (MASL), which is a real DRISL consumer.

   Floats are carried by a new `ATProtoDRISLFloat` box rather than `NSNumber`. Two reasons:
   `NSNumber` cannot represent `-0.0` distinctly from `0.0` (a decoded `-0.0` would re-encode as
   `0.0` — the exact same round-trip bug the tag/undefined fixes were closing), and GNUstep's
   `NSNumber` reports some boxed integers as floating types via `-objCType`, which would misclassify
   ordinary integers as floats if float-vs-integer dispatch used that API.

2. **`ATProtoDASLCIDProfile`** (`Core/CID+DASL.h`, a category on `CID` — no call-site churn for the
   existing permissive parser):
   - `+daslCIDFromBytes:profile:` / `+daslCIDFromString:profile:` / `-isDASLConformantForProfile:`
     enforce the single canonical spelling byte-exact and string-exact (`01 (55|71) 12 20 ‖
     <32-byte digest>`; `b`-prefixed, 59 chars, lowercase RFC 4648 no padding, trailing padding
     bits zero).
   - `ATProtoDASLCIDProfileBig` additionally accepts BLAKE3-256 (multihash `0x1e`) — the CID-level
     half of Phase 6 (BDASL). The base profile rejects it, so a BDASL CID cannot reach ordinary
     repository data through this path.
   - The pre-existing permissive `CID` parser (`+cidFromBytes:`, `+cidFromBuffer:length:consumed:`)
     is untouched. Tag-42 links decoded under `ATProtoDRISLProfileATProto` still resolve through
     it, because atproto wire syntax and pre-DASL blob references require it, as described above.

3. **Strict is opt-in per call site, not global**, applied only where content-addressing integrity
   actually depends on it: the DRISL profile choice at any `ATProtoDagCBOR` call, and
   `CAR +readFromData:strict:` / `+readFromPath:strict:`. Strict CAR additionally verifies every
   block CID against a fresh SHA-256 of its payload — a check that did not exist before this work
   at all (see Consequences) — and rejects the CID-synthesizing `parseLegacyData:` fallback, which
   is not a CAR variant and can mask a malformed v1 archive by manufacturing plausible CIDs for it.
   Strict is wired at the two boundaries where CAR bytes arrive from an untrusted peer:
   `Network/XrpcRepoPack+Import.m` (repo import uploads) and
   `AppView/Server/Backfill/AppViewBackfillWorker.m` (archives fetched from remote PDSes). Every
   other caller keeps `strict:NO` and current behavior.

## Consequences

- **Zero behavior change for existing repository data.** The ATProto DRISL profile is what every
  call site used before; its output for any input that was previously valid is unchanged. Only
  previously-*invalid*-but-silently-accepted input (unknown tags, `undefined`, integer keys) now
  correctly fails, which is the bug being fixed, not a behavior change to defend.
- **A real security finding, not just conformance polish.** CAR strict mode's CID-vs-payload check
  did not exist in any form before this ADR. Non-strict CAR reading — every call site until this
  change — trusted a block's declared CID without verifying it against the block's bytes, meaning
  a peer could ship arbitrary bytes under an arbitrary CID and every downstream lookup would treat
  the mislabeled content as if it were the content the CID actually committed to. This is now
  closed at the two untrusted-input boundaries; it is deliberately not enabled everywhere, since
  CAR files produced internally (e.g. from this repo's own MST) are already trusted and the check
  has a real cost on large archives.
- **`ATProtoDRISLFloat` is a new type**, not `NSNumber`, for the reasons in Decision (1). Any
  future DRISL-profile consumer (Phase 7/MASL) must handle this box rather than assuming
  `NSNumber` covers all decoded scalars.
- **Documented deviation from the upstream corpus:** integers stay clamped to `int64_t`. Exactly
  two of the 104 upstream vectors fail for this reason (`2^64-1` and `-(2^64)` — the latter has no
  `NSNumber` representation at all). This is a deliberate bound on attacker-supplied integer
  magnitude, not an oversight. It is recorded in `DASLKnownDeviations()`
  (`Garazyk/Tests/Core/DASLConformanceTests.m`), which fails the test suite if either listed vector
  starts passing, so the deviation list cannot silently rot into hiding a real regression.
- **Enforcement stays narrow by design.** Tag-42 links under the ATProto profile, and the
  permissive `CID` parser generally, are left conformant-but-not-enforced on purpose — tightening
  them would reject valid atproto wire syntax (dag-pb CIDs) and break resolution of blob references
  inside records that were signed before DASL's CID rules existed. If a future workstream wants to
  migrate historical data off non-DASL CIDs, that is a data-migration project, not a parser change.
- **Rollback.** Each profile is additive: deleting `ATProtoDRISLProfileDRISL` and
  `ATProtoDASLCIDProfileBig` leaves the ATProto profile and base CID profile as the sole
  behavior, unchanged from pre-ADR code modulo the five defect fixes (which should not be
  reverted — they were bugs). Reverting strict CAR at the two call sites drops the CID/payload
  check and returns to trusting declared CIDs, which should only be done together with an explicit
  decision to accept that risk again.

## Cross-links

- Continuation of workstream 01 §S19 / `docs/plans/security-review-2026-07-28.md` §3.4, which
  moved content-addressed decoding onto `ATProtoDagCBOR`. §S19's own consumer table listed
  `Repository/CAR.m` (row 10) as importer-only with no migration needed; this work supersedes that
  finding — the CAR header now decodes through `ATProtoDagCBOR` instead of the generic
  `[CBORValue decode:]`, closing that row for real. See
  [workstream 01, §S19 update](../plans/workstreams/01-security-and-protocol-correctness.md).
- Conformance evidence: `Garazyk/Tests/Core/DASLConformanceTests.m`, 104 vendored vectors under
  `Garazyk/Tests/fixtures/dasl-testing/`.
- Governing workstream: [workstream 10](../plans/workstreams/10-dasl-conformance.md).
