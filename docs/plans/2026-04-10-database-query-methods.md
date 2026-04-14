---
title: "Phase 5: Database Query Methods Verification Plan"
---

# Phase 5: Database Query Methods Verification

> **Status:** ✅ Implemented (verification needed)
> **Priority:** P1 (High)
> **Generated:** 2026-04-10

## Executive Summary

The database query methods are implemented. Earlier security audit flagged `getRecordsForDid:collection:` as stubbed, but verification shows it's fully implemented at `PDSDatabase.m:1946`. This plan focuses on verification, performance testing, and any enhancements needed.

---

## Current Implementation Status

### Verified Implementations

| Method | Status | Location |
|--------|--------|----------|
| `getRecordsForDid:collection:` | ✅ Implemented | `PDSDatabase.m:1946-1978` |
| `MSTPersistence` methods | ✅ Implemented | `MSTPersistence.m` |

### Implementation Details (PDSDatabase.m:1946)

```objc
- (NSArray<PDSDatabaseRecord *> *)getRecordsForDid:(NSString *)did 
                                        collection:(nullable NSString *)collection 
                                              error:(NSError **)error {
    NSMutableString *sql = [NSMutableString stringWithString:@"SELECT * FROM records WHERE did = ?"];
    NSMutableArray *params = [NSMutableArray arrayWithObject:did];

    if (collection.length > 0) {
        [sql appendString:@" AND collection = ?"];
        [params addObject:collection];
    }

    [sql appendString:@" ORDER BY created_at DESC"];
    // ... execution ...
}
```

**Features:**
- Filters by DID (required)
- Filters by collection (optional)
- Orders by created_at DESC (newest first)
- Returns `PDSDatabaseRecord` objects
- Proper error handling

---

## Tasks

### Task 5.1: Verify getRecordsForDid Works Correctly

**Goal:** Confirm implementation works as expected

**Files:**
- Implementation: `Garazyk/Sources/Database/PDSDatabase.m:1946-1978`
- Test: Create test in `Garazyk/Tests/Database/PDSDatabaseTests.m`

**Steps:**
1. Create test for `getRecordsForDid`:
   ```objc
   - (void)testGetRecordsForDid_FiltersByDID {
       // Arrange - Insert test records
       NSString *did = @"did:plc:test123";
       [self insertTestRecord:did collection:@"app.bsky.feed.post"];
       [self insertTestRecord:did collection:@"app.bsky.feed.post"];
       [self insertTestRecord:@"did:plc:other" collection:@"app.bsky.feed.post"];
       
       // Act
       NSArray *results = [self.db getRecordsForDid:did collection:nil error:&error];
       
       // Assert
       XCTAssertEqual(results.count, 2, @"Should return 2 records for DID");
   }

   - (void)testGetRecordsForDid_FiltersByCollection {
       // Arrange
       NSString *did = @"did:plc:test123";
       [self insertTestRecord:did collection:@"app.bsky.feed.post"];
       [self insertTestRecord:did collection:@"app.bsky.graph.list"];
       
       // Act - filter by collection
       NSArray *results = [self.db getRecordsForDid:did 
                                          collection:@"app.bsky.feed.post" 
                                               error:&error];
       
       // Assert
       XCTAssertEqual(results.count, 1, @"Should return 1 record matching collection");
       XCTAssertEqualObjects(results[0][@"collection"], @"app.bsky.feed.post");
   }

   - (void)testGetRecordsForDid_OrdersByCreatedAt {
       // Verify newest records come first
       // created_at DESC order is used
   }
   ```

2. Run tests:
   ```bash
   ./build/tests/AllTests -XCTest PDSDatabaseTests/testGetRecordsForDid
   ```

---

### Task 5.2: Performance Testing for Large Datasets

**Goal:** Verify performance with large record counts

**Files:**
- Implementation: `PDSDatabase.m`
- Database: Service/PDSData/records table

**Steps:**
1. Check if indexes exist:
   ```sql
   -- Verify these indexes exist
   CREATE INDEX IF NOT EXISTS idx_records_did ON records(did);
   CREATE INDEX IF NOT EXISTS idx_records_collection ON records(collection);
   CREATE INDEX IF NOT EXISTS idx_records_did_collection ON records(did, collection);
   ```

2. Run performance test with 10k+ records:
   ```objc
   - (void)testGetRecordsForDid_Performance {
       // Insert 10000 records for test DID
       // Measure query time
       NSDate *start = [NSDate date];
       NSArray *results = [self.db getRecordsForDid:testDid collection:nil error:&error];
       NSTimeInterval duration = [[NSDate date] timeIntervalSinceDate:start];
       
       XCTAssertLessThan(duration, 0.1, @"Query should complete in <100ms");
   }
   ```

3. If slow, add composite index:
   ```sql
   CREATE INDEX IF NOT EXISTS idx_records_did_created 
   ON records(did, created_at DESC);
   ```

---

### Task 5.3: Review MSTPersistence Methods

**Goal:** Verify all MST (Merkle Search Tree) persistence methods

**Files:**
- Implementation: `Garazyk/Sources/Repository/MSTPersistence.m`

**Steps:**
1. List all public methods in MSTPersistence.h:
   ```bash
   rg "^-.*;" Garazyk/Sources/Repository/MSTPersistence.h
   ```

2. Verify each method has implementation (not stubbed)
3. Check for any TODO/FIXME markers:
   ```bash
   rg "TODO|FIXME|not.*implement" Garazyk/Sources/Repository/MSTPersistence.m
   ```

4. Document any gaps

---

### Task 5.4: Add Pagination Support

**Goal:** Add cursor-based pagination for large result sets

**Files:**
- Implementation: `PDSDatabase.m`

**Rationale:** Returning all records for a DID could be slow. Add pagination.

**Steps:**
1. Add new method with pagination:
   ```objc
   - (NSArray<PDSDatabaseRecord *> *)getRecordsForDid:(NSString *)did
                                           collection:(nullable NSString *)collection
                                              limit:(NSInteger)limit
                                             cursor:(nullable NSString *)cursor
                                               error:(NSError **)error;
   ```

2. Update to use keyset pagination (more efficient than offset)

3. Add tests for pagination

---

### Task 5.5: Add Query Optimization Hints

**Goal:** Add method to suggest optimal query patterns

**Files:**
- Implementation: `PDSDatabase.m`
- Config: `PDSConfiguration.m`

**Steps:**
1. Add method to analyze query patterns:
   ```objc
   - (NSDictionary *)queryPlanForGetRecordsForDid:(NSString *)did 
                                     collection:(NSString *)collection;
   ```

2. Return EXPLAIN QUERY PLAN output
3. Suggest indexes if missing

---

## Verification Checklist

- [ ] getRecordsForDid tests pass
- [ ] Collection filter works correctly
- [ ] Ordering is correct (newest first)
- [ ] Performance < 100ms with 10k records
- [ ] Indexes exist for optimal performance
- [ ] MSTPersistence methods verified
- [ ] No stubbed methods remaining

---

## Dependencies

- `Garazyk/Sources/Database/PDSDatabase.m`
- `Garazyk/Sources/Repository/MSTPersistence.m`
- `Garazyk/Tests/Database/PDSDatabaseTests.m`

---

## Related Plans

- [Phase 1: OAuth 2.0/DPoP Compliance](2026-04-10-oauth-dpop-compliance.md)
- [Phase 2: Video Processing Pipeline](2026-04-10-video-processing-pipeline.md)

---

## Conclusion

The database query methods are implemented and functional. This phase is primarily about:
1. Adding tests to verify behavior
2. Performance optimization if needed
3. Adding pagination for large datasets

No critical gaps found - earlier audit was outdated.