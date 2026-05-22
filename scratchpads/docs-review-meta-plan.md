# Documentation Review Meta Plan

Date: 2026-05-22

## Goal

Review repository documentation for accuracy, ownership, redundancy, and usefulness. Produce a tracked backlog of docs to update, delete, merge, or keep, with scratchpad evidence linked from the deciduous graph.

## Tracking model

Use deciduous as the durable index. Use scratchpad files for temporary notes, mini-prompts, inventories, and evidence that are too detailed for graph node descriptions.

Graph shape:

```text
goal: Documentation review and cleanup
  -> action: Inventory documentation surfaces
  -> action: Classify docs by status
  -> decision: Choose update/delete/merge/keep criteria
  -> action: Draft targeted fixes or deletion list
  -> outcome: Review backlog with evidence links
```

Attach scratchpads to nodes with:

```bash
deciduous doc attach NODE_ID scratchpads/docs-review-meta-plan.md
deciduous doc attach NODE_ID scratchpads/docs-review-mini-prompts.md
```

For each substantial finding, add or link a node:

```bash
deciduous add action "Assess docs/<area> docs" -f "docs/<area>" -c 80
deciduous link GOAL_ID ACTION_ID -r "Part of documentation review"
deciduous doc attach ACTION_ID scratchpads/docs-review-<area>.md
```

## Phases

### 1. Inventory

Create a machine-generated inventory of docs and doc-like files:

- README, AGENTS, CONTRIBUTING, ops notes, deployment docs.
- `docs/`, `.agents/`, `.opencode/workflows/`, `scripts/` docs, scenario docs.
- Markdown embedded near source areas.
- Generated or historical docs that may no longer be authoritative.

Scratchpad output: `scratchpads/docs-review-inventory.md`.

### 2. Triage criteria

Classify each document with one primary status:

- **Keep**: current, owned, referenced, and useful.
- **Update**: useful but stale, incomplete, or mismatched with current commands/code.
- **Merge**: overlaps another doc; preserve unique content elsewhere.
- **Delete**: obsolete, misleading, orphaned, or superseded.
- **Archive**: historically useful but not operational guidance.

Capture rationale, evidence, owner/source area, and proposed action.

### 3. Evidence checks

For docs marked update/delete/merge, verify against code or current commands before recommending action:

- Build/test commands and service-control instructions.
- Docker/local-network docs.
- Deployment and ops docs.
- XRPC/lexicon coverage docs.
- Scenario runner docs.
- Admin UI docs.
- Agent/workflow instructions.

### 4. Mini-prompt passes

Run focused review passes using `scratchpads/docs-review-mini-prompts.md`:

- Staleness pass.
- Duplicate/overlap pass.
- Dangerous instruction pass.
- Missing owner/path pass.
- User journey pass.

Store pass outputs in separate scratchpads and attach them to related deciduous nodes.

### 5. Backlog and decisions

Create a final review backlog with sections:

| Path | Status | Evidence | Proposed change | Risk | Deciduous node |
| --- | --- | --- | --- | --- | --- |

Record decisions in deciduous when choosing between delete/merge/update. Link decisions back to the original goal and attach evidence scratchpads.

### 6. Execution plan

After review, implement in small batches:

1. Delete or archive clearly obsolete docs.
2. Merge duplicates.
3. Update high-risk operational docs.
4. Update developer workflow docs.
5. Run link checks, command checks, and relevant tests.

## Definition of done

- Inventory exists and is linked from deciduous.
- Each update/delete/merge recommendation has evidence.
- Final backlog maps every recommendation to a deciduous node.
- Any changed docs are checked for broken links and stale commands.
- Outcome node summarizes completed changes and remaining follow-up.
