# ADR 0028: `updateSet` Wraps Membership Replacement in a Single Transaction

**Status:** Accepted
**Date:** 2026-07-27

## Context

Workstream 01 S14 (phase-24 slice 6) identified a non-atomic
delete-then-insert pattern in `ModerationService.m:276-283`. The
`updateSet:` method replaces the members of a moderation set by:

1. `DELETE FROM moderation_set_members WHERE set_id = ?`
2. Loop: `INSERT INTO moderation_set_members (set_id, member_did, ...)`

These two operations are not wrapped in a transaction. If the process
crashes, the database connection is interrupted, or a timeout occurs between
the DELETE and the INSERTs, the set is left with **zero members** — the old
members are gone, and the new members were never written.

The same pattern exists in `addSetValues` and `deleteSetValues`, which also
perform single-statement operations without an explicit transaction boundary.
While single-statement writes are atomic in SQLite, the delete-then-insert
sequence is not.

The fix is to wrap the delete-then-insert sequence in an explicit
`BEGIN IMMEDIATE` / `COMMIT` transaction. Two alternatives were considered:

- **Use `INSERT OR REPLACE` with a version column.** This would make each
  member upsert atomic but would require a schema change and would not
  handle the delete of removed members. Rejected as more complex than the
  transaction approach.

- **Use `ON CONFLICT` upsert.** Same tradeoff — handles adds but not removes.

## Decision

1. **`updateSet:` wraps the delete-then-insert sequence in `BEGIN IMMEDIATE`
   / `COMMIT`.** If `membership` is provided in the body, the DELETE and
   subsequent INSERTs execute within a single transaction. On any failure,
   the transaction is rolled back, preserving the old membership.

2. **The transaction uses `BEGIN IMMEDIATE` for write-acquisition.**
   `BEGIN IMMEDIATE` acquires the write lock immediately, preventing
   `SQLITE_BUSY` races from concurrent updates to the same set.

3. **`sqlite3_exec` with error-checking is used for BEGIN/COMMIT/ROLLBACK.**
   The transaction is managed with explicit error checks — if `BEGIN
   IMMEDIATE` fails, the method returns `NO` immediately; if any INSERT
   fails, `ROLLBACK` is executed and the method returns `NO`.

4. **The name-only update path (no membership change) is not wrapped.**
   When only the set name changes, the single `UPDATE moderation_sets SET
   name = ? WHERE id = ?` is already atomic on its own and does not need a
   transaction boundary.

5. **A test asserts crash-safety.** `testUpdateSetMembershipIsAtomic`
   creates a set with members, calls `updateSet` with a new member list
   while simulating a mid-operation failure (by injecting a mock database
   that fails on the third INSERT), and asserts the old membership is
   preserved — no partial replacement.

## Consequences

- **No data loss on crash or timeout during membership replacement.** The
  old membership is preserved until the entire delete-then-insert sequence
  commits atomically.

- **Slight latency increase for membership updates.** `BEGIN IMMEDIATE`
  acquires the write lock at the start rather than at the first write
  statement. This is negligible for the expected workload (moderation set
  updates are infrequent admin operations).

- **No schema change.** The `moderation_set_members` table is unchanged.

- **Rollback.** Revert the slice-6 commit to restore non-transactional
  delete-then-insert. Crash-during-update resumes the risk of zero-member
  sets. The crash-safety test is removed with the revert.
