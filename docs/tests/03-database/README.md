# Database Tests

Tests for SQLite-based persistence: actor stores, service databases, and connection pooling.

## Files

| File | Description |
|------|-------------|
| [actor-store.md](actor-store.md) | Per-user SQLite storage for accounts, records, blocks, blobs, signing keys |
| [service-databases.md](service-databases.md) | Global service databases for accounts, invite codes, DID cache, handle reservations |
| [pool-integration.md](pool-integration.md) | Connection pooling with LRU eviction, concurrent access, health checks |

## Test Classes

| Class | File Location | Purpose |
|-------|---------------|---------|
| ActorStoreTests | Tests/Database/ActorStore/ActorStoreTests.m | Per-actor storage |
| DatabasePoolTests | Tests/Database/Pool/DatabasePoolTests.m | LRU eviction |
| ServiceDatabasesTests | Tests/Database/Service/ServiceDatabasesTests.m | Service database manager |
| ServiceDatabasesPruningTests | Tests/ServiceDatabasesPruningTests.m | Event pruning |
| PDSHealthCheckTests | Tests/Database/Monitoring/PDSHealthCheckTests.m | Database health |
| PDSDatabaseIntegrationTests | Tests/Database/Integration/PDSDatabaseIntegrationTests.m | E2E database ops |
| DatabaseMigrationTests | Tests/Database/DatabaseMigrationTests.m | Schema migrations |
| MultiTenantDatabaseTests | Tests/Database/MultiTenantDatabaseTests.m | Tenant isolation |

## Running Tests

```bash
./build/tests/AllTests -only-testing:AllTests/ActorStoreTests
./build/tests/AllTests -only-testing:AllTests/DatabasePoolTests
./build/tests/AllTests -only-testing:AllTests/ServiceDatabasesTests
```
