# Repository Basics

## Overview

A repository is a versioned data store for a user. It contains:
- **Records** — User data (posts, profiles, likes, etc.)
- **Blobs** — Binary files (images, videos, etc.)
- **Commits** — Versioned snapshots of repository state
- **MST** — Merkle Search Tree for efficient lookups

## Repository Structure

```
Repository (did:plc:user123)
├── Records
│   ├── app.bsky.feed.post/abc123
│   ├── app.bsky.feed.post/def456
│   ├── app.bsky.actor.profile/self
│   └── app.bsky.feed.like/ghi789
├── Blobs
│   ├── bafyreiabc123...
│   └── bafyredef456...
└── Commits
    ├── Commit 1 (root)
    ├── Commit 2
    └── Commit 3 (head)
```

## Records

### Record Identifiers

Records are identified by:
- **DID** — User identifier
- **Collection** — Record type (e.g., `app.bsky.feed.post`)
- **RKey** — Record key (unique within collection)

**Full URI:** `at://did:plc:user123/app.bsky.feed.post/abc123`

### Record Keys (RKeys)

RKeys can be:
- **TID** — Timestamp Identifier (for time-ordered records)
- **Random** — Random string (for unordered records)
- **"self"** — Singleton records (like profile)

### Creating Records

```objc
// In PDSRecordService.m
- (void)createRecord:(NSDictionary *)record
          collection:(NSString *)collection
                 did:(NSString *)did
          completion:(void (^)(NSString *uri, NSError *error))completion {
    
    // 1. Validate record against lexicon
    NSError *error = nil;
    if (![self validateRecord:record againstLexicon:collection error:&error]) {
        completion(nil, error);
        return;
    }
    
    // 2. Generate RKey (TID for time-ordered, random for unordered)
    NSString *rkey = [self generateRKeyForCollection:collection];
    
    // 3. Encode record to CBOR
    NSData *cbor = [ATProtoCBORSerialization encodeDataWithJSONObject:record error:&error];
    if (!cbor) {
        completion(nil, error);
        return;
    }
    
    // 4. Calculate CID
    NSData *hash = [CID sha256Digest:cbor];
    CID *cid = [CID cidWithDigest:hash codec:0x71];
    
    // 5. Store in database
    PDSActorStore *store = [self.app.databasePool storeForDid:did error:&error];
    if (!store) {
        completion(nil, error);
        return;
    }
    
    // 6. Create URI
    NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];
    completion(uri, nil);
}
```

**Source:** `ATProtoPDS/Sources/Blob/BlobStorage.m` (lines 35-85); `ATProtoPDS/Sources/Core/ATProtoCBORSerialization.m` (lines 8-20); `ATProtoPDS/Sources/Core/CID.m` (lines 280-295)

## Blobs

### Blob Storage

Blobs are stored separately from records:
- **CID** — Content identifier (hash of blob data)
- **Size** — Blob size in bytes
- **MIME type** — Content type

### Uploading Blobs

```objc
// In PDSBlobService.m
- (void)uploadBlob:(NSData *)data
        completion:(void (^)(NSString *blobCID, NSError *error))completion {
    
    // 1. Calculate CID
    NSString *cid = [CID calculateCIDForData:data];
    
    // 2. Store blob
    PDSActorDatabase *db = [self.app.databasePool databaseForDID:self.userDID error:nil];
    [self storeBlob:data cid:cid db:db];
    
    completion(cid, nil);
}

- (void)getBlob:(NSString *)blobCID
     completion:(void (^)(NSData *data, NSError *error))completion {
    
    // 1. Retrieve blob from database
    PDSActorDatabase *db = [self.app.databasePool databaseForDID:self.userDID error:nil];
    NSData *data = [self retrieveBlob:blobCID db:db];
    
    if (!data) {
        NSError *error = [NSError errorWithDomain:@"Blob" code:1 
            userInfo:@{NSLocalizedDescriptionKey: @"Blob not found"}];
        completion(nil, error);
        return;
    }
    
    completion(data, nil);
}
```

## Commits

### Commit Structure

A commit contains:
- **Root CID** — Hash of repository's MST
- **Previous CID** — Hash of previous commit
- **Timestamp** — When commit was created
- **Signature** — Cryptographic signature

### Creating Commits

```objc
// In PDSRepositoryService.m
- (void)createCommitWithRootCID:(NSString *)rootCID
                            did:(NSString *)did
                     completion:(void (^)(NSString *commitCID, NSError *error))completion {
    
    // 1. Get previous commit
    NSString *prevCID = [self getHeadCommitCID:did];
    
    // 2. Create commit object
    NSDictionary *commit = @{
        @"root": rootCID,
        @"prev": prevCID ?: [NSNull null],
        @"timestamp": [NSDate date],
        @"did": did
    };
    
    // 3. Encode commit
    NSData *commitData = [ATProtoCBORSerialization encodeObject:commit error:nil];
    
    // 4. Sign commit
    NSString *signature = [self signData:commitData withKey:self.userPrivateKey];
    
    // 5. Create signed commit
    NSDictionary *signedCommit = @{
        @"commit": commit,
        @"signature": signature
    };
    
    // 6. Calculate commit CID
    NSData *signedData = [ATProtoCBORSerialization encodeObject:signedCommit error:nil];
    NSString *commitCID = [CID calculateCIDForData:signedData];
    
    // 7. Store commit
    PDSActorDatabase *db = [self.app.databasePool databaseForDID:did error:nil];
    [self storeCommit:signedCommit cid:commitCID db:db];
    
    completion(commitCID, nil);
}
```

## Repository Operations

### Reading Records

```objc
// In PDSRecordService.m
- (void)getRecord:(NSString *)did
       collection:(NSString *)collection
             rkey:(NSString *)rkey
       completion:(void (^)(NSDictionary *record, NSError *error))completion {
    
    // 1. Get actor database
    PDSActorDatabase *db = [self.app.databasePool databaseForDID:did error:nil];
    
    // 2. Query database
    const char *sql = "SELECT data FROM records WHERE collection = ? AND rkey = ?";
    sqlite3_stmt *stmt;
    sqlite3_prepare_v2(db.connection, sql, -1, &stmt, NULL);
    
    sqlite3_bind_text(stmt, 1, [collection UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, [rkey UTF8String], -1, SQLITE_TRANSIENT);
    
    // 3. Fetch result
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        const void *data = sqlite3_column_blob(stmt, 0);
        int size = sqlite3_column_bytes(stmt, 0);
        
        NSData *cbor = [NSData dataWithBytes:data length:size];
        NSDictionary *record = [ATProtoCBORSerialization decodeData:cbor error:nil];
        
        sqlite3_finalize(stmt);
        completion(record, nil);
    } else {
        sqlite3_finalize(stmt);
        NSError *error = [NSError errorWithDomain:@"Record" code:1 
            userInfo:@{NSLocalizedDescriptionKey: @"Record not found"}];
        completion(nil, error);
    }
}
```

### Updating Records

```objc
// In PDSRecordService.m
- (void)updateRecord:(NSDictionary *)record
          collection:(NSString *)collection
                rkey:(NSString *)rkey
                 did:(NSString *)did
          completion:(void (^)(NSString *uri, NSError *error))completion {
    
    // 1. Validate record
    if (![self validateRecord:record againstLexicon:collection error:nil]) {
        NSError *error = [NSError errorWithDomain:@"Record" code:1 
            userInfo:@{NSLocalizedDescriptionKey: @"Invalid record"}];
        completion(nil, error);
        return;
    }
    
    // 2. Encode record
    NSData *cbor = [ATProtoCBORSerialization encodeObject:record error:nil];
    NSString *cid = [CID calculateCIDForData:cbor];
    
    // 3. Update in database
    PDSActorDatabase *db = [self.app.databasePool databaseForDID:did error:nil];
    [self updateRecordInDatabase:record collection:collection rkey:rkey cid:cid db:db];
    
    // 4. Update MST and create commit
    [self.app.repositoryService updateMSTWithRecord:record 
                                         collection:collection 
                                              rkey:rkey 
                                               did:did 
                                        completion:^(NSString *rootCID, NSError *error) {
        if (error) {
            completion(nil, error);
            return;
        }
        
        NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];
        completion(uri, nil);
    }];
}
```

### Deleting Records

```objc
// In PDSRecordService.m
- (void)deleteRecord:(NSString *)did
          collection:(NSString *)collection
                rkey:(NSString *)rkey
          completion:(void (^)(NSError *error))completion {
    
    // 1. Delete from database
    PDSActorDatabase *db = [self.app.databasePool databaseForDID:did error:nil];
    [self deleteRecordFromDatabase:collection rkey:rkey db:db];
    
    // 2. Update MST
    [self.app.repositoryService updateMSTWithDeletedRecord:collection 
                                                      rkey:rkey 
                                                       did:did 
                                                completion:^(NSString *rootCID, NSError *error) {
        if (error) {
            completion(error);
            return;
        }
        
        // 3. Create commit
        [self.app.repositoryService createCommitWithRootCID:rootCID 
                                                       did:did 
                                                completion:^(NSString *commitCID, NSError *error) {
            completion(error);
        }];
    }];
}
```

## Repository Sync

### Syncing Repositories

```objc
// In PDSRepositoryService.m
- (void)syncRepository:(NSString *)remoteDID
            completion:(void (^)(NSError *error))completion {
    
    // 1. Get local MST
    MST *localMST = [self getMSTForDID:remoteDID];
    
    // 2. Get remote MST
    [self fetchRemoteMST:remoteDID completion:^(MST *remoteMST, NSError *error) {
        if (error) {
            completion(error);
            return;
        }
        
        // 3. Calculate differences
        NSArray *diffs = [self diffMST:localMST remoteMST:remoteMST];
        
        // 4. Apply differences
        for (NSDictionary *diff in diffs) {
            NSString *type = diff[@"type"];
            NSString *key = diff[@"key"];
            
            if ([type isEqualToString:@"add"]) {
                [self addRecordFromRemote:key];
            } else if ([type isEqualToString:@"remove"]) {
                [self removeRecordLocally:key];
            } else if ([type isEqualToString:@"update"]) {
                [self updateRecordFromRemote:key];
            }
        }
        
        completion(nil);
    }];
}
```

## Best Practices

1. **Validate records** — Always validate against lexicon
2. **Use transactions** — Ensure atomicity
3. **Sign commits** — Always sign repository changes
4. **Verify signatures** — Always verify before accepting
5. **Handle conflicts** — Implement conflict resolution
6. **Monitor performance** — Track repository size and access patterns

## Next Steps

- **[CBOR Serialization](./cbor-serialization.md)** — Data encoding
- **[CAR Format](./car-format.md)** — Archive format
- **[CID and Hashing](./cid-and-hashing.md)** — Content addressing
