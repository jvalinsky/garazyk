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

### Segment CIDs are SHA-256 raw, not BLAKE3

Segments are addressed with the base DASL profile (`0x55` raw, SHA-256), matching
every other atproto blob. `Garazyk/Sources/Core/CID+DASL.h:61` is explicit that
BLAKE3 CIDs are not interoperable with atproto peers and must never be written
into a record; that constraint holds here even though segment CIDs appear only
inside manifest bytes, because the manifest is itself repo-referenced content.

BDASL/BLAKE3 addressing is deferred to the point where trustless *partial*
verification is actually needed (seeking against an untrusted mirror). When it
lands it applies to segment `src` values only, never to the manifest blob's own
CID.

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
- **Deferred**: BDASL range verification, MUXL determinism, and peer transports
  are all out of scope and gated separately.
- **Unresolved**: `Garazyk/Resources/lexicons/place/stream/` (Streamplace's
  `segment.json`, `livestream.json`, and related defs) is vendored and referenced
  by nothing in `Garazyk/Sources/`. Streamplace models one record per segment,
  which suits live ingest — segments flow through the firehose — but is wrong for
  VOD at 600+ records per hour per rendition. The record shape for this workstream
  is deliberately left open rather than adopted from those lexicons.

## See also

- [Workstream 12: content-addressed video](../plans/workstreams/12-content-addressed-video.md)
  — phased execution, gates, and rollback.
- [ADR 0013](0013-blob-lifecycle-conformance.md) — the blob lifecycle this
  decision routes around.
- [ADR 0032](0032-dasl-conformance-profiles.md) — the DASL profile model that
  segment and manifest addressing selects from.
- [Workstream 10](../plans/workstreams/10-dasl-conformance.md) — RASL, BDASL,
  MASL, and MUXL slices this workstream consumes.
