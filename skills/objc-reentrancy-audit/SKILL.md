---
name: objc-reentrancy-audit
description: "Audit Objective-C and Objective-C++ for re-entrancy bugs, including callbacks under locks, notification and KVO recursion, and synchronous queue re-entry into partially-updated state. Use when reviewing crashes, recursive call loops, inconsistent state bugs, delegate/completion ordering issues, or any request mentioning re-entrancy."
---

# Objective-C Re-entrancy Audit

Use this skill to find and triage re-entrancy hazards before they become production crashes or corrupt state.

## Quick start
1. Run:
```bash
/Users/jack/Software/objpds/skills/objc-reentrancy-audit/scripts/scan_reentrancy_patterns.sh . /tmp/objc-reentrancy-audit
```
2. Read `/tmp/objc-reentrancy-audit/summary.md`.
3. Review candidate files with `references/reentrancy-checklist.md`.

## Workflow
1. Locate lock or synchronization regions (`@synchronized`, mutex, semaphore, `[lock lock]`).
2. Locate callbacks (`delegate`, `completion`, `handler`, `postNotification`) near those regions.
3. Trace whether callback targets can re-enter the caller before state is fully committed.
4. Flag findings where re-entry can observe partial mutation or violate invariants.

## Triage priorities
- P0: callback under lock can re-enter same object and deadlock.
- P1: callback can re-enter and read or write partially-mutated state.
- P2: notification or KVO cycles can recurse without guard.
- P3: low-confidence pattern that needs runtime confirmation.

## Fix patterns
- Snapshot mutable state under lock, release lock, then invoke callback.
- Add re-entrancy guard flags for non-recursive sections.
- Move state transitions into single queue-confined critical sections.
- Break notification recursion with idempotent updates or cycle guards.

## Resources
- Script: `scripts/scan_reentrancy_patterns.sh`
- Reference: `references/reentrancy-checklist.md`
