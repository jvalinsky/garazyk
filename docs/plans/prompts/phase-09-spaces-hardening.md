---
phase: 9
title: Permissioned spaces production hardening
status: pending
agent: claude
depends_on: [2]
---

# Phase 9: Permissioned spaces production hardening

## Mission

Take permissioned spaces from "acceptance-proven" (phase 2) to
"operator-ready": dedicated signing key rotation, operational drills and
observability, and the app-attestation decision. Gated on phase 2 because
the current key fallback must be proven end-to-end before rotating away
from it.

## Read first

- `docs/plans/workstreams/06-permissioned-spaces.md` (P6.2, P6.3, P6.5 —
  authoritative)
- `docs/adr/0004-experimental-permissioned-spaces.md` (key fallback,
  attestation rejection rationale, rollback semantics)
- `docs/permissioned-spaces-compatibility.md` (DID-resolution row)

## Scope

1. **P6.2 dedicated key** — design first, as an ADR amendment: independent
   `#atproto_space` key generation, PLC rotation operation, credential
   issuance cutover, old-credential expiry window; operator tooling for
   migrating existing DIDs (the PDS never rewrites a DID document
   implicitly); verification against both key layouts during overlap.
2. **P6.5 ops readiness**: backup/restore drill (space DB + WAL onto a
   fresh instance, LtHash/commit verification green for every restored
   repo); verify disable-flag rollback retains data and a downgraded
   binary never deletes it; structured counters/logs for replay attempts,
   gap detections, recovery-path choice, pruned revisions.
3. **P6.3 attestation** — decision brief only: implement full end-to-end
   attestation validation vs keep configuration rejected until upstream
   standardizes. A structural-only check is not an option. Set
   `status: blocked` and present the brief — **the choice needs the
   operator**; record the outcome as an ADR amendment. Implement only if
   option 1 is chosen, as its own slice.

## Constraints

- Observability additions must not change protocol behavior.
- Credentials and delegation tokens are never logged (ADR 0004 invariant).

## Acceptance gate

- Rotation design ADR merged; rotation exercised in a test topology with
  both key layouts verified during overlap.
- Restore drill documented with dated evidence; downgrade-retention test.
- Metrics visible without reading SQLite; global gates + space suites
  green.

## On completion

Update workstream 06 P6.2/P6.3/P6.5, compatibility DID row, mega-plan
Phase 4 items 5-6 and Phase 5 item 4; set `status: complete` here.
