---
title: Phase Execution Prompts
last_verified: 2026-07-16
---

# Phase Execution Prompts

Self-contained agent prompts that execute the remaining mega-plan work.
These are **derived execution prompts, not plans**: the
[mega plan](../mega-plan.md) and workstreams stay authoritative. If a prompt
and a workstream disagree, the workstream wins and the prompt gets fixed.

## Loop protocol

Each phase file has frontmatter:

```yaml
phase: 3                # ordering
status: pending         # pending | in-progress | complete | blocked
agent: claude           # recommended agent type (claude | Plan | Explore)
depends_on: []          # phase numbers that must be complete first
```

A driver (human, `/loop`, or a spawned agent) repeats:

1. Pick the lowest-numbered phase whose `status` is not `complete` and whose
   `depends_on` phases are all `complete`.
2. Set `status: in-progress`. Read the phase file and every source it lists
   before writing code.
3. Execute one coherent slice at a time. Run the mega plan's global gates
   plus the phase's acceptance gate. Commit per the repo's conventions.
4. On finishing the phase: record evidence (commit hashes, dated structured
   runs) in the relevant workstream/mega-plan entries, then set
   `status: complete` here.
5. On hitting a human checkpoint: set `status: blocked`, write what is
   needed under a `## Blocked on` heading in the phase file, and stop.

Rules:

- Never run two mutating phases concurrently in one worktree. Parallel
  execution requires separate git worktrees (phases 1-5 are independent).
- A phase agent updates plan state in the same change as its code, per the
  plan-governance rules in [../README.md](../README.md).
- When all phases are complete, delete this directory; the ledger and Git
  history retain it.

## Phase index

| # | File | Focus | Depends on |
| - | ---- | ----- | ---------- |
| 1 | [phase-01](phase-01-browser-baseline.md) | Browser smoke baseline (closes mega Phase 0) | — |
| 2 | [phase-02](phase-02-spaces-acceptance.md) | Permissioned spaces multi-PDS acceptance | — |
| 3 | [phase-03](phase-03-xrpc-truth-and-spec-matrix.md) | Truthful XRPC metrics + spec conformance matrix | — |
| 4 | [phase-04](phase-04-federation-lifecycle.md) | Backpressure, adversarial ingress, account lifecycle, gated CI | — |
| 5 | [phase-05](phase-05-repo-boundaries.md) | Deno repo extraction and package publication | — |
| 6 | [phase-06](phase-06-nsid-and-cli-adoption.md) | Generated NSID constants + CLI/lifecycle adoption | 3 |
| 7 | [phase-07](phase-07-relay-and-sync.md) | Relay product decision + incremental public sync | 4 |
| 8 | [phase-08](phase-08-admin-ui.md) | Admin UI accessibility and structural cleanup | 1 |
| 9 | [phase-09](phase-09-spaces-hardening.md) | Space key rotation, ops readiness, attestation decision | 2 |
| 10 | [phase-10](phase-10-deferred-products.md) | WASM baseline + SMTP/blob/STAR decisions + drift cadence | — |
