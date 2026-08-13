---
title: DASL Conformance
status: active
last_verified: 2026-08-12
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

## Status (updated 2026-08-12)

Phases 1–11 have bounded, independently gated slices; the macOS portion of the Phase 0 close-out is verified.
Phase 0 (this doc + ADR 0032) landed alongside the initial implementation, deliberately after
implementation so it records what was built rather than what was predicted. Phase 5 has strict URL
parsing, a registered GET/HEAD well-known route, bounded local block/blob resolution, mandatory
SHA-256 CID verification, and an SSRF-safe parallel client. Phase 6 has the reusable BLAKE3
streaming verifier, range mapper, and verified HTTP range integration that keeps the sidecar
caller-supplied. Phases 7–11 are
bounded document, identifier, media, COSE, and data-protocol/policy slices; Phase 8
(PFP producer + Ozone column) and Phase 9 (MUXL) are complete. Phase 10 S2PA has
COSE + leaf + JUMBF uuid + SHA-256 hard binding + `c2pa.hash.data` assertion
(2026-08-13); `c2pa.hash.bmff.v3` root-box hashing + `c2pa.soft-binding` encode
landed 2026-08-13; claim-map-v2 + assertion store landed 2026-08-13;
ingredient claims (v3 encode landed 2026-08-13; validationResults / embedded
manifest verify remain), soft-binding algorithms, and Merkle bmffHash remain
open. Transcoder auto-sign landed 2026-08-13 (opt-in). Phase 7 production paths
remain open.
Phase 11 mothership resolve-path + getBlob load landed 2026-08-13; Deno
`@dasl/tiles` / live embed remainders remain open.

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

### GNUstep RASL/BDASL TLS and SSRF evidence (2026-08-08)

The current `codex/dasl-network` source was mounted into the existing
from-source GNUstep proof image `garazyk-gnustep-proof:2026-08-08`. A GNUstep
CMake configure with `BUILD_TESTS=ON`, followed by
`cmake --build ... --target AllTests --parallel 4`, compiled the current Core,
Transport, RASL, BDASL, and SSRF sources but could not link `AllTests`: the
unrelated Admin UI `UIAuthManager.m` compilation failed at five `HttpRequest`
forward-declaration uses. Admin UI was not changed.

The bounded GNUstep harness then compiled the current
`ATProtoRASLClientTests`, `ATProtoBDASLVerifierTests`, and
`SSRFValidatorTests` objects and ran all registered methods: **43 tests, 0
failures**. This includes the RASL range fixture, per-chunk BLAKE3 checks,
wrong-response rejection, and SSRF validator coverage under GNUstep.

For live TLS evidence, a temporary local HTTPS fixture served 25 bytes through
GNUstep's `ATProtoSafeHTTPClient` libcurl path. The fixture CA was installed
only in the ephemeral container trust path and private-host access was enabled
only for that local fixture. A second request using the default policy to
`https://127.0.0.1/` was rejected before connection with
`ATProtoSafeHTTPClientErrorSSRFBlocked` (code 3). This proves the GNUstep HTTPS
transport path and the default RASL SSRF boundary without weakening product
policy. The full `AllTests` GNUstep gate remains blocked only by the unrelated
Admin UI compile failure above.

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
  its original CID key and confirms both methods fail closed. GNUstep
  SSRF/HTTPS evidence is recorded in the dated section above.
- Rollback: route and client are additive; delete the route registration and the client class.

**Phase 6 — BDASL — IMPLEMENTED (bounded sidecar and HTTP range integration).** The CID half was already done
(Phase 2, `ATProtoDASLCIDProfileBig`). `Core/ATProtoBDASLVerifier` now verifies an explicit sidecar
of one BLAKE3 digest per 1 KiB payload chunk while data arrives in arbitrary-sized pieces, then
verifies the complete payload root against the BLAKE3 CID. It also maps inclusive HTTP byte ranges
to the containing chunk indices, including open-ended and clamped ranges. This is an interim,
repository-owned sidecar shape, not the full BDASL hash-tree wire format: the sidecar remains an
explicit caller-supplied array because BDASL requires hash-tree metadata, and this slice does not
invent a network sidecar format or silently trust an HTTP server.

BLAKE3 is vendored (`Security/Space/Vendor/BLAKE3`) and already linked into `ATProtoCore` (used by
`PDSSpaceLtHash`). The RASL client now fetches one exact single-range response per chunk through
the existing SSRF-safe/pinned-egress HTTP boundary, verifies each body against the caller-supplied
sidecar, assembles the bytes in chunk order, and verifies the complete payload against the BLAKE3
CID. It falls back across hints per chunk, and rejects non-206 or wrong-length responses before
verification. This phase does not emit BDASL CIDs into records, alter blob upload/CID assignment,
or wire existing blob download paths to the new verifier. The bounded sidecar transport contract
is: the caller supplies the conformant
BLAKE3 CID, exact payload length, and complete per-1 KiB chunk digest array; no sidecar is fetched
from a server. HTTP integration requests one single inclusive range per chunk. The requested
range is authoritative, so a response is accepted only for HTTP 206 with a body whose length is
exactly the requested range length; `Content-Range`, `Content-Length`, and server-specific
metadata are observational only and cannot define ranges, lengths, chunk counts, or digests.
Each response is verified against its caller-supplied chunk digest, and the assembled payload is
verified against the caller-supplied BLAKE3 CID before return. This is a repository-owned boundary,
not an invented full BDASL hash-tree wire format.

- Owner boundary: `Garazyk/Sources/Core` owns the reusable verifier and range mapper;
  `Garazyk/Sources/Network` owns RASL HTTP and SSRF/pinned-egress composition. Existing blob/video
  download and upload paths remain untouched.
- Evidence: `ATProtoBDASLVerifierTests` covers split-input verification, sidecar and payload
  corruption (including the final short chunk), truncated streams, root mismatch, exact chunk
  boundaries, open-ended/clamped ranges, and reversed-range rejection. `ATProtoRASLClientTests`
  covers three exact chunk ranges, deliberately incorrect response metadata, final CID verification,
  and corrupted-range rejection through an injected HTTP seam. The focused macOS run is 11 tests,
  0 failures. GNUstep live HTTPS/SSRF evidence is recorded separately below. Both suites remain
  registered in `Tests/test_main.m`.
- Rollback: remove the additive verifier, range method, HTTP seam, and test updates; existing blob
  upload and download behavior is unchanged.

**Phase 7 — MASL — IMPLEMENTED (validated Core document model + CAR/bundle integration).**
`Core/ATProtoMASLDocument` validates DRISL metadata documents in single mode (`src`) and bundle
mode (`resources` with an exact `/` entry), preserves arbitrary namespaced metadata, validates
`$type`, `prev`, and bundle resource CIDs, and exposes the lower-case HTTP-header allow-list
without reflecting unknown or incorrectly-cased fields. `sourcemap`, `speculation-rules`, and Web
App Manifest icon/screenshot references must name exact bundle paths. Bundle CID lookup strips
query strings and fragments before exact pathname matching.

`Repository/CAR` now retains the complete decoded DRISL header metadata, exposes a validated MASL
document when the header conforms, writes validated MASL metadata without dropping application
fields, permits the CAR-specified empty `roots` array, and resolves bundle paths to body blocks
through the resource `src` CIDs. Existing root-only CAR APIs remain compatible; no blob-upload
CID assignment or existing blob path was changed.

- Owner boundary: `Garazyk/Sources/Core` owns MASL validation and path resolution; `Repository/CAR`
  owns header retention/encoding and bounded body lookup. No web runtime or new metadata transport
  was invented.
- Evidence (2026-08-08, merged to `main` as `4bfd6a8a`):
  `cmake --build build --target AllTests --parallel 4` passed on macOS.
  Focused `./build/tests/AllTests --filter 'ATProtoMASLDocumentTests' --gated=run` passed
  12/12; `./build/tests/AllTests --filter 'CARInteropTests' --gated=run` passed 24/24
  executions (the existing test registry lists `CARInteropTests` twice), including strict MASL
  metadata round-trip, empty roots, query/fragment pathname resolution, missing-resource
  rejection, and CID-verified body lookup. The first fresh-worktree configure attempt was
  blocked by the local `secp256k1` symlink not resolving in that invocation; an independent
  dependency configure passed and the repository configure then completed successfully.
  A full `./build/tests/AllTests --gated=run` was started but interrupted before
  its suite summary; it is incomplete and is not claimed as pass or fail.
  After the later WS08 manifest merge, a fresh configure and native `AllTests`
  build passed; focused MASL/CAR (12 + 24), RASL (4), and BDASL (7) suites
  passed on the combined `main` branch.
- Explicit remainder: no web runtime, RASL fetching, or arbitrary tile execution is wired here.
- Rollback: remove the additive MASL path/CAR metadata APIs and focused tests; existing root-only
  CAR serialization and blob upload behavior remain unchanged.

**Phase 8 — PFP — COMPLETE (identifier + PDQ Hamming + Meta PDQ producer +
Ozone subject column).** `Core/ATProtoPFP` implements the registered PDQ
(`0x01`, 32-byte inline hash) and TMK+PDQF (`0x02`, 36-byte strict base-DASL
CID) forms, plus PDQ Hamming-distance comparison with the ThreatExchange
recommended match threshold (≤ 31). It enforces the lowercase `p` prefix,
lowercase RFC4648 base32 with zero trailing padding bits, canonical unsigned
varints, exact algorithm-specific lengths, no trailing bytes, and strict CID
validation. It also exposes the exact `{"__pfp": "p…"}` JSON pseudo-type
boundary.
`Core/ATProtoPFPProducer` hashes float luma or packed RGB8 into DASL PDQ PFPs
using Meta ThreatExchange float-luma PDQ (Jarosz → 64×64 → 16×16 DCT → median
bits); image decode/resize remains caller-owned. TMK video production stays
out of scope.
Ozone stores a nullable `pfp TEXT` on `moderation_subjects` (fresh schema +
migration `PDSV19ModerationSubjectPFP`), with `PDSModerationService`
`setSubjectPFP:…` and `subjectsMatchingPDQ:maxDistance:limit:error:`.

- Owner boundary: `Garazyk/Sources/Core` for identifier, JSON boundary, PDQ
  distance, and the PDQ producer; Ozone moderation owns subject storage and
  Hamming match queries.
- Evidence: `ATProtoPFPTests` (identifier/comparator), `ATProtoPFPProducerTests`
  (deterministic RGB hash, near-duplicate Hamming ≤ recommended distance,
  invalid-buffer reject), `ModerationServiceTests/testSetAndMatchSubjectPFP`.
  Registered in `Tests/test_main.m`.
- Explicit remainder: none for Phase 8. Callers still supply decoded pixels;
  no automatic blob→PFP pipeline or TMK producer.
- Rollback: drop producer sources/`ATProtoCore` export, V19 migration + schema
  column, moderation APIs/tests; identifier APIs remain independently usable.

**Phase 9 — MUXL — COMPLETE (catalog + fragments + fMP4 + flat MP4 + elst +
playback sanity + transcoder bridge).**
`MediaCore/ATProtoMUXLBox` validates a canonical single-track video or audio
catalog, encodes and decodes the normative fixed `uuid-muxl` BMFF atom with
DRISL bytes, and composes `[uuid-muxl][moof][mdat]...` segments.
`MediaCore/ATProtoMUXLFragment` mints one-sample `[moof][mdat]` fragments with
normative `mfhd`/`tfhd`/`tfdt`/`trun`/`mdat` layout (1-based sequence,
`default-base-is-moof`, sync/non-sync sample flags, optional composition-time
offset) and validates that nested structure.
`Video/ATProtoMUXLFMP4` synthesizes both presentation headers from catalogs /
canonical segments:
- fMP4 init (`ftyp` brands `muxl`/`isom`/`iso2` + `moov` with empty sample
  tables, sorted `trak`, and `mvex`/`trex`), prepended without altering
  segment bytes;
- Flat MP4 (`ftyp` + populated `moov` without `mvex` + 64-bit outer `mdat`
  envelope). Sample tables include `stts`/`ctts`/`stsz`/`stsc`/`co64`/`stss`
  as specified; `co64` points at sample payloads inside the verbatim envelope.
`Video/ATProtoMUXLPlayback` validates fMP4 and Flat presentations for playback
sanity (init/header strip, segment split, fragment mint checks, Flat
round-trip).
`Video/ATProtoMUXLTranscoderBridge` extracts a catalog from CMAF `init.mp4`,
wraps `[moof][mdat]` HLS media segments with `uuid-muxl`, and writes a `muxl/`
sidecar package. Flat packaging is best-effort when fragments are MUXL-minted;
ffmpeg CMAF may omit Flat. Opt-in via `enableMUXLPresentation` on
`ATProtoVideoProcessor` / `ATProtoVideoWorker` (default OFF — HLS playlists and
CMAF segments stay unchanged).

- Owner boundary: `Garazyk/Sources/MediaCore` for catalog/box/fragment primitives;
  presentation-header synthesis, playback checks, and transcoder bridge live in
  `Garazyk/Sources/Video`.
- Evidence: `ATProtoMUXLBoxTests`, `ATProtoMUXLFragmentTests`,
  `ATProtoMUXLFMP4Tests`, `ATProtoMUXLPlaybackTests`, and
  `ATProtoMUXLTranscoderBridgeTests` (catalog round-trip from MUXL init; HLS
  variant directory packaging + write; fMP4/Flat playback validation). All
  registered in `Tests/test_main.m`. Verified 2026-08-12.
- Explicit remainder: none for Phase 9. Codec decode / player integration is out
  of scope; CA VOD does not require MUXL determinism (ADR 0036).
- Rollback: additive MediaCore/Video primitives, opt-in flag (default OFF), and
  test registration; existing HLS/transcoder output is untouched unless opted in.

**Phase 10 — S2PA — PARTIAL (COSE + leaf + JUMBF uuid + SHA-256 hard binding).**
`Security/S2PA/ATProtoS2PACOSE` implements an attached COSE_Sign1 envelope with the normative
ES256K algorithm (`-47`), canonical protected header `{1: -47}`, empty unprotected headers, the
COSE `Sig_structure`, and 64-byte low-S secp256k1 signatures through the existing primitive. It
rejects alternate CBOR encodings, unsupported algorithms, malformed fields, and signature/payload
mismatch. Verification consumes a supplied public key and intentionally does not consult X.509
trust anchors, matching S2PA's self-certifying trust model.
`Security/S2PA/ATProtoS2PALeafCertificate` mints and verifies the deterministic self-issued X.509
v3 leaf: DID in `commonName`, secp256k1 SPKI, normative extensions (basicConstraints cA=FALSE,
digitalSignature keyUsage, emailProtection EKU, matching SKI/AKI), and self-signature over TBS.
No trust-anchor chaining is performed.
`Security/S2PA/ATProtoS2PAJUMBF` builds a nested JUMBF Manifest Store (`jumb`/`jumd`/`bidb`) that
carries the COSE envelope and leaf DER, wraps it in a BMFF `uuid` box using the C2PA user-type
UUID (`d8fec3d6-…`), verifies by recursive `bidb` extraction + leaf + COSE checks, and prepends
the uuid box onto unchanged media bytes for MUXL-style presentation.
**Hard binding (2026-08-13):** `hardBindingSHA256ForMediaData:` hashes canonical media alone
(uuid carrier excluded by construction); `uuidBoxHardBindingMediaData:` /
`verifyUUIDBox:hardBoundToMediaData:` / `presentationHardBindingMediaData:` sign and check that
digest as the COSE payload — the MUXL-friendly “hash then prepend” path.
**`c2pa.hash.data` (2026-08-13):** `ATProtoS2PAHashDataAssertion` encodes/decodes the CBOR
assertion (`alg`/`hash`/`exclusions`/`name`), hashes with ordered non-overlapping exclusion
ranges, and `uuidBoxSigningHashDataAssertionForMediaData:` signs the assertion map as the COSE
payload. **`c2pa.hash.bmff.v3` (2026-08-13):** `ATProtoS2PAHashBMFFAssertion`
implements root-box v3 hashing (`offset_be64 || box` with xpath/data exclusions),
CBOR encode/decode, and a two-pass JUMBF sign/verify path that excludes the C2PA
uuid box. Merkle trees, nested xpath, and the full claim/assertion-store graph
remain open. **`c2pa.soft-binding` (2026-08-13):**
`ATProtoS2PASoftBindingAssertion` encodes/decodes alg + blocks (value + optional
timespan scope); does not run watermark/fingerprint algorithms.
**Claim + assertion store (2026-08-13):** `ATProtoS2PAClaim` builds
`c2pa.claim.v2` with `created_assertions` hashed URIs, a `c2pa.assertions`
JUMBF store (`cbor` content boxes), and JUMBF claim-bound sign/verify
(`uuidBoxSigningAssertions:` / `verifyUUIDBoxClaimBound:`). Ingredient claims,
gathered/redacted assertions, and Merkle remain open.
**`c2pa.ingredient.v3` (2026-08-13):** `ATProtoS2PAIngredientAssertion`
encodes/decodes relationship + optional title/format/instanceID/description/
digitalSourceType and activeManifest/claimSignature hashed URIs; rejects
activeManifest∩digitalSourceType. Proven in claim-bound multi-assertion stores.
`validationResults` and embedded-ingredient hash validation remain open.

- Owner boundary: `Garazyk/Sources/Security/S2PA` owns the COSE envelope, leaf certificate, and
  JUMBF/BMFF carrier; it consumes `Auth/Crypto/Secp256k1` read-only and does not alter repository
  signatures or auth JWTs. Opt-in transcoder auto-sign (default OFF) lives on
  `ATProtoMUXLTranscoderBridge` / `ATProtoVideoProcessor` / `ATProtoVideoWorker`.
- Evidence: `ATProtoS2PACOSETests`, `ATProtoS2PALeafCertificateTests`,
  `ATProtoS2PAHashDataAssertionTests` (empty exclusion, prefix exclusion ≡ media-only digest,
  JUMBF sign/verify), `ATProtoS2PAHashBMFFAssertionTests` (uuid exclusion + CBOR
  round-trip, tamper detect, two-pass JUMBF sign/verify),
  `ATProtoS2PASoftBindingAssertionTests`, `ATProtoS2PAClaimTests` (multi-assertion
  hashed URIs + claim-bound JUMBF sign/verify),
  `ATProtoS2PAIngredientAssertionTests`, and `ATProtoS2PAJUMBFTests`.
  All registered in `Tests/test_main.m`.
- Explicit remainder: ingredient `validationResults` / embedded-manifest verify,
  gathered/redacted assertions, soft-binding algorithm compute/verify, and Merkle
  `bmffHash` remain open.
  **MUXL producer wiring (2026-08-13):**
  `ATProtoMUXLPlayback` `presentationByHardBindingSegment:` /
  `verifyHardBoundPresentation:` prepends/verifies S2PA uuid over a canonical
  MUXL segment; `canonicalSegmentsFromPresentation:` recovers the unchanged
  segment (C2PA uuid skipped). Evidence: `ATProtoMUXLPlaybackTests`
  `testS2PAHardBindingPreservesCanonicalMUXL`.
  **Transcoder auto-sign (2026-08-13):**
  `ATProtoMUXLTranscoderBridge` `hardBoundPackage:withKeyPair:…` hard-binds each
  MUXL segment and `writePackage:` emits `segment_*.s2pa.m4s`. Opt-in via
  `enableS2PAAutoSign` + `s2paSigningKeyPair` on `ATProtoVideoProcessor` /
  `ATProtoVideoWorker` (default OFF; requires MUXL packaging). Evidence:
  `ATProtoMUXLTranscoderBridgeTests` `testHardBoundPackageWritesS2PASegments`.
- Rollback: remove the additive S2PA directory and test registration; existing signing and media
  paths are unchanged.

**Phase 11 — Web Tiles + Tiles Protocols + TP Data — PARTIAL (protocol, policy, unique-origin host, SW scripts, CAR load + path resolve + mothership mediation + getBlob load).**
`AdminUIServer/UITileDataProtocol` serves the reserved `/.well-known/web-tiles/data.js` module with
`addDataHandler`, `removeDataHandler`, `listen`, and `sendData`, using the normative
`tiles-protocol-up-data-ready`, `tiles-protocol-up-data-payload`, and
`tiles-protocol-down-data-payload` structured-clone message actions. `UITileExecutionPolicy` exposes
the normative restrictive CSP and isolation/security headers: no explicit `connect-src` or external
network origin, `object-src 'none'`, `base-uri 'none'`, and the required sandbox/COOP/CORP/referrer/
permission/DNS-prefetch headers. The policy is not itself a network boundary on a normal origin;
unique-origin hosting is still required before arbitrary tile execution.
`AdminUIServer/UITileLoadingHost` implements the loading-server redirect pattern: when
`GARAZYK_ADMIN_UI_TILES_BASE_HOST` / `PDS_ADMIN_UI_TILES_BASE_HOST` is set, `load.<base>` for
`/.well-known/web-tiles/` returns 303 to a random 20-letter subdomain of `<base>`; unique-origin
hosts serve a shuttle HTML shell with execution-policy headers and `service-worker-allowed: /`,
plus `shuttle.js` / `worker.js` that register a passthrough service worker for
`/.well-known/web-tiles/`. Without a base host the document and script routes remain 404.
`Core/ATProtoWebTile` validates MASL bundle tiles (`name`, `/` root); `Repository/ATProtoWebTile+CAR`
loads a CAR/`.tile` archive, retains the reader, and resolves arbitrary declared paths to
`{status, headers, body}` (404 for undeclared / missing blocks; QS/fragment stripped). Host-side
origin helpers (`GZAdminUITileIsTrustedEmbedOrigin`,
`GZAdminUITileDataProtocolJavaScriptWithTrustedOrigin`) gate postMessage peers when configured.
**Mothership + getBlob (2026-08-13):** `ATProtoWebTileMothership` mediates worker
`resolve-path` requests (echoes `requestId`, returns `response` or `error`) and loads a tile
CAR via injected HTTP `com.atproto.sync.getBlob`.

- Owner boundary: `Garazyk/Sources/AdminUIServer` owns the host-selected protocol module, policy
  helpers, loading-host redirect, and SW script routes. `Core` / `Repository` own tile validation,
  CAR loading, and mothership/getBlob mediation. Existing authenticated Admin UI CSP and routes
  are unchanged.
- Evidence: `UITileExecutionPolicyTests` (incl. trusted-origin JS), `UITileLoadingHostTests` (host
  classification, redirect, headers, shuttle/worker, trusted origin), `UIServerRuntimeTests`
  (`data.js`, load-host 303, unique-origin shuttle + script routes), `ATProtoWebTileTests` (MASL,
  CAR root, multi-path resolve + 404), `ATProtoWebTileMothershipTests` (resolve-path mediation +
  getBlob stub load).
- Explicit remainder: Deno `@dasl/tiles` protocol package and live Admin UI embedding of an
  arbitrary tile remain open. This slice does not claim a full browser tile host product.
- Rollback: remove the additive policy/protocol/loading-host/WebTile/Mothership helpers, reserved
  routes, and test registration; existing Admin UI routes and CSP remain unchanged.

### GNUstep package + DASL harness (2026-08-12)

`scripts/test/gnustep-package-dasl-evidence.sh` builds (or reuses) the
`toolchain` target of `docker/Dockerfile.gnustep`, runs
`scripts/test/package-consumer-smoke.sh` inside the image, then focused
`DASLConformanceTests` / `ATProtoDagCBOREdgeCaseTests` / `ATProtoS2PACOSETests` /
`ATProtoS2PALeafCertificateTests` / `ATProtoS2PAJUMBFTests` /
`ATProtoWebTileTests`.

**Verified 2026-08-12** on `garazyk-gnustep-toolchain:local` (arm64 OrbStack):
- `package-consumer-smoke: OK` (relocated prefix, core-only, full-graph,
  private-header-denied) after `GarazykConfig.cmake` reattaches GNUstep
  Foundation/`objc`/`dispatch` include+link requirements for Linux consumers.
- Focused DASL/S2PA/WebTile filters: 16+26+9+4+3+3 tests, **0 failures**.
  Portability fixes landed with this evidence: `CFAbsoluteTime` →
  `NSDate` in Mikrus/Beskid metrics, GNUstep-safe Web Tile grapheme counting,
  and `QOS_CLASS_DEFAULT` → `DISPATCH_QUEUE_PRIORITY_DEFAULT` in Relay admin
  UI tests.

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
