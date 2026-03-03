# Blob Garbage Collection

## Overview

This document covers garbage collection strategies for orphaned blobs in the September PDS. Blobs become orphaned when they are no longer referenced by any records in a user's repository. Garbage collection reclaims storage space by identifying and safely deleting these unreferenced blobs.

## Orphan Detection

### What Makes a Blob Orphaned?

A blob is considered orphaned when:

1. **No Record References** — No records in the user's repository contain a reference to the blob's CID
2. **Upload Timeout** — Blob was uploaded but never referenced within a grace period (e.g., 24 hours)
3. **Record Deletion** — The last record referencing the blob was deleted
4. **Failed Transactions** — Blob upload succeeded but record creation failed

### Blob Reference Format

Blobs are referenced in records through embed structures:

```json
{
  "$type": "app.bsky.feed.post",
  "text": "Check out this image!",
  "embed": {
    "$type": "app.bsky.embed.images",
    "images": [
      {
        "image": {
          "$type": "blob",
          "ref": {"$link": "bafkreiabcd1234..."},
          "mimeType": "image/jpeg",
          "size": 102400
        },
        "alt": "Description"
      }
    ]
  }
}
```

**Source:** `ATProtoPDS/Sources/App/Services/PDSBlobService.m` (lines 53-57)

The `$link` field contains the blob's CID. Garbage collection must scan all records to find these references.

## Detection Strategies

### Strategy 1: Mark-and-Sweep

The classic garbage collection approach:

```
┌─────────────────────────────────────────────────────────────┐
│              Mark-and-Sweep Algorithm                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Phase 1: Mark (Identify Referenced Blobs)                 │
│     ├─ List all records in repository                      │
│     ├─ Parse each record's CBOR data                       │
│     ├─ Extract blob CIDs from $link fields                 │
│     └─ Build set of referenced CIDs                        │
│                                                             │
│  Phase 2: Sweep (Delete Unreferenced Blobs)                │
│     ├─ List all blobs for user                             │
│     ├─ For each blob CID:                                  │
│     │   ├─ Check if in referenced set                      │
│     │   └─ If not referenced, delete blob                  │
│     └─ Update storage quota                                │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Implementation: Mark Phase

```objc
- (nullable NSSet<NSString *> *)findReferencedBlobsForDID:(NSString *)did
                                                     error:(NSError **)error {
    
    NSMutableSet<NSString *> *referencedCIDs = [NSMutableSet set];
    
    // 1. Get actor store for user
    PDSActorStore *store = [_databasePool storeForDid:did error:error];
    if (!store) {
        return nil;
    }
    
    // 2. List all records (paginated for large repositories)
    NSString *cursor = nil;
    NSUInteger limit = 100;
    
    do {
        NSArray<PDSDatabaseRecord *> *records = [store listRecordsForDid:did
                                                              collection:nil
                                                                   limit:limit
                                                                  cursor:cursor
                                                                   error:error];
        
        if (!records) {
            return nil;
        }
        
        // 3. Extract blob references from each record
        for (PDSDatabaseRecord *record in records) {
            NSSet<NSString *> *blobCIDs = [self extractBlobCIDsFromRecord:record
                                                                    error:error];
            if (blobCIDs) {
                [referencedCIDs unionSet:blobCIDs];
            }
        }
        
        // 4. Update cursor for pagination
        if (records.count < limit) {
            cursor = nil; // No more records
        } else {
            PDSDatabaseRecord *lastRecord = records.lastObject;
            cursor = lastRecord.rkey;
        }
        
    } while (cursor != nil);
    
    return referencedCIDs;
}
```


### Extracting Blob CIDs from Records

```objc
- (nullable NSSet<NSString *> *)extractBlobCIDsFromRecord:(PDSDatabaseRecord *)record
                                                     error:(NSError **)error {
    
    NSMutableSet<NSString *> *cidSet = [NSMutableSet set];
    
    // 1. Decode CBOR record data
    NSError *decodeError = nil;
    id jsonObject = [ATProtoCBORSerialization decodeDataToJSONObject:record.value
                                                               error:&decodeError];
    
    if (!jsonObject) {
        if (error) *error = decodeError;
        return nil;
    }
    
    // 2. Recursively search for blob references
    [self findBlobReferencesInObject:jsonObject collector:cidSet];
    
    return cidSet;
}

- (void)findBlobReferencesInObject:(id)obj collector:(NSMutableSet<NSString *> *)collector {
    
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)obj;
        
        // Check if this is a blob reference
        if ([dict[@"$type"] isEqualToString:@"blob"] && dict[@"ref"]) {
            NSDictionary *ref = dict[@"ref"];
            NSString *cidString = ref[@"$link"];
            
            if ([cidString isKindOfClass:[NSString class]]) {
                [collector addObject:cidString];
            }
        }
        
        // Recursively search all dictionary values
        for (id value in dict.allValues) {
            [self findBlobReferencesInObject:value collector:collector];
        }
        
    } else if ([obj isKindOfClass:[NSArray class]]) {
        NSArray *array = (NSArray *)obj;
        
        // Recursively search all array elements
        for (id element in array) {
            [self findBlobReferencesInObject:element collector:collector];
        }
    }
}
```

**Key points:**
- Handles nested structures (embeds within embeds)
- Recognizes blob references by `$type: "blob"` and `ref.$link` pattern
- Works with any record schema (posts, profiles, lists, etc.)


### Implementation: Sweep Phase

```objc
- (NSUInteger)collectGarbageBlobsForDID:(NSString *)did
                                   error:(NSError **)error {
    
    // 1. Mark: Find all referenced blobs
    NSSet<NSString *> *referencedCIDs = [self findReferencedBlobsForDID:did
                                                                   error:error];
    if (!referencedCIDs) {
        return 0;
    }
    
    // 2. List all blobs for user
    NSArray<PDSDatabaseBlob *> *allBlobs = [_blobStorage listBlobsForDID:did
                                                                    limit:1000
                                                                   cursor:nil
                                                                    error:error];
    if (!allBlobs) {
        return 0;
    }
    
    // 3. Sweep: Delete unreferenced blobs
    NSUInteger deletedCount = 0;
    
    for (PDSDatabaseBlob *blob in allBlobs) {
        CID *cid = [CID cidFromBytes:blob.cid];
        NSString *cidString = cid.stringValue;
        
        // Check if blob is referenced
        if (![referencedCIDs containsObject:cidString]) {
            // Blob is orphaned - delete it
            NSError *deleteError = nil;
            BOOL deleted = [_blobStorage deleteBlobWithCID:cid
                                                       did:did
                                                     error:&deleteError];
            
            if (deleted) {
                deletedCount++;
                PDS_LOG_INFO_C(PDSLogComponentBlob,
                    @"Deleted orphaned blob %@ for user %@",
                    cidString, did);
            } else {
                PDS_LOG_ERROR_C(PDSLogComponentBlob,
                    @"Failed to delete orphaned blob %@: %@",
                    cidString, deleteError);
            }
        }
    }
    
    return deletedCount;
}
```

**Source:** `ATProtoPDS/Sources/Blob/BlobStorage.m` (lines 213-224, 225-260)


### Strategy 2: Reference Counting

Track reference counts in the database:

```sql
CREATE TABLE blob_references (
    blob_cid BLOB NOT NULL,
    record_uri TEXT NOT NULL,
    did TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    PRIMARY KEY (blob_cid, record_uri),
    FOREIGN KEY (did) REFERENCES accounts(did)
);

CREATE INDEX idx_blob_references_cid ON blob_references(blob_cid);
CREATE INDEX idx_blob_references_did ON blob_references(did);
```

**Advantages:**
- Fast orphan detection (query for `COUNT(*) = 0`)
- No need to scan all records
- Immediate identification when last reference is deleted

**Disadvantages:**
- Additional storage overhead
- Must maintain reference counts on every record operation
- Risk of count drift if updates fail
- Requires careful transaction handling

### Strategy 3: Timestamp-Based Cleanup

Delete blobs that haven't been referenced within a grace period:

```objc
- (NSUInteger)cleanupStaleBlobsForDID:(NSString *)did
                          olderThanDays:(NSInteger)days
                                  error:(NSError **)error {
    
    // Calculate cutoff timestamp
    NSDate *cutoffDate = [NSDate dateWithTimeIntervalSinceNow:-(days * 24 * 60 * 60)];
    NSInteger cutoffTimestamp = (NSInteger)[cutoffDate timeIntervalSince1970];
    
    // Query for old blobs
    NSString *sql = @"SELECT cid FROM blobs "
                    @"WHERE did = ? AND created_at < ? "
                    @"ORDER BY created_at ASC LIMIT 100";
    
    NSArray *params = @[did, @(cutoffTimestamp)];
    
    PDSActorStore *store = [_databasePool storeForDid:did error:error];
    if (!store) {
        return 0;
    }
    
    NSArray *rows = [store executeQuery:sql withParams:params error:error];
    if (!rows) {
        return 0;
    }
    
    NSUInteger deletedCount = 0;
    
    for (NSDictionary *row in rows) {
        NSData *cidBytes = row[@"cid"];
        CID *cid = [CID cidFromBytes:cidBytes];
        
        // Verify blob is actually unreferenced before deleting
        NSSet<NSString *> *referencedCIDs = [self findReferencedBlobsForDID:did
                                                                       error:nil];
        
        if (![referencedCIDs containsObject:cid.stringValue]) {
            BOOL deleted = [_blobStorage deleteBlobWithCID:cid
                                                       did:did
                                                     error:nil];
            if (deleted) {
                deletedCount++;
            }
        }
    }
    
    return deletedCount;
}
```

**Use case:** Cleanup blobs uploaded but never referenced (failed transactions, abandoned uploads).


## Cleanup Strategies

### On-Demand Cleanup

Trigger garbage collection manually via CLI or admin endpoint:

```bash
# CLI command (hypothetical)
kaszlak gc blobs --did did:plc:abc123

# Or for all users
kaszlak gc blobs --all
```

**Implementation:**

```objc
// In PDSCLIGCCommand.m
- (void)executeWithContext:(PDSCLIContext *)context {
    NSString *did = [context.options objectForKey:@"did"];
    BOOL all = [[context.options objectForKey:@"all"] boolValue];
    
    if (all) {
        // Get all user DIDs
        NSArray<NSString *> *allDIDs = [self getAllUserDIDs];
        
        for (NSString *userDID in allDIDs) {
            [self collectGarbageForDID:userDID context:context];
        }
    } else if (did) {
        [self collectGarbageForDID:did context:context];
    } else {
        [context printError:@"Must specify --did or --all"];
    }
}

- (void)collectGarbageForDID:(NSString *)did context:(PDSCLIContext *)context {
    [context printInfo:[NSString stringWithFormat:@"Collecting garbage for %@...", did]];
    
    NSError *error = nil;
    NSUInteger deletedCount = [self.blobService collectGarbageBlobsForDID:did
                                                                     error:&error];
    
    if (error) {
        [context printError:[NSString stringWithFormat:@"GC failed: %@",
                            error.localizedDescription]];
    } else {
        [context printInfo:[NSString stringWithFormat:@"Deleted %lu orphaned blobs",
                           (unsigned long)deletedCount]];
    }
}
```

**Advantages:**
- Full control over when GC runs
- Can run during maintenance windows
- Predictable resource usage

**Disadvantages:**
- Requires manual intervention
- Storage may accumulate between runs


### Scheduled Background Cleanup

Run garbage collection periodically in the background:

```objc
@interface PDSBlobGarbageCollector : NSObject

@property (nonatomic, strong) NSTimer *gcTimer;
@property (nonatomic, assign) NSTimeInterval gcInterval; // Default: 24 hours

- (instancetype)initWithBlobService:(PDSBlobService *)blobService
                       databasePool:(PDSDatabasePool *)databasePool;

- (void)start;
- (void)stop;

@end

@implementation PDSBlobGarbageCollector

- (instancetype)initWithBlobService:(PDSBlobService *)blobService
                       databasePool:(PDSDatabasePool *)databasePool {
    self = [super init];
    if (self) {
        _blobService = blobService;
        _databasePool = databasePool;
        _gcInterval = 24 * 60 * 60; // 24 hours
    }
    return self;
}

- (void)start {
    // Schedule timer on main run loop
    self.gcTimer = [NSTimer scheduledTimerWithTimeInterval:self.gcInterval
                                                    target:self
                                                  selector:@selector(runGarbageCollection:)
                                                  userInfo:nil
                                                   repeats:YES];
    
    PDS_LOG_INFO_C(PDSLogComponentBlob,
        @"Blob garbage collector started (interval: %.0f hours)",
        self.gcInterval / 3600.0);
}

- (void)stop {
    [self.gcTimer invalidate];
    self.gcTimer = nil;
    
    PDS_LOG_INFO_C(PDSLogComponentBlob,
        @"Blob garbage collector stopped");
}

- (void)runGarbageCollection:(NSTimer *)timer {
    PDS_LOG_INFO_C(PDSLogComponentBlob,
        @"Starting scheduled blob garbage collection");
    
    // Run GC in background queue to avoid blocking
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        [self performGarbageCollection];
    });
}

- (void)performGarbageCollection {
    // Get all user DIDs
    NSArray<NSString *> *allDIDs = [self getAllUserDIDs];
    
    NSUInteger totalDeleted = 0;
    NSUInteger totalErrors = 0;
    
    for (NSString *did in allDIDs) {
        @autoreleasepool {
            NSError *error = nil;
            NSUInteger deleted = [self.blobService collectGarbageBlobsForDID:did
                                                                        error:&error];
            
            if (error) {
                totalErrors++;
                PDS_LOG_ERROR_C(PDSLogComponentBlob,
                    @"GC failed for %@: %@", did, error);
            } else {
                totalDeleted += deleted;
            }
        }
    }
    
    PDS_LOG_INFO_C(PDSLogComponentBlob,
        @"Garbage collection complete: %lu blobs deleted, %lu errors",
        (unsigned long)totalDeleted, (unsigned long)totalErrors);
}

- (NSArray<NSString *> *)getAllUserDIDs {
    // Query service database for all user DIDs
    NSString *sql = @"SELECT did FROM accounts";
    NSError *error = nil;
    NSArray *rows = [self.serviceDatabases executeQuery:sql
                                             withParams:@[]
                                                  error:&error];
    
    NSMutableArray<NSString *> *dids = [NSMutableArray array];
    for (NSDictionary *row in rows) {
        [dids addObject:row[@"did"]];
    }
    
    return dids;
}

@end
```

**Configuration:**

```json
{
  "blob_gc": {
    "enabled": true,
    "interval_hours": 24,
    "max_blobs_per_run": 1000
  }
}
```


### Incremental Cleanup

Process a small batch of users on each run to avoid resource spikes:

```objc
- (void)runIncrementalGarbageCollection {
    // Process 10 users per run
    NSUInteger batchSize = 10;
    NSUInteger offset = self.gcOffset;
    
    NSString *sql = @"SELECT did FROM accounts LIMIT ? OFFSET ?";
    NSArray *params = @[@(batchSize), @(offset)];
    
    NSError *error = nil;
    NSArray *rows = [self.serviceDatabases executeQuery:sql
                                             withParams:params
                                                  error:&error];
    
    if (!rows || rows.count == 0) {
        // Wrapped around - reset offset
        self.gcOffset = 0;
        return;
    }
    
    // Process batch
    for (NSDictionary *row in rows) {
        NSString *did = row[@"did"];
        [self.blobService collectGarbageBlobsForDID:did error:nil];
    }
    
    // Update offset for next run
    self.gcOffset += batchSize;
}
```

**Advantages:**
- Spreads load over time
- Reduces memory usage
- Less impact on server performance

**Disadvantages:**
- Takes longer to complete full cycle
- More complex state management


### Event-Driven Cleanup

Trigger garbage collection after specific events:

```objc
// After record deletion
- (BOOL)deleteRecord:(NSString *)uri
              forDid:(NSString *)did
               error:(NSError **)error {
    
    // 1. Get record to extract blob references
    PDSDatabaseRecord *record = [self getRecord:uri forDid:did error:error];
    if (!record) {
        return NO;
    }
    
    // 2. Extract blob CIDs from record
    NSSet<NSString *> *blobCIDs = [self extractBlobCIDsFromRecord:record
                                                             error:nil];
    
    // 3. Delete the record
    BOOL deleted = [self.recordService deleteRecord:uri
                                              forDid:did
                                               error:error];
    
    if (!deleted) {
        return NO;
    }
    
    // 4. Check if blobs are now orphaned and delete them
    for (NSString *cidString in blobCIDs) {
        [self checkAndDeleteOrphanedBlob:cidString forDid:did];
    }
    
    return YES;
}

- (void)checkAndDeleteOrphanedBlob:(NSString *)cidString
                            forDid:(NSString *)did {
    
    // Check if any other records reference this blob
    NSSet<NSString *> *referencedCIDs = [self findReferencedBlobsForDID:did
                                                                   error:nil];
    
    if (![referencedCIDs containsObject:cidString]) {
        // Blob is orphaned - delete it
        CID *cid = [CID cidFromString:cidString];
        [self.blobStorage deleteBlobWithCID:cid did:did error:nil];
        
        PDS_LOG_INFO_C(PDSLogComponentBlob,
            @"Deleted orphaned blob %@ after record deletion", cidString);
    }
}
```

**Advantages:**
- Immediate cleanup
- No orphaned blobs accumulate
- Minimal storage waste

**Disadvantages:**
- Adds latency to record deletion
- Must scan all records on each deletion
- Can be expensive for users with many records


## Safety Mechanisms

### Two-Phase Deletion

Never delete blob data immediately - use a two-phase approach:

```objc
// Phase 1: Mark for deletion
- (BOOL)markBlobForDeletion:(CID *)cid
                        did:(NSString *)did
                      error:(NSError **)error {
    
    NSString *sql = @"UPDATE blobs SET marked_for_deletion = 1, "
                    @"marked_at = ? WHERE cid = ? AND did = ?";
    
    NSInteger now = (NSInteger)[[NSDate date] timeIntervalSince1970];
    NSArray *params = @[@(now), [cid bytes], did];
    
    PDSActorStore *store = [_databasePool storeForDid:did error:error];
    if (!store) {
        return NO;
    }
    
    return [store executeUpdate:sql withParams:params error:error];
}

// Phase 2: Delete after grace period (e.g., 7 days)
- (NSUInteger)deleteMarkedBlobs:(NSError **)error {
    NSInteger gracePeriod = 7 * 24 * 60 * 60; // 7 days
    NSDate *cutoffDate = [NSDate dateWithTimeIntervalSinceNow:-gracePeriod];
    NSInteger cutoff = (NSInteger)[cutoffDate timeIntervalSince1970];
    
    NSString *sql = @"SELECT cid, did FROM blobs "
                    @"WHERE marked_for_deletion = 1 AND marked_at < ?";
    
    NSArray *params = @[@(cutoff)];
    NSArray *rows = [self.serviceDatabases executeQuery:sql
                                             withParams:params
                                                  error:error];
    
    NSUInteger deletedCount = 0;
    
    for (NSDictionary *row in rows) {
        NSData *cidBytes = row[@"cid"];
        NSString *did = row[@"did"];
        
        CID *cid = [CID cidFromBytes:cidBytes];
        
        // Final check: verify still unreferenced
        NSSet<NSString *> *referencedCIDs = [self findReferencedBlobsForDID:did
                                                                       error:nil];
        
        if (![referencedCIDs containsObject:cid.stringValue]) {
            // Safe to delete
            BOOL deleted = [_blobStorage deleteBlobWithCID:cid
                                                       did:did
                                                     error:nil];
            if (deleted) {
                deletedCount++;
            }
        } else {
            // Blob was re-referenced - unmark it
            [self unmarkBlobForDeletion:cid did:did error:nil];
        }
    }
    
    return deletedCount;
}
```

**Benefits:**
- Recovery window if blob was incorrectly marked
- Time to detect and fix reference counting bugs
- Safer for production systems


### Dry-Run Mode

Test garbage collection without actually deleting:

```objc
- (NSDictionary *)dryRunGarbageCollection:(NSString *)did
                                    error:(NSError **)error {
    
    // 1. Find referenced blobs
    NSSet<NSString *> *referencedCIDs = [self findReferencedBlobsForDID:did
                                                                   error:error];
    if (!referencedCIDs) {
        return nil;
    }
    
    // 2. List all blobs
    NSArray<PDSDatabaseBlob *> *allBlobs = [_blobStorage listBlobsForDID:did
                                                                    limit:1000
                                                                   cursor:nil
                                                                    error:error];
    if (!allBlobs) {
        return nil;
    }
    
    // 3. Identify orphans without deleting
    NSMutableArray<NSString *> *orphanedCIDs = [NSMutableArray array];
    NSUInteger totalSize = 0;
    
    for (PDSDatabaseBlob *blob in allBlobs) {
        CID *cid = [CID cidFromBytes:blob.cid];
        NSString *cidString = cid.stringValue;
        
        if (![referencedCIDs containsObject:cidString]) {
            [orphanedCIDs addObject:cidString];
            totalSize += blob.size;
        }
    }
    
    // 4. Return report
    return @{
        @"orphaned_count": @(orphanedCIDs.count),
        @"orphaned_cids": orphanedCIDs,
        @"total_size_bytes": @(totalSize),
        @"total_blobs": @(allBlobs.count),
        @"referenced_count": @(referencedCIDs.count)
    };
}
```

**Usage:**

```bash
# CLI dry-run
kaszlak gc blobs --did did:plc:abc123 --dry-run

# Output:
# Dry-run results for did:plc:abc123:
#   Total blobs: 150
#   Referenced: 142
#   Orphaned: 8
#   Reclaimable space: 2.4 MB
#
# Orphaned CIDs:
#   - bafkreiabc123... (512 KB)
#   - bafkreidef456... (1.2 MB)
#   ...
```


### Transaction Safety

Always use database transactions when deleting blobs:

```objc
- (BOOL)deleteBlobWithCID:(CID *)cid did:(NSString *)did error:(NSError **)error {
    __block BOOL success = NO;
    __block NSError *dbError = nil;
    
    // Delete metadata in transaction
    [_databasePool transactWithDid:did block:^(id<PDSActorStoreTransactor> transactor,
                                               NSError **blockError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        success = [store deleteBlobForCID:[cid bytes] forDid:did error:blockError];
    } error:&dbError];

    if (!success) {
        if (error) {
            *error = [NSError errorWithDomain:BlobStorageErrorDomain
                                         code:BlobStorageErrorStorageFailure
                                     userInfo:@{
                NSLocalizedDescriptionKey: @"Failed to delete blob metadata",
                NSUnderlyingErrorKey: dbError ?: [NSNull null]
            }];
        }
        return NO;
    }

    // Delete blob data from provider
    NSError *providerError = nil;
    if (![self.provider deleteBlobDataForCID:cid error:&providerError]) {
        PDS_LOG_ERROR_C(PDSLogComponentBlob,
            @"Failed to delete blob data from provider for CID %@: %@",
            cid.stringValue, providerError);
        // Note: We don't fail the operation if provider deletion fails
        // Garbage collection can clean up orphaned data later
    }

    return YES;
}
```

**Source:** `ATProtoPDS/Sources/Blob/BlobStorage.m` (lines 225-260)

**Key principles:**
- Metadata deletion is atomic (within transaction)
- Provider deletion failure doesn't fail the operation
- Orphaned provider data can be cleaned up separately
- Prevents partial deletions that corrupt state


### Deduplication Awareness

Remember that multiple users may reference the same blob data:

```objc
- (BOOL)canDeleteBlobDataFromProvider:(CID *)cid error:(NSError **)error {
    // Check if ANY user still has metadata for this blob
    NSString *sql = @"SELECT COUNT(*) as count FROM blobs WHERE cid = ?";
    NSArray *params = @[[cid bytes]];
    
    // Query across all actor databases (expensive!)
    NSArray<NSString *> *allDIDs = [self getAllUserDIDs];
    
    for (NSString *did in allDIDs) {
        PDSActorStore *store = [_databasePool storeForDid:did error:error];
        if (!store) continue;
        
        NSArray *rows = [store executeQuery:sql withParams:params error:error];
        if (rows.count > 0) {
            NSInteger count = [rows[0][@"count"] integerValue];
            if (count > 0) {
                // Another user still references this blob
                return NO;
            }
        }
    }
    
    // No users reference this blob - safe to delete from provider
    return YES;
}
```

**Important:** This is expensive for large user bases. Consider:

1. **Shared blob reference table:**
   ```sql
   CREATE TABLE shared_blob_refs (
       cid BLOB PRIMARY KEY,
       ref_count INTEGER NOT NULL DEFAULT 0
   );
   ```

2. **Increment on upload, decrement on metadata deletion:**
   ```objc
   // On blob upload
   UPDATE shared_blob_refs SET ref_count = ref_count + 1 WHERE cid = ?;
   
   // On metadata deletion
   UPDATE shared_blob_refs SET ref_count = ref_count - 1 WHERE cid = ?;
   
   // Delete from provider only when ref_count = 0
   DELETE FROM shared_blob_refs WHERE cid = ? AND ref_count = 0;
   ```


## Performance Considerations

### Memory Usage

Large repositories can have thousands of records. Use pagination:

```objc
- (nullable NSSet<NSString *> *)findReferencedBlobsForDID:(NSString *)did
                                                     error:(NSError **)error {
    
    NSMutableSet<NSString *> *referencedCIDs = [NSMutableSet set];
    NSString *cursor = nil;
    NSUInteger limit = 100; // Process 100 records at a time
    
    do {
        @autoreleasepool {
            NSArray<PDSDatabaseRecord *> *records = [store listRecordsForDid:did
                                                                  collection:nil
                                                                       limit:limit
                                                                      cursor:cursor
                                                                       error:error];
            
            if (!records) {
                return nil;
            }
            
            for (PDSDatabaseRecord *record in records) {
                NSSet<NSString *> *blobCIDs = [self extractBlobCIDsFromRecord:record
                                                                        error:error];
                if (blobCIDs) {
                    [referencedCIDs unionSet:blobCIDs];
                }
            }
            
            cursor = (records.count < limit) ? nil : records.lastObject.rkey;
        }
        
    } while (cursor != nil);
    
    return referencedCIDs;
}
```

**Key optimizations:**
- Use `@autoreleasepool` to release memory between batches
- Process records in chunks (100-1000 at a time)
- Don't load all records into memory at once


### Database Indexes

Create indexes to speed up garbage collection queries:

```sql
-- Index on blob CID for fast lookups
CREATE INDEX IF NOT EXISTS idx_blobs_cid ON blobs(cid);

-- Index on blob DID for listing user's blobs
CREATE INDEX IF NOT EXISTS idx_blobs_did ON blobs(did);

-- Index on creation time for timestamp-based cleanup
CREATE INDEX IF NOT EXISTS idx_blobs_created_at ON blobs(created_at);

-- Index on marked_for_deletion flag (if using two-phase deletion)
CREATE INDEX IF NOT EXISTS idx_blobs_marked 
    ON blobs(marked_for_deletion, marked_at) 
    WHERE marked_for_deletion = 1;

-- Composite index for efficient orphan detection
CREATE INDEX IF NOT EXISTS idx_blobs_did_cid ON blobs(did, cid);
```

**Query optimization:**

```sql
-- Fast: Uses idx_blobs_did
SELECT cid, size FROM blobs WHERE did = ? ORDER BY created_at DESC LIMIT 100;

-- Fast: Uses idx_blobs_marked
SELECT cid, did FROM blobs 
WHERE marked_for_deletion = 1 AND marked_at < ?;

-- Slow: Full table scan
SELECT cid FROM blobs WHERE size > 1000000; -- No index on size
```


### Parallel Processing

Process multiple users concurrently:

```objc
- (void)runParallelGarbageCollection {
    NSArray<NSString *> *allDIDs = [self getAllUserDIDs];
    
    // Create concurrent queue
    dispatch_queue_t gcQueue = dispatch_queue_create(
        "com.atproto.pds.blob.gc",
        DISPATCH_QUEUE_CONCURRENT
    );
    
    // Create semaphore to limit concurrency
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(4); // Max 4 concurrent
    
    dispatch_group_t group = dispatch_group_create();
    
    for (NSString *did in allDIDs) {
        dispatch_group_enter(group);
        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
        
        dispatch_async(gcQueue, ^{
            @autoreleasepool {
                NSError *error = nil;
                [self.blobService collectGarbageBlobsForDID:did error:&error];
                
                if (error) {
                    PDS_LOG_ERROR_C(PDSLogComponentBlob,
                        @"GC failed for %@: %@", did, error);
                }
            }
            
            dispatch_semaphore_signal(semaphore);
            dispatch_group_leave(group);
        });
    }
    
    // Wait for all to complete
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    
    PDS_LOG_INFO_C(PDSLogComponentBlob,
        @"Parallel garbage collection complete");
}
```

**Benefits:**
- Faster completion for large user bases
- Better CPU utilization
- Configurable concurrency limit

**Cautions:**
- Don't overwhelm database connection pool
- Monitor memory usage
- Consider I/O bandwidth limits


## Monitoring and Metrics

### Garbage Collection Metrics

Track GC performance and effectiveness:

```objc
@interface PDSBlobGCMetrics : NSObject

@property (nonatomic, assign) NSUInteger totalRuns;
@property (nonatomic, assign) NSUInteger totalBlobsDeleted;
@property (nonatomic, assign) NSUInteger totalBytesReclaimed;
@property (nonatomic, assign) NSTimeInterval totalDuration;
@property (nonatomic, assign) NSUInteger errorCount;

- (void)recordGCRun:(NSUInteger)blobsDeleted
       bytesReclaimed:(NSUInteger)bytes
             duration:(NSTimeInterval)duration
               errors:(NSUInteger)errors;

- (NSDictionary *)metricsReport;

@end

@implementation PDSBlobGCMetrics

- (void)recordGCRun:(NSUInteger)blobsDeleted
       bytesReclaimed:(NSUInteger)bytes
             duration:(NSTimeInterval)duration
               errors:(NSUInteger)errors {
    
    self.totalRuns++;
    self.totalBlobsDeleted += blobsDeleted;
    self.totalBytesReclaimed += bytes;
    self.totalDuration += duration;
    self.errorCount += errors;
}

- (NSDictionary *)metricsReport {
    return @{
        @"total_runs": @(self.totalRuns),
        @"total_blobs_deleted": @(self.totalBlobsDeleted),
        @"total_bytes_reclaimed": @(self.totalBytesReclaimed),
        @"total_duration_seconds": @(self.totalDuration),
        @"error_count": @(self.errorCount),
        @"avg_blobs_per_run": @(self.totalRuns > 0 ? 
            self.totalBlobsDeleted / self.totalRuns : 0),
        @"avg_duration_seconds": @(self.totalRuns > 0 ? 
            self.totalDuration / self.totalRuns : 0)
    };
}

@end
```

### Logging

Log garbage collection activity:

```objc
- (NSUInteger)collectGarbageBlobsForDID:(NSString *)did
                                   error:(NSError **)error {
    
    NSDate *startTime = [NSDate date];
    
    PDS_LOG_INFO_C(PDSLogComponentBlob,
        @"Starting garbage collection for %@", did);
    
    // Perform GC
    NSSet<NSString *> *referencedCIDs = [self findReferencedBlobsForDID:did
                                                                   error:error];
    if (!referencedCIDs) {
        PDS_LOG_ERROR_C(PDSLogComponentBlob,
            @"Failed to find referenced blobs for %@: %@", did, *error);
        return 0;
    }
    
    NSArray<PDSDatabaseBlob *> *allBlobs = [_blobStorage listBlobsForDID:did
                                                                    limit:1000
                                                                   cursor:nil
                                                                    error:error];
    
    NSUInteger deletedCount = 0;
    NSUInteger totalSize = 0;
    
    for (PDSDatabaseBlob *blob in allBlobs) {
        CID *cid = [CID cidFromBytes:blob.cid];
        NSString *cidString = cid.stringValue;
        
        if (![referencedCIDs containsObject:cidString]) {
            BOOL deleted = [_blobStorage deleteBlobWithCID:cid
                                                       did:did
                                                     error:nil];
            if (deleted) {
                deletedCount++;
                totalSize += blob.size;
                
                PDS_LOG_DEBUG_C(PDSLogComponentBlob,
                    @"Deleted orphaned blob %@ (%lu bytes)",
                    cidString, (unsigned long)blob.size);
            }
        }
    }
    
    NSTimeInterval duration = [[NSDate date] timeIntervalSinceDate:startTime];
    
    PDS_LOG_INFO_C(PDSLogComponentBlob,
        @"GC complete for %@: %lu blobs deleted, %lu bytes reclaimed, %.2f seconds",
        did, (unsigned long)deletedCount, (unsigned long)totalSize, duration);
    
    // Record metrics
    [self.metrics recordGCRun:deletedCount
               bytesReclaimed:totalSize
                     duration:duration
                       errors:0];
    
    return deletedCount;
}
```


## Best Practices

### 1. Start Conservative

Begin with manual, on-demand garbage collection:

```bash
# Run dry-run first
kaszlak gc blobs --did did:plc:abc123 --dry-run

# Review results, then run actual GC
kaszlak gc blobs --did did:plc:abc123

# Monitor for issues before enabling automatic GC
```

### 2. Use Grace Periods

Never delete blobs immediately:

- **Upload grace period:** 24-48 hours for newly uploaded blobs
- **Deletion grace period:** 7 days for marked blobs
- **Verification window:** Re-check references before final deletion

### 3. Monitor Storage Metrics

Track storage usage over time:

```sql
-- Total blob storage per user
SELECT did, 
       COUNT(*) as blob_count,
       SUM(size) as total_bytes,
       SUM(size) / 1024.0 / 1024.0 as total_mb
FROM blobs
GROUP BY did
ORDER BY total_bytes DESC;

-- Orphan candidates (old, unreferenced)
SELECT COUNT(*) as orphan_candidates,
       SUM(size) / 1024.0 / 1024.0 as reclaimable_mb
FROM blobs
WHERE created_at < strftime('%s', 'now', '-7 days');
```

### 4. Test on Non-Production First

Always test GC on development/staging:

1. Copy production database to staging
2. Run GC with dry-run
3. Verify results match expectations
4. Run actual GC
5. Verify no data loss
6. Monitor for 24-48 hours
7. Deploy to production

### 5. Implement Rollback Capability

Keep deleted blob data for recovery:

```objc
// Move to trash instead of immediate deletion
- (BOOL)moveToTrash:(CID *)cid did:(NSString *)did error:(NSError **)error {
    NSString *trashPath = [self.trashDirectory stringByAppendingPathComponent:
                          [NSString stringWithFormat:@"%@/%@",
                           did, cid.stringValue]];
    
    NSString *blobPath = [self.provider blobFilePathForCID:cid];
    
    // Move file to trash
    NSError *fileError = nil;
    [[NSFileManager defaultManager] moveItemAtPath:blobPath
                                            toPath:trashPath
                                             error:&fileError];
    
    if (fileError) {
        if (error) *error = fileError;
        return NO;
    }
    
    // Schedule permanent deletion after 30 days
    [self scheduleTrashDeletion:trashPath after:30 * 24 * 60 * 60];
    
    return YES;
}
```


### 6. Document Deduplication Behavior

Make it clear to operators that blob data is deduplicated:

```
# In documentation or admin guide:

IMPORTANT: Blob data is content-addressed and deduplicated across users.
When user A uploads an image, and user B uploads the same image, only
one copy is stored. Deleting user A's blob metadata does NOT delete the
shared blob data if user B still references it.

Garbage collection must check ALL users before deleting blob data from
the provider. Metadata deletion is per-user, but data deletion is global.
```

### 7. Rate Limit GC Operations

Prevent GC from overwhelming the system:

```objc
@interface PDSBlobGCRateLimiter : NSObject

@property (nonatomic, assign) NSUInteger maxBlobsPerSecond;
@property (nonatomic, assign) NSUInteger maxUsersPerMinute;

- (BOOL)canProcessBlob;
- (BOOL)canProcessUser;

@end
```

### 8. Provide Admin Visibility

Expose GC status via admin endpoint:

```objc
// GET /xrpc/com.atproto.admin.getBlobGCStatus
- (void)handleGetBlobGCStatus:(XrpcRequest *)request
                      response:(XrpcResponse *)response {
    
    NSDictionary *status = @{
        @"enabled": @(self.gcEnabled),
        @"last_run": self.lastGCRun,
        @"next_run": self.nextGCRun,
        @"metrics": [self.gcMetrics metricsReport],
        @"in_progress": @(self.gcInProgress)
    };
    
    response.statusCode = 200;
    response.body = [NSJSONSerialization dataWithJSONObject:status
                                                    options:0
                                                      error:nil];
}
```


## Common Pitfalls

### 1. Deleting Referenced Blobs

**Problem:** Deleting a blob that's still referenced by a record.

**Cause:** Race condition between record creation and GC, or incorrect reference detection.

**Solution:**
- Always re-verify references immediately before deletion
- Use database transactions
- Implement grace periods for newly uploaded blobs

```objc
// WRONG: Delete without verification
[blobStorage deleteBlobWithCID:cid did:did error:nil];

// RIGHT: Verify first
NSSet *refs = [self findReferencedBlobsForDID:did error:nil];
if (![refs containsObject:cid.stringValue]) {
    [blobStorage deleteBlobWithCID:cid did:did error:nil];
}
```

### 2. Ignoring Deduplication

**Problem:** Deleting shared blob data when another user still needs it.

**Cause:** Only checking one user's references.

**Solution:**
- Track reference counts across all users
- Only delete provider data when global ref count = 0
- Keep per-user metadata separate from shared data

### 3. Memory Exhaustion

**Problem:** Loading all records into memory at once.

**Cause:** Not using pagination.

**Solution:**
- Process records in batches (100-1000 at a time)
- Use `@autoreleasepool` for each batch
- Stream results instead of collecting all at once

### 4. Blocking Server Operations

**Problem:** GC runs on main thread, blocking requests.

**Cause:** Running GC synchronously.

**Solution:**
- Always run GC on background queue
- Use low priority: `DISPATCH_QUEUE_PRIORITY_LOW`
- Implement cancellation for long-running operations

```objc
// WRONG: Blocks main thread
[self collectGarbageBlobsForDID:did error:nil];

// RIGHT: Background queue
dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
    [self collectGarbageBlobsForDID:did error:nil];
});
```

### 5. No Rollback Capability

**Problem:** Accidentally deleted blobs cannot be recovered.

**Cause:** Immediate permanent deletion.

**Solution:**
- Implement two-phase deletion with grace period
- Move to trash before permanent deletion
- Keep backups of blob metadata


## Example: Complete GC Implementation

Here's a complete example combining the strategies above:

```objc
@interface PDSBlobGarbageCollector : NSObject

@property (nonatomic, strong) PDSBlobService *blobService;
@property (nonatomic, strong) PDSDatabasePool *databasePool;
@property (nonatomic, strong) PDSServiceDatabases *serviceDatabases;
@property (nonatomic, strong) BlobStorage *blobStorage;
@property (nonatomic, strong) PDSBlobGCMetrics *metrics;

@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) NSTimeInterval interval;
@property (nonatomic, strong) NSTimer *timer;

- (instancetype)initWithBlobService:(PDSBlobService *)blobService
                       databasePool:(PDSDatabasePool *)databasePool
                   serviceDatabases:(PDSServiceDatabases *)serviceDatabases
                        blobStorage:(BlobStorage *)blobStorage;

- (void)start;
- (void)stop;
- (NSUInteger)runGarbageCollectionForDID:(NSString *)did
                                   error:(NSError **)error;
- (NSDictionary *)dryRunForDID:(NSString *)did error:(NSError **)error;

@end

@implementation PDSBlobGarbageCollector

- (instancetype)initWithBlobService:(PDSBlobService *)blobService
                       databasePool:(PDSDatabasePool *)databasePool
                   serviceDatabases:(PDSServiceDatabases *)serviceDatabases
                        blobStorage:(BlobStorage *)blobStorage {
    self = [super init];
    if (self) {
        _blobService = blobService;
        _databasePool = databasePool;
        _serviceDatabases = serviceDatabases;
        _blobStorage = blobStorage;
        _metrics = [[PDSBlobGCMetrics alloc] init];
        _enabled = NO;
        _interval = 24 * 60 * 60; // 24 hours
    }
    return self;
}

- (void)start {
    if (self.enabled && !self.timer) {
        self.timer = [NSTimer scheduledTimerWithTimeInterval:self.interval
                                                      target:self
                                                    selector:@selector(scheduledGC:)
                                                    userInfo:nil
                                                     repeats:YES];
        
        PDS_LOG_INFO_C(PDSLogComponentBlob,
            @"Blob GC started (interval: %.0f hours)",
            self.interval / 3600.0);
    }
}

- (void)stop {
    [self.timer invalidate];
    self.timer = nil;
    
    PDS_LOG_INFO_C(PDSLogComponentBlob, @"Blob GC stopped");
}

- (void)scheduledGC:(NSTimer *)timer {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        [self runFullGarbageCollection];
    });
}

- (void)runFullGarbageCollection {
    PDS_LOG_INFO_C(PDSLogComponentBlob, @"Starting full GC cycle");
    
    NSDate *startTime = [NSDate date];
    NSArray<NSString *> *allDIDs = [self getAllUserDIDs];
    
    NSUInteger totalDeleted = 0;
    NSUInteger totalErrors = 0;
    
    for (NSString *did in allDIDs) {
        @autoreleasepool {
            NSError *error = nil;
            NSUInteger deleted = [self runGarbageCollectionForDID:did
                                                             error:&error];
            
            if (error) {
                totalErrors++;
                PDS_LOG_ERROR_C(PDSLogComponentBlob,
                    @"GC failed for %@: %@", did, error);
            } else {
                totalDeleted += deleted;
            }
        }
    }
    
    NSTimeInterval duration = [[NSDate date] timeIntervalSinceDate:startTime];
    
    PDS_LOG_INFO_C(PDSLogComponentBlob,
        @"Full GC cycle complete: %lu blobs deleted, %lu errors, %.2f seconds",
        (unsigned long)totalDeleted, (unsigned long)totalErrors, duration);
    
    [self.metrics recordGCRun:totalDeleted
               bytesReclaimed:0
                     duration:duration
                       errors:totalErrors];
}

- (NSUInteger)runGarbageCollectionForDID:(NSString *)did
                                   error:(NSError **)error {
    
    // 1. Find all referenced blobs
    NSSet<NSString *> *referencedCIDs = [self findReferencedBlobsForDID:did
                                                                   error:error];
    if (!referencedCIDs) {
        return 0;
    }
    
    // 2. List all blobs for user
    NSArray<PDSDatabaseBlob *> *allBlobs = [self.blobStorage listBlobsForDID:did
                                                                        limit:1000
                                                                       cursor:nil
                                                                        error:error];
    if (!allBlobs) {
        return 0;
    }
    
    // 3. Delete unreferenced blobs
    NSUInteger deletedCount = 0;
    
    for (PDSDatabaseBlob *blob in allBlobs) {
        CID *cid = [CID cidFromBytes:blob.cid];
        NSString *cidString = cid.stringValue;
        
        // Skip if referenced
        if ([referencedCIDs containsObject:cidString]) {
            continue;
        }
        
        // Skip if too new (grace period)
        NSTimeInterval age = [[NSDate date] timeIntervalSinceDate:blob.createdAt];
        if (age < 24 * 60 * 60) { // 24 hour grace period
            continue;
        }
        
        // Delete blob
        NSError *deleteError = nil;
        BOOL deleted = [self.blobStorage deleteBlobWithCID:cid
                                                       did:did
                                                     error:&deleteError];
        
        if (deleted) {
            deletedCount++;
            PDS_LOG_DEBUG_C(PDSLogComponentBlob,
                @"Deleted orphaned blob %@ for %@", cidString, did);
        } else {
            PDS_LOG_ERROR_C(PDSLogComponentBlob,
                @"Failed to delete blob %@: %@", cidString, deleteError);
        }
    }
    
    return deletedCount;
}

- (nullable NSSet<NSString *> *)findReferencedBlobsForDID:(NSString *)did
                                                     error:(NSError **)error {
    
    NSMutableSet<NSString *> *referencedCIDs = [NSMutableSet set];
    
    PDSActorStore *store = [self.databasePool storeForDid:did error:error];
    if (!store) {
        return nil;
    }
    
    NSString *cursor = nil;
    NSUInteger limit = 100;
    
    do {
        @autoreleasepool {
            NSArray<PDSDatabaseRecord *> *records = [store listRecordsForDid:did
                                                                  collection:nil
                                                                       limit:limit
                                                                      cursor:cursor
                                                                       error:error];
            
            if (!records) {
                return nil;
            }
            
            for (PDSDatabaseRecord *record in records) {
                NSSet<NSString *> *blobCIDs = [self extractBlobCIDsFromRecord:record
                                                                        error:error];
                if (blobCIDs) {
                    [referencedCIDs unionSet:blobCIDs];
                }
            }
            
            cursor = (records.count < limit) ? nil : records.lastObject.rkey;
        }
        
    } while (cursor != nil);
    
    return referencedCIDs;
}

- (nullable NSSet<NSString *> *)extractBlobCIDsFromRecord:(PDSDatabaseRecord *)record
                                                     error:(NSError **)error {
    
    NSMutableSet<NSString *> *cidSet = [NSMutableSet set];
    
    NSError *decodeError = nil;
    id jsonObject = [ATProtoCBORSerialization decodeDataToJSONObject:record.value
                                                               error:&decodeError];
    
    if (!jsonObject) {
        if (error) *error = decodeError;
        return nil;
    }
    
    [self findBlobReferencesInObject:jsonObject collector:cidSet];
    
    return cidSet;
}

- (void)findBlobReferencesInObject:(id)obj
                         collector:(NSMutableSet<NSString *> *)collector {
    
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)obj;
        
        // Check for blob reference
        if ([dict[@"$type"] isEqualToString:@"blob"] && dict[@"ref"]) {
            NSDictionary *ref = dict[@"ref"];
            NSString *cidString = ref[@"$link"];
            
            if ([cidString isKindOfClass:[NSString class]]) {
                [collector addObject:cidString];
            }
        }
        
        // Recurse into values
        for (id value in dict.allValues) {
            [self findBlobReferencesInObject:value collector:collector];
        }
        
    } else if ([obj isKindOfClass:[NSArray class]]) {
        NSArray *array = (NSArray *)obj;
        
        // Recurse into elements
        for (id element in array) {
            [self findBlobReferencesInObject:element collector:collector];
        }
    }
}

- (NSDictionary *)dryRunForDID:(NSString *)did error:(NSError **)error {
    NSSet<NSString *> *referencedCIDs = [self findReferencedBlobsForDID:did
                                                                   error:error];
    if (!referencedCIDs) {
        return nil;
    }
    
    NSArray<PDSDatabaseBlob *> *allBlobs = [self.blobStorage listBlobsForDID:did
                                                                        limit:1000
                                                                       cursor:nil
                                                                        error:error];
    if (!allBlobs) {
        return nil;
    }
    
    NSMutableArray<NSString *> *orphanedCIDs = [NSMutableArray array];
    NSUInteger totalSize = 0;
    
    for (PDSDatabaseBlob *blob in allBlobs) {
        CID *cid = [CID cidFromBytes:blob.cid];
        NSString *cidString = cid.stringValue;
        
        if (![referencedCIDs containsObject:cidString]) {
            [orphanedCIDs addObject:cidString];
            totalSize += blob.size;
        }
    }
    
    return @{
        @"orphaned_count": @(orphanedCIDs.count),
        @"orphaned_cids": orphanedCIDs,
        @"total_size_bytes": @(totalSize),
        @"total_blobs": @(allBlobs.count),
        @"referenced_count": @(referencedCIDs.count)
    };
}

- (NSArray<NSString *> *)getAllUserDIDs {
    NSString *sql = @"SELECT did FROM accounts";
    NSError *error = nil;
    NSArray *rows = [self.serviceDatabases executeQuery:sql
                                             withParams:@[]
                                                  error:&error];
    
    NSMutableArray<NSString *> *dids = [NSMutableArray array];
    for (NSDictionary *row in rows) {
        [dids addObject:row[@"did"]];
    }
    
    return dids;
}

@end
```


## Configuration

### Configuration File

Add GC settings to `config.json`:

```json
{
  "blob_gc": {
    "enabled": true,
    "interval_hours": 24,
    "grace_period_hours": 24,
    "deletion_grace_days": 7,
    "max_blobs_per_run": 1000,
    "parallel_workers": 4,
    "dry_run": false
  }
}
```

### Loading Configuration

```objc
@interface PDSBlobGCConfiguration : NSObject

@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) NSTimeInterval interval;
@property (nonatomic, assign) NSTimeInterval gracePeriod;
@property (nonatomic, assign) NSTimeInterval deletionGracePeriod;
@property (nonatomic, assign) NSUInteger maxBlobsPerRun;
@property (nonatomic, assign) NSUInteger parallelWorkers;
@property (nonatomic, assign) BOOL dryRun;

+ (instancetype)configurationFromDictionary:(NSDictionary *)dict;

@end

@implementation PDSBlobGCConfiguration

+ (instancetype)configurationFromDictionary:(NSDictionary *)dict {
    PDSBlobGCConfiguration *config = [[PDSBlobGCConfiguration alloc] init];
    
    config.enabled = [dict[@"enabled"] boolValue];
    config.interval = [dict[@"interval_hours"] doubleValue] * 3600;
    config.gracePeriod = [dict[@"grace_period_hours"] doubleValue] * 3600;
    config.deletionGracePeriod = [dict[@"deletion_grace_days"] doubleValue] * 86400;
    config.maxBlobsPerRun = [dict[@"max_blobs_per_run"] unsignedIntegerValue];
    config.parallelWorkers = [dict[@"parallel_workers"] unsignedIntegerValue];
    config.dryRun = [dict[@"dry_run"] boolValue];
    
    // Defaults
    if (config.interval == 0) config.interval = 24 * 3600;
    if (config.gracePeriod == 0) config.gracePeriod = 24 * 3600;
    if (config.deletionGracePeriod == 0) config.deletionGracePeriod = 7 * 86400;
    if (config.maxBlobsPerRun == 0) config.maxBlobsPerRun = 1000;
    if (config.parallelWorkers == 0) config.parallelWorkers = 4;
    
    return config;
}

@end
```

## See Also

- [Blob Lifecycle](./blob-lifecycle.md) — Upload, download, and deletion workflows
- [Blob Optimization](./blob-optimization.md) — Performance optimization techniques
- [Blob Storage](./blob-storage.md) — Storage architecture and providers
- [Blob Service](../03-application-layer/blob-service.md) — Service layer API
- [Database Layer](../05-database-layer/sqlite-architecture.md) — Database architecture

