# Refactor 5: Test Coverage

## Evidence

- **370 out of 372 source files** have no direct unit test match
- The architecture audit found 0 test files in `Tests/` (test runner path mismatch)
- Most uncovered modules:
  - Network: 72 uncovered files
  - AppView: 38 uncovered files
  - Auth: 33 uncovered files
  - Core: 29 uncovered files
  - Sync: 22 uncovered files
  - Database: 17 uncovered files

## Why It Matters

Refactoring the monolithic files (Refactors 1-4) is unsafe without characterization tests. External consumers need confidence in the library's correctness. The existing scenario test suite in `scripts/scenarios/` provides integration coverage, but there are no fast, focused unit tests.

## Strategy: Characterization Tests First

For each refactoring target, write tests that capture **current behavior** before changing anything. These tests encode the contract and catch regressions.

### Tier 1: Database Layer (prerequisite for Refactors 1, 2)

| Target | Files | Test Priorities |
|--------|-------|-----------------|
| PDSDatabase (Accounts) | PDSDatabase.m:accounts | CRUD, pagination, error cases |
| PDSDatabase (Records) | PDSDatabase.m:records | CRUD, URI parsing |
| PDSDatabase (Blocks) | PDSDatabase.m:blocks | CRUD, batch save |
| PDSDatabase (Blobs) | PDSDatabase.m:blobs | CRUD, per-DID listing |
| PDSDatabase (Transactions) | PDSDatabase.m:txn | commit, rollback, nesting |
| PDSDatabase (Moderation) | PDSDatabase.m:moderation | takedown, labels |
| PDSDatabase (AdminAudit) | PDSDatabase.m:audit | log entry, query, cleanup |
| PDSDatabase (Reports) | PDSDatabase.m:reports | create, query, status update |
| PDSDatabase (AdminConfig) | PDSDatabase.m:config | set/get config |
| PDSDatabase (VideoJobs) | PDSDatabase.m:video | create, update state, list |
| PDSConnectionPool | Pool/ | checkout/checkin, timeout, pruning |
| PDSDatabasePool | Pool/ | LRU eviction, DID sharding |

### Tier 2: XRPC Layer (prerequisite for Refactor 3)

| Target | Files | Test Priorities |
|--------|-------|-----------------|
| XrpcHandler | Network/XrpcHandler.m | dispatch, auth, validation |
| XrpcMethodRegistry | Network/XrpcMethodRegistry.m | registration, lookup, conflicts |
| Individual packs | Network/Xrpc*Pack.m | each pack: method count, auth requirements, input validation |
| RateLimiter | Network/RateLimiter.m | rate calculation, burst, cleanup |

### Tier 3: Service Layer (prerequisite for Refactor 4)

| Target | Files | Test Priorities |
|--------|-------|-----------------|
| PDSRecordService | Services/PDS/ | record lifecycle |
| PDSAccountService | Services/PDS/ | create, auth, tokens |
| PDSBlobService | Services/PDS/ | upload, verify, quota |

## Test Patterns to Follow

Based on existing tests in `Garazyk/Tests/`:

```objc
// Example: XRPCErrorTests.m pattern
- (void)testSomething {
    // Arrange
    // Act
    // Assert
}
```

Use:
- `Garazyk/Tests/fixtures/` for test data
- `XCTestExpectation` for async operations
- `dispatch_sync` / `dispatch_async` patterns consistent with source code conventions

## Staging

| Step | Description | Effort |
|------|-------------|--------|
| 1 | Database characterization tests for PDSDatabase | 3-4 sessions |
| 2 | Database pool tests | 1 session |
| 3 | XRPC handler + registry tests | 2 sessions |
| 4 | XRPC pack tests (top 5 by size) | 2-3 sessions |
| 5 | Service layer tests | 2 sessions |
| 6 | Binary startup tests | 1 session |

## Dependencies

- Test infrastructure is already in place (`scripts/test/run-tests.sh`, XCTest runner `Tests/test_main.m`)
- Tests should be written BEFORE each matching refactor

## Confidence: Medium

The scenario suite provides integration coverage. Unit tests are additive. The main risk is that some files are hard to test due to tight coupling — which is exactly why these tests are valuable before refactoring.
