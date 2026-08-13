---
title: Streamplace VOD Peership
status: complete
last_verified: 2026-08-13
---

# Streamplace VOD Peership

Treat [Streamplace](https://stream.place) nodes as **untrusted HTTPS origins**
that serve BDASL-addressed MUXL blobs via
`place.stream.playback.getVideoBlob`, pull them through Garazyk’s Phase 10
mirror seam into `jelcz`’s CA object store, and optionally serve the same
shape back for Streamplace clients. Live iroh / multi-node P2P stays under
[workstream 12 Phase 11](12-content-addressed-video.md) with execution detail
in [workstream 16](16-jelcz-p2p-peership.md) (iroh still blocked on reopen
criteria; HTTPS multi-provider discovery may proceed there).

Upstream reference: [tangled.org/stream.place/streamplace](https://tangled.org/stream.place/streamplace).
Decision context: [ADR 0036](../../adr/0036-content-addressed-video-distribution.md).

## Status (2026-08-13)

**Complete.** Phases 0–4 implemented in-repo (adapter, env provider, admin
posture, flag-gated compat serve, demo UI). Residual (not blocking close):

- Opt-in live smoke against public `stream.place`
  (`JELCZ_STREAMPLACE_SMOKE=1 ./scripts/test/streamplace_vod_mirror_smoke.sh`)
  — not default CI
- Firehose multi-origin indexing — deferred to WS16 provider index / AppView
- Origin attestation publish — WS16 Phase 3 ([ADR 0038](../../adr/0038-jelcz-p2p-layering.md): remote PDS write)

## Decision (locked)

- **VOD byte peership first** — HTTPS `getVideoBlob` + BLAKE3 verify + CA put.
- **Do not** join Streamplace’s live iroh swarm in this workstream.
- **Do not** adopt `place.stream.video` as Garazyk’s primary VOD NSID
  (ADR 0036 / WS12 Phase 7 chose `tools.garazyk.*`).

## Non-goals

- WHIP / RTMP ingest
- `getLiveSegment` mesh membership
- Becoming a Streamplace binary / indexer / chat host
- Link-time iroh or MediaCore→Network PUBLIC edges

## Owner boundaries

| Concern | Owner |
| --- | --- |
| Mirror protocol + verify/put | `Garazyk/Sources/MediaCore` (`ATProtoCAMirrorResolver`) |
| Streamplace URL shaping / attribution DID | jelcz composition root (`Garazyk/Binaries/jelcz`, Video helpers) |
| Admin Distribution posture | `Video/AdminUI` + `JelczAdminSnapshot` |
| Compat `getVideoBlob` serve | jelcz / MediaService runtime (flag-gated) |

## Phases

### Phase 0 — DONE: governance (2026-08-12)

This workstream, mega-plan item 15, README row, ADR 0036 / WS12 / discovery
guide cross-links.

### Phase 1 — DONE: Streamplace HTTPS provider adapter (2026-08-12)

`GZJelczStreamplaceBlobFetcher` implements `ATProtoCAMirrorFetching` by
calling `GET {base}/xrpc/place.stream.playback.getVideoBlob?did=&cid=` with
Range support. `BlobNotFound` / non-200 advances to the next provider.
MediaCore stays free of Streamplace-specific URL knowledge.

- Evidence: `JelczStreamplaceBlobFetcherTests` (URL building, BlobNotFound,
  MUXL fixture body acceptance before resolver verify).
- Rollback: do not install the fetcher; RASL HTTPS fetcher remains default.

### Phase 2 — DONE: origin / env provider wiring (2026-08-12)

Operator env:

- `JELCZ_STREAMPLACE_MIRROR_BASE` — HTTPS base of a Streamplace node
  (e.g. `https://stream.place` or `https://prod-sea0.stream.place`)
- `JELCZ_STREAMPLACE_ATTRIBUTION_DID` — DID passed as `did=` for egress
  accounting (required when the mirror base is set)
- Existing `JELCZ_CA_MIRROR_FETCH=1` still required to contact mirrors

`place.stream.media.origin` parsing helper maps a record’s blob CID to the
configured base (firehose multi-origin indexing deferred). Opt-in smoke:
`scripts/test/streamplace_vod_mirror_smoke.sh`.

### Phase 3 — DONE: operator visibility (2026-08-12)

jelcz admin Distribution / Overview show Streamplace mirror configured,
attribution DID present (yes/no only), and allowlisted fetch counters.

### Phase 4 — DONE: compat serve (2026-08-12)

Flag `JELCZ_STREAMPLACE_SERVE_COMPAT=1` registers
`place.stream.playback.getVideoBlob` on jelcz against the local CA store
(ranged GET). Does not publish `media.origin` to a server repo until a
Garazyk-operated server DID path exists; local attestation hook is stubbed
behind the same flag for follow-up.

- Gate: ranged GET + CID verify round-trip tests; module boundaries clean.
- Rollback: flag off — MASL `/watch` unchanged.

## Verification

```bash
cmake --build build --target AllTests --parallel 4
./build/tests/AllTests --filter 'JelczStreamplace*' --gated=run
./build/tests/AllTests --filter 'JelczAdminUIPackTests' --gated=run
# Opt-in live (not CI):
# JELCZ_STREAMPLACE_SMOKE=1 ./scripts/test/streamplace_vod_mirror_smoke.sh
```

## Demo (operator)

### Host (no Docker)

```bash
./scripts/demo/jelcz_streamplace_peer_demo.sh
# open http://127.0.0.1:2586/demo/streamplace
```

```bash
./scripts/demo/jelcz_https_mesh_demo.sh   # two local jelcz HTTPS peers
```

### Docker: Streamplace + local ATProto + 3× jelcz

```bash
./scripts/demo/streamplace_peership_up.sh
./scripts/demo/streamplace_peership_smoke.sh
# UIs: :2596 / :2597 / :2598 — Streamplace :38080
```

See [`docker/streamplace-peership/README.md`](../../../docker/streamplace-peership/README.md)
and the operator guide
[Streamplace and jelcz peership lab](../../20-explanation/guides/streamplace-jelcz-peership-lab.md).

Flag: `JELCZ_STREAMPLACE_DEMO=1`. UI lists live + VOD; **Peer via jelcz**
pulls small BDASL objects into the CA store and Range-proxies large MUXL
archives so the browser never fetches media from stream.place.

