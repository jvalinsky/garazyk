---
name: sqlite-sql-best-practices
description: "SQLite and SQL writing, review, and schema guidance with emphasis on correctness, query performance, index design, migrations, transactions, and security. Use when Codex writes or reviews SQL queries, SQLite schema changes, database access code, migrations, indexes, PRAGMAs, prepared statements, or performance/security-sensitive database logic."
---

# SQLite SQL Best Practices

## Core Workflow

Use this skill when writing or reviewing SQLite-backed data access. Optimize for correctness first, security second, and measured performance third.

1. Identify the database surface: raw SQL, query builder, migration, schema, index, transaction, application binding code, or operational setting.
2. Trace data from sources to SQL sinks. Treat request parameters, file contents, identifiers, sort keys, filters, JSON fields, and pagination cursors as untrusted until parsed.
3. Prefer safe primitives: prepared statements with bound values, typed query helpers, whitelisted identifiers, explicit transactions, constraints, and small composable query functions.
4. Check performance with evidence. Use `EXPLAIN QUERY PLAN`, representative data volumes, existing indexes, and workload shape before proposing indexes or rewrites.
5. Leave tests or verification that exercise injection attempts, constraint failures, empty result sets, high-cardinality lookups, pagination boundaries, and migration idempotence.

Read [sqlite-sql-checklist.md](references/sqlite-sql-checklist.md) when the task involves non-trivial query review, schema/index design, migrations, PRAGMAs, or security-sensitive SQL construction.

## Security Defaults

- Use prepared statements and `sqlite3_bind_*` or the framework's equivalent for every value.
- Never concatenate user input into SQL. Parameters cannot bind identifiers, table names, column names, operators, sort directions, or arbitrary `IN` list syntax; parse those into enums and whitelist each emitted token.
- Keep SQL authorization close to the data access boundary. Do not rely on UI filters or caller promises to enforce tenant, account, actor, or authorization predicates.
- Avoid enabling extension loading. Treat user-supplied database files as hostile; disable trusted schema behavior when opening untrusted databases and avoid executing schema-defined SQL from them.
- Do not log full SQL with secrets or user tokens embedded. Prefer templates plus redacted parameter summaries.

## Performance Defaults

- Measure before and after with `EXPLAIN QUERY PLAN` and realistic data distribution.
- Shape indexes around the exact workload: equality predicates first, then range/order terms, and include projected columns only when a covering index meaningfully helps.
- Prefer keyset pagination over deep `OFFSET`; keep stable ordering with a deterministic tie-breaker.
- Batch writes inside explicit transactions. Avoid autocommit loops for inserts, updates, deletes, or backfills.
- Keep predicates sargable: avoid wrapping indexed columns in functions, avoid leading-wildcard `LIKE` for indexed lookup, and avoid accidental type-affinity mismatches.
- Run `ANALYZE` or `PRAGMA optimize` when statistics materially affect planning, especially after large data changes.

## SQLite-Specific Review Points

- Enable and test foreign keys with `PRAGMA foreign_keys = ON` per connection when relying on references.
- Use constraints as part of the model: `NOT NULL`, `UNIQUE`, `CHECK`, foreign keys, and `STRICT` tables where supported and compatible.
- Choose conflict behavior deliberately. `INSERT OR REPLACE` deletes and reinserts; prefer explicit `ON CONFLICT DO UPDATE` when preserving row identity, triggers, and foreign-key relationships matters.
- Use WAL, `busy_timeout`, and short write transactions for concurrent readers/writers. Avoid long-running transactions on shared connections.
- Keep migrations forward-safe: create new tables/indexes, copy data in bounded batches when needed, validate counts/constraints, and make reruns harmless.

## Output Style

When giving guidance, include the reason for each recommendation and the risk it addresses. For reviews, lead with concrete bugs or risks, then provide a corrected SQL or schema snippet and the verification command or test that proves it.
