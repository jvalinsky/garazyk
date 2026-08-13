<!-- SPDX-FileCopyrightText: 2025-2026 Jack Valinsky -->
<!-- SPDX-License-Identifier: Unlicense OR CC0-1.0 -->

# ADR 0036: Content-Addressed Video — Live MASL Segments and Flat-VOD Rendition Objects

**Status:** Accepted
**Date:** 2026-08-12
**Amended:** 2026-08-12 — closed the VOD packaging and hashing decisions that
were previously recorded as open Phase 2 premises.

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

### Alternative considered: Streamplace-style flat VOD (one blob per video)

Streamplace's VOD model (`pkg/vod/flat_vod.go` in
[streamplace/streamplace](https://github.com/streamplace/streamplace)) stores
one blob per video: `[flat-header][canonical fragments]`, content-addressed by
the MUXL CID — the BDASL hash of the fragments alone. A JSON "metafile"
(`pkg/vod/metafile.go`) carries per-track byte ranges into that single object,
and HLS is served with `EXT-X-BYTERANGE`. The same bytes also serve as a
progressive faststart MP4.

Set against a pure MASL-per-segment VOD model: ~1,800 separately-addressed
segment objects and a ~123 KB path→CID manifest, versus a handful of objects
and a byte-offset table. The consequences are not marginal:

- Phase 2 becomes an immutable CA object store with range reads rather than a
  per-segment store that must refcount ~1,800 objects per hour of video.
- Phase 6 (reclamation) shrinks: GC per rendition/object is a delete, not
  refcounting thousands of segments against live manifests.
- Partial verification for multi-gigabyte objects needs authenticated slices
  (see Decision: hashing and Bao), not whole-object download-then-hash.

Streamplace's `pkg/vod/transfer.go` candidly notes that `TransferVOD` "has NOT
yet been ported to the flat-MP4 content model and will fail-safe (CID mismatch,
nothing stored)" — because their CID covers fragments while the network
transfers the whole blob. That failure motivates the invariant below
(complete object or authenticated slice of it) and the choice to address the
**entire served media object**, not a custom header+fragments envelope.

The flat-VOD model does not cover live streaming, where segments flow through
the firehose and `prev`-chained manifests are the natural shape. MASL
per-segment addressing is retained for live; flat VOD is for VOD only.

## Decision

### Dual packaging: live MASL segments; VOD flat rendition objects

| Profile | Packaging | Default hash | Notes |
| --- | --- | --- | --- |
| Live | MASL + individually addressed fMP4 segments | SHA-256 | Firehose-friendly cardinality; whole-segment verify |
| VOD | Flat range-addressable fMP4 objects, preferably **one object per rendition/track** | BLAKE3 | HLS `EXT-X-BYTERANGE` / `EXT-X-MAP`; small object count |
| ATProto repo / blobs | Unchanged | SHA-256 | Blessed atproto blob CID profile |

**ATProto identity uses SHA-256; jelcz VOD distribution objects use BLAKE3.**
Keeping BLAKE3 inside the opaque manifest payload (and the jelcz CA store)
avoids teaching PDS/repository machinery a nonstandard atproto blob CID.

VOD granularity is **not** "one giant object for the entire ladder." Prefer:

```
video-1080p.fmp4 -> CID A   (BLAKE3)
video-720p.fmp4  -> CID B
video-480p.fmp4  -> CID C
audio.m4a        -> CID D   (shared across video renditions when possible)
```

Going from ~1,800 segment objects to ~3–5 rendition objects is the lifecycle
win; collapsing further to a single ladder package buys little while coupling
mirroring, repair, eviction, and CDN cache behavior across renditions.

The addressed VOD object **is valid ISO-BMFF / fMP4** (or ordinary audio
container). Do not invent `[custom flat header][MP4 fragments]` unless a
header is proven essential. Range/init/fragment tables live in MASL / video
metadata (or are derived from the MP4 structure), so:

```
CID(BLAKE3, actual_media_file_bytes)
```

not `CID(custom_container(header + media))`.

HLS VOD playlists address fragments with standard `EXT-X-BYTERANGE` (and
`EXT-X-MAP` for init), so segmentation remains a playback indexing concern
rather than a storage-object concern ([RFC 8216](https://www.rfc-editor.org/rfc/rfc8216)).

### Only the manifest is an atproto blob

Live segments and VOD rendition objects are **not** stored in the atproto blob
store. They live in a `jelcz`-owned content-addressed object store. The single
atproto blob per video is a MASL manifest that names them (live: per-segment
paths; VOD: rendition objects plus range metadata).

This is not a workaround for the lifecycle defect — it is the correct layering.
It removes the recursive-pinning requirement, the per-account quota interaction,
and the upload storm at once, and it is what makes retrieval pluggable: media
bytes are no longer bound to `getBlob` semantics, so a mirror, CDN, or peer
transport can serve them without protocol changes.

### Invariant: complete object or authenticated slice

A content CID identifies the exact canonical bytes of an immutable media
object. A server MAY return a byte range rather than the complete object, but
verified clients MUST be able to authenticate that range, its offset, and its
length against the object's CID.

More compactly: **served bytes are either the addressed representation or an
authenticated slice of it.**

| Mode | Meaning |
| --- | --- |
| Live segment | `CID →` complete segment bytes |
| Flat VOD | `CID + offset + length + Merkle proof →` authenticated range |

Streamplace's fragment-only CID while serving the whole blob violates this.
HTTP partial representations ([RFC 9110](https://www.rfc-editor.org/rfc/rfc9110))
are expected; the cryptographic contract must cover them explicitly.

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
manifest blob by CID, which names every live segment or VOD rendition object by
CID. A client that has verified the commit signature can therefore accept media
bytes from **any** source — an untrusted mirror, a CDN, a peer — by checking
complete objects against the CID (live) or authenticated ranges against the
CID + Bao proof (VOD). This transitive signature is what makes third-party
redistribution safe, and it is why the manifest must be referenced by a record
rather than fetched out of band.

### Object addressing profiles (closed 2026-08-12)

Hashing is **not** a single project-wide SHA-256 vs BLAKE3 switch. Profiles:

| Profile | Algorithm | Role |
| --- | --- | --- |
| `ATPROTO_BLOB` | raw + SHA-256 | Repository blobs and atproto-interop CIDs |
| `JELCZ_LIVE_SEGMENT` | raw + SHA-256 | Live fMP4 segments (whole-object verify) |
| `JELCZ_VOD_OBJECT` | raw + BLAKE3 | Flat-VOD rendition/track media files |
| `JELCZ_VOD_PROOF` | derived Bao/outboard | Untrusted acceleration; **not** content identity |

`CID+DASL.h` still warns that BLAKE3 CIDs must not be written into records or
repository blocks. That constraint applies to structures an ATProto peer must
decode. A manifest blob's payload is neither: it is a blob referenced by a
record. `MASLIsCID` already validates `src` against `ATProtoDASLCIDProfileBig`
(accepts BLAKE3). Streamplace peers likewise address video with BDASL while
routing around `getBlob`.

**Live segments stay SHA-256.** A six-second segment is downloaded whole,
hashed, compared to the CID, and played. WebCrypto `SHA-256` makes browser
verification trivial; Merkle range proofs add little.

**Flat-VOD objects use BLAKE3.** Clients normally consume ranges of a
multi-gigabyte object. Whole-object SHA-256 after full download does not
authenticate a seeked range. BLAKE3 was designed for verified streaming; Bao
builds the range/slice protocol on that Merkle tree
([BLAKE3](https://github.com/BLAKE3-team/BLAKE3/blob/master/README.md),
[Bao spec](https://github.com/oconnor663/bao/blob/master/docs/spec.md)).

**Correct the earlier Bao claim.** Possessing `BLAKE3 root` +
`bytes[lo, hi)` is **not** enough to prove those bytes occupy that range.
The client also needs the Merkle authentication path (a Bao slice: content
plus tree parents). Phase 9 therefore does **not** disappear. It changes from
distributing a **trusted** per-chunk sidecar to providing **untrusted** Merkle
proof material whose authenticity is derived from the BLAKE3 CID:

```
signed repo → manifest → BLAKE3 CID (trusted root)
                         ↓
              untrusted mirror: range bytes + proof
                         ↓
              client verifies locally
```

Store layout for VOD objects:

```
objects/<cid>.fmp4     # identity-bearing media
proofs/<cid>.bao       # derived; regenerate from media; same media CID
```

Deleting or regenerating the proof index does not change the media CID.
Corrupting the proof makes verification fail until regeneration.

Browser consequence: WebCrypto registers SHA-1/SHA-2 digests, not BLAKE3
([Web Crypto API](https://www.w3.org/TR/WebCryptoAPI/)). VOD verifiers need
WASM/JS BLAKE3. At video bitrates that is bundle size, not throughput — an
accepted consequence of the untrusted-mirror architecture.

**Rejected:** flat VOD + SHA-256 while still claiming arbitrary untrusted-mirror
range verification — that rebuilds a separate authenticated chunk tree and
throws away much of the reason to choose the flat model.

The atproto manifest blob itself remains codec `0x55` / SHA-256 because atproto
blobs always do, even though its payload is DRISL (`0x71`). The blob's
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

### Object-store GC is jelcz-owned refcounting

Moving media out of the blob store relocates the recursive-pinning problem
rather than eliminating it: the object store needs reclamation keyed on whether
a live manifest still references an object.

This is the right owner. `jelcz` holds both the manifests and the objects, has
no ADR 0013 or protocol constraint to satisfy, and can maintain an explicit
refcount at manifest publish and retract time instead of scanning record JSON.

For VOD, cardinality is small (few rendition CIDs per video), so reclamation is
far cheaper than the ~1,800-segment live/VOD-segment model. Live still needs
per-segment refcounting for the duration of the stream and retention window.

### Retrieval is a strategy behind the manifest

Manifest resolution and byte retrieval are separated. The first implementation
resolves against the local object store (`get` / `get_range` + proof produce).
`rasl://` hints
(`Garazyk/Sources/Core/ATProtoRASLURL.m`,
`Garazyk/Sources/Network/ATProtoRASLClient.m`) add verified multi-origin HTTPS
retrieval with no new transport. Peer transports are evaluated later against
that same seam.

The manifest itself is immutable content and should sit behind the same seam.
The author PDS remains the authority of record, but operational fan-out should
not depend on repeated per-viewer manifest fetches from the author PDS.
Manifests are therefore cacheable and rehostable by the same retrieval
infrastructure as media objects, with CID verification unchanged.

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
- **Positive**: atproto still sees one blob per video rather than ~1,800, so the
  10 GiB per-account cap tracks source material rather than rendition count.
- **Positive**: VOD storage cardinality drops from ~1,800 segments to ~3–5
  rendition objects, collapsing the hard GC/refcounting surface for VOD while
  keeping independent mirror/repair/evict per rendition.
- **Positive**: third-party redistribution becomes safe without new protocol
  surface, because the commit signature transitively covers every media CID
  (and VOD ranges via Bao proofs rooted in those CIDs).
- **Positive**: the `%03d` numbering defect is fixed as a side effect, closing
  silent segment overwriting past 100 minutes.
- **Negative**: `jelcz` gains a content-addressed store with its own lifecycle
  and reclamation to maintain. The recursive-pin problem is relocated, not
  removed (live segments remain the expensive case).
- **Negative**: media objects are no longer covered by the PDS's blob backup,
  replication, or audit tooling (`PDSBlobReferenceScanOperation` and the blob
  audit surfaces do not see them). Operational parity has to be rebuilt in the
  object store or accepted.
- **Negative**: the fMP4 switch raises the client floor. Players without fMP4
  HLS support lose playback; TS output is not retained in parallel.
- **Negative**: verified playback imposes an additional client floor beyond
  fMP4 support. Clients that bypass application-level fetch (for example, native
  HLS paths that pull network bytes directly) cannot enforce CID verification.
  VOD browsers need a BLAKE3/Bao implementation outside WebCrypto.
- **Negative**: serving by manifest CID alone has no built-in moderation verdict
  surface. The serving route needs a locally-synced denylist at minimum (CID or
  record-level) before bytes are returned.
- **Changed (Phase 9):** BDASL work becomes Bao/outboard proof generation,
  persistence/regeneration, and range-proof serving for `JELCZ_VOD_OBJECT` —
  not a trusted per-chunk sidecar channel. Proof indexes are derived storage.
- **Deferred**: MUXL determinism and peer transports are gated separately.
- **Deferred**: short-form and long-form segment policy are intentionally split.
  This ADR keeps the content-addressing and layering decisions; profile tuning
  (segment duration, prefetch shape, startup targets) is recorded separately
  in ADR 0037.
- **Constraint**: a video-first service at live write rates has to be the PDS.
  A manifest republished every 10 seconds is a blob upload plus a repo commit
  plus a firehose event, six times a minute per live stream. The Bluesky PDS
  fleet is not designed for this traffic ([Streamplace hit the rate-limit wall
  and runs its own PDS](https://blog.stream.place/3lut7mgni5s2k) for the same
  reason). Garazyk is a PDS (`kaszlak`), so this is not a blocker — but "sign
  in with your existing Bluesky account and post video" is not a supportable
  story for live, and probably not for high-volume short-form. This constrains
  the product to be a PDS with an app, not an app on atproto.
- **Resolved (WS12 Phase 7, 2026-08-12):** Streamplace VOD lexicons
  (`place.stream.video`, `place.stream.media.track`, `place.stream.media.origin`)
  are vendored under `place/stream/`. Garazyk ships its own CA VOD records
  (`tools.garazyk.video`, `.distributionPolicy`, `.origin`) rather than
  adopting Streamplace's VOD NSID surface. `place.stream.broadcast.origin` and
  `place.stream.metadata.distributionPolicy` remain the shape references.
  `segment.json` stays live-ingest only and is still rejected as a VOD model.
  Product call: optional `compatMp4` for Bluesky `app.bsky.embed.video`; never
  put DRISL in that embed.

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
  per-asset path, and why Bao outboard encoding is the Phase 9 proof format for
  flat-VOD range authentication.
