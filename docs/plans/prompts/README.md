---
title: Phase Execution Prompts
last_verified: 2026-08-20
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
| 35 | [phase-35](phase-35-ws16-iroh-sidecar.md) | WS16 Track A — jelcz iroh-blobs sidecar (CA/VOD) | `blocked` — S9 complete; S10 measurement and S11 closeout require Docker disk headroom | — |
| 36 | [phase-36](phase-36-ws16-streamplace-iroh-bridge.md) | WS16 Track B — Streamplace live iroh bridge | `blocked` — Phase 35 completion + dated pinned-image Scenario 101 | 35 |
| 38 | [phase-38](phase-38-governed-backlog-closeout.md) | Parallel WS10 S2PA and WS11 Mikrus/Beskid acceptance closeout | `complete` — scoped implementations and acceptance evidence landed 2026-08-20 | — |

**Suggested order:** when Phase 35's input arrives, run its S10 fresh-miss/warm-hit
measurement in a fresh Track A lab, finish S11 closeout, then execute Phase 36
Scenario 101.

Phase 5 cannot start until a future maintainer message explicitly reopens JSR
publication. Workstream 03 R1 source synchronization is complete without
publication; one no-setup runtime compatibility check remains pending because
the local service topology is unavailable under current disk headroom.
