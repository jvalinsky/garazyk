<!-- SPDX-FileCopyrightText: 2025-2026 Jack Valinsky -->
<!-- SPDX-License-Identifier: Unlicense OR CC0-1.0 -->

# ADR 0036: Video Segments Are Addressed by a MASL Manifest Blob, Not Stored as Blobs

**Status:** Accepted
**Date:** 2026-08-12

## Context

Garazyk's video path (`jelcz`) currently mirrors the Bluesky reference
architecture: the original upload is stored as a single blob on the PDS, and
an adaptive-bitrate ladder is generated as a side effect and served — in
principle — from a CDN path. That works for short social clips. It does not
support a video-first product (long-form video, multiple renditions,
redistribution by third parties), which is the case this ADR addresses.

Three findings from the current tree set the constraints.

### The HLS stage is a stub

`ATProtoVideoHLSGenerator` shells out to ffmpeg and writes a variant ladder to
disk, but nothing consumes it:

| Site | State |
| --- | --- |
| `Garazyk/Sources/Video/VideoWorker.m:383` | `VideoHLSResult` is logged (`variants.count`) and discarded |
| `Garazyk/Sources/Video/ATProtoVideoProcessor.m:244` | keeps `hlsMasterPlaylist` / `hlsVariants` / `hlsBaseUrl` in a metadata dict |
| `Garazyk/Sources/AppView/Services/VideoUriBuilder.m:10` | builds `{videoServiceURL}/watch/{did}/{cid}/playlist.m3u8` as a *pattern string* |
| `Garazyk/Sources/MediaCore/ATProtoMediaServiceRuntime.m:106-146` | registers `/xrpc`, `/_health`, `/admin/api/media/*` — **no `/watch` route exists** |

So the ladder is generated, written, referenced by a URL nothing serves, and
never addressed. There is no existing behavior to preserve here, which makes
this a design choice rather than a migration.

### Indirect blob references are invisible to the blob lifecycle

`PDSBlobAuditBlobReferenceCIDsFromJSONObject`
(`Garazyk/Sources/Admin/Diagnostics/BlobAudit/PDSBlobAuditUtils.m:26`) walks a
record's JSON for `{"$type": "blob", "ref": {"$link": …}}`. That recursive walk
over *record JSON* is the only thing that writes a `blob_refs` row and promotes
a blob from `temporary` to `referenced`
(`Garazyk/Sources/Services/PDS/PDSRecordService+BlobLifecycle.m:48-49`).

Under [ADR 0013](0013-blob-lifecycle-conformance.md), a `temporary` blob is not
downloadable, and the hourly sweep reclaims it after the grace period (six
hours by default, clamped to a one-hour minimum).

A manifest referenced directly by a record is therefore promoted correctly. But
CIDs that appear only *inside the manifest's bytes* are never seen by the
extractor: they get no `blob_refs` row, are never promoted, remain undownloadable,
and are deleted by the next sweep. Storing segments as blobs would require a
recursive reference walk — the equivalent of IPFS recursive pinning — which
does not exist in the tree.

Segments-as-blobs carries further cost independent of that defect: a one-hour
video at three renditions is ~1,800 `uploadBlob` round trips and ~1,800 rows
counted against ADR 0013's 10 GiB per-account cap, in exchange for bytes that
`com.atproto.sync.getBlob` can only serve from one origin anyway.

### Determinism and verifiability are separate goals

Workstream 10 Phase 9 (MUXL) targets a deterministic MP4 muxer so that two
independent transcodes of the same source produce the same CID. That is a
strictly harder problem than the one video distribution needs, and the current
encoder settings (`libx264 -preset fast` with default threading,
`Garazyk/Sources/Video/VideoHLSGenerator.m:164-166`) are not reproducible across
thread counts or ffmpeg builds. Coupling distribution to reproducible addressing
would block the former on the latter for no distribution benefit.

### Alternative: flat VOD (one blob per video)

Streamplace's VOD model (`pkg/vod/flat_vod.go` in
[streamplace/streamplace](https://github.com/streamplace/streamplace)) stores
one blob per video: `[flat-header][canonical fragments]`, content-addressed by
the MUXL CID — the BDASL hash of the fragments alone. A JSON "metafile"
(`pkg/vod/metafile.go`) carries per-track byte ranges into that single object,
and HLS is served with `EXT-X-BYTERANGE`. The same bytes also serve as a
progressive faststart MP4.

Set against this ADR's MASL manifest model: ~1,800 separately-addressed segment
objects and a ~123 KB path→CID manifest, versus one object and a byte-offset
table. The consequences are not marginal:

- Phase 2 (segment store) becomes a blob store with range reads — which
  `BlobStorage.h` already is.
- Phase 6 (segment reclamation) collapses. Refcounting 1,800 segments per
  video against live manifests is the hardest correctness work in the plan;
  GC per-VOD is a delete.
- Phase 9 (BDASL sidecar) largely disappears. With BLAKE3 addressing, bao's
  root hash *is* the object CID, and [slice verification needs nothing but the
  root](https://github.com/oconnor663/bao/blob/master/docs/spec.md) — no
  sidecar to invent, ship, or find a trusted channel for.
- Manifest size stops scaling with segment count. Byte offsets compress;
  36-byte CIDs don't.

The counterweight is real. Streamplace's `pkg/vod/transfer.go` carries a
candid note that `TransferVOD` "has NOT yet been ported to the flat-MP4 content
model and will fail-safe (CID mismatch, nothing stored)" — because the CID
covers the fragments while the network transfers the whole blob, so the
receiver cannot verify what it downloaded. Their mirror path is currently
broken by the header decoupling.

This failure vindicates an invariant the MASL manifest model holds implicitly
and should state explicitly: **the addressed bytes are exactly the served
bytes.** A synthesis is available that is better than either option: one object
per VOD, addressed over the *entire* served object (not fragments alone), with
a byte-range track table. This gets the cardinality win, free incremental
verification, and the invariant intact.

The flat-VOD model does not cover live streaming, where segments flow through
the firehose and `prev`-chained manifests are the natural shape. The MASL
manifest model is retained for live; the flat-VOD synthesis is a candidate for
VOD only.

This fork is recorded as a considered alternative. The decision is **open** and
must be resolved before Phase 2 begins implementation — it is the phase's
premise.

## Decision

### Only the manifest is an atproto blob

Segments, variant playlists, and init segments are **not** stored in the atproto
blob store. They live in a `jelcz`-owned content-addressed segment store. The
single atproto blob per video is a MASL manifest that names them.

This is not a workaround for the lifecycle defect — it is the correct layering.
It removes the recursive-pinning requirement, the per-account quota interaction,
and the upload storm at once, and it is what makes retrieval pluggable: segments
are no longer bound to `getBlob` semantics, so a mirror, CDN, or peer transport
can serve them without protocol changes.

### Invariant: addressed bytes ≡ served bytes

The bytes a CID covers are exactly the bytes a client receives and verifies.
Streamplace's flat-VOD model violates this invariant by addressing fragments
alone while serving the whole blob, which breaks their transfer verification
path. Any content-addressing model adopted here must preserve it: the CID must
cover exactly what the network delivers, whether that is a segment, a whole
VOD object, or a rendition. This invariant is what makes untrusted mirrors
safe — a client can verify any byte range against the address without a
separate trust channel.

### The manifest is a MASL bundle document

MASL bundle mode is already a path-to-CID map with per-path HTTP headers
(`Garazyk/Sources/Core/ATProtoMASLDocument.m`). An HLS ladder is already a
path-to-file tree. The manifest is the identity mapping between them:

```
{
  "$type": "ing.dasl.masl",
  "resources": {
    "/":                        {"src": <cid>, "content-type": "application/vnd.apple.mpegurl"},
    "/720p/video.m3u8":         {"src": <cid>, "content-type": "application/vnd.apple.mpegurl"},
    "/720p/init.mp4":           {"src": <cid>, "content-type": "video/mp4"},
    "/720p/segment_00000.m4s":  {"src": <cid>},
    ...
  }
}
```

Every rule the existing validator enforces is satisfied by construction: the
`resources` map contains the root path `/`
(`ATProtoMASLDocument.m:144`), all paths are absolute and free of `?`/`#`, each
resource carries a DASL-conformant `src`, and `$type` is `ing.dasl.masl`.
`content-type` is on MASL's header allow-list (`ATProtoMASLDocument.m:44-48`),
so `-httpHeadersForPath:error:` supplies correct serving headers without a
parallel MIME table.

Per-segment `content-type` is omitted and derived from the path extension at
serve time. For one hour at `-hls_time 6` across three renditions — 1,800
segments plus three variant playlists, three init segments, and one master —
this is roughly 1,807 resources and ~123 KB encoded, against ~190 KB if
per-segment content types were emitted.

`prev` chains manifest versions and is the mechanism for live streams; each
published manifest points back at its predecessor.

### The integrity chain terminates at the repo commit

The signed commit covers the MST, which covers the record, which references the
manifest blob by CID, which names every segment by CID. A client that has
verified the commit signature can therefore accept segment bytes from **any**
source — an untrusted mirror, a CDN, a peer — by checking the bytes against the
CID in the manifest. This transitive signature is the property that makes
third-party redistribution safe, and it is the reason the manifest must be
referenced by a record rather than fetched out of band.

### Object addressing: SHA-256 default, BLAKE3 open

Segments are currently addressed with the base DASL profile (`0x55` raw,
SHA-256), matching every other atproto blob. `CID+DASL.h:61-62` states that
"BLAKE3 CIDs are not interoperable with ATProto peers — never write one into a
record or a repository block." That constraint applies to records and
repository blocks — the structures an ATProto peer must decode. A manifest
blob's payload is neither: it is a blob referenced by a record, not a record
or block itself.

Three things confirm the restriction does not reach manifest payload:

- `MASLIsCID` (`ATProtoMASLDocument.m:17-19`) validates manifest `src` values
  against `ATProtoDASLCIDProfileBig`, which accepts BLAKE3. Every `src` in the
  manifest, and `prev`, admits a BDASL CID today.
- Streamplace is an atproto peer and addresses video blobs with BDASL,
  routing around `getBlob` with `place.stream.playback.getVideoBlob`. This ADR
  already routes around the blob store for the same bytes.
- The cost of SHA-256 is Phase 9's entire existence. With BLAKE3, bao's root
  hash *is* the plain BLAKE3 hash, and [slice verification needs nothing but
  the root](https://github.com/oconnor663/bao/blob/master/docs/spec.md).
  BLAKE3-address the object and trustless partial verification is a property
  of the address, not a sidecar to invent, ship, and find a trusted channel
  for.

The sidecar scaling problem is the unrecorded cost of SHA-256.
`ATProtoBDASLVerifier.h:9-10` requires the caller to supply "the complete
sidecar array" of one BLAKE3 digest per 1 KiB chunk — 3.125% of payload. At
~5 Mbps aggregate across a three-rendition ladder, a one-hour video is ~2.2 GB
and that array is ~70 MB. It cannot live in a 123 KB manifest, and there is no
other trusted surface. Phase 9's owner boundary reads "Core/ verifier +
MediaCore fetch plumbing," as if it were plumbing. It is a contract
replacement, and the existing contract does not scale.

The one genuine objection to BLAKE3 is browser support: there is no
[SubtleCrypto BLAKE3](https://parsa.wtf/blake3/), so web clients need WASM
while SHA-256 is hardware-accelerated. At video bitrates this does not bind —
0.2–0.6 MB/s of payload against a WASM implementation doing hundreds of MB/s.
The cost is bundle size, not throughput. Worth recording as a consequence,
not treating as a blocker.

**Decision: open.** If the flat-VOD synthesis is adopted (see above), BLAKE3
addressing of the single VOD object is the natural choice and Phase 9
collapses. If the MASL manifest model is retained, the question is whether
segment `src` values in the manifest use BLAKE3 — which `MASLIsCID` already
permits — or stay SHA-256 and accept the Phase 9 sidecar cost. Must be
resolved before Phase 2.

The manifest blob receives codec `0x55` because atproto blobs always do, even
though its payload is DRISL (`0x71`). This is an accepted infelicity; the blob's
`mimeType` carries the real type.

### Segments are fragmented MP4, not MPEG-TS

`Garazyk/Sources/Video/VideoHLSGenerator.m:190` currently emits
`segment_%03d.ts`. This changes to fMP4 (`-hls_segment_type fmp4`,
`-hls_fmp4_init_filename init.mp4`, `.m4s` segments). MPEG-TS cannot carry a
MUXL catalog and does not decompose cleanly for range verification, so TS would
foreclose both later options.

The same line caps segment numbering at `%03d` — 1,000 segments, i.e. 100 minutes
at the configured six-second target — after which ffmpeg overwrites earlier
segments. That is a live defect for long-form video independent of this ADR and
is fixed to `%05d` in the same change.

### Verifiable distribution now; reproducible addressing separately

The manifest records the CIDs of the bytes that were actually produced. Nothing
requires that a second transcode reproduce them. This yields full verifiability
for distribution — any consumer can prove the bytes match the signed manifest —
without depending on a deterministic muxer.

MUXL (workstream 10 Phase 9) remains worthwhile for cross-server dedup and
re-derivation, and `ATProtoMUXLBox` is a prerequisite for it, but it is **not**
a prerequisite for this workstream. The fMP4 switch above is what keeps that
door open.

### Segment-store GC is jelcz-owned refcounting

Moving segments out of the blob store relocates the recursive-pinning problem
rather than eliminating it: the segment store needs its own reclamation keyed on
whether a live manifest still references a segment.

This is the right owner. `jelcz` holds both the manifests and the segments, has
no ADR 0013 or protocol constraint to satisfy, and can maintain an explicit
refcount at manifest publish and retract time instead of scanning record JSON.

### Retrieval is a strategy behind the manifest

Manifest resolution and byte retrieval are separated. The first implementation
resolves against the local segment store. `rasl://` hints
(`Garazyk/Sources/Core/ATProtoRASLURL.m`,
`Garazyk/Sources/Network/ATProtoRASLClient.m`) add verified multi-origin HTTPS
retrieval with no new transport. Peer transports are evaluated later against
that same seam.

The manifest itself is immutable content and should sit behind the same seam.
The author PDS remains the authority of record, but operational fan-out should
not depend on repeated per-viewer manifest fetches from the author PDS.
Manifests are therefore cacheable and rehostable by the same retrieval
infrastructure as segments, with CID verification unchanged.

Provider location hints are mutable operational state, not immutable content
identity. They belong on a **mirror-authored origin attestation record** — the
shape already vendored as `place.stream.broadcast.origin` (`broadcast/origin.json`)
— not on the author's video record or embedded in the immutable manifest payload.
The origin record is authored by the hosting node (the mirror), not the video
author, and carries the mirror's DID, address, and a heartbeat timestamp. This
decomposition yields three records with distinct owners:

| Record | Owner | Mutability | Answers |
| --- | --- | --- | --- |
| video record → manifest/blob CID | author | immutable identity | what is this |
| distribution policy | author | mutable | who may redistribute, how long |
| origin attestation | mirror | mutable + heartbeat | who has it right now |

Every mirror joining, leaving, or heartbeating writes to its own repo — not
the author's. The author cannot attest to a mirror's liveness. The vendored
`place.stream.metadata.distributionPolicy` lexicon carries `allowedBroadcasters`
(with `*` for anyone and a `!` prefix to ban) and `deleteAfter` — the consent
and retention primitive.

IPFS is rejected as a retrieval layer. UnixFS chunking produces a different CID
than the raw SHA-256 addressing used here, so the same video would carry two
incompatible identities and the manifest's CIDs would not match what a Bitswap
peer serves; DHT provider-record lookup latency is far above a video start
budget; and Bitswap has no range semantics, which makes seeking pathological.

## Consequences

- **Positive**: no change to ADR 0013 is required, and no recursive blob
  reference walk has to be written. The manifest is an ordinary record-referenced
  blob and behaves correctly under the existing lifecycle.
- **Positive**: one blob per video rather than ~1,800, so the 10 GiB per-account
  cap tracks source material rather than rendition count.
- **Positive**: third-party redistribution becomes safe without new protocol
  surface, because the commit signature transitively covers every segment CID.
- **Positive**: the `%03d` numbering defect is fixed as a side effect, closing
  silent segment overwriting past 100 minutes.
- **Negative**: `jelcz` gains a content-addressed store with its own lifecycle
  and reclamation to maintain. The recursive-pin problem is relocated, not
  removed.
- **Negative**: segments are no longer covered by the PDS's blob backup,
  replication, or audit tooling (`PDSBlobReferenceScanOperation` and the blob
  audit surfaces do not see them). Operational parity has to be rebuilt in the
  segment store or accepted.
- **Negative**: the fMP4 switch raises the client floor. Players without fMP4
  HLS support lose playback; TS output is not retained in parallel.
- **Negative**: verified playback imposes an additional client floor beyond
  fMP4 support. Clients that bypass application-level fetch (for example, native
  HLS paths that pull network bytes directly) cannot enforce CID verification.
- **Negative**: serving by manifest CID alone has no built-in moderation verdict
  surface. The serving route needs a locally-synced denylist at minimum (CID or
  record-level) before bytes are returned.
- **Deferred**: BDASL range verification, MUXL determinism, and peer transports
  are all out of scope and gated separately.
- **Deferred**: short-form and long-form segment policy are intentionally split.
  This ADR keeps the content-addressing and layering decisions; profile tuning
  (segment duration, prefetch shape, startup targets) is recorded separately.
- **Constraint**: a video-first service at live write rates has to be the PDS.
  A manifest republished every 10 seconds is a blob upload plus a repo commit
  plus a firehose event, six times a minute per live stream. The Bluesky PDS
  fleet is not designed for this traffic ([Streamplace hit the rate-limit wall
  and runs its own PDS](https://blog.stream.place/3lut7mgni5s2k) for the same
  reason). Garazyk is a PDS (`kaszlak`), so this is not a blocker — but "sign
  in with your existing Bluesky account and post video" is not a supportable
  story for live, and probably not for high-volume short-form. This constrains
  the product to be a PDS with an app, not an app on atproto.
- **Unresolved**: `Garazyk/Resources/lexicons/place/stream/` contains
  Streamplace's live/broadcast/chat/moderation lexicons only. `segment.json` is
  a live-ingest record (one record per segment, suited to firehose streaming) and
  is correctly rejected as a VOD model. Streamplace's VOD model uses
  `place.stream.video`, `place.stream.media.track`, and
  `place.stream.media.origin`, none of which are vendored. Re-vendor before
  Phase 7 defines anything. The `place.stream.broadcast.origin` lexicon
  (vendored, in `broadcast/origin.json`) is a mirror-authored origin attestation
  record — the right shape for provider hints — and
  `place.stream.metadata.distributionPolicy` carries `allowedBroadcasters` and
  `deleteAfter` — the consent and retention primitive.

## See also

- [Workstream 12: content-addressed video](../plans/workstreams/12-content-addressed-video.md)
  — phased execution, gates, and rollback.
- [ADR 0013](0013-blob-lifecycle-conformance.md) — the blob lifecycle this
  decision routes around.
- [ADR 0032](0032-dasl-conformance-profiles.md) — the DASL profile model that
  segment and manifest addressing selects from.
- [Workstream 10](../plans/workstreams/10-dasl-conformance.md) — RASL, BDASL,
  MASL, and MUXL slices this workstream consumes.
- [ADR 0037](0037-video-segment-profile-short-vs-long.md) — resolves short-form
  versus long-form segment and startup policy without changing this ADR's
  content-addressing model.
- [Video discovery and peer-sharing options](../20-explanation/guides/video-discovery-and-peer-sharing-options.md)
  — the discovery layer above the retrieval strategy this ADR leaves open.
- [Range-based set reconciliation and the Willow protocol](../20-explanation/guides/range-based-set-reconciliation.md)
  — why the manifest decided here removes the need for set reconciliation on the
  per-asset path, and the argument for resolving the deferred BDASL sidecar
  format with bao outboard encoding.
