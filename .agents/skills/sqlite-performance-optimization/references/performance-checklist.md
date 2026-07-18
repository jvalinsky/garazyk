# SQLite Performance Optimization Checklist

## Connection Initialization

- [ ] `PRAGMA journal_mode = WAL` set (persists in DB, verify once)
- [ ] `PRAGMA synchronous = NORMAL` set (per-connection)
- [ ] `PRAGMA foreign_keys = ON` set (per-connection)
- [ ] `PRAGMA busy_timeout = 5000` set (per-connection)
- [ ] `PRAGMA cache_size` set appropriately (negative = KB)
- [ ] `PRAGMA temp_store = MEMORY` set
- [ ] `PRAGMA mmap_size` set for read-heavy workloads
- [ ] All session PRAGMAs run on every new connection

## Query Analysis

- [ ] `EXPLAIN QUERY PLAN` run on slow queries
- [ ] Full table scans identified (`SCAN TABLE` on large tables)
- [ ] Temp B-tree sorts/grouping identified (`USE TEMP B-TREE`)
- [ ] Index usage confirmed (`SEARCH TABLE USING INDEX`)
- [ ] Query plan checked with realistic data volumes

## Index Audit

- [ ] Columns in WHERE clauses have matching indexes
- [ ] Equality columns precede range columns in composite indexes
- [ ] JOIN columns indexed
- [ ] ORDER BY / GROUP BY columns indexed or match index prefix
- [ ] Leftmost prefix rule verified
- [ ] No redundant indexes (one is prefix of another)
- [ ] Partial indexes used for filtered subsets (active records, pending items)
- [ ] Covering indexes used for hot read paths
- [ ] Unused indexes identified and dropped
- [ ] Indexes verified with `EXPLAIN QUERY PLAN`

## Query Rewrites

- [ ] `SELECT *` replaced with explicit column list on hot paths
- [ ] Functions on indexed columns eliminated (sargable predicates)
- [ ] Leading wildcard `LIKE '%...'` replaced with trailing wildcard or FTS
- [ ] Deep `OFFSET` replaced with keyset pagination
- [ ] Type-affinity mismatches fixed (integer vs text comparisons)
- [ ] Autocommit loops replaced with batched transactions

## Write Optimization

- [ ] Bulk inserts wrapped in transactions
- [ ] `INSERT OR REPLACE` replaced with `ON CONFLICT DO UPDATE` where FK/trigger preservation matters
- [ ] `BEGIN IMMEDIATE` used for write transactions that should fail fast on contention
- [ ] Write transactions kept short (no network calls inside)
- [ ] Long-running read transactions avoided (they block writers in WAL)

## Concurrency

- [ ] WAL mode enabled for mixed read/write workloads
- [ ] Connection pool configured with single writer, multiple readers
- [ ] `busy_timeout` set to handle normal contention
- [ ] No SQLite connections shared across threads without explicit contract
- [ ] `PRAGMA wal_autocheckpoint` set appropriately (default 1000 is fine)

## Storage & Maintenance

- [ ] `PRAGMA optimize` run after large data changes
- [ ] `VACUUM` scheduled after bulk deletes or schema changes
- [ ] `PRAGMA incremental_vacuum` used if auto_vacuum=INCREMENTAL
- [ ] Database file size monitored
- [ ] Large BLOBs (>1MB) stored externally
- [ ] Page size appropriate for row size (4096 default, 32768 for large rows)

## Security (Performance-Adjacent)

- [ ] Prepared statements used for all values (prevents injection + enables plan cache)
- [ ] Dynamic identifiers from allowlists only
- [ ] Database file permissions restricted
- [ ] Extension loading disabled
- [ ] Secrets redacted from SQL logs

## Verification

- [ ] Before/after benchmarks for each optimization
- [ ] `EXPLAIN QUERY PLAN` confirms index usage after changes
- [ ] `PRAGMA integrity_check` passes after schema changes
- [ ] Migrations tested on realistic data volumes
- [ ] Performance regression tests in place for critical queries
