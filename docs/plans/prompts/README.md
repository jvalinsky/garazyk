---
title: Phase Execution Prompts
last_verified: 2026-08-13
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
agent: worker           # recommended Codex built-in role (default | worker | explorer)
depends_on: []          # phase numbers that must be complete first
```

A driver (human, the primary Codex agent, or a delegated worker) repeats:

1. Pick the lowest-numbered phase whose `status` is `pending` or
   `in-progress` and whose `depends_on` phases are all `complete`. Skip
   `blocked` phases: they resume only when the input named under their
   `## Blocked on` heading has actually arrived (then reset them to
   `in-progress` with a note recording the unblock). A dependency that is
   `blocked` does not satisfy `depends_on`; if every remaining phase is
   blocked, stop and report rather than looping.
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
  execution requires separate git worktrees.
  **Before starting any mutating phase, run `git status`; if another
  phase's uncommitted changes are present, commit or coordinate first —
  never fold two phases into one commit.**
- Frontmatter must stay one valid YAML block: only the declared keys
  (`phase`, `title`, `status`, `agent`, `depends_on`, optionally
  `last_updated`/`completed_at`/`commit`). Progress notes belong in a
  `## Progress` body section, never in frontmatter.
- Set `status: in-progress` only together with a body note saying what
  started; a bare status flip with no recorded work gets reset to
  `pending` on review.
- A phase agent updates plan state in the same change as its code, per the
  plan-governance rules in [../README.md](../README.md).
- When all phases are complete, delete this directory; the ledger and Git
  history retain it.

Use `worker` for implementation-heavy phases, `explorer` for read-only
investigation, and `default` for mixed planning, decisions, and execution.
These are Codex built-in agent types; project audit roles live under
`.codex/agents/` and are delegated separately when a phase needs them.

## Phase index

Completed prompts are archived under
[`docs/archive/planning/phase-prompts/`](../../archive/planning/phase-prompts/README.md)
(including phase 30 Admin UI extraction). Open prompts:

| # | File | Focus | Status | Depends on |
| - | ---- | ----- | ------ | ---------- |
| 5 | [phase-05](phase-05-repo-boundaries.md) | Deno repo extraction and package publication | `blocked` — maintainer must lift the publication deferral | — |
| 31 | [phase-31](phase-31-s2pa-ingredient-verify.md) | S2PA ingredient `validationResults` + embedded-manifest verify | `complete` | — |
| 32 | [phase-32](phase-32-s2pa-merkle-bmff.md) | S2PA `c2pa.hash.bmff.v3` Merkle trees | `complete` | — |
| 33 | [phase-33](phase-33-s2pa-soft-binding-algs.md) | Soft-binding algorithm compute/verify | `complete` | — |
| 34 | [phase-34](phase-34-dasl-tiles-package-and-embed.md) | Deno tiles package + live Admin UI embed | `complete` | — |
| 35 | [phase-35](phase-35-ws16-iroh-sidecar.md) | WS16 iroh sidecar + live Streamplace mesh | `blocked` — production CA VOD or lab exception | — |
| 37 | [phase-37](phase-37-zuk-cursor-containment.md) | Zuk omitted-cursor correctness and replay-loop containment | `blocked` — implementation/scenario green; unrelated global gates red | — |
| 38 | [phase-38](phase-38-zuk-bounded-ingress.md) | Byte-bounded ingress, ordered processing, and socket backpressure | `pending` | 37 |
| 39 | [phase-39](phase-39-zuk-durable-replay.md) | Segmented disk replay and durable output sequence | `pending` | 38 |
| 40 | [phase-40](phase-40-zuk-validation-efficiency.md) | P-256/k256 validation and bounded identity resolution | `pending` | 38 |
| 41 | [phase-41](phase-41-zuk-admission-observability.md) | Crawl quotas, authoritative health, NixOS resource guardrails | `pending` | 38 |
| 42 | [phase-42](phase-42-zuk-production-canary.md) | `bingus` 24-hour resource canary, rollback, and closeout | `pending` | 37–41 |

**Suggested order:** phases 37–38 are P0 incident containment and may proceed
in an isolated worktree without waiting for the independently blocked Phase
35 feature lane. Then run 39; phases 40 and 41 both depend on 38 but are
serialized by the ordinary lowest-phase loop; Phase 42 closes only after all
five implementation phases. Phases 31–34 are complete.

Phase 5 cannot start until a future maintainer message explicitly reopens JSR
publication. Workstream 03 R1 source synchronization is complete without
publication; one no-setup runtime compatibility check remains pending because
the local service topology is unavailable under current disk headroom.
