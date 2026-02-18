---
name: objc-test-gap-mapper
description: "Map Objective-C source modules to test coverage and identify high-risk files without obvious tests. Use when planning reliability work, prioritizing new tests, or reviewing regression risk before refactors."
---

# Objective-C Test Gap Mapper

Use this skill to quickly identify where test coverage is likely missing or thin.

## Quick start
1. Run:
```bash
/Users/jack/Software/objpds/skills/objc-test-gap-mapper/scripts/map_test_gaps.sh . /tmp/objc-test-gap-mapper
```
2. Read `/tmp/objc-test-gap-mapper/summary.md`.
3. Prioritize with `references/test-gap-triage-checklist.md`.

## Workflow
1. Enumerate source implementation files.
2. Enumerate test implementation files.
3. Map source basenames to probable test basenames.
4. Rank uncovered sources by risk and module criticality.

## Triage priorities
- P0: security/auth/network/database source with no obvious tests.
- P1: high-churn or bug-prone module with weak test presence.
- P2: utility/core parser code with only indirect coverage.
- P3: low-risk gaps suitable for backlog.

## Fix patterns
- Add focused unit tests for invariants and failure paths.
- Add integration tests at service/endpoint boundaries.
- Add regression tests for previously fixed defects.
- Track coverage deltas as part of review gates.

## Resources
- Script: `scripts/map_test_gaps.sh`
- Reference: `references/test-gap-triage-checklist.md`
