# ADR 0024: `updateSafelink` Requires a Malformed-ID Early-Return Guard

**Status:** Accepted
**Date:** 2026-07-27

## Context

Workstream 01 S14 (phase-24 slice 2) identified a mass-update vulnerability in
`ModerationService.m:709-714`. The `updateSafelink:` method constructs a SQL
`UPDATE` statement with an optional `WHERE` clause gated on the safelink ID
format:

```objc
NSArray *parts = [safelinkId componentsSeparatedByString:@":"];
if (parts.count == 2) {
    [sql appendFormat:@" WHERE url = ? AND pattern = ?"];
    [params addObject:parts[0]];
    [params addObject:parts[1]];
}
return [self.database executeParameterizedUpdate:sql params:params error:error];
```

A `safelinkId` is a compound key `"url:pattern"`. If the caller passes a
malformed ID (no colon, e.g., `"malformed"`), `parts.count` is 1, the `WHERE`
clause is never appended, and the `UPDATE` runs against **every row** in
`moderation_safelinks` — changing the action of all rules simultaneously.

The sibling `deleteSafelink:` method at `:723-728` does **not** have this bug:
it uses an early-return pattern — `if (parts.count != 2) { error; return NO; }`
— which rejects malformed IDs before any SQL is executed.

No alternative was considered — the fix is to bring `updateSafelink:` into
parity with `deleteSafelink:`'s validation pattern.

## Decision

1. **`updateSafelink:` gains a `parts.count != 2` early-return guard matching
   `deleteSafelink:`'s pattern.** If the safelink ID does not contain exactly
   one colon, the method sets an `NSError` with domain `@"ModerationService"`,
   code `1`, and message `@"Invalid safelink ID format"`, then returns `NO`.
   No SQL is executed for malformed IDs.

2. **The `WHERE` clause is unconditionally appended after the guard.**
   Since the ID format is validated upfront, the `WHERE` clause is always
   needed and is no longer gated on `parts.count == 2`.

3. **The error domain and message exactly match `deleteSafelink:`'s
   validation.** Both methods use `@"ModerationService"` domain, code `1`,
   and `@"Invalid safelink ID format"` message — a consistent error surface
   for malformed safelink IDs.

4. **A negative test is added to `ModerationServiceTests.m`.**
   `testUpdateSafelinkRejectsMalformedId` inserts two safelink rules (block
   and warn), calls `updateSafelink` with the malformed ID `"malformed"`,
   asserts the method returns `NO` with an error, then queries the table
   and asserts both rules retain their original action values (block, warn)
   — proving no mass-update occurred.

## Consequences

- **Mass-update on malformed ID is eliminated.** A caller who passes a
  malformed safelink ID gets a clear error (`"Invalid safelink ID format"`)
  instead of silently updating all rules.

- **No contract change.** Valid safelink IDs (`url:pattern`) work identically.
  Only malformed IDs — which were never valid safelink IDs — are now rejected.

- **Consistent error surface with `deleteSafelink:`.** Both methods now
  validate the ID format in the same way, with the same error domain, code,
  and message.

- **Rollback.** Revert the slice-2 commit to restore the conditional
  `WHERE` clause. Malformed IDs resume silently updating all rows. The
  negative test is removed with the revert.
