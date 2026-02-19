---
name: rewrite-dev-docs-comments
description: "Rewrite engineering docs and code comments to remove low-signal LLM-speak (marketing tone, vague claims, filler, repeated obvious statements, and unnatural phrasing) and produce concise, technically precise prose for experienced developers. Use when editing READMEs, design docs, API docs, migration notes, runbooks, PR descriptions, or in-code comments."
---

# Rewrite Dev Docs Comments

Produce high-signal technical writing that sounds like a senior engineer communicating with peers.

## Quick Start
1. Scan candidate text:
```bash
python3 skills/rewrite-dev-docs-comments/scripts/scan_llm_speak.py <path>
```
2. Rewrite using `references/rewrite-patterns.md`.
3. Preserve behavior facts, constraints, and caveats.
4. Re-scan and then manually verify technical correctness.

## Rewrite Workflow
1. Preserve facts first.
- Keep APIs, invariants, limits, error behavior, security assumptions, and version details.
- Do not invent claims or remove required warnings.
2. Remove low-signal language.
- Delete hype words, obvious statements, and throat-clearing intros.
- Collapse repeated points to one concrete sentence.
3. Make claims testable.
- Replace vague adjectives with measurable detail (latency, complexity, scope, limits, failure modes).
- Prefer exact nouns and verbs over abstractions.
4. Tune tone for peer developers.
- Write directly and impersonally.
- Prefer active voice and short sentences.
- Avoid baby-talk phrasing such as "simply," "just," and "easy."
5. Re-evaluate comment necessity.
- Keep comments that explain why, invariants, edge cases, protocol constraints, or non-obvious tradeoffs.
- Remove comments that restate code.

## Quality Bar
- Ensure the first sentence contains a non-obvious fact or decision.
- Ensure each paragraph contains at least one concrete detail.
- Delete any sentence that only sounds good but adds no information.

## Scope Guidance
- For code comments, optimize for maintainers reading code under time pressure.
- For docs, optimize for implementation and incident-response decisions.
- If detail is unknown, state uncertainty explicitly instead of padding with generic prose.

## Resources
- Scanner: `scripts/scan_llm_speak.py`
- Rewrite patterns and examples: `references/rewrite-patterns.md`
