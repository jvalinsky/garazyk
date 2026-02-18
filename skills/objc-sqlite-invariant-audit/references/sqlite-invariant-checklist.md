# SQLite Invariant Checklist

Use this checklist while validating candidates from `scan_sqlite_invariants.sh`.

## Transaction integrity
- Verify each write transaction has explicit success and failure exits.
- Verify rollback is guaranteed on every error path.
- Verify nested transactions use savepoints consistently.

## Statement lifecycle
- Verify each prepared statement is finalized on all paths.
- Verify statement reset or clear-bindings policy is explicit for reuse.
- Verify no statement is stepped after a terminal error without reset.

## Locking and queueing
- Verify DB handle access is queue-confined or lock-disciplined.
- Verify lock ordering avoids DB re-entry deadlocks.
- Verify no long blocking operation occurs inside transaction lock scope.

## Schema assumptions
- Verify required pragmas are set during DB init and tested.
- Verify migration ordering preserves compatibility and data integrity.
- Verify constraints (unique, foreign key) match application invariants.
