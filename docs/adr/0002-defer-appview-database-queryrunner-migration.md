# ADR 0002 — Defer AppViewDatabase migration to QueryRunner

**Status:** Superseded
**Date:** 2026-07-11
**Superseded:** 2026-07-24 — both conditions met; see below.
**Context skill:** raised during the QueryRunner deepening pilot
(`queryrunner_deepening_pilot_plan.md`).

## Context

`AppView/Server/AppViewDatabase.m` uses raw `sqlite3_*` (≈34 calls) behind a 39-table schema
with cursors and a dead-letter path. It is a natural-looking target for
`ATProtoDatabaseQueryRunner` adoption on the surface — "another store running raw SQLite."

However, the May-2026 refactor audit (`refactor_opportunity_audit_report.md`) already ranked
"AppView connection unification" last and **deferred** it, explicitly because it changes
**concurrency assumptions** (connection pooling), not merely because it removes duplicated
prepare/bind/step/finalize boilerplate.

The QueryRunner pilot confirmed the distinction: routing a store's *mechanics* through
QueryRunner is safe when the store already uses `ATProtoConnectionManagerSerial` (the adapter
serializes via its own `dispatch_queue`). AppView's open question is not mechanics — it is
whether it should move to a **pooled** connection model, which is a separate design decision
with its own correctness and performance implications.

## Decision

`AppViewDatabase` **stays off** `ATProtoDatabaseQueryRunner` for now. Its migration is coupled
to a deliberate concurrency/pooling decision and is **not** part of the "finish QueryRunner
adoption" work. It keeps its raw SQLite mechanics and inline schema until that decision is
made.

## Supersession

Both conditions from the original "Consequences" section are now met:

1. **QueryRunner pattern proven** — the pilot shipped and multiple stores adopted
   `ATProtoDatabaseQueryRunner` without regressions.
2. **Pooling migration scoped and completed** — commit `e1f5ee2f` replaced the serial
   dispatch queue with `ATProtoConnectionPool` (min 1, max 8) +
   `ATProtoConnectionManagerPooled` + `ATProtoDatabaseQueryRunner`. All 30 AppViewDatabase
   tests passed.

The inline schema management (`kSchemaV1`, `appview_schema_version` table, hand-rolled
migration switch) was subsequently migrated to `PDSMigrationManager` classes
(`AppViewV1InitialSchema` through `AppViewV4LegacySchemaBridge`), completing the adoption.

## Consequences

- **Superseded.** The conditions listed below were met and `AppViewDatabase` was migrated
  to `ATProtoDatabaseQueryRunner` + `ATProtoConnectionManagerPooled` (commit `e1f5ee2f`).
  Inline schema was migrated to `PDSMigrationManager` classes. This ADR is retained for
  historical context only.
- ~~Revisit only when **both** hold: (a) the QueryRunner pilot has proven the mechanics-routing
  pattern, and (b) a concurrency/pooling migration for AppView has been scoped as its own
  effort (likely involving `ATProtoConnectionManagerPooled`).~~
- ~~Future architecture reviews should treat AppView as a **concurrency migration**, not a
  simple "finish adoption" item, and not re-raise it as low-hanging fruit.~~
