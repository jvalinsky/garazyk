<!-- SPDX-FileCopyrightText: 2026 Jack Valinsky -->
<!-- SPDX-License-Identifier: Unlicense OR CC0-1.0 -->

# Research and Recommendation: Phase 35 / WS16 iroh Sidecars

**Date:** 2026-08-13  
**Scope:** [WS16](../../plans/workstreams/16-jelcz-p2p-peership.md) Phases 4–6 /
[phase-35](../../plans/prompts/phase-35-ws16-iroh-sidecar.md)  
**Status:** Decision-ready; implementation remains gated

## Executive summary

Phase 35 is **formally governance-gated** by the production CA VOD /
bandwidth-evidence requirement in [ADR 0038](../../adr/0038-jelcz-p2p-layering.md)
§6, [WS16](../../plans/workstreams/16-jelcz-p2p-peership.md) `## Blocked on`, and
[WS12 Phase 11](../../plans/workstreams/12-content-addressed-video.md), unless
maintainers record the already-permitted lab-only exception.

That governance gate is not the only unresolved issue. This investigation found
an architectural boundary that should drive the plan:

> **Garazyk CA/VOD peering and Streamplace live syndication are separate
> applications of iroh and must not be implemented as one protocol.**

Garazyk Phases 0–3 already delivered the control plane: provider discovery,
consent allowlists, HTTPS mirrors, remote-PDS origin announcement, and additive
`irohTicket` / `httpsBase` fields. There is no iroh data plane yet.

Streamplace's current `irohTicket` is an iroh **`NodeTicket`** (node dial
information), not an `iroh-blobs` `BlobTicket`. Live segment transport uses
custom ALPN `/iroh/streamplace/1`, RPC subscription keyed by streamer DID, and
pushed canonical MUXL segment bytes — not `iroh-blobs` fetch-by-content-hash.

| Track | Purpose | Protocol | Compatibility target |
| --- | --- | --- | --- |
| **A — Garazyk CA/VOD** | Content-addressed jelcz↔jelcz backfill | `iroh-blobs` | Current iroh 1.x stack |
| **B — Streamplace live** | Streamplace live segment syndication | `/iroh/streamplace/1` + Streamplace RPC | Streamplace's actual implementation |

**Recommendation:** record a **narrow lab-only exception for Track A**, build and
validate the CA/VOD sidecar behind default-off flags, and leave Track B blocked
until maintainers explicitly choose a Streamplace compatibility strategy. Track B
must **not** be implemented by extending the Track A daemon.

---

## 1. Decision required before implementation

| Input | Current status | Clearing evidence |
| --- | --- | --- |
| Production CA VOD | Open | Dated production `/watch` or equivalent CA VOD traffic |
| Origin bandwidth / cache-miss measurements | Open | Evidence that P2P materially improves cost or delivery over HTTPS mirrors/CDN |
| Phase 3 identity / origin announce | Done | Remote-PDS origin write and smoke coverage |

A lab exception answers a different question than production clearance:

| Question | Lab exception | Production gate |
| --- | --- | --- |
| Can we validate architecture, boundaries, CID↔BLAKE3 mapping, NAT/relay behavior? | Yes | No |
| Does P2P justify production complexity and operating cost? | No | Yes |

### Recommendation

Amend [ADR 0038](../../adr/0038-jelcz-p2p-layering.md) (or record the project's
normal equivalent decision note) to permit **Track A only — default-off
jelcz↔jelcz iroh-blobs experimentation.**

The exception should explicitly state that it:

- does not satisfy the production cost-justification gate;
- does not imply supported Streamplace live interoperability;
- does not promote the sidecar to a default dependency;
- requires security and operational evidence before any production-support claim.

Do not create a second broad P2P ADR if a small ADR 0038 amendment expresses the
decision adequately.

---

## 2. Existing Garazyk work that must remain intact

| Area | Primary paths |
| --- | --- |
| ADR 0038 | `docs/adr/0038-jelcz-p2p-layering.md` — HTTPS-first; iroh outside MediaCore |
| ADR 0036 | `docs/adr/0036-content-addressed-video-distribution.md` — BLAKE3 CA VOD trust model |
| Provider index | `Garazyk/Sources/Video/GZJelczPeerProviderIndex.{h,m}`; `JelczPeerProviderIndexTests` |
| Origin announcer | `Garazyk/Sources/Video/GZJelczOriginAnnouncer.{h,m}`; `JELCZ_ORIGIN_ANNOUNCE_*` |
| CA mirror resolver | `Garazyk/Sources/MediaCore/ATProtoCAMirrorResolver.{h,m}` |
| HTTPS fetcher | `Garazyk/Sources/MediaCore/ATProtoCAMirrorHTTPSFetcher.{h,m}` |
| jelcz composition | `Garazyk/Binaries/jelcz/main.m` — `GZJelczCAMirrorCompositeFetcher` |
| HTTPS mesh demo | `scripts/demo/jelcz_https_mesh_demo.sh` |
| Streamplace lab | `docker/streamplace-peership/`, `scripts/demo/streamplace_peership_*.sh` |
| Lexicons | `Garazyk/Resources/lexicons/tools/garazyk/video/origin.json`, `place/stream/broadcast/origin.json` |

The iroh implementation should consume these seams rather than introduce parallel
provider-discovery or verification systems.

> **The CA resolver remains the final content-integrity authority from Garazyk's
> point of view.**

`iroh-blobs` performs BLAKE3-verified transfer, but that does not replace
Garazyk's verification boundary. Garazyk must still prove that the requested
DASL/BDASL CID maps to the exact iroh BLAKE3 hash that was transferred before
committing bytes to the CA store.

---

## 3. Streamplace live protocol: confirmed shape

Streamplace's Rust crate
[`rust/iroh-streamplace`](https://github.com/streamplace/streamplace/tree/next/rust/iroh-streamplace)
(`next` branch, verified 2026-08-13) declares:

```toml
iroh = { version = "0.93", features = ["discovery-local-network"] }
iroh-base = "0.93.0"
iroh-gossip = "0.93.1"
irpc = "0.9.0"
irpc-iroh = "0.9.0"
```

The checked-in local `Cargo.lock` still contains iroh-family **0.91.1** packages,
so the repository currently has a **manifest/lock mismatch**. Before building
against this crate, determine which lockfile and dependency graph Streamplace's
actual CI/release process uses; do not infer runtime compatibility from the local
lockfile alone.

Rust source confirms:

```text
ticket type: iroh_base::ticket::NodeTicket
ALPN:        /iroh/streamplace/1

remote RPC:  Subscribe, Unsubscribe, RecvSegment
local API:   Subscribe, Unsubscribe, SendSegment, JoinPeers, AddTickets, GetNodeAddr, Shutdown
```

`Node::ticket()` builds a `NodeTicket` from node address information;
`node_id_from_ticket()` parses the same type (`src/lib.rs`, `src/node_addr.rs`).

Go integration (Streamplace `next`, syndication path):

1. obtain the node ticket;
2. publish it as `place.stream.broadcast.origin.irohTicket`;
3. parse remote origin tickets back into node IDs;
4. add the ticket's addressing information;
5. check whether the streamer is permitted;
6. subscribe using **the streamer DID as the stream key**;
7. push `not.Muxl` using `SendSegment`;
8. validate received MP4/MUXL data.

Lexicon: [place.stream.broadcast.origin](https://stream.place/docs/lex-reference/broadcast/place-stream-broadcast-origin/)
— optional `irohTicket` maxLength 2048.

Syndication overview:
[How Streamplace Works: Syndication](https://blog.stream.place/3m3ngytdrws2k).

### Consequence

A consumer of a Streamplace origin **cannot** implement live compatibility with:

```text
irohTicket + CID → iroh-blobs fetch
```

The actual flow is:

```text
origin.irohTicket
    → parse Streamplace NodeTicket
    → learn node identity + dial information
    → connect using /iroh/streamplace/1
    → Subscribe(streamer DID)
    → receive pushed MUXL segments
```

That is a **separate protocol implementation** (Track B), not an extension of
Track A.

---

## 4. Version strategy (architecture decision, not a risk footnote)

Public iroh is **1.0.3** ([docs.rs iroh](https://docs.rs/crate/iroh/latest)).
The [Iroh 1.0 announcement](https://www.iroh.computer/blog/v1) (2026-06-15)
states:

- wire stability within the iroh v1 line;
- **0.9x canary releases are not supported after 1.0**;
- **0.35 minor will not receive further releases**; public relay support for
  0.35x continues through **Dec 31, 2026**;
- public relay support for 0.9x ends **Sept 30, 2026**.

Current `iroh-blobs` **0.103.0** depends on the iroh 1.0 family and implements
BLAKE3-verified blob transfer, but its documentation still labels the current
release as not yet production quality
([docs.rs iroh-blobs Cargo.toml.orig](https://docs.rs/crate/iroh-blobs/latest/source/Cargo.toml.orig)).

**Do not design one sidecar binary to accommodate both Garazyk Track A (iroh 1.x)
and Streamplace Track B (iroh 0.9x ecosystem).** If Track B is ever implemented,
use a **separate executable/crate** whose dependency graph follows the
Streamplace implementation being tested.

### Track A (Garazyk CA/VOD)

Use a dedicated Rust crate/binary with an **exactly locked iroh 1.x + compatible
iroh-blobs dependency graph**.

For the lab exception, the current 1.x ecosystem is preferable to deliberately
starting new work on legacy iroh 0.35 or 0.9x. Promotion beyond lab status
requires a separate dependency-maturity review — upstream's "use 0.35 for
production" guidance is not an attractive 2026 architectural choice given relay
EOL and lack of further 0.35 releases.

### Track B (Streamplace live)

If approved, options include:

- consume or vendor `iroh-streamplace`;
- reproduce `/iroh/streamplace/1` wire semantics against a compatible iroh build;
- wait for Streamplace to move to iroh 1.x;
- or document that Garazyk does not support Streamplace's live iroh mesh.

No assumption that Streamplace 0.9x interoperates with iroh 1.x merely because
both are named iroh.

---

## 5. Ticket and origin semantics

The term `irohTicket` must **not** acquire multiple incompatible meanings.

**Streamplace (unchanged):**

```text
place.stream.broadcast.origin.irohTicket = Streamplace-compatible NodeTicket
```

**Garazyk CA/VOD:** do not store a `BlobTicket` in a field operators may read as
Streamplace-compatible.

[Iroh ticket documentation](https://docs.iroh.computer/concepts/tickets) recommends
`EndpointID` + address lookup over long-lived tickets when the application already
has a coordination server. ATProto origins are that coordination plane. Tickets
contain immediate dial information (including IP addresses), are reusable, and
go stale.

Preferred Track A identity model:

```text
content identity:   CA CID  ↔  (explicit tested conversion)  ↔  32-byte BLAKE3 root
provider identity:  stable iroh EndpointID
optional bootstrap: EndpointTicket (short-lived hint only)
```

Future Garazyk-specific origin fields should prefer explicit names such as
`irohEndpointId` and `irohEndpointTicket` rather than overloading `irohTicket`
as `NodeTicket | EndpointTicket | BlobTicket`. Ticket type must not be inferred
contextually.

---

## 6. Track A architecture

```text
jelcz
  ├─ provider index
  ├─ CA mirror resolver (verifies expected CID/hash before CA-store commit)
  └─ iroh mirror adapter
       │ local IPC only (UDS preferred)
       ▼
jelcz-iroh-blobs-sidecar          ← separate binary/crate from Track B
  ├─ iroh Endpoint (1.x)
  ├─ iroh-blobs provider / requester
  └─ sidecar-owned blob staging (not CA authority)
```

Rules:

- Sidecar may return or stage candidate bytes; it does not commit to the CA store.
- MediaCore remains free of iroh link dependencies.
- Sidecar independently restartable and optional.
- If absent or disabled: HTTPS mirror behavior unchanged.

Suggested ownership:

```text
tools/jelcz-iroh-blobs-sidecar/       Track A — iroh 1.x only
tools/jelcz-streamplace-iroh-bridge/  Track B — only if Phase 5 approved
```

---

## 7. IPC contract

Prefer Unix-domain sockets. If loopback TCP is used, bind to loopback only.

**Do not** use `GET /peer/blob?cid=&ticket=`. Query strings leak tickets into
logs; tickets are reusable and may contain direct addresses.

The primary threat is **attacker-directed network egress and resource exhaustion
through valid iroh dialing information**, not classic HTTP SSRF via URL fetch.

Illustrative versioned API:

```text
GET  /v1/health
GET  /v1/identity

POST /v1/fetch
POST /v1/offer
```

Example `POST /v1/fetch` body:

```json
{
  "cid": "<garazyk-ca-cid>",
  "provider": {
    "endpointId": "<iroh-endpoint-id>",
    "endpointTicket": "<optional-bootstrap-ticket>"
  }
}
```

Flow:

```text
CID → decode/validate hash algorithm → iroh Hash
    → fetch from allowed provider identity only
    → enforce byte/time/concurrency limits
    → candidate bytes → Garazyk resolver verification → CA store
```

Do not send a `BlobTicket` merely to duplicate information already represented by
the CA CID unless experimentation proves it materially simplifies the system.

For large VOD objects, a lab HTTP body API must not automatically become the
production API without measuring copying, duplicate storage, and range behavior.

---

## 8. CID ↔ iroh hash mapping (prerequisite)

Both systems use BLAKE3; external string forms are **not** interchangeable until
fixture-proven.

Before network work, create cross-language fixtures:

```text
known bytes → Garazyk CA encoder → DASL/BDASL CID
           → decode multibase/multicodec → 32-byte BLAKE3 digest
           → iroh_blobs::Hash
```

Reverse-check: iroh hash → raw 32 bytes → Garazyk expected digest.

Required cases: empty object; small binary; multi-chunk object; malformed CID;
wrong hash algorithm; correct bytes under wrong expected CID.

This fixture is the contract between ObjC and Rust. Complete **before** NAT or
peer-discovery work.

---

## 9. Security model

Untrusted input: ATProto origin records with attacker-controlled provider fields.

| Risk | Control |
| --- | --- |
| Unauthorized auto-peering | Consent / `JELCZ_P2P_ALLOWED_*` before dial |
| Attacker-directed egress | Parse only expected iroh types; never treat tickets as generic URLs |
| Resource exhaustion | Connection, request, byte, stream, concurrency limits |
| Stale addressing | Prefer EndpointID lookup; tickets as hints only |
| IP/address disclosure | Document that endpoint tickets may contain direct addresses |
| Ticket logging | No query-string tickets; redact structured logs |
| Corrupt/mismatched content | Verify expected Garazyk CID after transfer |
| Sidecar exposure | UDS or strict loopback; authenticate if host isolation insufficient |
| Dependency/protocol drift | Exact Cargo lock + interop fixtures |

Endpoint/Node tickets are not automatically secret capabilities — they carry
reusable reachability information. Authorization remains application-level
([iroh tickets](https://docs.iroh.computer/concepts/tickets)).

---

## 10. Implementation sequence (S-prefix)

Use `S` prefixes to avoid confusion with WS16 phase numbers and phase-35 slice
numbers.

| Step | Work | Exit evidence |
| --- | --- | --- |
| **S0 — governance** | Record Track A lab exception; update phase-35/WS16 | ADR/decision link |
| **S1 — contracts** | Freeze Track A provider identity, ticket semantics, IPC version, dependency pin | Decision note + schema |
| **S2 — hash fixture** | Prove CID ↔ 32-byte BLAKE3 ↔ iroh Hash | Cross-language tests |
| **S3 — local sidecar** | iroh 1.x endpoint + iroh-blobs provider/requester | Rust integration test |
| **S4 — IPC adapter** | UDS/loopback service + ObjC `ATProtoCAMirrorFetching` adapter | Local fetch smoke |
| **S5 — integrity path** | Sidecar result → resolver → verified CA put | Wrong-CID rejection test |
| **S6 — configuration** | Default-off `JELCZ_P2P` / sidecar endpoint + docs | HTTPS-only unchanged |
| **S7 — two-node lab** | Two jelcz nodes exchange CA object via iroh | Dated demo log |
| **S8 — announce** | Optional stable EndpointID/bootstrap in Garazyk origin | Round-trip origin test |
| **S9 — security/limits** | Dial gating, limits, redaction, malformed input | Negative test suite |
| **S10 — measurement** | HTTPS vs P2P hit/miss, bytes, relay/direct | Lab measurement table |
| **S11 — closeout** | Record what was proved vs production-gated | WS16/phase-35 update |

**Track B is not S12.** Streamplace live opens as a separate work package after an
explicit compatibility decision. Minimum acceptance:

```text
real Streamplace origin → real irohTicket parsed → peer reached
→ /iroh/streamplace/1 negotiated → Subscribe(real streamer DID)
→ real MUXL segment received → segment validation succeeds
```

Parsed ticket, generic iroh connection, or successful `iroh-blobs` transfer alone
does **not** satisfy this gate.

---

## 11. Promotion gates

### Track A: lab complete

- Governance exception recorded
- Hash mapping fixture-tested
- Two jelcz processes transfer a CA object
- Garazyk rejects wrong bytes/CID mismatches
- HTTPS fallback with sidecar disabled
- Security limits and consent gating exercised
- Evidence notes direct vs relayed transfer where possible

### Track A: production supported

Requires production CA VOD, measured cache misses/bandwidth, demonstrated P2P
benefit, accepted iroh-blobs version, relay/discovery ops plan, and load-tested
fallback — in addition to lab complete.

### Track B: Streamplace compatible

Requires the full custom-protocol acceptance test against an actual Streamplace
implementation.

---

## 12. Recommended maintainer decisions

| ID | Decision | Recommendation |
| --- | --- | --- |
| A | Governance | Approve narrow Track A lab exception |
| B | Architecture | Two binaries/crates; never one multi-protocol sidecar |
| C | Origin semantics | Reserve Streamplace `irohTicket` for NodeTicket; Garazyk uses EndpointID + CID + optional bootstrap ticket field |
| D | Dependencies | Lab: locked iroh 1.x / compatible iroh-blobs; production: separate maturity gate |

---

## 13. Final recommendation

Proceed with **Track A only** under the lab exception.

Prove:

```text
ATProto provider discovery + stable iroh provider identity
+ Garazyk CID ↔ BLAKE3 mapping + iroh-blobs transport
+ existing Garazyk integrity verification + HTTPS fallback
```

Do **not**:

- make the prototype solve Streamplace live replication;
- overload Streamplace's `irohTicket` field;
- constrain Track A to iroh 0.9x for hypothetical Streamplace compatibility;
- treat Streamplace live as an extension of the Track A daemon.

Streamplace live support is a separate bridge whose acceptance criterion is
byte-level interoperability with `/iroh/streamplace/1`.

P2P still has to **earn** production complexity with real VOD measurements before
it becomes a supported production path.

---

## Sources

### In-repo (verified 2026-08-13)

- `docs/plans/prompts/phase-35-ws16-iroh-sidecar.md`
- `docs/plans/workstreams/16-jelcz-p2p-peership.md`
- `docs/plans/workstreams/12-content-addressed-video.md` (Phase 11 gate)
- `docs/adr/0036-content-addressed-video-distribution.md`
- `docs/adr/0038-jelcz-p2p-layering.md`
- `Garazyk/Sources/MediaCore/ATProtoCAMirrorResolver.h`
- `Garazyk/Resources/lexicons/**/origin.json`

### External

- [Streamplace syndication blog](https://blog.stream.place/3m3ngytdrws2k)
- [place.stream.broadcast.origin lexicon](https://stream.place/docs/lex-reference/broadcast/place-stream-broadcast-origin/)
- [streamplace/iroh-streamplace](https://github.com/streamplace/streamplace/tree/next/rust/iroh-streamplace)
- [Iroh 1.0 announcement](https://www.iroh.computer/blog/v1)
- [Iroh tickets](https://docs.iroh.computer/concepts/tickets)
- [Iroh blobs protocol](https://docs.iroh.computer/protocols/blobs)
- [iroh 1.0.3 on docs.rs](https://docs.rs/crate/iroh/latest)
- [iroh-blobs 0.103.0 on docs.rs](https://docs.rs/crate/iroh-blobs/latest/source/Cargo.toml.orig)

### Not fully reached

- GitHub code search API (401) — used raw `next` tree URLs
- Live public/staging Streamplace origins with real `irohTicket` samples
- Exhaustive Go call-site trace (syndication flow characterized from Streamplace `next`)
- [mfzx.net iroh-with-atp draft](https://mfzx.net/drafts/iroh-with-atp) (WS16 reference; not re-fetched)
