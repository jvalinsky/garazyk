# ADR 0029: `cancelScheduledAction` Writes an Audit Log Entry

**Status:** Accepted
**Date:** 2026-07-27

## Context

Workstream 01 S14 (phase-24 slice 7) identified a missing audit log entry in
`ModerationService.m:600-605`. The `cancelScheduledAction:` method performs a
direct database update to set the action's status to `'cancelled'` but does
**not** write to `admin_audit_log`. Every other moderation lifecycle
operation — `emitModerationEvent`, `scheduleAction`, `updateSet`,
`deleteSet`, `addTeamMember`, `removeTeamMember` — writes an audit entry with
the admin's DID, the action taken, the subject, and a timestamp.
`cancelScheduledAction` is the only mutation endpoint that does not.

This means a scheduled action cancellation is unattributed: the audit trail
shows the action was scheduled and later cancelled, but there is no record of
**who** cancelled it or **when**. This is a compliance gap for operators who
rely on the audit log for moderation accountability.

The fix is to add an `INSERT INTO admin_audit_log` call mirroring the pattern
used by `scheduleAction` (which writes `SCHEDULED_ACTION` entries) and
`emitModerationEvent` (which writes `MODERATION_EVENT` entries).

No alternative was considered — the fix is to add the audit log entry
following the existing pattern.

## Decision

1. **`cancelScheduledAction:` writes an `admin_audit_log` entry after the
   status update.** The entry uses:

   - `admin_did`: the `cancelledBy` DID passed from the handler
   - `action`: `@"CANCELLED_ACTION"`
   - `subject_type`: `@"com.atproto.admin.defs#repoRef"`
   - `subject_id`: the DID of the subject the cancelled action was targeting
   - `details`: JSON with the action ID and cancellation timestamp
   - `created_at`: `datetime('now')`

2. **The audit log write is not transactional with the status update.**
   The status update is a single `UPDATE` (already atomic). The audit log
   `INSERT` is a separate statement. If the INSERT fails, the cancellation
   has already been committed — the audit gap exists but the cancellation
   itself is not lost. This is consistent with how `emitModerationEvent`
   handles the event INSERT and audit INSERT as separate operations (they
   are sequential, not wrapped in a transaction).

3. **A test asserts the audit entry is written.**
   `testCancelScheduledActionLogsAuditTrail` schedules an action, cancels
   it, queries `admin_audit_log` for `action = 'CANCELLED_ACTION'`, and
   asserts the entry exists with the correct `admin_did` and subject
   reference.

## Consequences

- **All moderation lifecycle operations now produce audit entries.**
  The audit log is complete — scheduling, execution, and cancellation are
  all traceable to the admin who performed them.

- **No contract change.** The response shape of `cancelScheduledAction` is
  unchanged. The audit entry is an internal side effect.

- **No schema change.** `admin_audit_log` already supports the columns used.

- **Rollback.** Revert the slice-7 commit to remove the audit log INSERT.
  Cancellations resume being unattributed. The audit-trail test is removed
  with the revert.
