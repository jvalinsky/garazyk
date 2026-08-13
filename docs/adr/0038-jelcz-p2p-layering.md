<!-- SPDX-FileCopyrightText: 2025-2026 Jack Valinsky -->
<!-- SPDX-License-Identifier: Unlicense OR CC0-1.0 -->

# ADR 0038: Jelcz P2P Layering (Origins, HTTPS, iroh Sidecar)

**Status:** Accepted  
**Date:** 2026-08-13

## Context

[ADR 0036](0036-content-addressed-video-distribution.md) makes video bytes
content-addressed and verifiable from untrusted origins. [Workstream
15](../plans/workstreams/15-streamplace-vod-peership.md) pulls Streamplace
`getVideoBlob` over HTTPS into jelcz’s CA store. [Workstream
16](../plans/workstreams/16-jelcz-p2p-peership.md) Phase 2 adds multi-provider
HTTPS ranking and a multi-jelcz mesh.

Streamplace’s syndication model
([blog](https://blog.stream.place/3m3ngytdrws2k)) separates:

- **Control plane:** `place.stream.broadcast.origin` on the firehose (tracker-like,
  carries `irohTicket`)
- **Data plane:** iroh between nodes; browsers still use HTTPS

Garazyk must not link iroh into MediaCore, must not adopt IPFS, and must not
merge Streamplace’s embedded PDS into kaszlak without an explicit identity
decision.

## Decision

### 1. Control plane = ATProto origin records + index

Provider discovery uses:

- Live / Streamplace-shaped: `place.stream.broadcast.origin`
- Garazyk VOD: `tools.garazyk.video.origin` (and optional
  `place.stream.media.origin` hints)

Any firehose consumer or AppView indexer may answer `cid` / stream → providers.
**Rejected:** IPNI as the primary discovery system; a Garazyk-owned DHT.

### 2. Data plane = HTTPS first; iroh as optional sidecar

| Path | Role |
| --- | --- |
| HTTPS `getVideoBlob` / RASL / `/watch` | Default fetch and all browser playback |
| iroh sidecar process | Optional node↔node backfill into the CA store |

ObjC talks to the sidecar over localhost HTTP or UDS. **No** link-time iroh in
`ATProtoMediaCore` / Video static libraries; **no** new MediaCore→Network
PUBLIC edge for peership.

### 3. Ticket fields on Garazyk origins

Extend `tools.garazyk.video.origin` (additive lexicon revision) with:

- `irohTicket` (optional string) — same role as Streamplace’s field
- `httpsBase` (optional URI) — explicit HTTPS provider when `watchBaseUrl` is
  insufficiently specific

Do **not** invent a parallel ticket-only record. Streamplace live continues to
use `place.stream.broadcast.origin` unchanged.

### 4. Announce identity (Phase 3)

**Chosen for Garazyk:** operator-configured **remote PDS write** (app password
or OAuth client) using a dedicated broadcaster/server DID the operator
controls.

| Option | Disposition |
| --- | --- |
| A. Remote PDS write | **Accepted** — reuses kaszlak; no embedded PDS in jelcz |
| B. Embedded/static PDS in jelcz | Deferred — Streamplace-shaped, large security surface |
| C. Admin-only announce API | Allowed as a thin wrapper over A for lab/ops |

Pull-only peership (WS16 Phase 2) does not require announce. Publishing
origins is gated on this identity path being configured.

### 5. Threat model (summary)

- Peers are **untrusted**; BLAKE3/BDASL (and Bao ranges where used) before CA put
- Tickets are capability-like: treat as secret-ish, rotate via origin heartbeat,
  drop stale `updatedAt` / `lastSeenAt`
- Consent: honor `distributionPolicy` / `JELCZ_P2P_ALLOWED_*` before auto-ingest
  or syndicate; empty allowlists deny record auto-ingest (env peer lists still apply)
- Egress: keep attribution DID for Streamplace-shaped accounting
- Sidecar: bind localhost only; no SSRF via attacker-controlled ticket URLs
  without allowlisting

### 6. iroh implementation gate

iroh sidecar work stays **closed-not-pursued** until production CA VOD traffic
exists and origin bandwidth is measured, **or** an explicit lab-only exception
is recorded in WS16. Short-form WebRTC swarms remain out of scope ([ADR
0037](0037-video-segment-profile-short-vs-long.md)).

## Consequences

- WS16 Phase 1 complete (this ADR).
- Phase 2 HTTPS mesh remains the supported multi-jelcz lab path.
- Phase 3 implements remote-PDS origin publish behind flags; lexicon additive
  fields land with that work.
- Phase 4+ stays blocked on evidence (or lab exception).
- Browser UX unchanged: always HTTPS to a jelcz/Streamplace origin.

## See also

- [WS16](../plans/workstreams/16-jelcz-p2p-peership.md)
- [WS15](../plans/workstreams/15-streamplace-vod-peership.md)
- [Streamplace and jelcz peership lab](../20-explanation/guides/streamplace-jelcz-peership-lab.md)
- [Video discovery guide](../20-explanation/guides/video-discovery-and-peer-sharing-options.md)
