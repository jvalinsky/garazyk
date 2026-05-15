# SQLite Architecture

Garazyk uses SQLite as a distributed, application-level storage system. Data is split between shared service databases and isolated per-actor stores.

## Architectural Choices
- **Tenant Isolation**: Actor repository state is isolated into individual database files.
- **Shared Infrastructure**: Sessions, account metadata, DID caches, and sequencer data reside in shared service stores.
- **Concurrency Control**: Write-Ahead Logging (WAL) mode enables concurrent reads and writes.
- **Data Access**: The storage layer enforces the use of prepared statements and explicit transaction boundaries.

## Database Families

### Service Databases
Service databases manage shared operational state for the entire process. This includes user accounts, authentication sessions, and configuration.

### Actor Databases
Actor databases store the repository, blocks, and blob metadata for a single DID. These are managed and opened via the `PDSDatabasePool`.

This boundary ensures that repository-level mutations are isolated from global service state.

## Implementation Guidelines
When modifying persistence logic, identify:
1. **Ownership**: Which database family owns the target data?
2. **Scope**: Is the operation scoped to a single actor or the entire runtime?
3. **Atomicity**: Does the operation require cross-database consistency or specific transaction ordering?

## Related Deep Dives
- [Shared vs Actor Database Boundary](./shared-vs-actor-database-boundary)
- [Transactions, WAL, and Concurrency](./transactions-wal-and-concurrency)
- [Service Databases](./service-databases)
- [Actor Databases](./actor-databases)
- [WAL Mode](./wal-mode)
- [Migrations](./migrations)
- [Zero Downtime Migrations](./zero-downtime-migrations)

## Related Reading
- [Repository Basics](../07-repository-protocol/repository-basics)
- [Firehose Overview](../08-sync-firehose/firehose-overview)
- [Session and JWT Lifecycle](../06-authentication/session-and-jwt-lifecycle)
- [Glossary](../GLOSSARY)

