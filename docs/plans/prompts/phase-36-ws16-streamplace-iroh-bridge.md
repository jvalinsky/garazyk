---
phase: 36
title: WS16 Track B — Streamplace live iroh bridge
status: blocked
agent: worker
depends_on: [35]
last_updated: 2026-08-13
---

# Phase 36: Track B — Streamplace live iroh bridge

## Mission

Optional interoperability with Streamplace's **live** segment syndication over
iroh. This is a **separate executable/crate** from Track A — not an extension of
`jelcz-iroh-blobs-sidecar`.

## Progress

- 2026-08-13: the pin-specific bridge, authenticated peer binding, bounded
  receive path, capability-protected Jelcz attestation, persistent acceptance
  report, independent firehose/CAR evidence, and isolated fault topology are
  implemented and statically verified. The static checker and Scenario 101 now
  also fail closed unless Streamplace, publisher, and bridge images are all
  SHA-256 digest references.
- 2026-08-13: repository verification drift was repaired. Deno gates pass, the
  complete native target links, the two focused peering classes pass 17/17, and
  the corrected session-store class passes 24/24. The full native gated run was
  interrupted during slow integration fixtures and is not claimed green.
- **Remaining boundary:** Phase 35 must complete, then Scenario 101 must produce
  a dated pass against the required pinned Streamplace publisher image. No live
  Track B acceptance is currently recorded.
- **Current readiness:** the host is running the Track A-only services, has no
  PDS/relay listener on 2583/2584, and has no Track B environment file. Disk
  headroom is now under 3 GiB. Do not pull/build the Track B images in this
  state.

## Read first

- [`2026-08-13-phase-35-iroh-sidecar-research.md`](../../archive/planning/2026-08-13-phase-35-iroh-sidecar-research.md)
  §3, §4, §10
- [`docs/plans/workstreams/16-jelcz-p2p-peership.md`](../workstreams/16-jelcz-p2p-peership.md)
  Phase 5
- Streamplace:
  [`rust/iroh-streamplace`](https://github.com/streamplace/streamplace/tree/next/rust/iroh-streamplace)
- [Streamplace syndication blog](https://blog.stream.place/3m3ngytdrws2k)

## Blocked on

The maintainer-approved compatibility decision is **implemented as static source
evidence**, but this phase cannot complete until all of the following are true:

1. **[Phase 35](phase-35-ws16-iroh-sidecar.md) Track A is complete.** Its
   default-off lab work, security/limits, measurement, and closeout evidence
   remain in progress; the Track A exception alone does not satisfy this
   dependency.
2. **Dated Track B live acceptance on the pinned image.** Run and preserve
   `JELCZ_STREAMPLACE_TRACK_B_LAB=1 deno task hamownia run --no-setup 101`
   against a real Streamplace publisher image whose OCI revision label is
   `5ba597dbedda8f2fdb84b815ee633301212f5f51`. The run must prove the complete
   NodeTicket → exact ALPN → Subscribe → authenticated pushed-MUXL chain.
3. **Dated negative/fault execution.** The bridge persists only its
   authenticated transport facts, Jelcz capability-attests structural MUXL
   validation of the exact returned bytes, and Scenario 101 independently
   decodes the causal firehose commit/CAR. Private pin-specific fault peers now
   implement wrong-streamer, wrong-ALPN, authenticated `from` spoof,
   corrupt/oversize segment, and dropped-Subscribe bounded reconnect exercises.
   Isolated stale and malformed origins are capability-protected, entirely
   replaced per case, and asserted not to create bridge sessions. These cases
   still need to pass in the dated live run from item 2.
4. **Immutable auxiliary images — complete 2026-08-13.** The static checker and
   Scenario 101 require SHA-256 digest references for publisher and bridge as
   well as Streamplace; Scenario 101 records all three immutable references as
   provenance. The live run must still verify the required Streamplace OCI
   revision label.
5. **Runnable local topology and secrets.** Provide the Track B env files,
   streamer DID, bridge capability, Jelcz demo capability, host firehose URL,
   Compose relay URL, and local PDS/relay listeners on 2583/2584. Reclaim disk
   before any image build or pull.

No live Scenario 101 run is recorded by this prompt.

Post-hardening static gates on 2026-08-13 include locked/offline `cargo check`
and 17/17 Rust library tests. The crate target was removed after verification.
Scenario 101 passes direct `deno check`/lint/format, the Hamownia metadata and
preflight suites pass 28/28, `deno task check`, the Track B Compose contract,
module boundaries, VideoService compilation, and the focused peer-demo test
object all pass. Follow-up verification on 2026-08-13 found that the reported
OAuth/PDS link failures came from interrupted, truncated build archives rather
than source dependencies: `ATProtoServices` contained 31/117 members and
`ATProtoAppViewServer` 3/29. Rebuilding those generated archives restored all
members, all required binaries link, and the `AllTests` target builds with
`--parallel 4`. `JelczStreamplaceIrohBridgeTests` passes 6/6 and
`JelczStreamplacePeerDemoTests` passes 11/11, including separate assertions for
the trusted local identity refresh and the forbidden unknown-provider fetch. The
stale `SessionStoreTests` registration was corrected to `PDSSessionStoreTests`;
the registration audit passes and that class passes 24/24. The unrelated Schemat
unused import was removed and the checked-in Gruszka client regenerated;
`deno task check`, `deno task lint`, and the full loopback-enabled package suite
pass (1,271 passed, 0 failed, 1 ignored). A full native `AllTests --gated=run`
was started and made progress without a failure, but was intentionally
interrupted after integration fixture latency grew to 8–10 seconds per method;
it is not claimed as a completed green gate.

## Compatibility decision and static implementation evidence

The approved Track B implementation is a **separate, pin-specific bridge** at
`tools/jelcz-streamplace-iroh-bridge/`, distinct from the Track A `iroh-blobs`
sidecar. It reproduces the exact Streamplace `/iroh/streamplace/1` wire shape at
source revision `5ba597dbedda8f2fdb84b815ee633301212f5f51` (compatible iroh
`0.93.2` / irpc `0.9.0`), rather than linking Track A's iroh 1.x stack or
assuming an upstream library boundary.

At that pin, the upstream generic handler discards the authenticated connection
identity while handling serialized `RecvSegment.from`. The bridge's custom
`ProtocolHandler` captures `Connection::remote_node_id()` and rejects a segment
unless `RecvSegment.from`, the parsed NodeTicket identity, and the subscribed
streamer match that authenticated QUIC peer. Local IPC is receive-only,
loopback/UDS by default, and the Compose Track B bridge has no published host
port. Subscription IPC requires a per-run bearer capability shared with Jelcz.
The Track B Compose override actually wires all three Jelcz services to the
private bridge; its non-loopback bind and Jelcz private-host allowance both
require explicit lab flags. It is opt-in, not a default dependency or CI
topology.

[Scenario 101](../../../scripts/scenarios/scenarios/101_streamplace_track_b_live_iroh.ts)
enforces the pinned OCI revision and digest, excludes Track A containers and
configuration, opens a same-relay cursor observer before a causal publisher
refresh, binds the origin op CID to its decoded CAR block, exercises denial
before dial, rejects isolated stale and malformed origins without creating
bridge session evidence, and correlates the observed ticket fingerprint with the
bridge's authenticated NodeID/session and Jelcz's exact-byte MUXL attestation.
It then requires real fault-peer session evidence for wrong streamer, wrong
ALPN, authenticated identity spoof, corrupt MUXL, oversize segment, and exact
bounded retry exhaustion. Its source/static checks are not a dated live
acceptance result.

## Confirmed Streamplace protocol (do not assume iroh-blobs)

```text
place.stream.broadcast.origin.irohTicket  →  NodeTicket
    → dial peer → ALPN /iroh/streamplace/1
    → Subscribe(streamer DID)
    → RecvSegment (pushed MUXL bytes)
```

Minimum acceptance (research §10):

```text
real Streamplace origin → ticket parsed → peer reached
→ /iroh/streamplace/1 → Subscribe(real streamer DID)
→ MUXL segment received → validation succeeds
```

Parsed ticket, generic iroh connection, or iroh-blobs transfer **does not**
count.

## Ownership

```text
tools/jelcz-streamplace-iroh-bridge/   # separate from jelcz-iroh-blobs-sidecar
```

## Out of scope

- Replacing WS15 HTTPS VOD peership
- Merging into Track A daemon
- Browser↔browser WebRTC
- Overloading Garazyk `irohTicket` for Streamplace NodeTickets on
  `tools.garazyk.video.origin`

## Acceptance gate (after dependencies clear)

Opt-in smoke only (not default CI): dated log of full minimum acceptance chain
above; consent env exercised; security review for egress/limits.
