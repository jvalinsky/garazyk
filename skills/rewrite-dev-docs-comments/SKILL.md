---
name: rewrite-dev-docs-comments
description: "Rewrite engineering docs and code comments to remove hype, LLM-isms, filler, and vague claims while preserving verifiable technical facts. Improve Objective-C header docs and implementation comments, and reorganize content into semantically or operationally correct documentation locations. Use when editing READMEs, API docs, runbooks, design docs, migration notes, PR descriptions, or in-code comments."
---

# Rewrite Dev Docs Comments

Produce clear, situationally useful technical writing for maintainers and operators.

## Quick Start
1. Scan candidate text:
```bash
python3 skills/rewrite-dev-docs-comments/scripts/scan_llm_speak.py <path>
```
2. Decide content destination and doc type using `references/doc-organization.md`.
3. For Objective-C public APIs, apply `references/objc-header-docs.md`.
4. Rewrite using `references/rewrite-patterns.md`.
5. Re-scan and manually verify facts against code, config, and tests.

## Rewrite Workflow
1. Preserve facts first.
- Keep APIs, invariants, limits, error behavior, security assumptions, and version details.
- Do not invent claims or remove required warnings.
2. Put information where it belongs.
- `.h`: Document public contracts and caller-visible behavior.
- `.m`: Explain non-obvious rationale, invariants, and hazards near risky logic.
- `docs/how-to` or runbooks: Put step-by-step operational actions and recovery procedures.
- `docs/reference`: Put exhaustive command, schema, and API surface details.
- `docs/explanation` or design docs: Put tradeoffs and architecture reasoning.
3. Organize by reader intent.
- Use tutorial/how-to/reference/explanation distinctions from `references/doc-organization.md`.
- Move misplaced content instead of padding the current file.
4. Remove low-signal language.
- Delete hype words, obvious statements, timeline anchors, and throat-clearing intros.
- Collapse repeated points to one concrete sentence.
5. Make claims testable.
- Replace vague adjectives with measurable detail (latency, complexity, scope, limits, failure modes).
- Prefer exact nouns and verbs over abstractions.
6. Tune tone for peer developers.
- Write directly and impersonally.
- Prefer active voice and short sentences.
- Avoid minimizing language that downplays complexity.
7. Re-evaluate comment necessity.
- Keep comments that explain why, invariants, edge cases, protocol constraints, or non-obvious tradeoffs.
- Remove comments that restate code.
8. Validate.
- Re-scan with `scan_llm_speak.py`.
- Build/test when API contracts, examples, or operator procedures change.
- Ensure commands, paths, and examples still run as written.

## Objective-C Rules
1. Document public symbols at declarations in `.h`.
2. Document contracts, not implementation internals.
3. Include only applicable details:
- Summary sentence.
- Preconditions and postconditions.
- Parameter meaning and units.
- Return value semantics.
- Error behavior (`NSError` domain/codes when known).
- Ownership/lifetime and nullability expectations.
- Threading requirements and side effects.
4. Keep `.m` comments for invariants, lock ordering, parser assumptions, and non-obvious tradeoffs.
5. Match repository comment style; if absent, use templates in `references/objc-header-docs.md`.

## Quality Bar
- Ensure the first sentence contains a non-obvious fact or decision.
- Ensure each paragraph contains at least one concrete detail.
- Delete any sentence that only sounds good but adds no information.
- Ensure each paragraph answers a maintainer or operator question.

## Scope Guidance
- For code comments, optimize for maintainers reading code under time pressure.
- For docs, optimize for implementation and incident-response decisions.
- If detail is unknown, state uncertainty explicitly instead of padding with generic prose.

## Resources
- Scanner: `scripts/scan_llm_speak.py`
- Rewrite patterns and examples: `references/rewrite-patterns.md`
- Objective-C header doc templates: `references/objc-header-docs.md`
- Semantic and operational doc organization: `references/doc-organization.md`
- External guidance used for this skill: `references/external-guidance.md`
