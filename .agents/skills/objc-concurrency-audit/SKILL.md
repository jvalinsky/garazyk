---
name: objc-concurrency-audit
description: "Deprecated legacy Objective-C/C++ concurrency audit. Use only when explicitly requested for historical native code; do not use for current Deno/TypeScript work."
---

# Objective-C Concurrency Audit

This master skill covers thread-safety, re-entrancy, and lock/queue discipline.

## Quick Start

1. **Run the concurrency scanner**:
   ```bash
   ./.agents/skills/objc-concurrency-audit/scripts/run_concurrency_audit.sh . /tmp/objc-concurrency-audit
   ```
2. **Review findings** in `/tmp/objc-concurrency-audit/summary.md`.

## Audit Domains

### 1. Data Races & Shared State
- **Goal**: Identify unsafe shared mutable state (ivars, globals) accessed across threads without protection.
- **Priority**: P0 if multiple threads write to the same `NSMutable*` without a lock/queue.

### 2. Deadlocks & Lock Discipline
- **Goal**: Detect `dispatch_sync` to the main queue from the main queue, or lock-order inversions.
- **Priority**: P0 for deadlocks; P1 for unbalanced lock/unlock in error paths.

### 3. Re-entrancy
- **Goal**: Find callbacks (delegates, completion handlers) invoked while holding a lock.
- **Priority**: P0 if the callback can re-enter the object and deadlock.

### 4. Queue Contracts
- **Goal**: Verify queue ownership assertions and prevent cross-queue state access.
- **Priority**: P2 for missing `dispatch_assert_queue` on stateful APIs.

## Fix Patterns
- Snapshot state under lock, then release lock before invoking callbacks.
- Enforce queue confinement and use assertions.
- Replace ad-hoc locking with serialized queues where possible.
