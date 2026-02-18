---
name: objc-parser-hardening-audit
description: "Audit Objective-C parsing and decoding code for bounds checks, integer overflow risks, malformed input handling, and unsafe memory operations. Use when reviewing parser security, fuzzing gaps, or crash-prone decoding paths."
---

# Objective-C Parser Hardening Audit

Use this skill to find high-risk parsing paths and prioritize hardening work.

## Quick start
1. Run:
```bash
/Users/jack/Software/objpds/skills/objc-parser-hardening-audit/scripts/scan_parser_hardening.sh . /tmp/objc-parser-hardening-audit
```
2. Read `/tmp/objc-parser-hardening-audit/summary.md`.
3. Validate candidates with `references/parser-hardening-checklist.md`.

## Workflow
1. Map parser/decoder entry points.
2. Map risky memory and integer operations.
3. Verify bounds and length preconditions near each operation.
4. Verify malformed input exits are fail-closed and test-covered.

## Triage priorities
- P0: unchecked length/offset before memory access.
- P1: integer conversion or arithmetic overflow risk.
- P2: malformed input path with partial state mutation.
- P3: low-confidence parser smell.

## Fix patterns
- Add explicit precondition checks before every offset/range use.
- Use overflow-safe arithmetic and explicit type bounds.
- Keep parse state immutable until full validation succeeds.
- Expand fuzzer corpus with edge-case malformed inputs.

## Resources
- Script: `scripts/scan_parser_hardening.sh`
- Reference: `references/parser-hardening-checklist.md`
