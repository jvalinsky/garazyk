# Repository Service

## Overview

The `PDSRepositoryService` manages ATProto repositories including Merkle Search Tree (MST) operations, commit processing, and repository synchronization. It provides the core data structure for storing and verifying records.

## Responsibilities

- MST loading and persistence
- Repository record updates
- Commit generation and application
- Repository export (CAR format)
- Repository synchronization
- Repository initialization
- Block retrieval and management

## Architecture

```
┌──────────────────────────────────────────┐
│   XRPC Sync Endpoints                    │
│  (com.atproto.sync.*)                    │
└────────────────┬─────────────────────────┘
                 │
┌────────────────▼─────────────────────────┐
│   PDSRepositoryService                   │
│  - loadMST()                             │
│  - updateMST()                           │
│  - getRepoRoot()                         │
│  - getRepoContents()                     │
│  - updateRepo()                          │
│  - initializeRepo()                      │
└────────────────┬─────────────────────────┘
                 │
        ┌────────┴────────┐
        │                 │
┌───────▼──────────┐  ┌──▼──────────────┐
│ MST Operations   │  │ CAR Encoding    │
│ (Tree Updates)   │  │ (Export/Import) │
└──────────────────┘  └──────────────────┘
        │
        └────────┬────────┘
                 │
        ┌────────▼────────────┐
        │ PDSDatabasePool     │
        │ (Repository Storage)│
        └─────────────────────┘
```

## Key Methods

### Load MST

```objc
- (nullable MST *)loadMSTForDid:(NSString *)did error:(NSError **)error;
```

Loads the Merkle Search Tree for a repository.

**Parameters:**
- `did`: Decentralized identifier of repository owner
- `error`: Error pointer for loading failures

**Returns:** MST instance or nil if repository doesn't exist

**Implementation pattern (from PDSRepositoryService.m lines 30-50):**

The service loads all records and constructs the MST:

```objc
- (nullable MST *)loadMSTForDid:(NSString *)did error:(NSError **)error {
    PDSActorStore *store = [_databasePool storeForDid:did error:error];
    if (!store) return nil;

    NSArray<PDSDatabaseRecord *> *records = [self loadAllRecordsForStore:store did:did error:error];
    if (!records && error && *error) {
        return nil;
    }
    return [self mstFromRecords:records ?: @[]];
}
```

**Example usage:**
```objc
NSError *error = nil;
MST *mst = [repositoryService loadMSTForDid:@"did:plc:user123" error:&error];

if (mst) {
    // MST is now loaded and ready for queries
    NSData *value = [mst getValueForKey:@"app.bsky.feed.post/abc123"];
}
```

### Update MST

```objc
- (BOOL)updateMSTForDid:(NSString *)did 
                   key:(NSString *)key 
                   cid:(nullable CID *)cid 
                 error:(NSError **)error;
```

Updates a single key in the repository MST.

**Parameters:**
- `did`: Repository owner DID
- `key`: Record key (e.g., "app.bsky.feed.post/123")
- `cid`: Content identifier of record value, or nil to delete
- `error`: Error pointer for update failures

**Returns:** YES on success, NO on failure

**Implementation pattern (from PDSRepositoryService.m lines 50-100):**

The service updates the MST and persists the new root CID:

```objc
- (BOOL)updateMSTForDid:(NSString *)did key:(NSString *)key cid:(nullable CID *)cid error:(NSError **)error {
    MST *mst = [self loadMSTForDid:did error:error];
    if (!mst) return NO;
    
    if (cid) {
        [mst put:key valueCID:cid subKey:nil];
    } else {
        [mst delete:key];
    }
    
    CID *repoRoot = mst.rootCID;
    if (!repoRoot) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.repo"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to compute repo root CID"}];
        }
        return NO;
    }
    
    PDSActorStore *store = [_databasePool storeForDid:did error:error];
    if (!store) return NO;
    
    __block BOOL success = NO;
    [store transactWithBlock:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
        success = [transactor updateRepoRoot:did
                                     rootCid:[repoRoot bytes]
                                         rev:[TID tid].stringValue
                                       error:blockError];
    } error:error];
    
    return success;
}
```

**Example usage:**
```objc
// Create a new record
NSError *error = nil;
CID *recordCid = [self generateCIDForRecord:recordData];

BOOL success = [repositoryService updateMSTForDid:@"did:plc:user123"
                                              key:@"app.bsky.feed.post/abc123"
                                              cid:recordCid
                                            error:&error];

// Delete a record
success = [repositoryService updateMSTForDid:@"did:plc:user123"
                                         key:@"app.bsky.feed.post/abc123"
                                         cid:nil
                                       error:&error];
```

### Get Repository Root

```objc
- (nullable NSData *)getRepoRoot:(NSString *)did error:(NSError **)error;
```

Gets the root CID of a repository.

**Parameters:**
- `did`: Repository owner DID
- `error`: Error pointer for retrieval failures

**Returns:** CAR-encoded commit root data or nil if not found

**Implementation pattern (from PDSRepositoryService.m lines 100-150):**

The service retrieves the stored repo root and associated block data:

```objc
- (nullable NSData *)getRepoRoot:(NSString *)did error:(NSError **)error {
    PDS_LOG_DB_DEBUG(@"Looking up repo root for DID: %@", did);

    PDSActorStore *store = [_databasePool storeForDid:did error:error];
    if (!store) {
        PDS_LOG_DB_DEBUG(@"storeForDid returned nil for: %@", did);
        return nil;
    }
    
    __block NSData *rootData = nil;
    [store readWithBlock:^(id<PDSActorStoreReader> reader, NSError **blockError) {
        NSData *rootCidBytes = [reader getRepoRootForDid:did error:blockError];
        if (rootCidBytes) {
            NSData *blockData = [reader getBlockForCID:rootCidBytes forDid:did error:blockError];
            if (blockData) {
                rootData = blockData;
            }
        }
    } error:error];

    return rootData;
}
```

**Example usage:**
```objc
NSError *error = nil;
NSData *rootData = [repositoryService getRepoRoot:@"did:plc:user123" error:&error];

if (rootData) {
    // Parse CAR data to get root CID
    NSString *rootCid = [self parseRootCidFromCAR:rootData];
}
```

### Get Repository Contents

```objc
- (nullable NSData *)getRepoContents:(NSString *)did 
                               since:(nullable NSString *)sinceRev 
                               error:(NSError **)error;
```

Gets repository contents as CAR-encoded data.

**Parameters:**
- `did`: Repository owner DID
- `sinceRev`: Previous commit revision for incremental sync (nil for full export)
- `error`: Error pointer for export failures

**Returns:** CAR-encoded repository blocks or nil on failure

**Implementation pattern (from PDSRepositoryService.m lines 200-220):**

The service builds a CAR writer and serializes the repository:

```objc
- (nullable NSData *)getRepoContents:(NSString *)did since:(nullable NSString *)sinceRev error:(NSError **)error {
    CARWriter *writer = [self buildRepoWriterForDid:did since:sinceRev error:error];
    if (!writer) {
        return nil;
    }
    return [writer serialize];
}
```

**Example usage:**
```objc
// Full export
NSError *error = nil;
NSData *carData = [repositoryService getRepoContents:@"did:plc:user123"
                                               since:nil
                                               error:&error];

// Incremental export since last sync
NSData *deltaData = [repositoryService getRepoContents:@"did:plc:user123"
                                                 since:@"bafyrev123"
                                                 error:&error];
```

### Write Repository Contents to File

```objc
- (BOOL)writeRepoContents:(NSString *)did 
                    since:(nullable NSString *)sinceRev 
                   toPath:(NSString *)path 
                   error:(NSError **)error;
```

Writes repository contents directly to a CAR file without loading into memory.

**Parameters:**
- `did`: Repository owner DID
- `sinceRev`: Previous commit revision for incremental sync
- `path`: Output file path
- `error`: Error pointer for export failures

**Returns:** YES on success, NO on failure

**Implementation pattern (from PDSRepositoryService.m lines 220-300):**

The service streams repository data directly to a file handle:

```objc
- (BOOL)writeRepoContents:(NSString *)did since:(nullable NSString *)sinceRev toPath:(NSString *)path error:(NSError **)error {
    PDSActorStore *store = nil;
    MST *mst = nil;
    CID *commitCID = nil;
    NSData *commitBlock = nil;
    BOOL noChangesSince = NO;
    BOOL includeFullMST = YES;
    NSArray<NSString *> *changedMSTKeys = nil;
    NSArray<NSString *> *recordCIDStrings = nil;
    NSDictionary<NSString *, PDSDatabaseRecord *> *recordByCID = nil;
    NSDictionary<NSString *, NSData *> *materializedBlocks = nil;
    
    if (![self prepareRepoExportForDid:did
                                 since:sinceRev
                                 store:&store
                                   mst:&mst
                             commitCID:&commitCID
                           commitBlock:&commitBlock
                        noChangesSince:&noChangesSince
                        includeFullMST:&includeFullMST
                        changedMSTKeys:&changedMSTKeys
                       recordCIDStrings:&recordCIDStrings
                            recordByCID:&recordByCID
                    materializedBlocks:&materializedBlocks
                                 error:error]) {
        return NO;
    }

    if (![[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil]) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.repo"
                                         code:7
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to create repo CAR file"}];
        }
        return NO;
    }

    NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!fileHandle) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.repo"
                                         code:8
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to open repo CAR file"}];
        }
        return NO;
    }

    @try {
        if (![CARWriter writeHeaderWithRootCID:commitCID toFileHandle:fileHandle error:error]) {
            [fileHandle closeFile];
            return NO;
        }

        if (noChangesSince) {
            [fileHandle closeFile];
            return YES;
        }

        if (![CARWriter writeBlock:[CARBlock blockWithCID:commitCID data:commitBlock]
                      toFileHandle:fileHandle
                             error:error]) {
            [fileHandle closeFile];
            return NO;
        }
    } @finally {
        [fileHandle closeFile];
    }

    return YES;
}
```

**Example usage:**
```objc
NSError *error = nil;
BOOL success = [repositoryService writeRepoContents:@"did:plc:user123"
                                              since:nil
                                             toPath:@"/tmp/repo.car"
                                              error:&error];

if (success) {
    // CAR file is ready for transmission
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *attrs = [fm attributesOfItemAtPath:@"/tmp/repo.car" error:nil];
    NSNumber *fileSize = attrs[NSFileSize];
}
```

### Repository Contents Chunk Producer

```objc
- (nullable PDSRepoChunkProducer)repoContentsChunkProducer:(NSString *)did
                                                    since:(nullable NSString *)sinceRev
                                                    error:(NSError **)error;
```

Creates a pull-based chunk producer for streaming repository contents.

**Parameters:**
- `did`: Repository owner DID
- `sinceRev`: Previous commit revision for incremental sync
- `error`: Error pointer for preparation failures

**Returns:** Chunk producer block or nil on failure

**Example:**
```objc
NSError *error = nil;
PDSRepoChunkProducer producer = [repositoryService repoContentsChunkProducer:@"did:plc:user123"
                                                                       since:nil
                                                                       error:&error];

if (producer) {
    while (YES) {
        NSError *chunkError = nil;
        NSData *chunk = producer(&chunkError);
        
        if (!chunk) {
            if (chunkError) {
                // Handle error
            }
            break; // End of stream
        }
        
        // Send chunk to client
        [self sendChunkToClient:chunk];
    }
}
```

### Update Repository

```objc
- (BOOL)updateRepo:(NSString *)did 
             commit:(NSData *)commitData 
              error:(NSError **)error;
```

Applies a commit to update the repository.

**Parameters:**
- `did`: Repository owner DID
- `commitData`: CAR-encoded commit containing MST root and signature
- `error`: Error pointer for commit failures

**Returns:** YES on success, NO on failure

**Example:**
```objc
NSError *error = nil;
BOOL success = [repositoryService updateRepo:@"did:plc:user123"
                                      commit:commitCAR
                                       error:&error];

if (success) {
    // Repository has been updated with new commit
} else if (error.code == 409) {
    // Conflict: repo was modified, retry
}
```

### Get Blocks

```objc
- (nullable NSData *)getBlocksForDid:(NSString *)did 
                                cids:(NSArray<NSString *> *)cids 
                               error:(NSError **)error;
```

Gets CAR file containing specific blocks.

**Parameters:**
- `did`: Repository DID
- `cids`: Array of CID strings to fetch
- `error`: Error pointer

**Returns:** CAR data with requested blocks

### Get Latest Commit

```objc
- (nullable NSDictionary *)getLatestCommitForDid:(NSString *)did error:(NSError **)error;
```

Gets the latest commit CID and revision.

**Parameters:**
- `did`: Repository DID
- `error`: Error pointer

**Returns:** Dictionary with @"cid" and @"rev" keys

**Implementation pattern (from PDSRepositoryService.m lines 150-200):**

The service retrieves the stored commit metadata or rebuilds it if needed:

```objc
- (nullable NSDictionary *)getLatestCommitForDid:(NSString *)did error:(NSError **)error {
    PDSActorStore *store = [_databasePool storeForDid:did error:error];
    if (!store) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"com.atproto.sync"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Repo not found"}];
        }
        return nil;
    }

    // Fast path: use already-persisted signed head commit metadata
    CID *storedCommitCID = nil;
    NSData *unusedCommitBlock = nil;
    CID *unusedDataCID = nil;
    NSString *storedCommitRev = nil;
    BOOL storedCommitIsSigned = NO;
    BOOL hasStoredHead = [self loadStoredHeadCommitForDid:did
                                                    store:store
                                                commitCID:&storedCommitCID
                                              commitBlock:&unusedCommitBlock
                                                  dataCID:&unusedDataCID
                                                      rev:&storedCommitRev
                                                 isSigned:&storedCommitIsSigned];
    if (hasStoredHead && storedCommitIsSigned && storedCommitCID.stringValue.length > 0) {
        NSString *rev = [store getRepoRevisionForDid:did error:nil];
        if (rev.length == 0) {
            rev = storedCommitRev ?: @"";
        }
        return @{@"cid": storedCommitCID.stringValue, @"rev": rev ?: @""};
    }

    // Slow path: rebuild export state, self-heal head commit if needed
    MST *mst = nil;
    CID *commitCID = nil;
    NSData *commitBlock = nil;
    BOOL noChangesSince = NO;
    BOOL includeFullMST = YES;
    NSArray<NSString *> *changedMSTKeys = nil;
    NSArray<NSString *> *recordCIDStrings = nil;
    NSDictionary<NSString *, PDSDatabaseRecord *> *recordByCID = nil;
    NSDictionary<NSString *, NSData *> *materializedBlocks = nil;

    if (![self prepareRepoExportForDid:did
                                 since:nil
                                 store:&store
                                   mst:&mst
                             commitCID:&commitCID
                           commitBlock:&commitBlock
                        noChangesSince:&noChangesSince
                        includeFullMST:&includeFullMST
                        changedMSTKeys:&changedMSTKeys
                       recordCIDStrings:&recordCIDStrings
                            recordByCID:&recordByCID
                    materializedBlocks:&materializedBlocks
                                 error:error]) {
        return nil;
    }

    NSString *rev = [store getRepoRevisionForDid:did error:nil] ?: @"";
    return @{@"cid": commitCID.stringValue ?: @"", @"rev": rev};
}
```

**Example usage:**
```objc
NSError *error = nil;
NSDictionary *commit = [repositoryService getLatestCommitForDid:@"did:plc:user123" error:&error];

if (commit) {
    NSString *cid = commit[@"cid"];
    NSString *rev = commit[@"rev"];
}
```

### Initialize Repository

```objc
- (BOOL)initializeRepoForDid:(NSString *)did error:(NSError **)error;
```

Initializes an empty repository for a new account.

**Parameters:**
- `did`: Repository owner DID
- `error`: Error pointer for initialization failures

**Returns:** YES on success, NO on failure

**Example usage:**
```objc
NSError *error = nil;
BOOL success = [repositoryService initializeRepoForDid:@"did:plc:user123"
                                                 error:&error];

if (success) {
    // Repository is now ready for records
}
```

## MST Structure

The Merkle Search Tree provides:

- **Content-addressed storage**: Each node has a CID
- **Cryptographic integrity**: Root CID verifies entire tree
- **Efficient updates**: Only affected nodes are recomputed
- **Proof generation**: Can prove record existence/non-existence

## CAR Format

Repository contents are exported as CAR (Content Addressable aRchive) v1:

```
CAR Header
├── Root CID
└── Block Count

Blocks
├── Block 1 (CID + Data)
├── Block 2 (CID + Data)
└── Block N (CID + Data)
```

## Commit Structure

Commits contain:

```
Commit
├── MST Root CID
├── Signature (DID key)
├── Timestamp
└── Previous Commit CID (optional)
```

## Error Handling

Common error scenarios:

| Error | Cause | Handling |
|-------|-------|----------|
| Not found | Repository doesn't exist | Return 404 |
| Invalid commit | Signature verification failed | Return 400 |
| Conflict | Concurrent modification | Return 409 |
| Corrupted | Missing blocks or invalid structure | Return 500 |

## Best Practices

1. **MST Operations**
   - Load MST once per request
   - Batch updates when possible
   - Use transactions for consistency

2. **Repository Export**
   - Use chunk producer for large repos
   - Implement streaming for memory efficiency
   - Support incremental sync with sinceRev

3. **Commit Processing**
   - Verify signatures before applying
   - Check commit ordering
   - Maintain commit history

4. **Synchronization**
   - Use sinceRev for incremental sync
   - Implement retry logic for failed commits
   - Handle concurrent modifications

## Common Patterns

### Exporting a Repository

```objc
// Stream large repository without loading into memory
NSError *error = nil;
PDSRepoChunkProducer producer = [repositoryService repoContentsChunkProducer:userDid
                                                                       since:nil
                                                                       error:&error];

if (producer) {
    NSOutputStream *output = [NSOutputStream outputStreamToFileAtPath:@"/tmp/export.car"
                                                               append:NO];
    [output open];
    
    while (YES) {
        NSError *chunkError = nil;
        NSData *chunk = producer(&chunkError);
        
        if (!chunk) break;
        [output write:chunk.bytes maxLength:chunk.length];
    }
    
    [output close];
}
```

### Synchronizing Repositories

```objc
// Get last known commit
NSDictionary *lastCommit = [self getLastSyncedCommit:userDid];
NSString *sinceRev = lastCommit[@"rev"];

// Get incremental changes
NSError *error = nil;
NSData *deltaCAR = [repositoryService getRepoContents:userDid
                                                since:sinceRev
                                                error:&error];

// Apply changes
if (deltaCAR) {
    BOOL success = [repositoryService updateRepo:userDid
                                          commit:deltaCAR
                                           error:&error];
    
    if (success) {
        // Update last synced commit
        NSDictionary *newCommit = [repositoryService getLatestCommitForDid:userDid
                                                                     error:&error];
        [self saveLastSyncedCommit:newCommit forDid:userDid];
    }
}
```

## See Also

- [Record Service](./record-service)
- [Services Overview](./services-overview)
- [MST Trees](../02-core-concepts/mst-trees)
- [CAR Format](../07-repository-protocol/car-format)
