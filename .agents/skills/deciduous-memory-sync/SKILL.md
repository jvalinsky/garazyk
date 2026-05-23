---
name: deciduous-memory-sync
description: Bidirectional sync between Letta agent memory and the deciduous decision graph. Push knowledge from memory files (preferences, reference docs) into deciduous nodes; pull graph state back into memory reference docs. Use when syncing project context, recovering from context loss, onboarding new sessions, or after completing work that should be reflected in the decision graph.
---

# Deciduous ↔ Letta Memory Sync

Keep the deciduous decision graph and Letta agent memory in sync. Memory holds accumulated project knowledge; deciduous holds the structured decision trail. This skill bridges them so neither system becomes stale.

## When to Sync

| Trigger | Direction | What happens |
|---------|-----------|--------------|
| After completing a phase of work | Push | Memory preferences/reference docs → deciduous goal/decision/outcome nodes |
| Starting a new session or recovering context | Pull | deciduous graph state → memory reference docs |
| After a major architecture decision | Push | Record the decision in deciduous with links to memory reference docs |
| When memory and deciduous seem out of date | Status | Dry-run comparison showing what would sync |

## Quick Reference

```bash
# Push: Letta memory → deciduous
deno run -A .agents/skills/deciduous-memory-sync/scripts/sync.ts push

# Pull: deciduous → Letta memory
deno run -A .agents/skills/deciduous-memory-sync/scripts/sync.ts pull

# Dry-run (show what would change without modifying anything)
deno run -A .agents/skills/deciduous-memory-sync/scripts/sync.ts push --dry-run
deno run -A .agents/skills/deciduous-memory-sync/scripts/sync.ts status
```

## What Gets Synced

### Push (memory → deciduous)

Source files in `$MEMORY_DIR`:

| File | Extracted as |
|------|-------------|
| `system/human/preferences.md` | `### Section (status)` headers → goals/decisions; `- **Phase X**: ...` bullets → decisions |
| `reference/*.md` | `## Header` patterns → goals/decisions; `### Category X:` patterns → decisions; priority table rows → goals |

All synced nodes are tagged with the `letta-sync` theme for traceability.

Deduplication: nodes with matching titles are updated (status changes) rather than re-created.

### Pull (deciduous → memory)

| Output file | Content |
|-------------|---------|
| `reference/deciduous-graph-state.md` | Active goals with linked decisions, recent decisions/outcomes, completed goals |
| `reference/deciduous-pulse.md` | Output of `deciduous pulse --summary` |

These files are auto-generated — do not edit them manually. They get overwritten on each pull.

## Manual Sync Patterns

For fine-grained control, use the deciduous CLI directly:

### Record a completed phase from memory

```bash
# Create goal → decision → action → outcome chain
deciduous add goal "Title from memory" -d "Description" -c 90
deciduous add decision "Chosen approach" -d "Why" -c 85
deciduous link GOAL_ID DECISION_ID -r "chosen approach"
deciduous add action "What was done" --commit HEAD -c 85
deciduous link DECISION_ID ACTION_ID -r "implementing"
deciduous add outcome "Results" -c 95
deciduous link ACTION_ID OUTCOME_ID -r "implementation result"
```

### Attach a memory reference doc to a node

```bash
deciduous doc attach NODE_ID "$MEMORY_DIR/reference/some-doc.md" -d "Description"
```

### Update node status from memory

```bash
deciduous status NODE_ID completed  # or: active, pending, rejected
```

### Record a pivot (approach changed)

```bash
deciduous archaeology pivot OLD_ID "What was learned" "New approach" -c 80
```

## Sync Script Details

See `scripts/sync.ts` for the full implementation. Key behaviors:

- **Deduplication**: Matches nodes by title; updates status instead of creating duplicates
- **Theme tagging**: All pushed nodes get the `letta-sync` theme
- **Doc attachment**: Reference docs are attached to nodes whose titles match the doc topic
- **Pull overwrites**: `reference/deciduous-graph-state.md` and `reference/deciduous-pulse.md` are regenerated each pull
- **Dry-run**: `--dry-run` flag on push/pull shows what would change without modifying either system

## Workflow: After Completing Work

1. Update memory files (preferences, reference docs) with what was done
2. Commit and push memory changes
3. Run `sync.ts push` to reflect the work in deciduous
4. Run `deciduous status NODE_ID completed` for any finished goals

## Workflow: Recovering Context

1. Run `sync.ts pull` to get current graph state into memory
2. Read `reference/deciduous-graph-state.md` for active goals and recent decisions
3. Run `deciduous pulse` for a quick health check
4. Use `deciduous show ID` to drill into specific nodes
