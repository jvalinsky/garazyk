# SQLite and SQL Checklist

## Query Construction

- Bind all values through prepared statements.
- Emit dynamic identifiers only from a closed allowlist.
- Build dynamic `IN` clauses with one placeholder per value; handle the empty-list case explicitly.
- Parse sort field, sort direction, comparison operator, and filter mode into enums before generating SQL.
- Keep authorization predicates in every query that reads or mutates scoped data.
- Avoid multi-statement execution APIs for request-controlled input.
- Avoid `sqlite3_exec` for anything that takes data from outside the module.

## Injection Review

Look for these sink patterns:

```sql
WHERE name = '{input}'
ORDER BY {sort}
LIMIT {limit}
IN ({ids})
LIKE '%{term}%'
ATTACH DATABASE '{path}'
```

Safer replacements:

- `WHERE name = ?` with a bound string.
- `ORDER BY created_at DESC` selected from an enum-to-SQL mapping.
- `LIMIT ? OFFSET ?` with parsed integer bounds and maximums.
- `IN (?, ?, ?)` generated from a counted list of bound values.
- `LIKE ? ESCAPE '\'` with explicit escaping when user text should be literal.
- Avoid `ATTACH` for untrusted paths; if needed, canonicalize and authorize the path before opening.

## Schema Design

- Model invariants in the database, not only in application code.
- Prefer stable primary keys and explicit unique constraints.
- Use `INTEGER PRIMARY KEY` only when rowid semantics are intended.
- Use `WITHOUT ROWID` only for tables with natural primary keys after measuring.
- Use `STRICT` tables for new schemas when compatibility allows.
- Choose timestamp storage consistently: integer epoch values or normalized text, not mixed formats.
- Add `CHECK` constraints for finite states, non-negative counts, normalized booleans, and valid ranges.
- Store JSON only when the access pattern is document-like; promote frequently queried fields to columns or generated columns with indexes.

## Index Design

- Start from the workload: filters, joins, ordering, grouping, uniqueness, and pagination.
- Create composite indexes that match query order: equality columns, then range columns, then order columns.
- Remember the leftmost-prefix rule; an index on `(actor_id, created_at)` helps `actor_id = ? ORDER BY created_at`, but not `created_at = ?` alone.
- Use partial indexes for hot subsets such as non-deleted rows or active records.
- Use expression indexes only when the query uses the same expression.
- Avoid duplicate indexes where one is a prefix of another unless uniqueness or planner behavior requires both.
- Revisit indexes after schema changes; every index speeds some reads and slows writes.

## Query Performance

- Use `EXPLAIN QUERY PLAN` and confirm that important lookups use the expected index.
- Watch for `SCAN` on large tables, temporary B-trees for sorting/grouping, and joins with the wrong driving table.
- Avoid `SELECT *` on wide or hot paths.
- Avoid functions on indexed columns in predicates.
- Avoid type-affinity mismatches, such as comparing integer columns to text values.
- Use keyset pagination:

```sql
WHERE (created_at, id) < (?, ?)
ORDER BY created_at DESC, id DESC
LIMIT ?
```

- Do not use deep `OFFSET` for feed, inbox, or scrolling workflows.
- Split large backfills and deletes into bounded batches.

## Transactions and Concurrency

- Wrap multi-step writes in explicit transactions.
- Prefer `BEGIN IMMEDIATE` when a write transaction should fail or wait before doing expensive work.
- Keep write transactions short and avoid network calls inside them.
- Use WAL mode for read-heavy services that need readers during writes.
- Configure a busy timeout or retry policy instead of treating transient lock contention as data failure.
- Do not share one SQLite connection across threads unless the chosen SQLite build and wrapper contract explicitly allow it.

## Migrations

- Make migrations idempotent where the runner permits it.
- Separate schema creation from large data backfills.
- Validate row counts, nullability, uniqueness, and foreign-key integrity after migration.
- Add indexes after bulk loads when practical.
- For destructive changes, create a replacement table, copy data, validate, then swap.
- Test migrations on realistic data volume, not only empty databases.

## PRAGMAs and Operational Settings

- `PRAGMA foreign_keys = ON` per connection when foreign keys matter.
- `PRAGMA journal_mode = WAL` for concurrent service workloads where suitable.
- `PRAGMA busy_timeout = N` to handle normal writer contention.
- `PRAGMA optimize` after significant changes or during maintenance.
- `PRAGMA integrity_check` or `quick_check` for diagnostics, not as a substitute for constraints and tests.
- Avoid global PRAGMA changes in libraries unless the caller owns the connection lifecycle.

## Security Hardening

- Keep database files in directories with least-privilege permissions.
- Treat database paths as sensitive inputs; canonicalize and authorize them.
- Disable extension loading unless a trusted, explicit extension workflow requires it.
- Avoid attaching arbitrary databases in request paths.
- Redact secrets from SQL logs, migration logs, failed statements, and test snapshots.
- Consider `sqlite3_db_config` defensive/trusted-schema settings in C/C++/Objective-C code when opening untrusted databases or running hostile SQL is in scope.

## Verification Prompts

Use these checks before finishing:

- Can a quote, comment marker, wildcard, or encoded payload change query structure?
- Does every scoped query include tenant/account/actor authorization predicates?
- Does the query plan still look good with realistic row counts?
- Are all expected constraints enforced by the database?
- Do migrations survive rerun, partial failure, and existing production data?
- Does concurrency behavior match the service's connection and queue contract?
