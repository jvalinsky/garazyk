---
name: refactor-opportunity-audit
description: Use when performing evidence-backed refactor research, whole-repo technical-debt review, architecture archaeology, or decision-tracked refactor roadmap planning.
---

# Refactor Opportunity Audit

Use this skill to find and rank refactor opportunities without immediately changing implementation code.

## Workflow

1. Create a dated scratchpad directory for the investigation.
2. Record a deciduous goal with the exact user prompt and attach the methodology scratchpad.
3. Write metaplans before deep reading:
   - core implementation,
   - tests,
   - UI/frontend,
   - scripts/tooling,
   - docs/reports,
   - any embedded runtimes or side projects.
4. Inventory every major surface before ranking.
5. Score candidates consistently:
   - boundary risk,
   - structural drag,
   - test leverage,
   - change safety,
   - refactor payoff.
6. Deep-dive only the highest-scoring candidates.
7. Produce a ranked roadmap with characterization tests, staging, and rollback notes.
8. Add deciduous action/outcome nodes and attach scratchpads.

## Evidence Sources

Prefer repo truth over guesses:

```bash
rg --files
rg -n "TODO|FIXME|not implemented|not_implemented|placeholder|stub|HACK|temporary"
rg -n "componentsSeparatedByString:|substringFromIndex:|sqlite3_exec|sqlite3_prepare|dispatch_sync|@synchronized|innerHTML|onclick=|rm -rf|Authorization|Bearer"
```

Use project-specific audit skills when available:

```bash
./.agents/skills/objc-architecture-audit/scripts/run_architecture_audit.sh . /tmp/refactor-architecture-audit
./.agents/skills/objc-concurrency-audit/scripts/run_concurrency_audit.sh . /tmp/refactor-concurrency-audit
./.agents/skills/objc-security-audit/scripts/run_all_security_scans.sh . /tmp/refactor-security-audit
```

## Output Template

Write these scratchpads:

- `00-methodology.md`
- `01-inventory-matrix.md`
- `02-risk-scores.md`
- `03-deep-dives.md`
- `04-ranked-roadmap.md`
- `05-skill-notes.md`

Each top candidate should include:

- evidence,
- why it matters,
- proposed refactor boundary,
- required characterization tests,
- staging and rollback notes,
- confidence.

## Guardrails

- Do not implement the refactors during the research pass.
- Do not overwrite dirty user work.
- Generated reports are inputs, not proof.
- Prefer small, staged extraction plans over big-bang rewrites.
- If external protocol contracts are involved, verify current primary specs and cite them in the methodology.
