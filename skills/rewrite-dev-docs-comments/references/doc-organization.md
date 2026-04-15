# Documentation Organization

Place content by reader intent first, then by repository location.

## Semantic Buckets
- Tutorial: Teach a beginner through an end-to-end, validated path.
- How-to: Solve one concrete task for a reader who already knows basics.
- Reference: Provide complete, factual lookup material.
- Explanation: Clarify why the system is designed this way and tradeoffs.

## Quick Decision Tree
1. Ask: "Is the reader trying to learn, do, look up, or understand why?"
2. Choose bucket:
- learn -> tutorial
- do -> how-to/runbook
- look up -> reference
- understand why -> explanation/design doc
3. Move content that does not match bucket intent.

## Operational Layer
Use operational placement when content is execution-critical:
- Runbooks: on-call triage, rollback, incident response.
- Playbooks: repeatable operator tasks with prerequisites and verification.
- ADRs/design docs: decisions, alternatives, consequences.
- API reference: symbol/endpoint contracts and machine-facing details.

## README Scope
- Keep README to orientation: what the project is, quick start, key links.
- Link out to tutorials/how-to/reference/explanation instead of embedding all details.

## Anti-Misplacement Checks
- If a how-to starts teaching fundamentals, split tutorial content out.
- If reference contains opinions or rationale, move that to explanation.
- If explanation contains step lists, move steps to how-to/runbook.
- If code comments contain operations guidance, move to runbook and keep short pointer in code.
