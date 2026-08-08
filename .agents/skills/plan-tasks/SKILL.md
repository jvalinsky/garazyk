---
name: plan-tasks
description: Read Garazyk's current plans fresh and summarize remaining governed work. Use for roadmap, progress, phase status, or “what next” requests.
---

# Plan Tasks

`docs/plans/mega-plan.md` is the only repository-wide backlog. Workstreams
hold execution detail; phase prompts are derived and lose on disagreement. This
skill is client-neutral: Claude, Codex, Letta, and human reviewers use the same
read-only procedure.

## Read fresh, never cache

For every invocation, read in order:

1. `docs/plans/README.md`
2. `docs/plans/mega-plan.md`
3. every active `docs/plans/workstreams/*.md`
4. the YAML frontmatter and `## Blocked on` sections of every live
   `docs/plans/prompts/phase-*.md`

Do not read `docs/archive/planning/` to reconstruct a backlog. An active
summary that points there is authoritative; an apparent omission is an active
plan defect to report, not a reason to revive archived task text.

`deciduous pulse` is optional corroboration only. The graph is decision history,
not the backlog. When it disagrees with plans, name the discrepancy rather than
silently selecting either source.

## What to report

Include a row when a live phase is not `complete`, a workstream explicitly
describes remaining/open/blocked/follow-up work, or a mega-plan item lacks a
Complete/Closed disposition. Exclude completed material unless its active
summary explicitly names residual scope.

Use the mega plan's priority model verbatim when it covers an item. Otherwise:

- **Blocked**: waiting for named external input or maintainer decision.
- **P0**: security, crash, integrity, or release-gate risk.
- **P1**: current protocol correctness or a core active phase.
- **P2**: structural cleanup with no blocked dependency.

Return exactly one table:

| Source | Task | Status | Priority | Codebase impact |
| --- | --- | --- | --- | --- |

Then state which rows specifically need a human decision and identify the
lowest-order unblocked actionable phase. Do not create graph nodes, edit plan
files, or run implementation gates while answering a status question.
