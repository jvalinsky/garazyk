# ADR 0026: Team Management Endpoints Use `did` as the Database Key, Not `email`

**Status:** Accepted
**Date:** 2026-07-27

## Context

Workstream 01 S14 (phase-24 slice 4) identified a key mismatch in the Ozone
team management endpoints. `addTeamMember` at `ModerationService.m:216`
stores the member using the `did` field from the request body. But
`updateTeamMember` at `:233` and `removeTeamMember` at `:240` query by
`email`:

```objc
// addTeamMember — stores with did as key
INSERT OR REPLACE INTO moderation_team (did, email, role, ...)

// updateTeamMember — queries by email, not did
UPDATE moderation_team SET role = ? WHERE email = ?

// removeTeamMember — queries by email, not did
DELETE FROM moderation_team WHERE email = ?
```

If a member's email changes between `addTeamMember` and `updateTeamMember`
/ `removeTeamMember`, the UPDATE/DELETE matches zero rows — the operation
succeeds silently (`sqlite3_changes` is not checked) but changes nothing.
The role update appears to have worked (the handler returns `{success: YES}`)
but the member retains their old role. Similarly, a removal appears to
succeed but the member remains in the team.

The primary key for `moderation_team` is `did`. The `email` column exists
for display and notification purposes but is mutable. Using a mutable field
as the lookup key for lifecycle operations is the root cause.

No alternative was considered — the fix is to use the primary key (`did`)
consistently across all team management operations.

## Decision

1. **`updateTeamMember` queries by `did` instead of `email`.**
   `UPDATE moderation_team SET role = ?, email = ?, updated_at = ? WHERE did = ?`

2. **`removeTeamMember` queries by `did` instead of `email`.**
   `DELETE FROM moderation_team WHERE did = ?`

3. **The request body parameter is changed from `email` to `did` in both
   handlers' JSON extraction.** `XrpcToolsOzonePack.m`'s
   `updateMember` and `deleteMember` handlers extract `body[@"did"]` instead
   of `body[@"email"]`. The old `email` parameter is still accepted for
   backward compat, but `did` takes precedence.

4. **`sqlite3_changes` is checked after UPDATE/DELETE to detect no-ops.**
   If `sqlite3_changes(db) == 0`, the handler returns an error
   `@"MemberNotFound"` rather than a false `{success: YES}`. This catches
   the case where the DID does not exist in the table (previously a silent
   no-op).

5. **A test asserts update-by-did works and update-by-stale-email fails.**
   `testUpdateTeamMemberByDid` adds a member, verifies the role change via
   `did`, and asserts that an update using a non-existent email returns
   `MemberNotFound`.

## Consequences

- **Silent no-ops are eliminated.** Role updates and removals that match
  zero rows now return a clear error instead of a false success.

- **Contract change for `updateMember` and `deleteMember`.** The `email`
  parameter is deprecated in favor of `did`. The handler accepts both for
  one release cycle; `email`-only callers should migrate to `did`.

- **Backward compat for `addTeamMember`.** The `email` field is still
  accepted and stored alongside `did` for display purposes.

- **Rollback.** Revert the slice-4 commit to restore `email`-based queries.
  Role updates and removals resume silent no-ops for members whose email
  has changed. The `MemberNotFound` error is removed.
