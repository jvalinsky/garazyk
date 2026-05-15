---
title: WAL Mode
---

# WAL Mode

## Overview

Garazyk enables SQLite Write-Ahead Logging (WAL) mode so reads can continue while writes are being staged. This is critical for performance in a multi-actor environment.

## Benefits of WAL Mode

- **Concurrent Access**: Read-heavy workloads for shared operational state are not blocked by writes.
- **Repository Performance**: Repository reads can occur during write activity without contention.
- **Practical Concurrency**: Provides a balance between the simplicity of SQLite and the need for concurrent access.

## What WAL Does Not Solve

WAL mode is not a magic bullet. It does not replace the need for:

- **Transaction Serialization**: Actor-store writes must still be serialized on their respective queues.
- **Ordering Decisions**: Service-layer coordination is still required across multiple store families.
- **Prepared Statements**: Proper use of prepared statements is still mandatory for performance and security.
- **Schema Discipline**: Migrations must still be handled carefully.

## Related Deep Dives
- [Shared vs Actor Database Boundary](./shared-vs-actor-database-boundary)
- [Transactions, WAL, and Concurrency](./transactions-wal-and-concurrency)
- [SQLite Architecture](./sqlite-architecture)

## Related Reading
- [Service Databases](./service-databases)
- [Actor Databases](./actor-databases)
- [Glossary](../GLOSSARY)

