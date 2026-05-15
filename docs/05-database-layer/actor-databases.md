---
title: Actor Databases
---

# Actor Databases

## Overview

Actor databases hold per-DID repository state. Each actor store is isolated so record, block, commit, and blob metadata changes stay local to the owning repository instead of sharing one global data file.

## What Lives In An Actor Store

The actor path is where the runtime keeps:

- Records and tombstones
- Repository root and revision state
- Stored IPLD blocks and signed commit material
- Blob metadata tied to that actor

If a bug is specific to one repo, this is usually where the issue lies.

## Why Isolation Matters

Per-actor isolation provides several benefits:

- Repository mutations are easier to reason about.
- Corruption or migration issues are contained to a single actor.
- Debugging does not require a global shared schema mental model.

## Pooling And Path Selection

The runtime does not keep every actor database open. `PDSDatabasePool` resolves a sharded path from the DID, opens or reuses the actor store, and manages reuse and eviction.

## Related Deep Dives
- [Shared vs Actor Database Boundary](./shared-vs-actor-database-boundary)
- [Transactions, WAL, and Concurrency](./transactions-wal-and-concurrency)
- [WAL Mode](./wal-mode)
- [Data Integrity Verification](./data-integrity)

## Related Reading
- [SQLite Architecture](./sqlite-architecture)
- [Service Databases](./service-databases)
- [Repository Basics](../07-repository-protocol/repository-basics)
- [Record Write to Commit Walkthrough](../07-repository-protocol/record-write-to-commit-walkthrough)
- [Blob Storage](../07-repository-protocol/blob-storage)
- [Glossary](../GLOSSARY)

