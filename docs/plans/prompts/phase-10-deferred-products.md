---
phase: 10
title: Deferred products, WASM baseline, and drift cadence
status: in-progress
agent: default
depends_on: []
---

# Phase 10: Deferred products, WASM baseline, and drift cadence

## Mission

Clear the "Decision needed" ledger: regenerate the WASM capability
baseline, decide the incomplete product surfaces, and stand up the
recurring Proposal 0016 upstream-drift check. Mostly decision briefs — the
implementation load depends on what the operator chooses.

## Progress

**Slice 1 complete (2026-07-22): P6.4 drift cadence.**
`scripts/check_permissioned_spaces_drift.sh` is the monthly read-only check
for the pinned Proposal 0016 source, atproto PR 5187 implementation commit,
and vendored space lexicons. The first run at `2026-07-22T05:36:04Z` found no
drift: both upstream references remained pinned and all 28 lexicons matched
byte-for-byte. The compatibility document records the source links, response
to a future nonzero result, and the only documentation-only upstream delta.

## Read first

- `docs/plans/workstreams/05-embedded-runtime-and-deferred-products.md`
  (E1, E3 authoritative; E4 stays deferred under ADR 0002)
- `docs/plans/workstreams/06-permissioned-spaces.md` (P6.4)
- `objc-jupyter-wasm/kernel/PARSER_STATUS.md` and the conflicting gap
  reports E1 describes

## Scope

1. **E1 WASM baseline** (`worker` agent): reproducible kernel build from a
   clean checkout; one command running smoke/notebook/compat/runtime-gap
   probes; one generated capability matrix (supported / partial / stub /
   intentionally unsupported / missing); delete or redirect contradictory
   hand-maintained status tables. Only then propose the next supported
   subset — favor notebook + compatibility-corpus behavior over Foundation
   imitation. Subset choice is a human checkpoint.
2. **E3 product surfaces** (`default` agent → human checkpoint): one brief
   covering SMTP delivery, cloud blob copy/delete, STAR reconstruction
   from CAR blocks, Skylab repost/Germ E2EE, dashboard TODO metadata —
   support / experimental / remove for each, with the workstream's rule
   that config must not promise `NotImplemented`. Set `status: blocked`,
   present, then implement the chosen dispositions.
3. **P6.4 drift cadence** (`worker` agent): a documented, repeatable
   monthly re-diff procedure of the pinned Proposal 0016 reference (script
   or runbook), recording deltas and impact into the compatibility doc.
   First run executed as part of this phase.

## Acceptance gate

- Kernel builds reproducibly twice from clean checkouts; matrix generated
  from test results, no hand-maintained contradictions left.
- Every E3 surface has a recorded decision and matching code/config state.
- Drift-check procedure exists, first run recorded; global gates pass.

## On completion

Update workstreams 05 and 06, mega-plan Phase 5; set `status: complete`
here. If all ten phases are complete, delete `docs/plans/prompts/` per the
loop protocol and record the program's completion in the retired-plans
ledger.
