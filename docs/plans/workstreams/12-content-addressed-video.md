---
title: Content-Addressed Video
status: active
last_verified: 2026-08-12
---

# Content-Addressed Video

Turn `jelcz`'s adaptive-bitrate output into content-addressed, independently
verifiable, redistributable media, addressed by a single MASL manifest blob per
video. Decision and rationale: [ADR 0036](../../adr/0036-content-addressed-video-distribution.md).

This workstream *consumes* the DASL primitives that
[workstream 10](10-dasl-conformance.md) built (MASL, RASL, BDASL, and later
MUXL). It does not duplicate them. Where the two touch, workstream 10 owns the
spec conformance and this workstream owns the product integration.

**Scope boundary with workstream 10 Phase 9 (MUXL).** ADR 0036 decides that
verifiable distribution does not depend on reproducible addressing. Nothing in
Phases 1–8 below requires a deterministic muxer. Phase 1's fMP4 switch is what
keeps MUXL viable later; it is not an implementation of it.

## Status (2026-08-12)

Phase 0 only. Phases 1–8 are specified below with evidence, owner boundary,
gate, and rollback; none are implemented. Phases 9–10 are deferred and are
explicitly *not* ready for implementation — they need their own evidence and
gates recorded here first, per `docs/plans/README.md`.

## Current-state evidence (verified 2026-08-12)

The HLS ladder is generated and then dropped on the floor. No route serves it,
and nothing content-addresses it.

| Site | Observed state |
| --- | --- |
| `Garazyk/Sources/Video/VideoHLSGenerator.m:184-191` | `-f hls -hls_time 6 -hls_list_size 0`, segments `segment_%03d.ts` (MPEG-TS) |
| `Garazyk/Sources/Video/VideoHLSGenerator.m:164-166` | `libx264 -preset fast`, default threading — not reproducible |
| `Garazyk/Sources/Video/VideoWorker.m:371-389` | `VideoHLSResult` logged, then discarded; failure is non-fatal |
| `Garazyk/Sources/Video/ATProtoVideoProcessor.m:226-253` | retains `hlsMasterPlaylist` / `hlsVariants` / `hlsBaseUrl` in a metadata dict |
| `Garazyk/Sources/AppView/Services/VideoUriBuilder.m:10-11` | `/watch/{did}/{cid}/playlist.m3u8` exists only as a pattern string |
| `Garazyk/Sources/MediaCore/ATProtoMediaServiceRuntime.m:106-146` | routes are `/xrpc`, `/_health`, `/admin/api/media/*` — no `/watch` |
| `Garazyk/Sources/Video/JelczDatabase.m:69-90` | `video_jobs` has `thumbnail_blob_cid`, `processed_blob_cid`; no manifest column |
| `Garazyk/Sources/Admin/Diagnostics/BlobAudit/PDSBlobAuditUtils.m:26` | blob reference extraction matches `$type == "blob"` in record JSON only |
| `Garazyk/Resources/lexicons/place/stream/` | Streamplace lexicons vendored; zero references from `Garazyk/Sources/` |

## Phase 0 — DONE: governance

This document and [ADR 0036](../../adr/0036-content-addressed-video-distribution.md).
Registered in the [mega plan](../mega-plan.md) Phase 4 and the
[workstreams table](../README.md#active-structure).

## Phase 1 — fMP4 segments and segment-numbering fix

Smallest independently shippable slice; carries a real defect fix and is
worth landing on its own merit even if later phases slip.

- **Evidence.** `VideoHLSGenerator.m:190` emits `segment_%03d.ts`. `%03d` wraps
  at 1,000 segments — 100 minutes at the configured `-hls_time 6` — after which
  ffmpeg silently overwrites earlier segments. MPEG-TS also forecloses MUXL and
  clean range decomposition (ADR 0036).
- **Change.** Add `-hls_segment_type fmp4` and `-hls_fmp4_init_filename init.mp4`;
  segments become `segment_%05d.m4s`. Extend `VideoHLSResult` to carry the
  produced file list — it currently exposes only `{resolution, bandwidth,
  playlistPath}` per variant, which is insufficient for Phase 3.
- **Owner boundary.** `Garazyk/Sources/Video/VideoHLSGenerator.{h,m}` only. No
  caller changes; both existing call sites treat HLS failure as non-fatal.
- **Gate.** A new `VideoHLSGeneratorTests` suite asserting the produced tree
  shape (init segment present, `.m4s` extension, ≥10,000-segment numbering
  width) against a short fixture. Requires `cmake -S . -B build` reconfigure
  **and** registration in `Garazyk/Tests/test_main.m` — the registration audit
  fails the run on either omission. Gate is skipped when ffmpeg is absent, tagged
  consistently with the existing transcoder suites.
- **Rollback.** Revert the argument list. No persisted state, no schema, no
  wire format depends on this phase in isolation.

## Phase 2 — Segment store

- **Evidence.** ADR 0036 decides segments are not atproto blobs. There is no
  store for them today; the ladder is left on local disk under
  `hlsDirectoryForDID:cid:` with no addressing and no lifecycle.
- **Change.** A content-addressed segment store keyed by DASL CID (SHA-256, raw
  `0x55`), with put/get/exists and a byte-range read. Backed by the same provider
  abstraction pattern as `PDSBlobProvider` so disk and object-storage backends
  are interchangeable.
- **Owner boundary.** New files under `Garazyk/Sources/MediaCore/`. Must not
  import `Database/` or PDS blob types. Run
  `./scripts/dev/check_module_boundaries.sh .` — `ATProtoCore` (for `ATProtoCID`
  and `CID+DASL`) is an allowed dependency; confirm before adding any edge
  toward Network or Storage.
- **Gate.** Unit suite: round-trip, CID mismatch rejection on put, range reads
  at segment boundaries and past EOF. Registered per the Phase 1 note.
- **Rollback.** Store is additive and unreferenced until Phase 3. Deleting it
  restores current behavior.

## Phase 3 — Manifest builder

- **Evidence.** `ATProtoMASLDocument` validates and encodes bundle documents
  today (`documentWithObject:error:`, `DRISLDataWithError`) and is used by no
  production call site — workstream 10 Phase 7 landed it as a bounded slice.
  This is its first consumer.
- **Change.** After HLS generation, walk the output tree, put each file into the
  segment store, and build the MASL bundle described in ADR 0036 (root `/` maps
  to the master playlist; `content-type` on playlists and init segments only).
  Encode with the DRISL profile, upload the encoded bytes as the single atproto
  blob for the video.
- **Owner boundary.** Insertion point is `ATProtoVideoProcessor.m:243-249`, which
  already accumulates HLS metadata, in preference to `VideoWorker.m:383`, which
  discards its result. Both paths must end up producing a manifest; do not leave
  the legacy worker silently manifest-less.
- **Gate.** Round-trip test: build a manifest from a fixture ladder, re-decode
  through `ATProtoMASLDocument`, assert every `resourceCIDForPath:` resolves and
  that each resolved CID equals SHA-256 of the stored segment. Assert the encoded
  manifest is under 1 MiB for a 1-hour three-rendition fixture (ADR 0036
  estimates ~123 KB; a 1 MiB ceiling catches a per-entry regression without
  pinning the exact encoding).
- **Rollback.** Manifest production is gated behind a configuration flag
  defaulting off until Phase 5 can serve it. Off restores current behavior
  exactly.

## Phase 4 — Job store and status plumbing

- **Evidence.** `video_jobs` (`JelczDatabase.m:69-90`) has no column for a
  manifest, and `app.bsky.video.getJobStatus` has no field to return one.
- **Change.** Add `manifest_blob_cid TEXT`, following the existing
  `thumbnail_blob_cid` / `processed_blob_cid` pattern, plus a migration. Return
  it from job status so a client can construct the record.
- **Owner boundary.** `Garazyk/Sources/Video/JelczDatabase.m`,
  `Garazyk/Sources/Video/VideoXrpcPack.m`. Migration follows
  `PDSMigrationManager` conventions; see `.agents/skills/garazyk-database`.
- **Gate.** Migration test on a populated pre-migration database. Existing
  `getJobStatus` tests must pass unchanged — the new field is additive and
  optional.
- **Rollback.** Column is nullable and ignored by readers that do not know it;
  a down-migration is not required for correctness.

## Phase 5 — Serving route

- **Evidence.** No `/watch` route exists (`ATProtoMediaServiceRuntime.m:106-146`),
  so `VideoUriBuilder`'s URL pattern currently resolves to nothing.
- **Change.** Register a route that resolves manifest CID plus request path to a
  segment CID via `resourceCIDForPath:`, streams from the segment store, and
  applies MASL's `httpHeadersForPath:` allow-list output as response headers.
  Range support is required; `BlobStorage.h:139` is the existing precedent for
  the response shape.
- **Owner boundary.** `Garazyk/Sources/MediaCore/`. Path traversal is structurally
  prevented by resolving through the manifest's exact-path map rather than the
  filesystem — no request path ever reaches a file API. That property is the
  point of the design and must be asserted, not assumed.
- **Gate.** Route tests: exact-path hit, unknown path 404, `..` and encoded
  traversal attempts 404 (not 403, not a filesystem error), range request
  returns 206 with exact requested length, unsatisfiable range 416. Tagged
  `socket`/`integration` consistently with existing route-pack suites, so
  `--gated=run` covers them.
- **Rollback.** Route registration is behind the Phase 3 configuration flag.

## Phase 6 — Segment reclamation

- **Evidence.** ADR 0036 records that moving segments out of the blob store
  relocates the recursive-pinning problem to `jelcz` rather than removing it.
  Without this phase the segment store grows without bound.
- **Change.** Refcount segments against live manifests, incremented at manifest
  publish and decremented at retract/supersede. A sweep reclaims zero-refcount
  segments after a grace period, mirroring ADR 0013's shape (configurable, with
  a clamped minimum) so operators meet one model rather than two.
- **Owner boundary.** `Garazyk/Sources/MediaCore/`. Explicitly **not** the PDS
  blob sweep — do not extend `PDSBlobReferenceScanOperation` to cover segments;
  that would recreate the coupling ADR 0036 removes.
- **Gate.** Lifecycle test: publish two manifests sharing a segment, retract one,
  assert the shared segment survives and unshared segments are reclaimed only
  after the grace period.
- **Rollback.** Sweep disabled by configuration leaves segments in place; the
  failure mode is disk growth, not data loss.

## Phase 7 — Record and lexicon shape

- **Evidence.** `app.bsky.embed.video` carries a single `video: blob` intended
  as a playable MP4; handing it a DRISL manifest would break Bluesky clients.
  `place/stream/*` is vendored but unused, and its one-record-per-segment model
  does not fit VOD (600+ records per hour per rendition) — see ADR 0036's
  unresolved note.
- **Change.** Define a Garazyk-owned lexicon carrying the manifest blob plus
  duration, renditions, and aspect ratio. NSIDs come from
  `Network/Generated/GZXrpcNSID.h` via `scripts/generate_nsid_constants.ts`;
  raw literals are rejected by the `narzedzia` lint (ADR 0003).
- **Owner boundary.** `Garazyk/Resources/lexicons/`, regenerated constants,
  AppView view builders. Decide explicitly whether `app.bsky.embed.video`
  remains populated with a compatibility rendition — this is a product call,
  recorded here when made, not assumed.
- **Gate.** `deno run -A scripts/generate_nsid_constants.ts --check` and
  `deno run --allow-read packages/narzedzia/nsid_registration_literal_check.ts .`
  both pass; lexicon validation suite covers the new record.
- **Rollback.** Additive lexicon; no existing record shape changes.

## Phase 8 — RASL retrieval hints

- **Evidence.** `ATProtoRASLURL` and `ATProtoRASLClient` exist and are exercised
  only by workstream 10's conformance slice; nothing emits hints.
- **Change.** Allow a manifest's segments to be resolved from mirror hosts when
  absent locally, via the existing parallel verified-fetch client. Mirrors are
  ordinary HTTPS origins; the manifest's CIDs make them untrusted-safe.
- **Owner boundary.** `ATProtoRASLClient` lives in `Network/`, and MediaCore
  reaching it may add a `PUBLIC` link edge not in the allow-list in
  `scripts/dev/check_module_boundaries.sh`. **Resolve this before implementing**
  — either inject the fetcher through the existing `ATProtoRASLHTTPFetching`
  protocol from the composition root, or add the edge deliberately with ADR
  coverage. Do not discover it at link time.
- **Gate.** Fetch-fallback test against a stub fetcher: local hit does not fetch,
  local miss fetches and verifies, CID mismatch from a hostile mirror is rejected
  and does not poison the store.
- **Rollback.** Hint emission and resolution are independently configurable; off
  means local-only, which is Phase 5 behavior.

## Deferred — needs evidence before implementation

Neither item below is ready. Per `docs/plans/README.md`, each needs source
evidence, an owner boundary, a verification gate, and rollback notes recorded
here before any implementation starts.

- **Phase 9 — BDASL range verification.** `ATProtoBDASLVerifier` provides
  streaming BLAKE3 verification, but its header states it does not define a wire
  format for the chunk-digest sidecar. Trustless partial verification against an
  untrusted mirror needs one — either a Garazyk-defined sidecar or adoption of
  bao's outboard encoding. Interacts with ADR 0036's SHA-256 segment addressing:
  BLAKE3 may appear only in segment `src` values, never in the manifest blob's
  own CID.
- **Phase 10 — Peer transports.** Evaluated only after Phase 8 is in production
  and origin bandwidth is measured. The candidate seam is the Phase 8 resolver.
  iroh is the leading candidate (BLAKE3 range verification, QUIC, dial-by-key,
  NAT traversal for residential seeders) and would run as a sidecar process, not
  as a link-time dependency of the Objective-C tree. IPFS is rejected in ADR 0036
  with reasons; do not re-open without new evidence.

## Verification gates for the workstream

Beyond each phase's own gate:

- `cmake --build build --target AllTests --parallel 4` then
  `./build/tests/AllTests --gated=run` — bound `--parallel` to 4.
- `./scripts/dev/check_module_boundaries.sh .` — no new violations against the
  recorded baseline.
- `deno run -A --config=deno.json scripts/docs/repo_docs.ts validate --internal-strict`.
- Objective-C doc coverage stays ≥90% (`scripts/docs/doc-coverage.ts`).
