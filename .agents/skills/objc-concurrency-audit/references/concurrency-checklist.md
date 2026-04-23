# Concurrency Checklist

Use this checklist while validating candidates from `scan_concurrency_patterns.sh`.

## Shared state model
- Identify owner for each mutable state object.
- Verify each owner is explicit: lock, serial queue, or immutable snapshot.
- Flag mutable globals and static caches without clear owner.

## Access model
- Verify reads and writes happen on the same queue or under same lock.
- Verify no mixed strategy (sometimes lock, sometimes queue) for same state.
- Verify completion blocks do not mutate shared state from unexpected threads.

## Deadlock and ordering
- Flag `dispatch_sync` paths that can run on same queue.
- Flag lock ordering inversions across functions/modules.
- Flag sync wait inside callback chains where caller thread is required.

## Property and API surface
- Review `nonatomic` properties accessed from multiple threads.
- Verify thread-safe wrappers for mutable collection properties.
- Verify public APIs document threading expectations.

## Typical fixes
- Constrain mutable state to one serial queue.
- Replace broad shared mutable state with immutable snapshots.
- Add queue assertions in debug builds.
- Convert sync waits to async completion where safe.
