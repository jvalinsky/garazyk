---
title: SQLite Architecture
---

# SQLite Architecture

## Overview

September uses SQLite as an application-level storage system rather than as one monolithic database file. Shared operational data lives in service databases, while per-actor repository data lives in isolated actor stores opened through the database pool.

## Why SQLite Fits This Repo

The design depends on a few concrete choices:

- per-actor isolation for repository state
- shared stores for sessions, account metadata, DID cache, and sequencer data
- WAL mode for practical read/write concurrency
- prepared statements and explicit transactions in the storage layer

The interesting part is not "SQLite exists." The interesting part is how the repo splits ownership across store families.

## The Two Main Store Families

Keep this distinction clear:

- service databases hold shared operational state for the whole process
- actor databases hold one DID's repository, blocks, blob metadata, and related state

That boundary explains why a healthy account lookup does not prove a repository write path is healthy.

## What Contributors Usually Need To Know

When changing persistence code, the first questions are:

- which store family owns this data?
- is the operation local to one actor or shared across the whole runtime?
- does the change rely on transaction ordering, not just schema shape?

Those questions lead you to the right deep dive much faster than reading raw schema dumps.

## Related Deep Dives

- [Shared vs Actor Database Boundary](./shared-vs-actor-database-boundary)
- [Transactions, WAL, and Concurrency](./transactions-wal-and-concurrency)

## Related Reading

- [Service Databases](./service-databases)
- [Actor Databases](./actor-databases)
- [WAL Mode](./wal-mode)
- [Migrations](./migrations)
