# Bugfix Design Document

## Root Cause Analysis

### Investigation Summary

After analyzing the code flow in `PDSRepositoryService.m` and `ActorStore.m`, the root cause has been identified:

**The blocks are stored in a transaction within `prepareRepoExportForDid`, but the retrieval happens OUTSIDE that transaction in `buildRepoWriterForDid`, using a potentially different store instance or connection state.**

### Evidence

#### 1. Transaction Flow in prepareRepoExportForDid (lines 608-630)

```objc
[store transactWithBlock:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
    if (newRecordBlocks.count > 0 && ![transactor putBlocks:newRecordBlocks forDid:did error:blockError]) {
        persisted = NO;
        return;
    }
    // ... record updates
    persisted = YES;
} error:error];
```

This transaction stores blocks and commits when the block completes successfully.

#### 2. Retrieval Flow in buildRepoWriterForDid (line 842)

```objc
NSData *data = [store getBlockForCID:cid.bytes forDid:did error:nil];
```

This retrieval happens AFTER `prepareRepoExportForDid` returns, using the `store` variable that was passed out.

#### 3. The Critical Issue

Looking at `getRepoContents` (lines 169-172):

```objc
- (nullable NSData *)getRepoContents:(NSString *)did since:(nullable NSString *)sinceRev error:(NSError **)error {
    CARWriter *writer = [self buildRepoWriterForDid:did since:sinceRev error:error];
    if (!writer) return nil;
    return [writer serialize];
}
```

And `buildRepoWriterForDid` (lines 789-850):

```objc
- (nullable CARWriter *)buildRepoWriterForDid:(NSString *)did
                                         since:(nullable NSString *)sinceRev
                                         error:(NSError **)error {
    PDSActorStore *store = nil;
    // ... other variables
    
    if (![self prepareRepoExportForDid:did
                                 since:sinceRev
                                 store:&store
                                 // ... other params
                                 error:error]) {
        return nil;
    }
    
    // ... later, retrieval attempts
    NSData *data = [store getBlockForCID:cid.bytes forDid:did error:nil];
}
```

**The problem**: `prepareRepoExportForDid` gets a store via `[_databasePool storeForDid:did error:error]` at line 489, stores blocks in a transaction, then returns. Later, `buildRepoWriterForDid` uses that same `store` reference to retrieve blocks.

However, there's a subtle issue: **the transaction commits, but the store might be getting a fresh connection from the pool for subsequent operations, or there's a WAL mode read consistency issue.**

### 4. Database Connection Analysis

From `ActorStore.m`:
- `getBlockForCID` (line 1076) uses `safeExecuteSync` which executes on the store's database connection
- `putBlock` (line 1140) also uses `prepareStatement` on the same connection
- Both should see the same data IF they're on the same connection AND the transaction is committed

### 5. WAL Mode Consideration

SQLite WAL (Write-Ahead Logging) mode can cause read-after-write visibility issues if:
- Reads happen on a different connection before WAL checkpoint
- The reader hasn't updated its view of the database

## Root Cause Conclusion

**Primary Root Cause**: Transaction isolation or WAL mode read consistency issue where blocks stored in a transaction are not immediately visible to subsequent reads on the same connection.

**Secondary Contributing Factor**: The code materializes blocks from records and stores them, but then immediately tries to retrieve them in the same operation flow, which may hit a timing or consistency window.

## Solution Design

### Option 1: Store Blocks in a Separate Transaction Before Export (RECOMMENDED)

**Approach**: Separate the block materialization/storage phase from the export phase with an explicit commit boundary.

**Changes**:
1. In `prepareRepoExportForDid`, after storing blocks, explicitly verify they're retrievable before returning
2. Add a verification step that attempts to read back one of the stored blocks
3. If verification fails, return an error

**Pros**:
- Minimal code changes
- Maintains existing transaction boundaries
- Easy to test and verify

**Cons**:
- Adds a verification step (small performance cost)

### Option 2: Pass Block Data Through Instead of Re-retrieving

**Approach**: Instead of storing blocks and then retrieving them, pass the block data directly through the export flow.

**Changes**:
1. Modify `prepareRepoExportForDid` to return a dictionary of CID → block data for newly materialized blocks
2. Modify `buildRepoWriterForDid` to use this dictionary first before attempting database retrieval
3. Update `repoContentsChunkProducer` similarly

**Pros**:
- Eliminates the retrieval problem entirely
- More efficient (no redundant database reads)
- Cleaner data flow

**Cons**:
- More extensive code changes
- Changes function signatures
- Requires careful memory management for large exports

### Option 3: Use Single Transaction for Entire Export

**Approach**: Wrap the entire export operation in a single read transaction after blocks are stored.

**Changes**:
1. Store blocks in a write transaction (current behavior)
2. Wrap the entire export/retrieval phase in a read transaction
3. Ensure WAL mode allows reading committed data

**Pros**:
- Ensures consistency
- Proper transaction semantics

**Cons**:
- Longer transaction duration
- May impact concurrency

## Recommended Solution: Hybrid Approach

**Combine Option 1 and Option 2 for robustness:**

1. **Immediate Fix (Option 2 - Pass Data Through)**:
   - Modify `prepareRepoExportForDid` to return newly materialized block data
   - Use this data directly in export without re-retrieving
   - Fall back to database retrieval only for pre-existing blocks

2. **Long-term Improvement (Option 1 - Verification)**:
   - Add verification that stored blocks are retrievable
   - Add better error messages for debugging

## Implementation Plan

### Phase 1: Pass Block Data Through (Fixes the immediate bug)

1. Modify `prepareRepoExportForDid` signature to include output parameter:
   ```objc
   materializedBlocks:(NSDictionary<NSString *, NSData *> * _Nullable * _Nonnull)materializedBlocksOut
   ```

2. Build dictionary of CID string → block data for newly materialized blocks

3. Update `buildRepoWriterForDid` to:
   - Check `materializedBlocks` dictionary first
   - Fall back to `[store getBlockForCID:...]` only if not in dictionary

4. Update `repoContentsChunkProducer` similarly

5. Update `writeRepoContents` similarly

### Phase 2: Add Verification (Prevents future issues)

1. After storing blocks in `prepareRepoExportForDid`, verify one block is retrievable
2. Add detailed error logging if verification fails
3. Add metrics/monitoring for block storage/retrieval failures

## Testing Strategy

1. **Unit Tests**: All existing PDSRepositoryServiceTests should pass
2. **Integration Tests**: Verify CAR export works end-to-end
3. **Regression Tests**: Ensure no existing functionality breaks
4. **Performance Tests**: Verify no significant performance degradation

## Rollback Plan

If the fix causes issues:
1. The changes are localized to `PDSRepositoryService.m`
2. Can revert to previous behavior by removing the dictionary pass-through
3. No database schema changes required

## Success Criteria

1. All 11 PDSRepositoryServiceTests pass
2. No new test failures introduced
3. CAR export produces valid CAR files with all required blocks
4. Block retrieval errors eliminated from logs
