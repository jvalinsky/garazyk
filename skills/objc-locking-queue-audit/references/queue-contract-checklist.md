# Queue and Lock Contract Checklist

Use this checklist while reviewing `scan_locking_queue_contracts.sh` results.

## Lock discipline
- Verify each lock acquisition has matching release on all return paths.
- Verify no callback or blocking call executes while lock is held unless required.
- Verify lock acquisition order is documented and consistent across modules.

## Queue ownership
- Verify each mutable subsystem has one owner queue.
- Verify APIs that require a queue context assert it in debug builds.
- Verify queue hops are explicit and minimal.

## Deadlock risk
- Flag `dispatch_sync` to main queue from paths that can already run on main.
- Flag nested sync dispatch between mutually dependent queues.
- Flag lock + sync dispatch combinations in same call path.

## Review output grading
- P0: clear deadlock path or guaranteed lock leak.
- P1: probable contract violation with user-visible impact.
- P2: suspicious pattern needing control-flow proof.
- P3: low-confidence style warning.

## Typical fixes
- Use owner-queue model and queue assertions.
- Replace sync dispatch with async and completion handoff.
- Use structured cleanup to guarantee unlock.
- Split large critical sections into lock-free read phases plus short commit phase.
