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

- `httpsBase` (optional URI) — explicit HTTPS provider when `watchBaseUrl` is
  insufficiently specific

**Amended 2026-08-13 (Track A):** For Garazyk CA/VOD peering, prefer additive
`irohEndpointId` (stable iroh EndpointID) and optional `irohEndpointTicket`
(bootstrap hint only). Do **not** store `iroh-blobs` `BlobTicket` values in a
field named `irohTicket` — that name is reserved for Streamplace-compatible
**NodeTicket** semantics on `place.stream.broadcast.origin`.

The lexicon currently also carries optional `irohTicket` from the initial
revision; new Track A work should migrate announce paths to the explicit fields
above and treat legacy `irohTicket` on Garazyk origins as deprecated for P2P.

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
- Sidecar: bind localhost/UDS only; consent before dial; limit egress bytes and
  concurrency. Attacker-controlled origin records may carry valid iroh dial
  information — treat as directed egress risk, not HTTP SSRF.

### 6. iroh implementation gate

iroh sidecar work stays **closed-not-pursued** until production CA VOD traffic
exists and origin bandwidth is measured, **or** an explicit lab-only exception
is recorded in WS16. Short-form WebRTC swarms remain out of scope ([ADR
0037](0037-video-segment-profile-short-vs-long.md)).

#### 6.1 Track A lab exception (recorded 2026-08-13)

Maintainers approve **Track A only** — default-off jelcz↔jelcz `iroh-blobs`
experimentation on **iroh 1.x** in a separate sidecar binary
(`tools/jelcz-iroh-blobs-sidecar/`). This exception:

- **does not** satisfy the production cost-justification gate (§6 opening);
- **does not** imply supported Streamplace live interoperability (Track B remains
  blocked — [phase-36](../plans/prompts/phase-36-ws16-streamplace-iroh-bridge.md));
- **does not** promote the sidecar to a default dependency (`JELCZ_P2P=0` remains
  the default);
- requires security and operational evidence before any production-support claim.

Garazyk CA/VOD peering (`iroh-blobs`) and Streamplace live syndication
(`/iroh/streamplace/1`, iroh 0.9x ecosystem) are **separate protocols** — two
binaries, not one multi-protocol sidecar. Research:
[`2026-08-13-phase-35-iroh-sidecar-research.md`](../archive/planning/2026-08-13-phase-35-iroh-sidecar-research.md).

Execution: [phase-35](../plans/prompts/phase-35-ws16-iroh-sidecar.md) (S0–S11).

#### 6.2 Track B compatibility decision (recorded 2026-08-13)

Maintainers approve a separate, default-off Streamplace live bridge at
`tools/jelcz-streamplace-iroh-bridge/`. It reproduces the exact
`/iroh/streamplace/1` wire at Streamplace source revision
`5ba597dbedda8f2fdb84b815ee633301212f5f51` (the iroh 0.93 ecosystem), rather
than coupling Track B to Track A's iroh 1.x `iroh-blobs` sidecar or assuming an
upstream Rust-library import.

The implementation must not use the pinned upstream generic RPC handler for
incoming segments: that handler discards the authenticated connection identity.
A custom `ProtocolHandler` captures QUIC `Connection::remote_node_id()` and
accepts `RecvSegment` only when its `from` field, the parsed NodeTicket identity,
and the subscribed streamer agree with that authenticated peer. The bridge is
receive-only, defaults to loopback/UDS local IPC, and the Compose profile
publishes no bridge port. Local subscription IPC also requires a per-run bearer
capability; Jelcz supplies it only after streamer consent and freshness checks.

[Scenario 101](../../scripts/scenarios/scenarios/101_streamplace_track_b_live_iroh.ts)
is the opt-in acceptance lane. It requires the running image's OCI revision,
private topology, NodeTicket/origin/firehose proof, exact ALPN, authenticated
NodeID binding, structural MUXL validation, and negative cases. This is source
and static implementation evidence only: no dated real-peer Scenario 101 pass
is recorded. Phase 36 remains blocked until Phase 35 completes and that pinned
image acceptance is preserved as dated evidence.
The bridge must also gain a real firehose-fed, process-persistent acceptance
report; the current CLI fails closed until that evidence plumbing exists.

## Consequences

- WS16 Phase 1 complete (this ADR).
- Phase 2 HTTPS mesh remains the supported multi-jelcz lab path.
- Phase 3 implements remote-PDS origin publish behind flags; lexicon additive
  fields land with that work.
- Phase 4 Track A **in progress** (lab exception §6.1, 2026-08-13). Phase 5
  Track B's compatibility decision is approved (§6.2), but it remains blocked
  on Phase 35 and dated pinned-image Scenario 101 acceptance.
- Browser UX unchanged: always HTTPS to a jelcz/Streamplace origin.

## See also

- [WS16](../plans/workstreams/16-jelcz-p2p-peership.md)
- [WS15](../plans/workstreams/15-streamplace-vod-peership.md)
- [Streamplace and jelcz peership lab](../20-explanation/guides/streamplace-jelcz-peership-lab.md)
- Research: [`2026-08-13-phase-35-iroh-sidecar-research.md`](../archive/planning/2026-08-13-phase-35-iroh-sidecar-research.md)
- [phase-35](../plans/prompts/phase-35-ws16-iroh-sidecar.md), [phase-36](../plans/prompts/phase-36-ws16-streamplace-iroh-bridge.md)
