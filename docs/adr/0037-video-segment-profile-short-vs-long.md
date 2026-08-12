<!-- SPDX-FileCopyrightText: 2025-2026 Jack Valinsky -->
<!-- SPDX-License-Identifier: Unlicense OR CC0-1.0 -->

# ADR 0037: Separate Segment Profiles for Short-Form and Long-Form Video

**Status:** Accepted
**Date:** 2026-08-12

## Context

ADR 0036 intentionally addresses content identity, integrity, and retrieval
layering. It does not fix a single segment duration policy for all products.

The product constraints for short-form and long-form differ:

- Short-form prioritizes startup latency and feed continuity.
- Long-form prioritizes seek behavior and storage/manifest efficiency.

Using one fixed profile for both forces a bad tradeoff in at least one path.

## Decision

`jelcz` exposes two segment profiles:

1. **Short-form profile**
   - segment duration: **2 seconds** (reference: Streamplace uses 1s;
     conventional HLS ladders use [4–6 seconds](https://gcore.com/blog/optimizing-hls-dash-3sec).
     2s balances startup latency against per-segment overhead for content
     under ~60 seconds)
   - discovery response includes prefetch-critical fields for next-item
     playback (manifest CID plus first-segment access metadata)
   - mirrors to untrusted origins require incremental verification support
     (BDASL/bao sidecar) before rollout
   - **Open question: should short-form be segmented at all?** A 15-second
     clip at 1.5 Mbps is ~2.8 MB. You cannot meaningfully adapt bitrate inside
     15 seconds — TikTok-class players pick a rendition up front from a network
     estimate. The short-form profile may plausibly be *one object per
     rendition, no segmentation, byte-range seek, progressive playback* —
     which is the flat-MP4 path documented in ADR 0036's considered alternative.
     This drops short-form store cardinality by a factor of 15–40 and removes
     ABR machinery that cannot be used. Must be resolved before Phase 2.
2. **Long-form profile**
   - segment duration: **6 seconds** (the current `jelcz` configuration;
     conventional for VOD ladders, balances seek granularity against manifest
     size)
   - seek and storage efficiency prioritized
   - mirror rollout may proceed earlier in trusted/same-operator environments

Both profiles keep ADR 0036 invariants:

- manifest is the atproto blob
- segments are content-addressed outside blob lifecycle
- provider locations remain mutable metadata, not immutable manifest identity

## Consequences

- **Positive:** short-form feed startup and long-form efficiency can be tuned
  independently without changing record semantics.
- **Positive:** rollout gates become explicit: incremental verification is a
  short-form mirror-path dependency, not only a seek-path hardening task.
- **Negative:** more configuration and test surface (profile-specific fixtures,
  startup/perf gates, and client compatibility checks).
- **Negative:** discovery APIs must carry prefetch-oriented fields for
  short-form product paths.
- **Manifest-size interaction:** Phase 3 gates the encoded manifest at 1 MiB
  using ADR 0036's ~123 KB estimate for 1,800 resources at 6s segments. At 1s
  segments (Streamplace's profile), an hour at three renditions is 10,800
  resources — roughly 740 KB. It passes, barely, and fails at four renditions or
  ninety minutes. The gate and the segment profile are coupled; neither the
  gate nor this ADR previously said so. If short-form adopts 2s segments, the
  count is 5,400 (~370 KB), which is safe. If the flat-MP4 path is adopted for
  short-form (no segmentation), the manifest is a byte-offset table that does
  not scale with segment count at all.
- **Prefetch-waste budget:** Phase 8's gate measures "reduced startup stalls"
  but has no waste budget. [Network-aware prefetching
  research](https://arxiv.org/abs/2209.02927) reports 37–52% data-waste
  reduction over naive methods, which tells you naive prefetch wastes a great
  deal. Prefetching N videos a user swipes past is the dominant cost of a
  short-form feed; measure both sides. Phase 8's gate should include a
  prefetch-waste ceiling alongside its startup-stall target.
- **Short-form P2P is structurally dead:** Phase 11 (peer transports) for
  short-form is not just unmeasured — it is unavailable without measuring. A
  WebRTC swarm needs concurrent viewers of the same asset; peers find each
  other through [trackers keyed on the
  stream](https://github.com/Novage/p2p-media-loader). A short-form feed
  fragments its audience across thousands of clips and each viewer holds a
  given clip for ~15 seconds — swarm lifetime ≈ view duration. "Evaluate after
  measuring origin bandwidth" is the right discipline for long-form; for
  short-form the answer is available now.

## See also

- [ADR 0036](0036-content-addressed-video-distribution.md)
- [Workstream 12](../plans/workstreams/12-content-addressed-video.md)
