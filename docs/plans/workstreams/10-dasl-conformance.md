---
title: DASL Conformance
status: active
last_verified: 2026-08-03
---

# DASL Conformance

[DASL](https://dasl.ing/) is a family of 12 specs formalising the content-addressing primitives
atproto grew organically — CIDs, deterministic CBOR, CAR — plus higher-layer specs for retrieval,
metadata, media, and sandboxed web documents. The atproto data model explicitly aligns with DASL.
Garazyk implemented the bottom three specs ad hoc; this workstream makes them conformant and
*proves* it against the upstream [hyphacoop/dasl-testing](https://github.com/hyphacoop/dasl-testing)
vectors, then adds the remaining specs as separate, individually-gated products.

Continuation of [workstream 01 §S19](01-security-and-protocol-correctness.md) /
`docs/plans/security-review-2026-07-28.md` §3.4, which moved content-addressed decoding onto
`ATProtoDagCBOR`. §S19's consumer table (row 10) had recorded `Repository/CAR.m` as importer-only,
needing no migration; Phase 3 below found that finding incomplete — the CAR header itself was
still decoding through the generic `CBORValue` decoder — and closed it for real.

**Scale warning.** All 12 specs is a multi-month program. Phases 5–11 are additive; each needs its
own evidence, owner boundary, verification gate and rollback notes recorded here before
implementation starts, per `docs/plans/README.md` rules. Phase 9 (MUXL) means writing a
deterministic MP4 muxer rather than shelling out to ffmpeg, and is the largest single item.

### Strictness model (decided, implemented — see ADR 0032)

Layered profiles, not a global strict flip. `ATProtoDRISLProfile` separates "DRISL permits f64"
from "atproto records forbid floats" — both are correct, for different documents.
`ATProtoDASLCIDProfile` keeps the existing permissive `CID` parser untouched (atproto wire syntax
and legacy blob references require accepting non-DASL CID spellings) while adding a byte-exact
strict path used only where content-addressing integrity depends on it. Full rationale, defect
list, and consequences: [ADR 0032](../../adr/0032-dasl-conformance-profiles.md).

## Status (2026-08-03)

Phases 1–4 implemented and passing. Phase 0 (this doc + ADR 0032) landed alongside them,
deliberately after implementation so it records what was built rather than what was predicted.
Regression suite and cross-platform (GNUstep/Linux) UTF-8 verification pending. Phases 5–11 not
started.

## DONE — Phase 1: DRISL conformance

`Garazyk/Sources/Core/ATProtoDagCBOR.{h,m}`. Five defects fixed: unknown CBOR tags silently
unwrapped instead of rejected, `undefined` (`0xF7`) decoded to `null`, integer map keys accepted on
decode and non-string keys accepted on encode, and floats unconditionally rejected instead of
gated by profile. Four of the five were content-addressing bugs — a document could decode and
re-encode to different bytes, i.e. a different CID for the same logical input. Full defect table
and the `ATProtoDRISLFloat` box rationale: ADR 0032.

**Documented deviation:** integers clamp to int64. Two upstream vectors (`2^64-1`,
`-(2^64)`) fail for this reason; recorded in `DASLKnownDeviations()`
(`Garazyk/Tests/Core/DASLConformanceTests.m`), which fails the suite if either starts passing.

## DONE — Phase 2: strict DASL CID profile

`Garazyk/Sources/Core/CID+DASL.{h,m}` — a category on `CID`, no call-site churn for the existing
permissive parser. Byte-exact and string-exact canonical-spelling enforcement
(`+daslCIDFromBytes:profile:`, `+daslCIDFromString:profile:`, `-isDASLConformantForProfile:`).
`ATProtoDASLCIDProfileBig` additionally accepts BLAKE3-256 (multihash `0x1e`) — the CID-level half
of Phase 6 (BDASL); rejected under the base profile.

## DONE — Phase 3: DASL CAR

`Garazyk/Sources/Repository/CAR.{h,m}`. Header now decodes through `ATProtoDagCBOR` instead of the
generic `[CBORValue decode:]`, closing workstream 01 §S19 row 10. New
`+readFromData:strict:error:` / `+readFromPath:strict:error:` (existing entry points delegate with
`strict:NO` — no behavior change for current callers). Strict mode verifies every block CID is
DASL-conformant **and** equals SHA-256 of its own payload — a check that did not exist in any form
before this phase, so a peer could previously ship arbitrary bytes under an arbitrary CID and every
downstream lookup would trust the mislabeled content. Strict also requires every declared root
present in the body and skips the CID-synthesizing `parseLegacyData:` fallback. Enabled at the two
untrusted-input boundaries: `Network/XrpcRepoPack+Import.m` (repo import uploads) and
`AppView/Server/Backfill/AppViewBackfillWorker.m` (archives fetched from remote PDSes).

## DONE — Phase 4: conformance harness

104 vectors vendored to `Garazyk/Tests/fixtures/dasl-testing/` (README documents format, tag
semantics, refresh command). `Garazyk/Tests/Core/DASLConformanceTests.m`, 16 tests, 104/104 vectors
accounted for (`testEveryVectorIsAccountedFor` pins the corpus count so a fixture refresh that
drops files fails loudly). Registered in `Garazyk/Tests/test_main.m`.

**Result:** `./build/tests/AllTests --filter 'DASLConformanceTests' --gated=run` → 16 tests,
0 failures.

## Outstanding — Phase 0 close-out

1. Full regression run (`ctest --test-dir build --output-on-failure`), compared against the
   15-known-unrelated-failure baseline (DPoP-nonce, X-Forwarded-For) from workstream 01 §S19.
2. UTF-8 rejection (`_decodeTextString:` on `62c328`) verified on GNUstep/Linux, not just macOS.
3. `./scripts/dev/check_module_boundaries.sh .` and `./scripts/check-recursive-setters.sh`.

## Phases 5–11 — the remaining specs

Each phase below needs its own evidence/gate/rollback slice added here before implementation
starts; the summaries are the plan, not a completed record.

**Phase 5 — RASL** (`rasl://<cid>/?hint=<host>`). `ATProtoRASLURL` parser in Core; a
`GET|HEAD /.well-known/rasl/{cid}` route serving blocks and blobs as `application/octet-stream`
(alongside `App/NodeInfo/NodeInfoHandler.m`'s existing well-known routes); `ATProtoRASLClient` in
Transport doing parallel hint fetch, abort-on-first-success, non-307-redirects-treated-as-307, and
mandatory CID verification before returning bytes. The client fetches caller-supplied hosts, so it
must route through the existing SSRF validator and pinned-egress resolution (ADR 0016).

- Owner boundary: `Garazyk/Sources/Core` (URL parser), `Garazyk/Sources/App/NodeInfo` or a new
  well-known route pack (server side), `Garazyk/Sources/Transport` (client). Does not touch
  Storage or repository record contracts.
- Gate: new `ATProtoRASLURLTests` (parse/reject table), route-level test hitting the well-known
  endpoint with a known CID, SSRF-validator test proving hint hosts can't reach internal
  addresses.
- Rollback: route and client are additive; delete the route registration and the client class.

**Phase 6 — BDASL.** The CID half is already done (Phase 2, `ATProtoDASLCIDProfileBig`).
Remaining: the 1 KiB-chunk streaming verifier and HTTP-range→chunk mapping for blob/video
downloads. BLAKE3 is already vendored (`Garazyk/Sources/Security/Space/Vendor/BLAKE3`) and already
linked into `ATProtoCore` (used by `PDSSpaceLtHash`), so the hash primitive is free. Gate behind
config; never emit BDASL CIDs into records — only `ATProtoDASLCIDProfileBig` accepts them, and
nothing routes ordinary repository writes through that profile.

- Owner boundary: blob/video download path only (`Garazyk/Sources/Video`, blob serving in
  `Services/PDS`). Does not change blob upload or CID assignment.
- Gate: streaming verifier test with a truncated/corrupted chunk mid-stream; range-request test
  confirming byte ranges map to the correct chunk boundaries.
- Rollback: config flag off restores current (unverified streaming) behavior.

**Phase 7 — MASL.** DRISL metadata documents: single mode (`src`), bundle mode (`resources` path
map with a required `/` entry), `prev` history chain, curated HTTP-header allow-list, web-app-
manifest fields. Sits in Core; integrates with Phase 3 as CAR header metadata. First real consumer
of `ATProtoDRISLProfileDRISL` (Phase 1). Prerequisite for Phase 11.

- Owner boundary: `Garazyk/Sources/Core` only for the document model; CAR integration touches
  `Repository/CAR.m` read path.
- Gate: MASL document round-trip tests (single + bundle mode), `prev` chain validation test,
  header allow-list rejection test.
- Rollback: additive document type; no existing CAR consumer depends on MASL fields being present.

**Phase 8 — PFP.** Identifier type (`p` prefix, algo byte, length, inline hash or CID) plus the
`{"__pfp": "p…"}` JSON pseudo-type. ADR 0013 (claim-type rejection at JSON boundaries) governs
adding a new pseudo-type — must be read before implementation. Ships identifier, storage, and
comparison plumbing for Ozone moderation; PDQ / TMK+PDQF perceptual hashers are separate work (none
exists in-tree) — this phase only implements the identifier format the spec defines.

- Owner boundary: `Garazyk/Sources/Core` (identifier type), Ozone moderation storage/comparison
  call sites.
- Gate: identifier round-trip tests, JSON pseudo-type boundary rejection test per ADR 0013.
- Rollback: additive identifier type; no perceptual-hash producer exists yet to depend on it.

**Phase 9 — MUXL.** Deterministic ISO-BMFF: `[uuid-muxl][moof][mdat]…` fragments with a DRISL
catalog in the `uuid` atom, plus fMP4 and flat-MP4 presentation synthesis. Lands in
`Garazyk/Sources/MediaCore` + `Video` (jelcz). Current backends
(`Video/FFmpegTranscoder.m`, `Video/AVFoundationTranscoder.m`) shell out and emit HLS — MUXL
requires an in-repo muxer for byte-stability. **Largest item in this workstream** — a full
deterministic MP4 muxer, not a wrapper.

- Owner boundary: `Garazyk/Sources/MediaCore`, `Garazyk/Sources/Video`. Does not change the
  existing HLS transcode paths, which stay as fallback/alternative output.
- Gate: byte-stable re-mux test (same input twice → identical bytes), fMP4/flat-MP4 playback
  sanity check, DRISL catalog round-trip test.
- Rollback: new muxer is an additional output path; existing transcoders untouched, so reverting
  drops the new path without affecting current video delivery.

**Phase 10 — S2PA.** ES256K and DID key handling already exist (`PLC/PLCDIDKey.m`,
`vendor/secp256k1`). New: C2PA manifest structure (JUMBF), COSE_Sign1, and the deterministic
self-signed X.509 leaf derived from a DID + public key, with verifiers explicitly *not* chaining to
trust anchors. Depends on Phase 9 for video embedding.

- Owner boundary: new `Garazyk/Sources/Security/S2PA` (or similar), consuming `PLC/PLCDIDKey.m`
  read-only.
- Gate: manifest round-trip test, COSE_Sign1 verify test, explicit test that verification does
  *not* chain to a trust anchor (the deliberate deviation from standard C2PA trust behavior).
- Rollback: additive signing/verification path; nothing else depends on manifests existing.

**Phase 11 — Web Tiles + Tiles Protocols + TP Data.** A tile is a MASL bundle-mode manifest
packaged as a CAR (`.tile`) or as PDS blobs — Phase 7 first. Needs a unique-origin sandboxed iframe
host with strict CSP (`'self'`, `blob:`, `data:`, no network); `garazyk-ui`
(`Sources/AdminUIServer`) is the natural first host, plus `/.well-known/web-tiles/data.js` serving
the protocol module and the `tiles-protocol-up-*` / `tiles-protocol-down-*` postMessage envelope.
JS protocol modules belong in a `packages/` Deno workspace member.

- Owner boundary: `Garazyk/Sources/AdminUIServer` (host), new `packages/` member (protocol JS).
  Sandboxing/CSP changes must not weaken existing admin-UI CSP.
- Gate: CSP header test (no network origins permitted), postMessage envelope round-trip test,
  sandboxed-iframe escape test (confirm no `document.domain` / top-navigation access).
- Rollback: new route + new package; delete both, existing admin-UI routes unaffected.

**Optional, out of tree:** contribute an Objective-C harness to hyphacoop/dasl-testing so Garazyk
appears in the published conformance report.

## Repo conventions that apply to every phase

- SPDX headers on every new file (`scripts/add-spdx-headers.ts`); vendored fixtures declared in
  `.reuse/dep5`.
- Absolute imports from `Garazyk/Sources/` (`#import "Core/CID+DASL.h"`), never relative.
- New test suites: add to `testClasses` in `test_main.m` **and** re-run `cmake -S . -B build`.
- Match each file's existing style; do not run clang-format.
- Any new XRPC methods use generated constants from `Network/Generated/GZXrpcNSID.h`.

## Rollback (workstream-level)

Phases 1–4 are behavior-preserving for all pre-existing call sites (see ADR 0032 Consequences);
reverting any one phase does not require reverting the others except where noted per-phase above.
Phases 5–11 are each additive and independently revertible — no phase's production code is a
prerequisite for another phase's *existing* callers to keep working, only for that phase's own new
functionality (e.g. Phase 11 needs Phase 7's document model, but Phase 7 has no Phase 11
dependents until Phase 11 lands).
