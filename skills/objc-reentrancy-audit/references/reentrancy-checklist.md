# Re-entrancy Checklist

Use this checklist while reviewing candidates from `scan_reentrancy_patterns.sh`.

## Confirm re-entry edges
- Does code call delegate, completion, block, notification, or KVO from inside a mutation flow?
- Can callback code call back into the same object or subsystem?
- Is callback execution synchronous or effectively immediate?

## Confirm state hazard
- Is mutable state partially updated before callback runs?
- Is invariant restoration delayed until after callback?
- Can callback observe half-written state or trigger another write?

## Confirm lock hazard
- Is callback invoked while lock or `@synchronized` is active?
- Can callback acquire the same lock (directly or indirectly)?
- Can callback block on queue work that needs the current thread?

## Typical fixes
- Copy callback targets or snapshots under lock, then unlock, then invoke.
- Split mutation into prepare/commit phases and invoke callbacks after commit.
- Add explicit re-entrancy guard where recursion is invalid.
- Make updates idempotent so repeated entry does not corrupt state.
