---
name: using-deciduous
description: Use when tracking development goals, decisions, actions, outcomes, archaeology pivots, and scratchpad links in the deciduous decision graph.
---

# Deciduous: Decision Graph for AI Development

Use this skill to track goals, decisions, and outcomes in the `deciduous` graph.

## Core Commands

| Action | Command |
|--------|---------|
| Start goal | `deciduous add goal "Title" -d "Description" -c 90` |
| Record action | `deciduous add action "Doing X" -f "files" -c 85` |
| Link nodes | `deciduous link FROM TO -r "Reason"` |
| Update status | `deciduous status NODE_ID completed/pending/in_progress` |
| Log outcome | `deciduous add outcome "Results" --commit HEAD -c 95` |

## Archaeology Patterns

Use `deciduous archaeology pivot FROM_ID "Observation" "New Approach"` to document course corrections.

## Scratchpad Integration

Link major goals and decisions to scratchpad plans using `deciduous doc attach NODE_ID path/to/plan.md`.
