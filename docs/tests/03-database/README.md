---
title: Database Tests
---

# Database Tests

Tests for SQLite-based persistence: actor stores, service databases, and connection pooling.

## Files

| File | Description |
|------|-------------|
| [actor-store.md](actor-store) | Per-user SQLite storage for accounts, records, blocks, blobs, signing keys |
| [service-databases.md](service-databases) | Global service databases for accounts, invite codes, DID cache, handle reservations |
| [pool-integration.md](pool-integration) | Connection pooling with LRU eviction, concurrent access, health checks |

## Test Classes

| Class | File Location | Purpose |
|-------|---------------|---------|
| ActorStoreTests | Tests/Database/ActorStore/ActorStoreTests.m | Per-actor storage |
| DatabasePoolTests | Tests/Database/Pool/DatabasePoolTests.m | LRU eviction |
| ServiceDatabasesTests | Tests/Database/Service/ServiceDatabasesTests.m | Service database manager |
| ServiceDatabasesPruningTests | Tests/Database/Service/ServiceDatabasesPruningTests.m | Event pruning |
| PDSHealthCheckTests | Tests/Database/Monitoring/PDSHealthCheckTests.m | Database health |
| PDSDatabaseIntegrationTests | Tests/Database/Integration/PDSDatabaseIntegrationTests.m | E2E database ops |
| DatabaseMigrationTests | Tests/Database/Integration/DatabaseMigrationTests.m | Schema migrations |
| MultiTenantDatabaseTests | Tests/Database/Integration/MultiTenantDatabaseTests.m | Tenant isolation |
| PDSNewArchitectureTests | Tests/Database/PDSNewArchitectureTests.m | New architecture validation |
| PDSControllerTests | Tests/Database/PDSControllerTests.m | Controller database ops |

## Test Fixtures

| Fixture | File Location | Purpose |
|---------|---------------|---------|
| PDSDatabaseTestFixture | Tests/Database/Integration/PDSDatabaseTestFixture.m | Base test fixture |
| PDSDatabaseIntegrationTestSuite | Tests/Database/Integration/PDSDatabaseIntegrationTestSuite.m | Integration test suite |
| PDSDatabasePoolTestFixture | Tests/Database/Integration/PDSDatabasePoolTestFixture.m | Pool testing fixture |
| PDSMigrationTestFixture | Tests/Database/Integration/PDSMigrationTestFixture.m | Migration testing fixture |
| PDSMultiTenantTestFixture | Tests/Database/Integration/PDSMultiTenantTestFixture.m | Multi-tenant fixture |
| PDSSchemaValidationTestFixture | Tests/Database/Integration/PDSSchemaValidationTestFixture.m | Schema validation fixture |
| PDSConcurrentAccessTestFixture | Tests/Database/Integration/PDSConcurrentAccessTestFixture.m | Concurrent access fixture |

## Running Tests

```bash
./build/tests/AllTests -only-testing:AllTests/ActorStoreTests
./build/tests/AllTests -only-testing:AllTests/DatabasePoolTests
./build/tests/AllTests -only-testing:AllTests/ServiceDatabasesTests
```

## Related Documentation

- [Test Index](../README) - Main test documentation index
- [ATProto Architecture](../../architecture/atproto_pds_architecture) - System architecture
- [Repository Tests](../01-repository/README) - MST and CAR persistence
- [Application Tests](../04-application/README) - Services using databases
- [Integration Tests](../06-integration/README) - E2E database operations
- <!-- Link placeholder: SQLite Invariant Audit --> - SQLite correctness
