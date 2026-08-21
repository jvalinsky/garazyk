---
phase: 35
title: WS16 Track A — jelcz iroh-blobs sidecar (CA/VOD)
status: blocked
agent: worker
depends_on: []
last_updated: 2026-08-21
---

## Progress

- 2026-08-13: Research landed (two-track architecture).
- 2026-08-13: **S0 complete** — Track A lab exception recorded in
  [ADR 0038 §6.1](../../adr/0038-jelcz-p2p-layering.md); WS16 Phase 4
  unblocked for lab work.
- 2026-08-13: **S1 complete** — Track A contracts frozen in WS16 Phase 4.
- 2026-08-13: **S2–S7 implementation and live transport proof are present**:
  hash mapping and fixture, iroh-blobs sidecar, HTTP IPC adapter, verified CA
  resolver path, default-off configuration, and a project-scoped Compose run.
  Scenario 100 passed 12 steps with one explicit scope skip; the dated report
  is recorded below and in WS16.
- 2026-08-14: **S8 complete** — `tools.garazyk.video.origin` lexicon extended
  with `irohEndpointId` (stable EndpointID) and optional `irohEndpointTicket`
  (bootstrap ticket) fields. `GZJelczOriginAnnouncer` factory signature
  updated to `irohEndpointId:irohEndpointTicket:`. Demo handler in
  `GZJelczStreamplacePeerDemo.m` updated. `JelczOriginAnnouncerTests` extended
  to 6 cases (3 new: `testOriginRecordIncludesEndpointIdAndTicket`,
  `testOriginRecordOmitsEndpointFieldsWhenNil`, renamed httpsBase-only test).
  All 6 pass. Build clean. Legacy `irohTicket` property on announcer retained
  for broadcast-origin compatibility (NodeTicket semantic — not overloaded).
- **Current evidence boundary:** S8 and S9 complete. The Rust sidecar now uses progress-driven cancellation and bounded staging; tests passed. S10 fresh-miss/warm-hit measurement and S11 closeout remain blocked.
- **Next:** Host machine disk space must be expanded to allow Docker image building for the S10 measurement lab.

# Phase 35: Track A — jelcz iroh-blobs sidecar

## Mission

Execute WS16 Phase 4 (CA/VOD data plane) and the Garazyk-origin pieces of
Phase 6 under a **narrow lab exception** or production clearance. Build a
**separate** Rust sidecar (`tools/jelcz-iroh-blobs-sidecar/`) on **iroh 1.x +
iroh-blobs**; jelcz talks over **UDS or loopback IPC only**; CA resolver remains
the integrity authority.

**Do not** implement Streamplace live replication in this phase.

The canonical Compose lab is HTTP internally (`SP_SECURE=false`), with
loopback-published host ports. It does not assert HTTPS or true TLS; standalone
sidecar IPC is loopback by default, while Compose uses un-published private
service-name IPC under an explicit lab-only trust setting.

## Read first

- Research (authoritative for architecture):
  [`2026-08-13-phase-35-iroh-sidecar-research.md`](../../archive/planning/2026-08-13-phase-35-iroh-sidecar-research.md)
- [`docs/plans/workstreams/16-jelcz-p2p-peership.md`](../workstreams/16-jelcz-p2p-peership.md)
- [ADR 0038](../../adr/0038-jelcz-p2p-layering.md), [ADR 0036](../../adr/0036-content-addressed-video-distribution.md)
- `Garazyk/Sources/MediaCore/ATProtoCAMirrorResolver.{h,m}`
- `Garazyk/Binaries/jelcz/main.m` — mirror fetcher composition

## What is already correct — do not redo

- HTTPS peership (WS15), provider index, consent allow-lists, origin announce
- Additive `httpsBase` on `tools.garazyk.video.origin`
- Streamplace-shaped `irohTicket` on `place.stream.broadcast.origin` (NodeTicket
  semantics — **do not overload for Garazyk BlobTickets**)

## Governance gate

The formal gate required one of these paths before **S1**:

1. **Production clearance** — dated production CA VOD `/watch` traffic **and**
   origin bandwidth / cache-miss measurements showing P2P worth the complexity.
2. **Lab exception** — maintainer records narrow Track A exception in ADR 0038
   (or equivalent decision note): default-off, no production-cost claim, no
   Streamplace live interop implied.

The narrow lab exception was recorded in ADR 0038 §6.1 on 2026-08-13, so S0
is satisfied and this phase is `in-progress`. The production-clearance path
remains unsatisfied and no production-cost claim is made.

Independently, the Streamplace live Track B protocol/version decision and
static implementation are complete. Its live acceptance still depends on this
phase completing; see [phase-36](phase-36-ws16-streamplace-iroh-bridge.md).

## Architecture (frozen for this phase)

| Concern | Choice |
| --- | --- |
| Binary | `tools/jelcz-iroh-blobs-sidecar/` (Track A only) |
| iroh stack | Exactly locked **iroh 1.x** + compatible **iroh-blobs** |
| Provider identity | Stable **EndpointID** + existing CA **CID**; optional bootstrap **EndpointTicket** |
| Garazyk origin fields | Prefer `irohEndpointId` + optional `irohEndpointTicket` — **not** polymorphic `irohTicket` |
| IPC | Versioned `POST /v1/fetch` (UDS preferred); **no** tickets in query strings |
| Integrity | Sidecar stages bytes → `ATProtoCAMirrorResolver` verifies CID → CA put |
| Default | `JELCZ_P2P=0`; HTTPS unchanged when sidecar absent |
| Docker boundary | Host ports default to `127.0.0.1`; sidecars have no host port. Private Docker sidecar DNS requires `JELCZ_IROH_SIDECAR_TRUST_LAN=1` and is not a general LAN exposure. |

## Steps (S-prefix — not WS16 phase numbers)

### S0 — Governance

Record lab exception **or** production evidence in ADR 0038 + WS16 + this file
`## Progress`. Flip status to `in-progress`.

**Acceptance:** decision link exists; scope explicitly Track A only.

### S1 — Contracts

Freeze: IPC schema (`/v1/health`, `/v1/identity`, `/v1/fetch`, `/v1/offer`);
provider identity model; Cargo.lock pin for iroh 1.x; lexicon plan for
`irohEndpointId` / `irohEndpointTicket` (additive revision).

**Acceptance:** decision note in WS16 or ADR amendment; no code required.

### S2 — Hash fixture (prerequisite)

Cross-language tests: Garazyk DASL/BDASL CID ↔ 32-byte BLAKE3 ↔ iroh `Hash`.
Cases: empty, small, multi-chunk, malformed CID, wrong alg, wrong expected CID.

**Acceptance:** fixture tests green before any network code.

### S3 — Local sidecar

Rust: iroh 1.x endpoint + iroh-blobs provider/requester; local two-process
integration test (offer + fetch same hash).

**Acceptance:** `cargo test` in sidecar crate; no jelcz link deps.

### S4 — IPC adapter

UDS/loopback HTTP service; thin ObjC `ATProtoCAMirrorFetching` adapter wired
from jelcz composition root.

**Acceptance:** `./scripts/dev/check_module_boundaries.sh .` green; local fetch
smoke with sidecar running.

### S5 — Integrity path

Sidecar candidate bytes → existing resolver → verified CA put; reject
tampered/wrong-CID bytes.

**Acceptance:** negative tests; resolver remains authority.

### S6 — Configuration

`JELCZ_P2P`, `JELCZ_IROH_SIDECAR_URL` (or UDS path); operator docs beside
`JELCZ_PEER_*` vars.

**Acceptance:** default-off; HTTPS-only behavior unchanged.

### S7 — Two-node lab

Two jelcz instances: A seeds CA object, B fetches via iroh, serves locally.
Script sibling to `jelcz_https_mesh_demo.sh`.

**Acceptance:** dated demo log in WS16.

Use `scripts/demo/streamplace_peership_smoke.sh` or the opt-in external-lab
[Scenario 100](../../../scripts/scenarios/scenarios/100_jelcz_iroh_peership.ts).
Both require a fresh destination miss before the respective HTTP or iroh pull,
then require transport attribution, BLAKE3 verification, and local byte
equality. Scenario 100 is skipped unless an operator has started the Compose
lab and set `JELCZ_PEERSHIP_LAB=1`; it does not provision Docker.

### S8 — Origin announce (Garazyk)

Optional stable EndpointID + bootstrap ticket on `tools.garazyk.video.origin`
(additive lexicon); announcer + round-trip test.

**Acceptance:** `JelczOriginAnnouncerTests` extended; Streamplace `irohTicket`
semantics unchanged on broadcast origins.

### S9 — Security / limits

Consent before dial; byte/time/concurrency limits; ticket redaction in logs;
malformed provider input; loopback/UDS bind only. Delegate `security-auditor`
for review.

**Acceptance:** negative test suite; security findings recorded.

### S10 — Lab measurement

Table: canonical-lab HTTP vs iroh fresh-miss/warm-hit latency and application
payload bytes; record relay vs direct only where observable. This lab does not
measure HTTPS/TLS.

**Acceptance:** WS16 evidence paragraph (does not satisfy production gate).

### S11 — Closeout

WS16 Phase 4 + Garazyk-origin Phase 6 slices → complete for **Track A lab**.
Mega-plan note. Phase status → `complete` when S0–S11 evidence landed.

Source compilation, unit tests, Compose interpolation, and static boundary
checks are necessary but are not a substitute for the dated S7/S9/S10 live
evidence required for this state transition.

## Out of scope

- Streamplace live mesh ([phase-36](phase-36-ws16-streamplace-iroh-bridge.md))
- One multi-protocol sidecar binary
- Link-time iroh in ObjC static libraries
- Polymorphic `irohTicket` (NodeTicket | BlobTicket)
- IPFS (ADR 0036)
- Production-support claim without promotion gates in research doc §11

## Acceptance gate

```bash
./scripts/dev/check_module_boundaries.sh .
cmake --build build --target AllTests --parallel 4
./build/tests/AllTests -XCTest 'JelczPeerProviderIndexTests' --gated=run
./build/tests/AllTests -XCTest 'JelczOriginAnnouncerTests' --gated=run
# plus S2 hash fixture tests and sidecar crate tests
# Start the external Compose lab first; run the validated capability-loader
# command printed by the Docker wrapper, then collect the dated report:
JELCZ_PEERSHIP_LAB=1 deno task hamownia run --no-setup 100
# Optional, separately dated Docker-PDS publication evidence:
./scripts/demo/streamplace_peership_federation_smoke.sh
# S9 security review and S10 measurements must be recorded in WS16
```

The Streamplace catalog probe is optional and non-gating. The local Streamplace
v0.8.4 test stream does not currently provide a deterministic VOD
`getVideoBlob` record, so the acceptance procedure uses freshly seeded jelcz CA
bytes. Docker PDS origin announce/discovery and cross-PDS federation are also
outside Scenario 100 and remain unproven without their own dated artifact.

**2026-08-13 evidence:** the project-scoped Compose shell smoke passed, and
Scenario 100 passed 12 steps with one explicit scope skip in
`scripts/scenarios/reports/runs/2026-08-13t2257z-82379/reports/100_jelcz_iroh_peership.json`.
The separate federation smoke stopped before mutation because the local PDS was
not reachable on port 2583. This closes S7, but keep the phase `in-progress`:
S9 security/limits, S10 quantitative bandwidth/cache evidence, and S11
closeout remain. The `AllTests` target now links after rebuilding interrupted
static archives; a complete global `AllTests --gated=run` result is not claimed.

**2026-08-13 S10 attempt:**
`scripts/demo/jelcz_track_a_s10_measurement.ts` passed format and type checks,
then stopped before writing an artifact against the already-running isolated
Track A lab. Its source jelcz returned a `meshFanout` result, rather than the
required `meshFanoutSuppressed=true`, for `POST /demo/streamplace/api/seed?fanout=0`;
the active image consequently pre-populated both destinations and invalidated
the fresh-miss precondition. Recreate the isolated lab from the current image
before retrying. S10 remains pending; no latency, byte, or direct/relay result
is claimed.

**2026-08-13 S9 remediation checkpoint:** an independent security review found
three P1 boundaries. Capability protection and exact sidecar-host trust are now
implemented in source; the Compose wrapper generates both lab capabilities in
one per-project `0600` runtime file without printing them, and its fixed-format
loader rejects symlinks, unsafe permissions, and unexpected records. The peer
demo now sends the capability on both identity and fetch requests. Fetch admission is
bounded to two concurrent requests and the operation has a 60-second timeout.
The follow-up security re-audit found no residual issue in the capability,
host-trust, or runtime-secret fixes.
Primary-source review of `iroh-blobs` 0.103 confirms that
[`DownloadProgress::stream`](https://docs.rs/iroh-blobs/latest/iroh_blobs/api/downloader/struct.DownloadProgress.html)
exposes `Progress(u64)` events and receiver closure participates in cancellation,
but [`MemStore`](https://docs.rs/iroh-blobs/latest/iroh_blobs/store/mem/index.html)
is still memory-backed and `Blobs::get_bytes` warns about large-blob memory
exhaustion. The next S9 slice must therefore use progress-driven cancellation
with disk-backed or otherwise bounded staging, prove partial-download cleanup,
and apply a bounded final reader. Do not treat cancellation alone or the current
post-download check as acceptance. This leaves S9 open. Rust formatting, shell
syntax, Compose interpolation, and diff checks
pass. `ATProtoVideoService`, `jelcz`, and the four touched Objective-C test
objects compile after the remediation. Cargo compilation/tests could not run
offline because the local registry index is absent, and the native test methods
were not executed. The final native build reduced disk headroom to under 3 GiB, so
no further build or live-lab gate is safe in this session.

**2026-08-15 S9 completion:** The Rust sidecar now uses progress-driven cancellation and bounded staging; its local tests and the ObjC negative tests pass, thus completing S9. S10/S11 remain blocked.

## Blocked on

S10 live-lab measurement is blocked. The host machine is critically low on disk space, preventing Docker Compose from staging or exporting the required `garazyk/jelcz-peer:local` and `garazyk/jelcz-iroh-sidecar:local` images without exhausting the virtual disk. This phase cannot complete until the host environment is provisioned with sufficient storage to reliably run the multi-node S10 lab.

**2026-08-21 capacity check:** the available Crimson VM runs the production
`kaszlak` and `konbini` services. Its inactive Track A sidecar build output was
removed (2.7 GiB), preserving all service binaries and data, but the root volume
still has only 3.0 GiB free and no Docker images. The fresh lab necessarily
builds Linux jelcz and sidecar images and starts the local ATProto topology, so
running it at that capacity risks exhausting the volume beneath the active
services. Crimson is therefore not sufficient S10 capacity yet; no Compose lab
or scenario was started.
