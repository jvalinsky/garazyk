---
name: garazyk-database
description: "Garazyk Deno SQLite database patterns for the scenario dashboard and report storage. Use when writing or reviewing TypeScript SQLite schema, migrations, queries, or report import code."
---

# Garazyk Database Patterns

The current database surface is the Deno scenario dashboard, backed by SQLite through `deno.land/x/sqlite3`.

## File Layout

```text
scripts/scenario-dashboard/db/index.ts       Opens the dashboard database and starts report import
scripts/scenario-dashboard/db/schema.ts      Base schema for runs, scenario_results, and run_events
scripts/scenario-dashboard/db/migrations.ts  Incremental schema migrations
scripts/scenario-dashboard/db/queries.ts     Read/write query helpers
scripts/scenario-dashboard/services/report_scanner.ts  Imports scenario JSON reports
```

## Schema Rules

- Keep `SCHEMA` idempotent with `CREATE TABLE IF NOT EXISTS` and `CREATE INDEX IF NOT EXISTS`.
- Add columns through `migrations.ts` when existing dashboard databases need to be upgraded.
- Store structured scenario metadata as JSON text only at the boundary. Parse and validate before using nested values.
- Use integer epoch milliseconds for timestamps to match scenario reports and dashboard utilities.
- Keep foreign keys and indexes aligned with dashboard access patterns.

## Migration Rules

The migration runner tracks versions in `schema_migrations`.

When adding a migration:

- Gate it with `if (currentVersion < N)`.
- Make it idempotent where possible.
- Record the version only after all statements succeed.
- Keep `SCHEMA` updated to represent a fresh database at the latest schema.
- Add or update tests for migrated and fresh database behavior when the change affects queries.

For additive columns, use the existing `addColumns` helper rather than blindly running `ALTER TABLE`.

## Query Rules

- Use prepared statements for values.
- Do not interpolate untrusted values into SQL identifiers. If a table or column name must be dynamic, validate it against a hard-coded allowlist first.
- Keep row decoding typed at the call site. Avoid returning unshaped `any` from query helpers.
- Prefer explicit `ORDER BY` clauses for dashboard history and latest-run queries.
- Use transactions for multi-table writes that represent one run state transition.

## Dashboard Build Mode

`db/index.ts` exports a stub database object during Fresh build mode. If query helpers need richer database behavior, update the stub type deliberately instead of spreading `as any` across consumers.

## Verification

Run the dashboard-specific checks when database code changes:

```bash
deno test -A scripts/scenario-dashboard
deno check scripts/scenario-dashboard/*.ts scripts/scenario-dashboard/**/*.ts
```

Run root checks when package or scenario code also changes:

```bash
deno task check
deno task test
```
