---
title: DASL Conformance
status: active
last_verified: 2026-08-08
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

Phases 1–11 have bounded, independently gated slices; the macOS portion of the Phase 0 close-out is verified.
Phase 0 (this doc + ADR 0032) landed alongside the initial implementation, deliberately after
implementation so it records what was built rather than what was predicted. Phase 5 has strict URL
parsing, a registered GET/HEAD well-known route, bounded local block/blob resolution, mandatory
SHA-256 CID verification, and an SSRF-safe parallel client. Phase 6 has the reusable BLAKE3
streaming verifier and range mapper, but no invented HTTP sidecar transport. Phases 7–11 are
bounded document, identifier, media, COSE, and data-protocol/policy slices; their explicit
production integration remainders remain open.

Phase 0 evidence: `build/tests/AllTests --gated=run` passes 4,955 tests with 0 failures;
`scripts/check_module_boundaries.sh build` reports no new violations with 26 baseline
violations remaining; `scripts/dev/check_module_boundaries.sh .` and
`scripts/check-recursive-setters.sh` pass. The source-boundary checker now permits the
intentional acyclic PLC→Storage edge documented in workstream 08 M4.2 (`06c0c8f5`). The
cross-platform UTF-8 follow-up and a full GNUstep `AllTests` run are now both closed (2026-08-04,
see "Outstanding — cross-platform DASL evidence" below and workstream 08's verified-status
section) — the GNUstep suite runs to completion (4,726 tests, 562 failures, 933s wall clock;
reproduced twice), a new backlog recorded but not yet triaged — 86.7% of it traces to one
shared-fixture root cause, see workstream 08.

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

## Outstanding — cross-platform DASL evidence

1. **Closed (2026-08-04).** The `1c8c2dd8` fix (`testInvalidUTF8TextStringIsRejected` in
   `ATProtoDagCBOREdgeCaseTests.m`, plus the `XCTAssertEqual`→`XCTAssertEqualObjects` boxing fixes
   in `PDSAdminServiceTests.m`/`PDSBlobAuditHandlerTests.m`) is committed and confirmed against a
   real GNUstep `AllTests` binary, not just the earlier standalone Foundation probe:
   `ATProtoDagCBOREdgeCaseTests` (26/26), `DASLConformanceTests` (16/16), `PDSAdminServiceTests`
   (47/47), and `PDSBlobAuditHandlerTests` (5/5) all pass 0 failures under
   `./tests/AllTests --filter '<class>' --gated=run` on GNUstep. See workstream 08's verified-status
   section for the toolchain and full-suite evidence.
2. **Closed for real (2026-08-04), new baseline recorded, reproduced twice.** A full GNUstep
   `AllTests --gated=run` now completes for the first time in this workstream's history:
   **4,726 tests run, 562 failures, 933s (~15.5 min) wall clock**, using the known-good
   from-source toolchain in `docker/Dockerfile.gnustep` (a first attempt, lost to an unrelated
   environment reset mid-capture, gave 4,723/560 with a misleading ~101-minute duration figure
   that turned out to be a clock-jump measurement artifact, not real elapsed time — see workstream
   08's verified-status section for the full reproduction and correction). This closes the "has
   not completed" gap, but 562 failures is a new, real backlog, not a clean pass — do not treat
   GNUstep as green. **The complete (untruncated) failure log shows 488 of 562 failures (86.7%)
   are one root cause**: `AdminAuthXrpcTestBase`/`RepoAuthTempTests`'s shared `-setUp` fails its
   own `XCTAssertTrue(adminAuthSuccess, ...)` assertion (`PDSAdminAuth
   authenticateWithPassword:error:` — password verification or JWT signing diverging from macOS
   on GNUstep, not yet root-caused), cascading into every inherited test method across 51 test
   classes regardless of what each one exercises. Remaining clusters: ~57 HTML-template-loading
   failures likely specific to this reproduction's container missing the built `Assets` directory
   (not necessarily a real GNUstep bug — `UITemplateEngine.m:31` logs "Failed to load template
   ...: (null)" alongside every one), ~9 environment-variable config-parsing failures in
   `ATProtoMediaServiceConfiguration`/`JelczCLITests` (genuinely distinct, worth its own
   investigation), 3 failures from a missing `ffprobe` binary (environment gap, not a code bug),
   and a handful of unclassified one-offs. Triaging and fixing this backlog is its own bounded
   follow-up workstream item, not attempted here — this entry proves the suite now runs to
   completion and records a precise, complete accounting of what it found, including the
   high-leverage root-cause finding above.

### GNUstep auth-fixture evidence (2026-08-08)

The focused GNUstep proof is now complete: a fresh builder image from
`docker/Dockerfile.gnustep` was built as `garazyk-gnustep-proof:2026-08-08`,
`AllTests` was configured with `BUILD_TESTS=ON` and built with
`cmake --build ... --target AllTests --parallel 4`, and
`./build-tests/tests/AllTests --filter PDSAdminAuthTests --gated=run` passed
15/15 with 0 failures. This includes the environment-snapshot regression and
confirms that the `getenv()` correction reaches password authentication, JWT
minting, and header-policy checks on GNUstep.

The affected shared-fixture rerun remains open: broad and narrowed selections
were interrupted by repeated OrbStack Docker-daemon resets before their final
summaries; a final 2-suite bounded retry entered an uninterruptible database
fixture wait without a summary. See workstream 08's dated evidence for the
exact commands, logs, and failure classifications. This does not change the
three recorded CI-policy options; no CI policy or product code was changed.

## Phases 5–11 — the remaining specs

Each phase below needs its own evidence/gate/rollback slice added here before implementation
starts; the summaries are the plan, not a completed record.**Phase 5 — RASL — IMPLEMENTED (base profile).** (`rasl://<cid>/?hint=<host>`).
`ATProtoRASLURL` parses strict base/Big-DASL authorities and bounded HTTPS hints. The registered
`GET|HEAD /.well-known/rasl/{cid}` route selects the base profile, serves locally resolved
blocks/blobs as `application/octet-stream`, and re-hashes every response against the requested
SHA-256 CID before serving. `ATProtoRASLClient` performs parallel hint fetches through the existing
SSRF validator and pinned-egress client, returning only a CID-verified response; it rejects a
parsed BLAKE3 CID before network access. BLAKE3/Big DASL is therefore rejected at the server route
and client verification boundary and remains Phase 6 work, rather than being served unverified.

- Owner boundary: `Garazyk/Sources/Core` (URL parser), `Garazyk/Sources/Network` (route/client),
  and `Garazyk/Sources/Services/PDS` (bounded resolver). Does not touch Storage or repository
  record contracts.
- Evidence: `ATProtoRASLURLTests`, `ATProtoRASLClientTests`, `PDSRASLResolverTests`, and
  `ATProtoHttpWellKnownRoutePackTests` are registered. The URL/client/resolver suites cover strict
  parsing, no-hint and unsupported-hash failures, block/blob lookup, scan bounds, and fail-closed
  BLAKE3 behavior. The live route fixture starts an ephemeral loopback server and exercises exact
  CID-verified GET and bodyless HEAD responses, then corrupts a repository block while retaining
  its original CID key and confirms both methods fail closed. GNUstep SSRF/HTTPS integration remains follow-up evidence
  because the current test harness has no local TLS fixture.
- Rollback: route and client are additive; delete the route registration and the client class.

**Phase 6 — BDASL — PARTIAL (bounded verifier primitive).** The CID half was already done
(Phase 2, `ATProtoDASLCIDProfileBig`). `Core/ATProtoBDASLVerifier` now verifies an explicit sidecar
of one BLAKE3 digest per 1 KiB payload chunk while data arrives in arbitrary-sized pieces, then
verifies the complete payload root against the BLAKE3 CID. It also maps inclusive HTTP byte ranges
to the containing chunk indices, including open-ended and clamped ranges. This is an interim,
repository-owned sidecar shape, not the full BDASL hash-tree wire format: the sidecar remains an
explicit caller-supplied array because BDASL requires hash-tree metadata, and this slice does not
invent a network sidecar format or silently trust an HTTP server.

BLAKE3 is vendored (`Security/Space/Vendor/BLAKE3`) and already linked into `ATProtoCore` (used by
`PDSSpaceLtHash`). This phase does not emit BDASL CIDs into records, alter blob upload/CID
assignment, or wire unverified existing HTTP blob responses to the new verifier. The production
HTTP-range integration is the next bounded slice. The bounded sidecar transport contract is now
recorded: the caller supplies the conformant
BLAKE3 CID, exact payload length, and complete per-1 KiB chunk digest array; no sidecar is fetched
from a server. HTTP integration requests one single inclusive range per chunk. The requested
range is authoritative, so a response is accepted only for HTTP 206 with a body whose length is
exactly the requested range length; `Content-Range`, `Content-Length`, and server-specific
metadata are observational only and cannot define ranges, lengths, chunk counts, or digests.
Each response is verified against its caller-supplied chunk digest, and the assembled payload is
verified against the caller-supplied BLAKE3 CID before return. This is a repository-owned boundary,
not an invented full BDASL hash-tree wire format.

- Owner boundary: `Garazyk/Sources/Core` for the reusable verifier; future integration belongs to
  blob/video download paths only (`Blob`, `Services/PDS`, `Video`).
- Evidence: `ATProtoBDASLVerifierTests` covers split-input verification, sidecar and payload
  corruption (including the final short chunk), truncated streams, root mismatch, exact chunk
  boundaries, open-ended/clamped ranges, and reversed-range rejection. Registered in
  `Tests/test_main.m`.
- Rollback: remove the additive verifier and test registration; existing blob upload and download
  behavior is unchanged.

**Phase 7 — MASL — PARTIAL (validated Core document model).** `Core/ATProtoMASLDocument` now
validates DRISL metadata documents in single mode (`src`) and bundle mode (`resources` with an
exact `/` entry), preserves arbitrary namespaced metadata, validates `$type`, `prev`, and bundle
resource CIDs, and exposes the lower-case HTTP-header allow-list without reflecting unknown or
incorrectly-cased fields. `sourcemap`, `speculation-rules`, and Web App Manifest icon/screenshot
references must name exact bundle paths. CAR compatibility is an explicit validation gate for
integer `version: 1` and CID-only `roots`; the existing CAR reader is not changed until a header
metadata integration contract is selected.

- Owner boundary: `Garazyk/Sources/Core` only for the document model; future CAR integration touches
  `Repository/CAR.m` read path.
- Evidence: `ATProtoMASLDocumentTests` covers single/bundle DRISL round-trip, required root and
  resource `src` fields, `prev`/`$type`, allow-listed header projection, manifest path references,
  and CAR compatibility validation. The model is registered in `Tests/test_main.m`.
- Explicit remainder: CAR header read/write integration and bundle resource lookup are not wired;
  this bounded slice does not invent a new CAR metadata transport or web runtime.
- Rollback: additive document type and test registration; no existing CAR consumer depends on MASL fields being present.

**Phase 8 — PFP — PARTIAL (strict identifier format).** `Core/ATProtoPFP` implements the
registered PDQ (`0x01`, 32-byte inline hash) and TMK+PDQF (`0x02`, 36-byte strict base-DASL CID)
forms. It enforces the lowercase `p` prefix, lowercase RFC4648 base32 with zero trailing padding
bits, canonical unsigned varints, exact algorithm-specific lengths, no trailing bytes, and strict
CID validation. It also exposes the exact `{"__pfp": "p…"}` JSON pseudo-type boundary. No PDQ or
TMK+PDQF producer, perceptual comparison metric, or Ozone storage integration is invented here.

- Owner boundary: `Garazyk/Sources/Core` for the immutable identifier and JSON boundary; future
  comparison/storage integration belongs to Ozone moderation only after a producer/metric contract
  is selected.
- Evidence: `ATProtoPFPTests` covers PDQ and TMK+PDQF byte/string round-trips, exact pseudo-type
  parsing, unknown algorithms, length/truncation/trailing-data failures, non-canonical varints,
  strict CID rejection, and lowercase/padding base32 rejection. Registered in `Tests/test_main.m`.
- Explicit remainder: no perceptual-hash producer, similarity comparator, or moderation database
  column is wired by this bounded slice.
- Rollback: additive identifier type and test registration; no existing moderation or media caller depends on PFP.

**Phase 9 — MUXL — PARTIAL (catalog atom and opaque fragment envelope).**
`MediaCore/ATProtoMUXLBox` validates a canonical single-track video or audio catalog, encodes and
decodes the normative fixed `uuid-muxl` BMFF atom with DRISL bytes, and composes
`[uuid-muxl][moof][mdat]...` segments while preserving each opaque fragment byte-for-byte. It
requires each supplied fragment to be exactly one standard-size `moof` followed by one `mdat`, but
does not reinterpret their sample tables.

- Owner boundary: `Garazyk/Sources/MediaCore` for catalog/box primitives; future sample minting
  belongs in `Garazyk/Sources/Video`. Existing HLS/transcoder paths are unchanged.
- Evidence: `ATProtoMUXLBoxTests` covers deterministic catalog round-trip, fixed UUID/type bytes,
  single-track/rendition and catalog-field validation, opaque fragment preservation, and malformed
  box/fragment rejection. Registered in `Tests/test_main.m`.
- Explicit remainder: fragment minting (`mfhd`/`traf`/`trun`), fMP4 init-header synthesis, flat-MP4
  indexing, and playback sanity remain open; this slice does not claim to be a complete muxer.
- Rollback: additive MediaCore primitive and test registration; existing HLS/transcoder output is untouched.

**Phase 10 — S2PA — PARTIAL (strict COSE_Sign1 ES256K core).**
`Security/S2PA/ATProtoS2PACOSE` implements an attached COSE_Sign1 envelope with the normative
ES256K algorithm (`-47`), canonical protected header `{1: -47}`, empty unprotected headers, the
COSE `Sig_structure`, and 64-byte low-S secp256k1 signatures through the existing primitive. It
rejects alternate CBOR encodings, unsupported algorithms, malformed fields, and signature/payload
mismatch. Verification consumes a supplied public key and intentionally does not consult X.509
trust anchors, matching S2PA's self-certifying trust model.

- Owner boundary: `Garazyk/Sources/Security/S2PA` owns the COSE envelope; it consumes
  `Auth/Crypto/Secp256k1` read-only and does not alter repository signatures or auth JWTs.
- Evidence: `ATProtoS2PACOSETests` covers exact protected-header bytes, Sig_structure shape,
  deterministic signing, attached-payload extraction, payload/key tampering, unsupported
  algorithms, non-canonical CBOR rejection, and explicit no-trust-anchor verification.
- Explicit remainder: the C2PA claim/manifest-store schema, JUMBF embedding, S2PA deterministic
  self-signed secp256k1 X.509 leaf, DID-to-certificate identity binding, and video integration
  remain open. This slice is a cryptographic COSE core, not a complete C2PA/S2PA asset manifest.
- Rollback: remove the additive S2PA directory and test registration; existing signing and media
  paths are unchanged.**Phase 11 — Web Tiles + Tiles Protocols + TP Data — PARTIAL (data protocol and execution policy).**
`AdminUIServer/UITileDataProtocol` serves the reserved `/.well-known/web-tiles/data.js` module with
`addDataHandler`, `removeDataHandler`, `listen`, and `sendData`, using the normative
`tiles-protocol-up-data-ready`, `tiles-protocol-up-data-payload`, and
`tiles-protocol-down-data-payload` structured-clone message actions. `UITileExecutionPolicy` exposes
the normative restrictive CSP and isolation/security headers: no explicit `connect-src` or external
network origin, `object-src 'none'`, `base-uri 'none'`, and the required sandbox/COOP/CORP/referrer/
permission/DNS-prefetch headers. The policy is not itself a network boundary on a normal origin;
unique-origin hosting is still required before arbitrary tile execution. The reserved route is
additive and does not serve arbitrary tile resources.

- Owner boundary: `Garazyk/Sources/AdminUIServer` owns the host-selected protocol module and pure
  policy helpers. The route is registered with the existing Lab route group; existing authenticated
  Admin UI CSP and routes are unchanged.
- Evidence: `UITileExecutionPolicyTests` checks the exact restrictive policy, isolation headers,
  protocol exports, action directions, payload requirements, and malformed-message rejection.
  `UIServerRuntimeTests` checks the reserved route, JavaScript content type, protocol exports,
  parent-window source filtering, and absence of a network fetch sink. `UITileExecutionPolicyTests`
  checks the policy helper independently; it is not applied to `data.js`, because CSP and sandboxing
  must protect the tile document rather than the imported protocol module.
- Explicit remainder: unique-origin iframe creation, CAR/MASL tile loading, blob resource mapping,
  host-side origin authentication, and a separate Deno protocol package remain open. This slice
  does not claim to execute arbitrary tile content or provide a full tile host.
- Rollback: remove the additive policy/protocol helpers, reserved route, and test registration;
  existing Admin UI routes and CSP remain unchanged.

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
