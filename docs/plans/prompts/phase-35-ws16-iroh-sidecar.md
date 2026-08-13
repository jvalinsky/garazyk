---
phase: 35
title: WS16 iroh sidecar and live Streamplace mesh
status: blocked
agent: worker
depends_on: []
---

# Phase 35: WS16 iroh sidecar + live mesh

## Mission

Execute workstream 16 Phases 4–6: iroh sidecar data plane, live ticket
consume/emit, and admin/demo peer-source mix. **No Phase 4+ implementation
until unblockers clear** (or an explicit lab exception is recorded).

## Read first

- [`docs/plans/workstreams/16-jelcz-p2p-peership.md`](../workstreams/16-jelcz-p2p-peership.md)
  — authoritative; Phases 0–3 complete; 4+ blocked
- ADR 0036 (IPFS rejected) and peership ADRs referenced from WS16
- Existing HTTPS demos: `scripts/demo/jelcz_https_mesh_demo.sh`,
  `scripts/demo/streamplace_peership_*.sh`
- Boundary rule: no link-time iroh inside ObjC static libraries; sidecar +
  localhost IPC only

## What is already correct — do not redo

- HTTPS peership, origin announce/retract, peer provider index, Docker lab
- Additive `irohTicket` / `httpsBase` fields on origin records (lexicon)
- Consent allow-lists (`JELCZ_P2P_ALLOWED_*`)

## Blocked on

Named inputs from WS16 (copy kept here so the prompt loop stops correctly):

1. **Production CA VOD** — at least one deployment serving real `/watch` (or
   WS15 compat) traffic so P2P solves a measured cost — **or** an explicit
   operator exception to prototype in lab only (record in ADR + WS16).
2. **Origin bandwidth / cache-miss measurements** — enough to justify sidecar
   complexity vs more HTTPS mirrors / CDN.

When both are satisfied, set this phase to `in-progress`, note the unblock in
`## Progress`, and proceed from Slice 1.

## Slices (after unblock)

### Unblocker record (pre-Slice 1)

#### Slice 0 — Record unblock

Cite production evidence or lab-exception ADR in WS16 `## Blocked on` and
here. Flip status to `in-progress`.

### Phase 4 — Sidecar MVP

#### Slice 1 — Sidecar process

Process wrapping iroh (ticket listen + fetch-by-hash/CID). Place under
`Garazyk/Binaries/` or `tools/`.

#### Slice 2 — IPC contract

Localhost HTTP or UDS API; thin ObjC client. No MediaCore→iroh link deps.

**Acceptance:** `./scripts/dev/check_module_boundaries.sh .` green.

#### Slice 3 — CID / blob mapping

Map CA object or segment identity to iroh fetch; unit + sidecar smoke.

#### Slice 4 — jelcz config

Env/config for sidecar endpoint; document beside existing `JELCZ_PEER_*` vars.

#### Slice 5 — Sidecar demo script

A serves via ticket; B fetches a segment. Sibling to existing peership smokes.

### Phase 5 — Live tickets

#### Slice 6 — Consume Streamplace `irohTicket`

From public/staging origins; dated evidence in WS16.

#### Slice 7 — Optional emit

Publish `irohTicket` on Garazyk origin records when serving via sidecar.

### Phase 6 — Observability + security

#### Slice 8 — Admin / demo peer source

Show `ca-store` / `https-mirror` / `iroh-peer` mix in jelcz admin + demo UI.

#### Slice 9 — Security review

Sidecar attack surface, SSRF via tickets, consent bypass. Delegate
`security_auditor` / `security-auditor` role; record findings.

#### Slice 10 — Plan closeout

WS16 Phases 4–6 → complete with commits + demo evidence; mega-plan note.

## Out of scope while blocked

- Any iroh link-time dependency in ObjC libraries
- Reopening IPFS (ADR 0036)
- Changing the HTTPS fallback path as the default browser serve path

## Acceptance gate (after unblock)

```bash
./scripts/dev/check_module_boundaries.sh .
cmake --build build --target AllTests --parallel 4
./build/tests/AllTests -XCTest 'JelczPeerProviderIndexTests' --gated=run
# plus new sidecar/IPC tests and demo scripts recorded in WS16 Verification
```
