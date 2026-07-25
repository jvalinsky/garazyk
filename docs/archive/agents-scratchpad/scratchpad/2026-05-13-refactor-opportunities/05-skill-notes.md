# Refactor Opportunity Audit Skill Notes

Date: 2026-05-13

Deciduous:
- Skill action node: 1581
- Skill outcome node: 1585
- Attached documents: 67, 68, 71

## Decision

Create `.agents/skills/refactor-opportunity-audit/SKILL.md`.

Reason:
- The investigation produced a reusable workflow: equal-surface inventory, metaplans, common scoring, scanner inputs, deep dives, ranked roadmap, and deciduous/scratchpad linking.
- This pattern is broader than one review and should be reusable before future large refactor research.

## Skill Scope

The skill should be used when the user asks for:
- deep refactor research,
- whole-repo code review for refactoring opportunities,
- evidence-backed architecture roadmap,
- decision-tracked technical debt investigation,
- metaplans for code archaeology.

## Skill Workflow

1. Create a scratchpad directory named by date and topic.
2. Record a deciduous goal from the exact user prompt.
3. Inventory every major repo surface before ranking.
4. Use a consistent scoring rubric.
5. Run or inspect relevant audit skills and reports.
6. Write deep dives only for candidates that survive initial scoring.
7. Produce a ranked roadmap with tests and rollback notes.

## Guardrails

- Do not implement refactors during the research pass.
- Do not overwrite user work.
- Treat generated reports as inputs, not final truth.
- Use external specs only for contract-sensitive surfaces.
- Prefer behavior-level recommendations over large file-by-file churn lists.
