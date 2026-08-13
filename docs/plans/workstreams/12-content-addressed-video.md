---
title: Content-Addressed Video
status: active
last_verified: 2026-08-12
---

# Content-Addressed Video

Turn `jelcz`'s adaptive-bitrate output into content-addressed, independently
verifiable, redistributable media. Live uses MASL per-segment objects; VOD uses
flat range-addressable rendition objects named by a MASL manifest blob.
Decision and rationale: [ADR 0036](../../adr/0036-content-addressed-video-distribution.md).

This workstream *consumes* the DASL primitives that
[workstream 10](10-dasl-conformance.md) built (MASL, RASL, BDASL, and later
MUXL). It does not duplicate them. Where the two touch, workstream 10 owns the
spec conformance and this workstream owns the product integration.

**Scope boundary with workstream 10 Phase 9 (MUXL).** ADR 0036 decides that
verifiable distribution does not depend on reproducible addressing. Nothing in
Phases 1–8 below requires a deterministic muxer. Phase 1's fMP4 switch is what
keeps MUXL viable later; it is not an implementation of it.

## Status (2026-08-12)

Phases 1–10 **complete**. Phase 11 (peer transports) is **closed-not-pursued**
until CA VOD is in production and origin bandwidth is measured (2026-08-12
decision); short-form peer swarming remains structurally out of scope.

Short-form versus long-form segment policy is now split by
[ADR 0037](../../adr/0037-video-segment-profile-short-vs-long.md). This
workstream owns implementation of both profiles, not a single hard-coded value.

## Current-state evidence (verified 2026-08-12)

The HLS ladder is generated and then dropped on the floor. No route serves it,
and nothing content-addresses it.

| Site | Observed state |
| --- | --- |
| `Garazyk/Sources/Video/VideoHLSGenerator.m` | fMP4: `-hls_segment_type fmp4`, `-hls_fmp4_init_filename init.mp4`, `segment_%05d.m4s`; `-hls_time` from `segmentProfile` (2s short / 6s long, ADR 0037) |
| `Garazyk/Sources/Video/VideoHLSGenerator.h` | `GZVideoHLSResult.producedFiles` maps bundle-root paths to absolute paths |
| `Garazyk/Tests/Video/VideoHLSGeneratorTests.m` | Integration suite (ffmpeg-gated) asserts fMP4 tree shape, init segment, numbering width, `producedFiles` completeness |
| `Garazyk/Sources/Video/VideoWorker.m:371-389` | `VideoHLSResult` logged, then discarded; failure is non-fatal |
| `Garazyk/Sources/Video/ATProtoVideoProcessor.m:226-253` | retains `hlsMasterPlaylist` / `hlsVariants` / `hlsBaseUrl` in a metadata dict |
| `Garazyk/Sources/AppView/Services/VideoUriBuilder.m:10-11` | `/watch/{did}/{cid}/playlist.m3u8` exists only as a pattern string |
| `Garazyk/Sources/MediaCore/ATProtoMediaServiceRuntime.m:106-146` | routes are `/xrpc`, `/_health`, `/admin/api/media/*` — no `/watch` |
| `Garazyk/Sources/Video/JelczDatabase.m:69-90` | `video_jobs` has `thumbnail_blob_cid`, `processed_blob_cid`; no manifest column |
| `Garazyk/Sources/Admin/Diagnostics/BlobAudit/PDSBlobAuditUtils.m:26` | blob reference extraction matches `$type == "blob"` in record JSON only |
| `Garazyk/Resources/lexicons/place/stream/` | Streamplace live + VOD lexicons vendored; zero production refs from `Garazyk/Sources/` |
| `Garazyk/Resources/lexicons/tools/garazyk/video/` | Garazyk CA VOD records (`tools.garazyk.video*`) — WS12 Phase 7 |

## Phase 0 — DONE: governance

This document and [ADR 0036](../../adr/0036-content-addressed-video-distribution.md).
Registered in the [mega plan](../mega-plan.md) Phase 4 and the
[workstreams table](../README.md#active-structure).

## Phase 1 — DONE: fMP4 segments and segment-numbering fix

Verified 2026-08-12. Gate: `VideoHLSGeneratorTests` + `ATProtoVideoHLSGeneratorTests`
(registered in `test_main.m`). See current-state evidence table above.

## Phase 1 specification (historical)

Smallest independently shippable slice; carries a real defect fix and is
worth landing on its own merit even if later phases slip.

- **Evidence.** `VideoHLSGenerator.m:190` emits `segment_%03d.ts`. `%03d` wraps
  at 1,000 segments — 100 minutes at the configured `-hls_time 6` — after which
  ffmpeg silently overwrites earlier segments. MPEG-TS also forecloses MUXL and
  clean range decomposition (ADR 0036).
- **Change.** Add `-hls_segment_type fmp4` and `-hls_fmp4_init_filename init.mp4`;
  segments become `segment_%05d.m4s`. Segment duration is profile-driven per
  ADR 0037 (short-form and long-form), not a single fixed product setting.
  Extend `VideoHLSResult` to carry the
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

## Phase 2 — DONE: content-addressed object store (2026-08-12)

- **Shipped.** `MediaCore/ATProtoCAObjectStore` — disk store under
  `objects/` + `proofs/`, serial-queue IO, digest profiles SHA-256 (live) and
  BLAKE3 (VOD). API: `put` / `stat` / `get` / `get_range` / `delete`,
  `generateProof` / `regenerateProof` / `produceProof`, and
  `+verifyProof:fullObjectData:error:`.
- **Outboard.** Versioned `GZBO` file: 1 KiB BLAKE3 chunk digests (BDASL-sized
  leaves). Regenerating the outboard does not change the media CID. Full
  wire-compatible Bao parent encoding remains Phase 9; this slice already
  verifies range leaves + BLAKE3 content root (and optional full BDASL
  sidecar path when all digests are present).
- **Evidence.** `ATProtoCAObjectStoreTests` (5/0): SHA-256+BLAKE3 round-trip,
  CID mismatch rejection, range boundaries/EOF, proof produce/verify/
  regenerate, delete. Registered in `Tests/test_main.m`. Module-boundary gate
  clean (MediaCore → Core only).
- **Rollback.** Additive MediaCore files + test registration; nothing consumes
  the store until Phase 3.

## Phase 3 — DONE: manifest builder (2026-08-12)

- **Shipped.** `MediaCore/ATProtoVODManifestBuilder` consumes HLS
  `producedFiles` (or in-memory fixtures), concatenates each variant's
  `init.mp4` + `segment_*.m4s` into one flat `video.fmp4`, puts media under
  BLAKE3 (with GZBO outboard) and playlists under SHA-256, rewrites variant
  playlists with `EXT-X-MAP` / `EXT-X-BYTERANGE`, and encodes a MASL bundle
  (`ing.dasl.masl`) via DRISL. Fragment tables live in `garazyk.vod.v1`
  application metadata on each media resource.
- **Wiring (flag default off).**
  `ATProtoMediaServiceConfiguration.enableContentAddressedManifest` /
  `caObjectStoreDirectory` (`JELCZ_CA_MANIFEST`, `JELCZ_CA_STORE_DIR`);
  `ATProtoVideoProcessor` and `ATProtoVideoWorker` call the builder after HLS
  when enabled; `jelcz` opens the CA store and attaches it. Off restores prior
  behavior exactly.
- **Evidence.** `ATProtoVODManifestBuilderTests` (3/0): flat VOD round-trip
  (MASL decode + every resource CID resolves; BLAKE3 media + proof;
  BYTERANGE playlist), 1-hour × 3-rendition fixture DRISL &lt; 1 MiB (7
  resources), missing-init failure. Registered in `Tests/test_main.m`.
- **Rollback.** Leave the flag off; builder is unused.

## Phase 4 — DONE: job store and status plumbing (2026-08-12)

- **Shipped.** `manifest_blob_cid TEXT` on `video_jobs` (Jelcz CREATE +
  `ALTER TABLE` ensure; PDS `Schema.m` + `ensureVideoJobsManifestColumn`).
  `VideoJobStore` / `updateVideoJobResults:...manifestBlobCid:` persists it.
  `getJobStatus` returns optional `manifestBlob` (lexicon
  `app.bsky.video.defs#jobStatus`). Worker/processor put DRISL under SHA-256
  in the CA store and record that CID when CA manifests are enabled.
- **Evidence.** `JelczDatabaseTests` migration on a populated pre-Phase-4 DB
  (row preserved; column writable); `testUpdateResultsWithManifestBlobCid`;
  `ATProtoVideoXrpcPackTests` optional `manifestBlob` + existing completed
  response unchanged when column absent. PDS video-job suites green.
- **Rollback.** Nullable column; omit `manifestBlob` when null.

## Phase 5 — DONE: serving route + moderation floor (2026-08-12)

- **Shipped.** `ATProtoCAWatchService` resolves
  `/watch/{did}/{manifestCid}/…` through MASL `resourceCIDForPath:` only
  (no filesystem join), streams from `ATProtoCAObjectStore`, applies
  `httpHeadersForPath:`, and supports HTTP Range (206 / 416). 
  `ATProtoCAMediaDenylist` (+ in-memory impl) is consulted for manifest and
  resource CIDs before any media bytes are written (`403 ContentDenied`).
- **Wiring.** Registered by `ATProtoMediaServiceRuntime` when
  `enableContentAddressedManifest` and `caObjectStore` are set. Jelcz skips
  legacy filesystem HLS `/watch` in that mode.
- **Evidence.** `ATProtoCAWatchServiceTests` (9/0, gated `socket`): path
  mapping + `%2e%2e`/`..` → 404; exact hit + MASL content-type; unknown 404;
  range 206 exact length; unsatisfiable 416; denied manifest/resource → 403
  JSON without media bytes. Registered in `Tests/test_main.m`.
- **Rollback.** Leave the CA flag off; filesystem HLS routes remain.

## Phase 6 — DONE: segment/object reclamation (2026-08-12)

- **Shipped.** `ATProtoCAObjectLifecycle` (`lifecycle.db` under the CA store
  root): publish increments refcounts for a manifest + its referenced object
  CIDs; retract decrements and stamps `zero_since`; sweep deletes zero-refcount
  objects after a grace period (default 6h, clamped ≥1h, ADR 0013 shape).
  Sweep defaults **off** (`caObjectSweepEnabled` / `JELCZ_CA_SWEEP`). Runtime
  opens the lifecycle when a CA store is attached; VideoProcessor/Worker
  publish on successful manifest put when a lifecycle is injected.
- **Evidence.** `ATProtoCAObjectLifecycleTests` (3/0): shared object survives
  retracting one of two manifests; unshared objects reclaim only after grace;
  sweep-disabled deletes nothing; grace clamp. Registered in `Tests/test_main.m`.
- **Rollback.** Leave sweep off; orphans remain on disk.

## Phase 7 — DONE: Record and lexicon shape (2026-08-12)

- **Shipped.** Garazyk-owned CA VOD records under `tools.garazyk.video*`:
  - `tools.garazyk.video` — author-owned identity: DRISL/MASL `manifest` blob,
    `durationMs`, optional `aspectRatio` / `renditions` / `thumb` / `title`,
    optional `compatMp4` progressive MP4.
  - `tools.garazyk.video.distributionPolicy` — author-mutable consent:
    `subject` strongRef, optional `deleteAfter`, optional `allowedBroadcasters`.
  - `tools.garazyk.video.origin` — mirror-authored attestation: `subject`,
    `server` DID, `watchBaseUrl`, `manifestCid`, heartbeat `lastSeenAt`.
  - `tools.garazyk.video.defs` — shared `aspectRatio` / `rendition`; `#view`
    defs on each record for later AppView hydration (indexer in Phase 8+).
- **Product call (recorded).** Keep `app.bsky.embed.video` as an optional
  Bluesky-compat progressive MP4 via `compatMp4` on `tools.garazyk.video`.
  Do **not** put a DRISL manifest in `app.bsky.embed.video` — that would break
  Bluesky clients that expect a playable MP4.
- **Prerequisite (satisfied).** Streamplace VOD lexicons
  `place.stream.video`, `place.stream.media.track`, and
  `place.stream.media.origin` are already vendored under
  `Garazyk/Resources/lexicons/place/stream/`; ADR 0036's old "not vendored"
  note is corrected.
- **Evidence.** `GarazykVideoLexiconTests` (7 cases): schemas registered
  (including Streamplace VOD prerequisite), valid video/policy/origin pass,
  missing required fields and invalid `watchBaseUrl` scheme fail. Registered
  in `Tests/test_main.m`. NSID `--check` and narzedzia registration literal
  check remain green (records are not XRPC endpoints; no new constants).
- **Rollback.** Additive lexicon + tests; no existing record shape changes.

## Phase 8 — DONE: Feed prefetch contract (2026-08-12)

- **Shipped.** Short-form prefetch contract (ADR 0037):
  - Lexicon `xyz.garazyk.video.getPrefetchBootstrap` +
    `tools.garazyk.video.defs#playbackBootstrap` / `#byteRange`.
  - `MediaCore/ATProtoVideoPrefetchBootstrap` builds the single-response
    shape (`items`, `windowSize`, `wasteCeilingBytes`) from hydrated inputs.
  - Defaults: window **N=2**, first-segment budget **512 KiB**, waste ceiling
    **1 MiB** (`ATProtoVideoPrefetchWasteCeilingBytes`) when the whole window
    is swiped past unplayed.
  - Discovery RTT model: naive = 3×playCount; bootstrap = 1 for the window.
- **Out of this slice.** Live XRPC registration that resolves at-uris from an
  AppView index — needs video/origin indexing. The lexicon NSID constant is
  generated; callers/AppView wire the builder when hydration exists. Flag the
  query additive/off until then.
- **Evidence.** `ATProtoVideoPrefetchBootstrapTests` (6/0): next-N single
  response, waste ceiling when all/partial swipe-past, discovery RTT reduction,
  lexicon registration. Registered in `Tests/test_main.m`. NSID `--check` green
  (428 endpoints).
- **Rollback.** Additive lexicon + MediaCore builder; no feed path changes.

## Phase 9 — DONE: Bao/outboard proofs for flat-VOD range verification (2026-08-12)

- **Shipped.** Wire-compatible Bao (Rust `bao` 0.13 outboard/slice):
  - `Core/ATProtoBao` + `ATProtoBaoEncode.c` — outboard encode, slice extract,
    slice verify against BLAKE3 root without the full object.
  - `ATProtoCAObjectStore` writes Bao outboards (still `.bao`); `produceProof`
    returns `baoSlice` + `rootHash` + `rangeData`; `verifyProof` accepts with
    `fullObjectData:nil` on the Bao path. Legacy GZBO outboards remain readable.
- **Evidence.** `ATProtoBaoTests` (4/0): golden outboards for lengths 0…2049
  matching `bao` crate vectors; tampered/truncated/wrong-offset rejected.
  `ATProtoCAObjectStoreTests` proof case verifies without full object, rejects
  tampered slices, regenerate keeps media CID. Local trusted `get_range` path
  unchanged (no startup regression vs local origin).
- **Rollback.** Fall back to trusted/local `get_range`; disable untrusted
  mirror incremental path.

## Phase 10 — DONE: Provider hint resolution and mirror retrieval (2026-08-12)

- **Boundary decision.** Do **not** add a MediaCore → Network `PUBLIC` link.
  Inject fetch through MediaCore-owned `@protocol ATProtoCAMirrorFetching`;
  the composition root adapts HTTPS. Recorded here so the allow-list is not
  discovered at link time.
- **Shipped.** `ATProtoCAMirrorResolver` — local-first resolution; optional
  mirror fetch (default **off** = Phase 5 local-only). Full-object path
  verifies BLAKE3 against the CID before `put`. Range miss may use optional
  Bao slice fetch (Phase 9) without storing the full object; bad slices do
  not poison the store.
- **Composition wiring (2026-08-12).** `ATProtoCAMirrorHTTPSFetcher` GETs
  `/.well-known/rasl/{cid}` via an injected sync HTTP client (jelcz adapts
  `ATProtoSafeHTTPClient`). `ATProtoCARASLWellKnown` serves the same path
  from the local CA store with SHA-256 **and** BLAKE3 re-verify. Flags:
  `JELCZ_CA_MIRROR_FETCH` / `JELCZ_CA_MIRROR_PROVIDERS`. Watch miss paths
  use the resolver when enabled.
- **Evidence.** `ATProtoCAMirrorResolverTests` (6/0): local hit skips fetch;
  miss fetches/verifies/stores; hostile CID mismatch rejected + store empty;
  mirrors disabled by default; Bao range path + bad-slice non-poison;
  SHA-256 playlist CID mirror put. `ATProtoCAMirrorHTTPSFetcherTests` (4/0);
  `ATProtoCARASLWellKnownTests` (3/0); watch mirror miss (10/0).
  `check_module_boundaries.sh` clean.
- **Rollback.** Leave `mirrorFetchEnabled` / `JELCZ_CA_MIRROR_FETCH` off.

## Deferred — closed pending production evidence

The item below is **not** an open implementation backlog. Per `docs/plans/README.md`,
it stays deferred with a recorded decision rather than drifting as "partial".

- **Phase 11 — Peer transports.** **Decision (2026-08-12): closed-not-pursued
  until CA VOD is in production and origin bandwidth is measured.** Evaluated
  only after Phase 10 is in production. The candidate seam is the Phase 10
  resolver. iroh is the leading candidate (BLAKE3 range verification, QUIC,
  dial-by-key, NAT traversal for residential seeders) and would run as a
  sidecar process, not as a link-time dependency of the Objective-C tree. IPFS
  is rejected in ADR 0036 with reasons; do not re-open without new evidence.

  *Blocked on:* production CA VOD deployment + origin bandwidth measurements
  (named input for reopening).

  *Short-form note:* peer transports for short-form are structurally dead, not
  just unmeasured. A WebRTC swarm needs concurrent viewers of the same asset;
  peers find each other through [trackers keyed on the
  stream](https://github.com/Novage/p2p-media-loader). A short-form feed
  fragments its audience across thousands of clips and each viewer holds a
  given clip for ~15 seconds — swarm lifetime ≈ view duration. "Evaluate after
  measuring" is the right discipline for long-form; for short-form the answer
  is available now.

  *Scoping note (2026-08-12, research only):* if peer transports raise a
  "which bytes does the peer hold" question, it decomposes by scale and only the
  largest scale is a set-reconciliation problem.

  | Question | Scale | Right answer |
  | --- | --- | --- |
  | Same version of asset X? | 1 asset | Compare manifest CIDs — 32 bytes, produced by Phase 3 |
  | Which segments of asset X? | ~10³ | Possession bitmap over manifest-ordered indices (~225 B for a 1-hour 3-rendition ladder) |
  | Which assets does this mirror hold? | ~10⁷–10⁸ CIDs | Range-based set reconciliation over the CID-ordered keyspace |

  Do not put a set-reconciliation protocol on the per-asset path: the manifest
  already enumerates the set, which is the question such protocols exist to
  answer. Where reconciliation *is* warranted (the third row), prefer RBSR over
  IBLT — the keyspace is ordered, RBSR has no decode-failure mode, it localizes
  divergence, and it can reconcile a slice, which a partial-catalog mirror needs.
  Reasoning and sizing in the
  [range-based set reconciliation guide](../../20-explanation/guides/range-based-set-reconciliation.md);
  the IBLT counterpart is
  [here](../../20-explanation/guides/iblt-for-atproto-reconciliation.md).

## Verification gates for the workstream

Beyond each phase's own gate:

- `cmake --build build --target AllTests --parallel 4` then
  `./build/tests/AllTests --gated=run` — bound `--parallel` to 4.
- `./scripts/dev/check_module_boundaries.sh .` — no new violations against the
  recorded baseline.
- `deno run -A --config=deno.json scripts/docs/repo_docs.ts validate --internal-strict`.
- Objective-C doc coverage stays ≥90% (`scripts/docs/doc-coverage.ts`).
