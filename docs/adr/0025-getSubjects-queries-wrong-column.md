# ADR 0025: `getSubjects` Queries `review_state` Instead of `reviewState`

**Status:** Accepted
**Date:** 2026-07-27

## Context

Workstream 01 S14 (phase-24 slice 3) identified a column-name mismatch in
`ModerationService.m:637`. The `getSubjects:` method builds a query against
`moderation_subjects` and returns rows keyed by the column name. The caller
at `XrpcToolsOzonePack.m` accesses `row[@"reviewState"]` (camelCase) to
display the moderation status, but the `getSubjects:` method uses `SELECT *`
from `moderation_subjects`, which has a column named `review_state`
(snake_case — the SQLite convention used throughout the Ozone schema).

Because SQLite column names in `SELECT *` are returned exactly as they appear
in the schema, and the caller reads `reviewState`, the value is always `nil`
— causing every subject to appear as though it has no active moderation
state (`reviewState = "none"`). This is a silent data defect: the row
exists, the value is present, but the caller cannot read it.

The bug was masked by the `getModerationRecord:` and `getModerationRepo:`
methods, which use explicit column aliases (`AS reviewState`) to bridge the
casing gap. `getSubjects:` never adopted this pattern.

One alternative was considered:

- **Change the caller to use `review_state`.** This would fix the immediate
  bug but would make the casing inconsistent with every other Ozone endpoint
  that returns `reviewState` (camelCase). The contract expects `reviewState`;
  the internal schema uses `review_state`; the mapper layer exists to bridge
  the two. This was rejected in favor of fixing the mapper.

## Decision

1. **`getSubjects:` uses an explicit column alias.** The query changes from
   `SELECT * FROM moderation_subjects` to a column list that aliases
   `review_state AS reviewState`, matching the pattern used by
   `getModerationRecord:` and `getModerationRepo:`.

2. **The alias matches the existing Ozone convention.** All other Ozone
   query methods that return moderation state to callers alias snake_case
   columns to camelCase. `getSubjects:` now follows the same convention.

3. **A test asserts `reviewState` is non-nil and reflects the actual
   database value.** `testGetSubjectsReturnsReviewState` creates a subject
   with a known review state, calls `getSubjects:`, and asserts the
   returned `reviewState` field matches the expected value — proving the
   column alias bridges the casing gap.

## Consequences

- **`reviewState` is no longer always nil.** Moderation dashboards and tools
  that call `getSubjects` can now read the actual review state of subjects.

- **No contract change.** The response shape is unchanged — `reviewState`
  was already the documented field name. The bug was that the field was
  always absent.

- **No schema change.** The column is still named `review_state` in the
  database. Only the query projection changes.

- **Rollback.** Revert the slice-3 commit to restore `SELECT *`. The caller
  resumes reading nil for `reviewState`. The test is removed with the
  revert.
