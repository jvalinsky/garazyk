# Shared vs Actor Database Boundary

Garazyk bifurcates storage into shared service databases and isolated per-actor stores. This split ensures process-wide data is decoupled from individual repository state.

## Architecture

```mermaid
flowchart TD
    App["Application and services"]
    Shared["ServiceDatabases and __service__ store"]
    ServiceDB["service, did-cache, and sequencer databases"]
    Pool["DatabasePool"]
    Actor["ActorStore for one DID"]
    ActorDB["Per-actor repository database"]

    App --> Shared
    Shared --> ServiceDB
    App --> Pool
    Pool --> Actor
    Actor --> ActorDB
```

## Storage Isolation
- **Service Databases**: Manage process-wide data, including the sequencer and DID cache.
- **Actor Stores**: Manage repository, block, and blob metadata for a single DID.

Queries against the shared service database operate independently of actor-specific stores.

## Implementation Path

### Account and Service Lookup
`ServiceDatabases.m` utilizes a dedicated pool for the `__service__` synthetic DID to manage shared stores.

### Per-Actor Operations
`DatabasePool.m` uses `storeForDid:` to resolve sharded actor paths. It instantiates or reuses an `ActorStore` for the specific DID.

## Data Placement Guidelines

### Service Databases
- Account metadata and invite codes.
- Authentication sessions and same-handle early returns.
- DID cache and sequencer event sequencing.
- Global operational configuration.

### Actor Stores
- Repository records and the Merkle Search Tree (MST) root.
- IPLD blocks and commit tombstones.
- Blob metadata and per-actor repository state.

## Debugging Surfaces
- **Global Failures**: Investigate `ServiceDatabases.m` for account, session, or sequencer issues.
- **Path Resolution**: Investigate `DatabasePool.m` if DID-specific storage paths fail to resolve or open.
- **State Corruption**: Investigate `ActorStore.m` for repository or block integrity failures.

## Related
- [SQLite Architecture](./sqlite-architecture)
- [Database Pool Tests](../11-reference/testing-map)
- [Repository Basics](../07-repository-protocol/repository-basics)

