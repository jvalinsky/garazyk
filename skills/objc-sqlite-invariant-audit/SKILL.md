---
name: objc-sqlite-invariant-audit
description: "Audit Objective-C SQLite persistence layers for invariants: transaction atomicity, statement lifecycle (prepare/step/finalize), lock and transaction interplay, and schema pragma assumptions. Use when reviewing database correctness, corruption risk, migration safety, or deadlocks around database calls."
---

# Objective-C SQLite Invariant Audit

Use this skill to quickly surface database consistency and lifecycle risks in Objective-C SQLite code.

## Quick start
1. Run:
```bash
./skills/objc-sqlite-invariant-audit/scripts/scan_sqlite_invariants.sh . /tmp/objc-sqlite-invariant-audit
```
2. Read `/tmp/objc-sqlite-invariant-audit/summary.md`.
3. Validate candidates with `references/sqlite-invariant-checklist.md`.

## Workflow
1. Map transaction boundaries (`BEGIN`, `COMMIT`, `ROLLBACK`).
2. Map statement lifecycle (`prepare`, `step`, `reset`, `finalize`).
3. Verify lock/queue usage around transaction and statement execution.
4. Confirm schema assumptions (`PRAGMA`, constraints, migration ordering).

## Triage priorities
- P0: transaction path without rollback or commit guarantees.
- P1: prepared statements with missing finalize/reset on some paths.
- P2: lock and transaction overlap with potential deadlock or starvation.
- P3: schema pragma mismatch or low-confidence lifecycle smell.

## Fix patterns
- Use explicit transaction helpers with guaranteed rollback-on-error.
- Enforce prepare/step/finalize discipline using structured cleanup.
- Keep transaction critical sections small and queue-confined.
- Assert required pragmas and constraints during DB initialization.

## Resources
- Script: `scripts/scan_sqlite_invariants.sh`
- Reference: `references/sqlite-invariant-checklist.md`
