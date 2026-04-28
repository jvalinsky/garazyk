---
title: Actor Databases
---

# Actor Databases

## Overview

Actor databases hold per-DID repository state. Each actor store is isolated so record, block, commit, and blob metadata changes stay local to the owning repository instead of sharing one global data file with every other account.

## What Lives In An Actor Store

The actor path is where the runtime keeps:

- records and tombstones
- repository root and revision state
- stored IPLD blocks and signed commit material
- blob metadata tied to that actor

If a bug is specific to one repo, this is usually the storage family you want.

## Why Isolation Matters

Per-actor isolation buys the codebase a few important properties:

- repository mutations are easier to reason about
- one actor's corruption or migration issue is easier to contain
- repository-level debugging does not require a global shared schema mental model

That is why repository and blob deep dives keep pointing back to actor stores.

## Pooling And Path Selection

The runtime does not keep every actor database permanently open. `DatabasePool` resolves a sharded path from the DID, opens or reuses the actor store, and manages reuse and eviction over time.

That means some actor-store bugs are really pool or path bugs, not record-format bugs.

## Related Deep Dives

- [Shared vs Actor Database Boundary](./shared-vs-actor-database-boundary)
- [Transactions, WAL, and Concurrency](./transactions-wal-and-concurrency)
- [Record Write to Commit Walkthrough](../07-repository-protocol/record-write-to-commit-walkthrough)

## Related Reading

- [SQLite Architecture](./sqlite-architecture)
- [Service Databases](./service-databases)
- [Repository Basics](../07-repository-protocol/repository-basics)

## Related

- [Documentation Map](../11-reference/documentation-map.md)
- [Contributor Guide](../index.md)
- [Repository Documentation Index](../repo-index/index.md)

