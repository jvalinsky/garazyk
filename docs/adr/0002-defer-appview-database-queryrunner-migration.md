# ADR 0002 — Defer AppViewDatabase migration to QueryRunner

**Status:** Accepted
**Date:** 2026-07-11
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

## Consequences

- AppView retains raw `sqlite3_*` and 39 inline `CREATE TABLE` statements with no migration
  path (see also the separate migration-engine adoption opportunity, report candidate 6).
- Revisit only when **both** hold: (a) the QueryRunner pilot has proven the mechanics-routing
  pattern, and (b) a concurrency/pooling migration for AppView has been scoped as its own
  effort (likely involving `ATProtoConnectionManagerPooled`).
- Future architecture reviews should treat AppView as a **concurrency migration**, not a
  simple "finish adoption" item, and not re-raise it as low-hanging fruit.
