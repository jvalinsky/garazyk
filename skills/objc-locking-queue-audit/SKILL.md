---
name: objc-locking-queue-audit
description: "Audit Objective-C lock and dispatch-queue contracts, including lock/unlock imbalance, lock plus synchronous-dispatch deadlock risk, missing queue assertions, and cross-queue state access. Use when reviewing queue ownership bugs, deadlocks, or lock discipline regressions."
---

# Objective-C Locking and Queue Contract Audit

Use this skill when correctness depends on strict lock discipline and queue ownership invariants.

## Quick start
1. Run:
```bash
./skills/objc-locking-queue-audit/scripts/scan_locking_queue_contracts.sh . /tmp/objc-locking-queue-audit
```
2. Read `/tmp/objc-locking-queue-audit/summary.md`.
3. Verify candidate files with `references/queue-contract-checklist.md`.

## Workflow
1. Map lock primitives and unlock sites.
2. Map queue creation, queue dispatch, and queue assertion use.
3. Flag lock-heavy files that also call `dispatch_sync`.
4. Flag files with lock/unlock imbalance as audit candidates.
5. Verify queue ownership assertions for stateful APIs.

## Triage priorities
- P0: sync-to-main from main path or obvious lock-order deadlock.
- P1: lock without balanced unlock in error/early-return paths.
- P2: mutable state touched from multiple queues without assertion.
- P3: suspicious pattern that needs control-flow inspection.

## Fix patterns
- Use one owner queue per mutable state domain and assert ownership.
- Use `@try/@finally` or equivalent structure to guarantee unlock.
- Avoid blocking sync-dispatch inside lock-protected sections.
- Document lock ordering and forbid inversions in code review.

## Resources
- Script: `scripts/scan_locking_queue_contracts.sh`
- Reference: `references/queue-contract-checklist.md`
