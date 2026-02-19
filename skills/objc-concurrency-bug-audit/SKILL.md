---
name: objc-concurrency-bug-audit
description: "Audit Objective-C and Objective-C++ code for concurrency defects such as data races, deadlocks, unsafe shared mutable state, non-atomic access across threads, and queue misuse. Use when reviewing thread-safety bugs, intermittent crashes, flakiness, or any request mentioning concurrency, races, or deadlocks."
---

# Objective-C Concurrency Bug Audit

Use this skill to perform a structured static audit for thread-safety defects and prioritize high-risk paths.

## Quick start
1. Run:
```bash
./skills/objc-concurrency-bug-audit/scripts/scan_concurrency_patterns.sh . /tmp/objc-concurrency-audit
```
2. Read `/tmp/objc-concurrency-audit/summary.md`.
3. Verify high-risk files with `references/concurrency-checklist.md`.

## Workflow
1. Identify shared mutable state (`NSMutable*`, static/global state, ivars with broad access).
2. Identify multi-threading entry points (`dispatch_async`, `NSThread`, operation queues).
3. Identify synchronization strategy (`@synchronized`, locks, queue confinement, atomic APIs).
4. Flag paths where shared state is accessed from threaded contexts without a clear strategy.

## Triage priorities
- P0: deadlock risk (`dispatch_sync` to main from main, lock-order inversion).
- P1: likely data race on shared mutable state.
- P2: non-atomic read/write crosses queues without confinement proof.
- P3: uncertain pattern requiring runtime trace or ThreadSanitizer.

## Fix patterns
- Enforce queue confinement for mutable state and assert queue ownership.
- Replace ad-hoc locking with one clear synchronization primitive per state domain.
- Move cross-thread mutable writes behind serialized APIs.
- Add runtime assertions for thread/queue ownership in debug builds.

## Resources
- Script: `scripts/scan_concurrency_patterns.sh`
- Reference: `references/concurrency-checklist.md`
