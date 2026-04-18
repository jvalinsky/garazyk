---
title: WAL Mode
---

# WAL Mode

## Overview

Garazyk enables SQLite WAL mode so reads can continue while writes are being staged. That is an important performance and concurrency choice, but it is only one part of the storage story.

## What WAL Gives The Runtime

In this repo, WAL mode helps with:

- read-heavy workloads around shared operational state
- repository reads during write activity
- practical concurrency without abandoning SQLite

It improves the storage model, but it does not remove the need for explicit transaction boundaries or queueing discipline.

## What WAL Does Not Replace

WAL mode does not replace:

- actor-store transaction serialization
- service-layer ordering decisions across multiple store families
- careful prepared-statement usage
- migration and schema discipline

If a write path is logically wrong, WAL will not make it safe.

## Why Contributors Should Care

When storage bugs look like timing or lock problems, this page is the conceptual starting point. The deeper analysis still belongs in the transaction and boundary docs, because the runtime's actual behavior depends on WAL plus queueing plus transaction scope.

## Related Deep Dives

- [Shared vs Actor Database Boundary](./shared-vs-actor-database-boundary)
- [Transactions, WAL, and Concurrency](./transactions-wal-and-concurrency)

## Related Reading

- [SQLite Architecture](./sqlite-architecture)
- [Service Databases](./service-databases)
- [Actor Databases](./actor-databases)
