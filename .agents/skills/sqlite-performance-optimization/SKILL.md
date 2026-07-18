---
name: sqlite-performance-optimization
description: "Deep SQLite performance optimization: query plan analysis, indexing strategies, PRAGMA tuning, advanced SQL patterns, write batching, and storage management. Use when optimizing slow SQLite queries, designing indexes, tuning PRAGMAs, rewriting queries for performance, profiling database operations, or configuring SQLite for production workloads."
---

# SQLite Performance Optimization

Expert guidance for making SQLite fast. Covers query analysis, indexing, PRAGMA tuning, advanced SQL patterns, write optimization, and storage management. Synthesized from SQLite documentation, production hardening guides, and real-world benchmarks.

## Core Workflow

1. **Measure first.** Run `EXPLAIN QUERY PLAN` on the actual query with realistic data volumes. Never guess.
2. **Identify the bottleneck.** Full table scan? Wrong index? Sort in memory? Lock contention? Large result set?
3. **Apply the smallest fix.** Add a targeted index, rewrite a predicate, or adjust a PRAGMA. Avoid premature optimization.
4. **Verify the fix.** Re-run `EXPLAIN QUERY PLAN` and benchmark before and after. Confirm the plan changed.
5. **Document the decision.** Record what was slow, what fixed it, and why. Future you will thank present you.

## Query Plan Analysis

`EXPLAIN QUERY PLAN` is the single most important performance tool. Read it.

### Reading the Output

```
SEARCH TABLE users USING INDEX idx_users_email (email=?)
SCAN TABLE posts USING INDEX idx_posts_created (created_at>?)
USE TEMP B-TREE FOR ORDER BY
USE TEMP B-TREE FOR GROUP BY
```

**Good signals:** `SEARCH` with an index name, `COVERING INDEX` (index-only scan), `USING INDEX` with matching predicates.

**Bad signals:** `SCAN TABLE` on large tables (full table scan), `USE TEMP B-TREE` for sorting/grouping (no suitable index), `SCAN TABLE` with `WHERE` clause (missing index).

### Systematic Analysis

```sql
-- Run this before any optimization attempt
EXPLAIN QUERY PLAN
SELECT * FROM users WHERE email = 'test@example.com';

-- For complex queries, add ANALYZE for actual row counts
EXPLAIN QUERY PLAN
SELECT u.name, COUNT(p.id)
FROM users u
JOIN posts p ON p.user_id = u.id
WHERE u.created_at > '2024-01-01'
GROUP BY u.id
ORDER BY COUNT(p.id) DESC
LIMIT 10;
```

### Common Plan Patterns to Recognize

| Plan Pattern | What It Means | Fix |
|---|---|---|
| `SCAN TABLE x` | Full table scan, no index used | Add an index on filtered/joined columns |
| `SEARCH TABLE x USING INDEX idx` | Index lookup, usually good | Verify it's the right index |
| `USE TEMP B-TREE FOR ORDER BY` | Sorting in temp storage | Add an index matching the ORDER BY |
| `USE TEMP B-TREE FOR GROUP BY` | Grouping in temp storage | Add an index on GROUP BY columns |
| `SCAN TABLE x USING covering index` | Index-only scan, ideal | No fix needed |

## Index Strategies

### Index Types and When to Use Them

**B-tree (default):** Covers 90% of use cases. Good for equality, range, and ORDER BY.

```sql
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_posts_user_created ON posts(user_id, created_at);
```

**Partial indexes:** Index only the rows you actually query. Saves space and write cost.

```sql
-- Only index active records
CREATE INDEX idx_users_active ON users(last_login)
WHERE status = 'active';

-- Only index pending items (common filter)
CREATE INDEX idx_orders_pending ON orders(created_at, customer_id)
WHERE status = 'pending';
```

**Covering indexes:** Include all columns needed by a query to avoid table lookups entirely.

```sql
-- Query: SELECT user_id, created_at FROM posts WHERE user_id = ? ORDER BY created_at DESC
CREATE INDEX idx_posts_covering ON posts(user_id, created_at);
-- SQLite can answer this entirely from the index (EXPLAIN will show "COVERING INDEX")
```

**Expression indexes:** Index computed values when the same expression is used consistently.

```sql
-- For case-insensitive email lookups
CREATE INDEX idx_users_email_lower ON users(LOWER(email));
-- Query must use the same expression: WHERE LOWER(email) = ?
```

**Unique indexes:** Enforce data integrity and provide fast lookups.

```sql
CREATE UNIQUE INDEX idx_users_email_unique ON users(email);
```

### Composite Index Design Rules

1. **Equality columns first, range columns second.** `WHERE a = ? AND b > ?` needs `(a, b)`.
2. **Match query ORDER BY.** An index on `(a, b)` satisfies `ORDER BY a, b` but not `ORDER BY b, a`.
3. **Leftmost prefix rule.** Index `(a, b, c)` helps queries on `a`, `(a, b)`, and `(a, b, c)` but not `b` alone or `(b, c)`.
4. **Avoid redundant indexes.** `(a, b)` already covers `(a)`. Don't create both unless planner behavior differs.

### Index Maintenance

```sql
-- Find unused indexes (check after significant workload)
SELECT * FROM sqlite_stat1;  -- Shows index usage statistics

-- Drop unused indexes to improve write performance
DROP INDEX IF EXISTS idx_old_unused;

-- Verify index is being used
EXPLAIN QUERY PLAN SELECT ... WHERE ...;
```

## PRAGMA Tuning

### Production Baseline

Apply these on every connection open:

```sql
PRAGMA journal_mode = WAL;           -- Concurrent reads during writes
PRAGMA synchronous = NORMAL;         -- Good balance of safety/speed with WAL
PRAGMA foreign_keys = ON;            -- Enforce referential integrity
PRAGMA busy_timeout = 5000;          -- Wait 5s before SQLITE_BUSY
PRAGMA cache_size = -20000;          -- 20MB page cache (negative = KB)
PRAGMA temp_store = MEMORY;          -- Temp tables in RAM
PRAGMA mmap_size = 268435456;        -- 256MB memory-mapped I/O
```

### Synchronous Modes

| Mode | fsync Behavior | Use When |
|---|---|---|
| `OFF` | No fsync | Never in production. Data loss risk. |
| `NORMAL` | WAL fsync deferred | **Default for WAL.** Best balance. |
| `FULL` | Every commit fsyncs | Critical financial data, non-WAL. |
| `EXTRA` | fsync + metadata fsync | Maximum safety. Rare. |

**With WAL, `NORMAL` is almost always correct.** The WAL file provides crash recovery; `FULL` adds redundant fsyncs.

### Cache and Memory

```sql
-- Page cache (negative = KB, positive = pages)
PRAGMA cache_size = -64000;          -- 64MB for read-heavy workloads

-- Memory-mapped I/O (read-only, skips copy from OS page cache)
PRAGMA mmap_size = 268435456;        -- 256MB. Set to 0 to disable.

-- WARNING: Don't set both cache_size and mmap_size too high
-- They can maintain redundant copies of the same pages in RAM
```

### Auto-Vacuum

```sql
-- Set on empty database only
PRAGMA auto_vacuum = INCREMENTAL;    -- Reclaim space without full VACUUM

-- Periodic cleanup
PRAGMA incremental_vacuum;           -- Reclaim one page group per call
```

### Statistics

```sql
-- Update query planner statistics (run after large data changes)
PRAGMA optimize;

-- Check database integrity (diagnostic, not a performance tool)
PRAGMA quick_check;
```

### Persistent vs Session PRAGMAs

**Persistent** (written to database file, survive all connections):
`journal_mode`, `auto_vacuum`, `encoding`, `page_size`, `application_id`, `user_version`

**Session** (per-connection, reset on reconnect):
`synchronous`, `busy_timeout`, `cache_size`, `mmap_size`, `temp_store`, `foreign_keys`, `wal_autocheckpoint`

**Implication:** Set session PRAGMAs in connection-open code. Set persistent PRAGMAs once during schema initialization.

## Advanced SQL Patterns

### Window Functions (SQLite 3.25+)

Window functions compute across rows without collapsing them like GROUP BY.

```sql
-- Ranking within groups
SELECT name, department, salary,
  ROW_NUMBER() OVER (PARTITION BY department ORDER BY salary DESC) AS dept_rank
FROM employees;

-- Running totals
SELECT sale_date, amount,
  SUM(amount) OVER (ORDER BY sale_date
    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_total
FROM daily_sales;

-- Period-over-period comparison
SELECT month, revenue,
  LAG(revenue) OVER (ORDER BY month) AS prev_month,
  revenue - LAG(revenue) OVER (ORDER BY month) AS change
FROM monthly_sales;

-- Top-N per group (the classic use case)
WITH ranked AS (
  SELECT name, department, salary,
    RANK() OVER (PARTITION BY department ORDER BY salary DESC) AS rnk
  FROM employees
)
SELECT * FROM ranked WHERE rnk <= 3;
```

**Common mistakes:**
- Cannot filter on window function results in WHERE. Wrap in subquery/CTE.
- `LAST_VALUE` returns current row by default (RANGE frame). Set explicit ROWS frame.
- Non-deterministic `ROW_NUMBER` with ties: add unique column as tiebreaker.
- Window functions require SQLite 3.25.0+. Verify with `SELECT sqlite_version()`.

### CTEs (Common Table Expressions)

```sql
-- Basic CTE for readability
WITH active_users AS (
  SELECT id, name FROM users WHERE status = 'active'
)
SELECT au.name, COUNT(p.id)
FROM active_users au
JOIN posts p ON p.user_id = au.id
GROUP BY au.id;

-- Recursive CTE for tree traversal
WITH RECURSIVE ancestors(id, name, parent_id, depth) AS (
  SELECT id, name, parent_id, 0 FROM categories WHERE parent_id IS NULL
  UNION ALL
  SELECT c.id, c.name, c.parent_id, a.depth + 1
  FROM categories c
  JOIN ancestors a ON c.parent_id = a.id
)
SELECT * FROM ancestors WHERE depth <= 3;

-- Recursive CTE for date series generation
WITH RECURSIVE dates(d) AS (
  SELECT DATE('2024-01-01')
  UNION ALL
  SELECT DATE(d, '+1 day') FROM dates WHERE d < DATE('2024-12-31')
)
SELECT d FROM dates;
```

**Performance note:** SQLite may re-evaluate CTEs on each reference. If a CTE is referenced multiple times, consider materializing it into a temp table.

### Sargable Predicates

Make predicates that the index can use:

```sql
-- BAD: Function on indexed column defeats index
WHERE YEAR(created_at) = 2024
WHERE LOWER(email) = 'test@example.com'
WHERE CAST(id AS TEXT) = '123'

-- GOOD: Rewrite to use index
WHERE created_at >= '2024-01-01' AND created_at < '2025-01-01'
WHERE email = 'test@example.com'  -- with COLLATE NOCASE if needed
WHERE id = 123

-- BAD: Leading wildcard
WHERE name LIKE '%smith'

-- GOOD: Trailing wildcard (can use index)
WHERE name LIKE 'smith%'

-- GOOD: Expression index for case-insensitive
CREATE INDEX idx_users_email_lower ON users(LOWER(email));
WHERE LOWER(email) = 'test@example.com'
```

### Pagination Patterns

```sql
-- BAD: Deep OFFSET is slow (scans and discards all prior rows)
SELECT * FROM posts ORDER BY created_at DESC LIMIT 20 OFFSET 10000;

-- GOOD: Keyset pagination (constant-time regardless of position)
SELECT * FROM posts
WHERE (created_at, id) < (?, ?)
ORDER BY created_at DESC, id DESC
LIMIT 20;

-- GOOD: For total count, use separate count query or window function
SELECT COUNT(*) OVER () AS total, p.*
FROM posts p
WHERE (created_at, id) < (?, ?)
ORDER BY created_at DESC, id DESC
LIMIT 20;
```

## Write Optimization

### Batch Inserts in Transactions

```sql
-- BAD: Individual inserts (autocommit, fsync per insert)
INSERT INTO logs (msg) VALUES ('a');
INSERT INTO logs (msg) VALUES ('b');
INSERT INTO logs (msg) VALUES ('c');

-- GOOD: Single transaction (one fsync for all)
BEGIN;
INSERT INTO logs (msg) VALUES ('a');
INSERT INTO logs (msg) VALUES ('b');
INSERT INTO logs (msg) VALUES ('c');
COMMIT;

-- BETTER: Single-statement batch
INSERT INTO logs (msg) VALUES ('a'), ('b'), ('c');
```

**Impact:** Autocommit inserts are 50-100x slower than batched. This is the single biggest write performance win.

### UPSERT Patterns

```sql
-- GOOD: Atomic insert-or-update
INSERT INTO counters (name, value) VALUES ('visits', 1)
ON CONFLICT(name) DO UPDATE SET value = value + 1;

-- AVOID: INSERT OR REPLACE (deletes and reinserts, breaks FKs/triggers)
-- INSERT OR REPLACE INTO counters (name, value) VALUES ('visits', 1);
```

### Write Transaction Patterns

```sql
-- Use BEGIN IMMEDIATE when the transaction must write soon
-- (fails immediately if another writer holds the lock)
BEGIN IMMEDIATE;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
COMMIT;

-- For long read-then-write, use deferred to avoid early lock
BEGIN DEFERRED;
SELECT balance FROM accounts WHERE id = 1;  -- reads don't lock
-- decide whether to write...
UPDATE accounts SET balance = balance - 100 WHERE id = 1;  -- acquires write lock
COMMIT;
```

## Storage Optimization

### VACUUM

```sql
-- Full VACUUM: rewrites entire database file, removes fragmentation
-- Requires 2x free disk space. Blocks readers during operation.
VACUUM;

-- Incremental VACUUM: reclaim space without full rewrite
PRAGMA auto_vacuum = INCREMENTAL;
-- Then periodically:
PRAGMA incremental_vacuum;
```

### Page Size

```sql
-- Set on empty database only (default 4096)
PRAGMA page_size = 32768;  -- 32KB for large databases with big rows
-- Smaller pages for small databases, larger for big rows/BLOBs
```

### When to VACUUM

- After deleting large amounts of data
- When database file is significantly larger than actual data
- Before backup or migration
- After schema changes that dropped columns/tables

### Monitoring Database Size

```sql
-- Check actual data size vs file size
SELECT
  page_count * page_size AS file_size,
  (SELECT SUM(data_length) FROM sqlite_stat1) AS data_estimate
FROM pragma_page_count(), pragma_page_size();
```

## Concurrency Patterns

### WAL Mode Best Practices

1. **Enable WAL once.** It persists in the database file. Don't re-set it on every connection.
2. **Readers don't block writers, writers don't block readers.** This is the key benefit.
3. **Writers are still serialized.** Only one write transaction at a time.
4. **Checkpoint automatically.** Default `wal_autocheckpoint = 1000` pages is fine for most workloads.

### Connection Pooling

```
Read-heavy: 1 writer + 4-8 readers (readers scale freely under WAL)
Write-heavy: Single writer connection (serialization is unavoidable)
Mixed: 1 writer + pooled readers, semaphore-based max connections
```

### Avoiding SQLITE_BUSY

```sql
-- Always set busy_timeout (5-10 seconds for most workloads)
PRAGMA busy_timeout = 5000;

-- For critical writes, BEGIN IMMEDIATE to acquire lock early
BEGIN IMMEDIATE;
-- ... write operations ...
COMMIT;
```

## Performance Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| `SELECT *` on wide tables | Fetches unused columns, defeats covering indexes | Select only needed columns |
| Functions on indexed columns | Defeats index usage, forces full scan | Rewrite predicate to be sargable |
| Deep `OFFSET` pagination | Scans and discards rows, O(n) cost | Keyset pagination |
| Autocommit inserts | Fsync per row, 50-100x slower | Batch in transactions |
| Too many indexes | Slows writes, increases storage | Drop unused indexes |
| Missing `EXPLAIN QUERY PLAN` | Blind optimization | Always measure |
| Long write transactions | Blocks all writers | Keep short, avoid network calls inside |
| No `busy_timeout` | Immediate SQLITE_BUSY errors | Set to 3000-10000ms |
| Inconsistent PRAGMAs across connections | Different behavior per connection | Set in connection-open code |
| Stale statistics | Bad query plans after data changes | Run `PRAGMA optimize` |

## Quick Reference

### Essential PRAGMAs for Production

```sql
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA foreign_keys = ON;
PRAGMA busy_timeout = 5000;
PRAGMA cache_size = -20000;
PRAGMA temp_store = MEMORY;
PRAGMA mmap_size = 268435456;
```

### Diagnostic Commands

```sql
EXPLAIN QUERY PLAN <query>;           -- See how query executes
PRAGMA optimize;                       -- Update statistics
PRAGMA integrity_check;                -- Verify database health
PRAGMA quick_check;                    -- Fast integrity check
SELECT sqlite_version();              -- Check SQLite version
PRAGMA journal_mode;                   -- Verify WAL is enabled
PRAGMA synchronous;                    -- Check sync level
PRAGMA cache_size;                     -- Check cache setting
```

### Index Design Checklist

- [ ] Indexes on columns in WHERE clauses (equality first, then range)
- [ ] Indexes on JOIN columns
- [ ] Indexes matching ORDER BY / GROUP BY
- [ ] No duplicate indexes (one is prefix of another)
- [ ] Partial indexes for filtered subsets
- [ ] Covering indexes for hot read paths
- [ ] All verified with `EXPLAIN QUERY PLAN`

## References

- [SQLite Query Optimizer Overview](https://sqlite.org/optoverview.html) -- Official documentation on how the planner works
- [SQLite PRAGMA Settings](https://sqlite.org/pragma.html) -- Complete PRAGMA reference
- [SQLite WAL Mode](https://www.sqlite.org/wal.html) -- Write-Ahead Logging documentation
- [SQLite Memory-Mapped I/O](https://sqlite.org/mmap.html) -- mmap configuration details
