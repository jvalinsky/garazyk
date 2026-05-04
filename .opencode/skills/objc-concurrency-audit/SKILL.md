name: objc-concurrency-audit
description: Audit Objective-C/C++ for concurrency bugs, deadlocks, re-entrancy, and queue contract violations. Use when reviewing thread-safety, intermittent crashes, or lock discipline.

# Objective-C Concurrency Audit

Full audit procedures are defined in `.agents/skills/objc-concurrency-audit/SKILL.md`.

## Quick Start
```bash
./.agents/skills/objc-concurrency-audit/scripts/run_concurrency_audit.sh . /tmp/objc-concurrency-audit
```

## Audit Domains
- **Data races**: Unsafe shared mutable state across threads
- **Deadlocks**: `dispatch_sync` to main queue from main queue, lock-order inversions
- **Re-entrancy**: Callbacks invoked while holding a lock
- **Queue contracts**: Missing queue ownership assertions

## Fix Patterns
- Snapshot state under lock, release before callbacks
- Enforce queue confinement with assertions
- Replace ad-hoc locks with serialized queues
