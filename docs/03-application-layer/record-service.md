# Record Service

## Overview

The `PDSRecordService` provides CRUD (Create, Read, Update, Delete) operations for ATProto records within repositories. It handles record validation, MST updates, transaction management, and batch operations.

## Responsibilities

- Record creation and updates (put operations)
- Record deletion
- Record retrieval by AT URI
- Record listing with pagination
- Batch write operations with atomic transactions
- Lexicon validation (optional)
- Repository statistics

## Architecture

```
┌──────────────────────────────────────────┐
│   XRPC Record Endpoints                  │
│  (com.atproto.repo.*)                    │
└────────────────┬─────────────────────────┘
                 │
┌────────────────▼─────────────────────────┐
│   PDSRecordService                       │
│  - putRecord()                           │
│  - deleteRecord()                        │
│  - getRecord()                           │
│  - listRecords()                         │
│  - applyWrites()                         │
│  - getRepoStats()                        │
└────────────────┬─────────────────────────┘
                 │
        ┌────────┴────────┐
        │                 │
┌───────▼──────────┐  ┌──▼──────────────┐
│ Lexicon         │  │ MST Updates      │
│ Validator       │  │ (via Repository) │
└──────────────────┘  └──────────────────┘
        │                 │
        └────────┬────────┘
                 │
        ┌────────▼────────────┐
        │ PDSDatabasePool     │
        │ (Record Storage)    │
        └─────────────────────┘
```

## Key Methods

### Put Record (Create/Update)

```objc
- (BOOL)putRecord:(NSString *)collection
              rkey:(NSString *)rkey
             value:(NSDictionary *)value
            forDid:(NSString *)did
          actorDid:(NSString *)actorDid
    validationMode:(PDSValidationMode)mode
             error:(NSError **)error;
```

Creates or updates a record in a collection. Validates the record against lexicon if enabled.

**Parameters:**
- `collection`: Collection NSID (e.g., "app.bsky.feed.post")
- `rkey`: Record key within the collection
- `value`: Record value as a dictionary
- `did`: Repository owner DID
- `actorDid`: Authenticated actor's DID (must equal did for self-modification)
- `mode`: Validation mode (Required, Optimistic, or Off)
- `error`: Error pointer for failure details

**Returns:** YES on success, NO on failure

**Implementation pattern (from PDSRecordService.m lines 150-250):**

The service validates authorization, performs lexicon validation, generates a CID, and stores the record:

```objc
- (BOOL)putRecord:(NSString *)collection
              rkey:(NSString *)rkey
             value:(NSDictionary *)value
            forDid:(NSString *)did
          actorDid:(NSString *)actorDid
    validationMode:(PDSValidationMode)mode
             error:(NSError **)error {
    
    // Check authorization
    if (![self checkAuthorizationForDid:did actorDid:actorDid error:error]) {
        return NO;
    }
    
    // Validate collection NSID format
    NSError *nsidError = nil;
    if (![ATProtoValidator validateNSID:collection error:&nsidError]) {
        PDS_LOG_ERROR(@"[PDSRecordService] Invalid collection NSID: %@", collection);
        if (error) *error = nsidError;
        return NO;
    }

    // Lexicon validation
    if (mode != PDSValidationModeOff) {
        ATProtoLexiconValidator *validator = [[ATProtoLexiconValidator alloc]
            initWithRegistry:[ATProtoLexiconRegistry sharedRegistry]];

        NSError *validationError = nil;
        if (![validator validateRecord:value
                            collection:collection
                                  mode:(ATProtoValidationMode)mode
                                 error:&validationError]) {
            PDS_LOG_ERROR(@"[PDSRecordService] Lexicon validation failed for %@: %@",
                          collection, validationError.localizedDescription);
            if (error) *error = validationError;
            return NO;
        }
    }

    // Validate createdAt timestamp coherence
    if (!validateCreatedAtCoherence(collection, rkey, value, mode, error)) {
        return NO;
    }

    // Generate CID using DAG-CBOR encoding
    NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];
    NSError *cidError;
    NSData *cborData = [ATProtoCBORSerialization encodeDataWithJSONObject:value error:&cidError];
    if (!cborData) {
        if (error) *error = cidError;
        return NO;
    }

    NSString *cidString = [self generateCIDForData:cborData error:&cidError];
    if (!cidString) {
        if (error) *error = cidError;
        return NO;
    }

    // Store record in database
    PDSDatabaseRecord *record = [[PDSDatabaseRecord alloc] init];
    record.uri = uri;
    record.did = did;
    record.collection = collection;
    record.rkey = rkey;
    record.cid = cidString;
    record.createdAt = [NSDate date];
    record.rev = [TID tid].stringValue;

    // Save to database
    PDSActorStore *store = [_databasePool storeForDid:did error:error];
    if (!store) return NO;

    __block BOOL success = NO;
    [store transactWithBlock:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
        success = [transactor putRecord:record error:blockError];
    } error:error];

    if (success) {
        // Post notification
        [[NSNotificationCenter defaultCenter] postNotificationName:PDSRecordDidChangeNotification
                                                            object:self
                                                          userInfo:@{
                                                              @"did": did,
                                                              @"collection": collection,
                                                              @"rkey": rkey,
                                                              @"action": @"create"
                                                          }];
    }

    return success;
}
```

**Example usage:**
```objc
NSDictionary *post = @{
    @"text": @"Hello, ATProto!",
    @"createdAt": @"2025-01-15T10:30:00Z",
    @"facets": @[]
};

NSError *error = nil;
BOOL success = [recordService putRecord:@"app.bsky.feed.post"
                                  rkey:@"abc123"
                                 value:post
                                forDid:@"did:plc:user123"
                              actorDid:@"did:plc:user123"
                        validationMode:PDSValidationModeOptimistic
                                 error:&error];
```

### Delete Record

```objc
- (BOOL)deleteRecord:(NSString *)collection
                 rkey:(NSString *)rkey
               forDid:(NSString *)did
             actorDid:(NSString *)actorDid
                error:(NSError **)error;
```

Deletes a record from a collection.

**Parameters:**
- `collection`: Collection NSID
- `rkey`: Record key to delete
- `did`: Repository owner DID
- `actorDid`: Authenticated actor's DID
- `error`: Error pointer for failure details

**Returns:** YES on success, NO on failure

**Example:**
```objc
NSError *error = nil;
BOOL deleted = [recordService deleteRecord:@"app.bsky.feed.post"
                                      rkey:@"abc123"
                                    forDid:@"did:plc:user123"
                                  actorDid:@"did:plc:user123"
                                     error:&error];
```

### Get Record

```objc
- (nullable NSDictionary *)getRecord:(NSString *)uri
                              forDid:(NSString *)did
                               error:(NSError **)error;
```

Retrieves a record by AT URI.

**Parameters:**
- `uri`: AT URI (e.g., "at://did:plc:user123/app.bsky.feed.post/abc123")
- `did`: Repository owner DID
- `error`: Error pointer for failure details

**Returns:** Record dictionary or nil if not found

**Implementation pattern (from PDSRecordService.m lines 100-150):**

The service retrieves the record from the database and parses the value:

```objc
- (nullable NSDictionary *)getRecord:(NSString *)uri forDid:(NSString *)did error:(NSError **)error {
    PDSDatabaseRecord *record = [_databasePool getRecord:uri forDid:did error:error];

    if (!record) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSController" code:1004
                                     userInfo:@{NSLocalizedDescriptionKey: @"Record not found"}];
        }
        return nil;
    }

    NSDictionary *parsedValue = @{};
    if (record.value) {
        if ([record.value respondsToSelector:@selector(dataUsingEncoding:)]) {
            NSData *data = [record.value dataUsingEncoding:NSUTF8StringEncoding];
            if (data) {
                parsedValue = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] ?: @{};
            }
        } else if ([record.value isKindOfClass:[NSDictionary class]]) {
            parsedValue = (NSDictionary *)record.value;
        }
    }

    return @{
        @"uri": record.uri,
        @"cid": record.cid,
        @"collection": record.collection,
        @"rkey": record.rkey,
        @"value": parsedValue
    };
}
```

**Example usage:**
```objc
NSError *error = nil;
NSDictionary *record = [recordService getRecord:@"at://did:plc:user123/app.bsky.feed.post/abc123"
                                        forDid:@"did:plc:user123"
                                         error:&error];
if (record) {
    NSString *text = record[@"value"][@"text"];
    NSString *cid = record[@"cid"];
}
```

### List Records

```objc
- (nullable NSArray *)listRecords:(NSString *)collection
                          forDid:(NSString *)did
                           limit:(NSUInteger)limit
                          cursor:(nullable NSString *)cursor
                          error:(NSError **)error;
```

Lists records in a collection with pagination.

**Parameters:**
- `collection`: Collection NSID
- `did`: Repository owner DID
- `limit`: Maximum records to return
- `cursor`: Pagination cursor from previous response
- `error`: Error pointer for failure details

**Returns:** Array of records or nil on failure

**Implementation pattern (from PDSRecordService.m lines 150-200):**

The service retrieves records from the database and formats them for the response:

```objc
- (nullable NSArray *)listRecords:(NSString *)collection
                          forDid:(NSString *)did
                           limit:(NSUInteger)limit
                          cursor:(nullable NSString *)cursor
                          error:(NSError **)error {

    PDSActorStore *store = [_databasePool storeForDid:did error:error];
    if (!store) return nil;

    NSArray<PDSDatabaseRecord *> *records = [store listRecordsForDid:did
                                                          collection:collection
                                                               limit:limit
                                                              offset:0
                                                               error:error];

    NSMutableArray *result = [NSMutableArray array];
    for (PDSDatabaseRecord *record in records) {
        NSDictionary *parsedValue = @{};
        if (record.value) {
            if ([record.value respondsToSelector:@selector(dataUsingEncoding:)]) {
                NSData *data = [record.value dataUsingEncoding:NSUTF8StringEncoding];
                if (data) {
                    parsedValue = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] ?: @{};
                }
            } else if ([record.value isKindOfClass:[NSDictionary class]]) {
                parsedValue = (NSDictionary *)record.value;
            }
        }
        
        [result addObject:@{
            @"uri": record.uri,
            @"cid": record.cid,
            @"collection": record.collection,
            @"rkey": record.rkey,
            @"value": parsedValue
        }];
    }

    return result;
}
```

**Example usage:**
```objc
NSError *error = nil;
NSArray *records = [recordService listRecords:@"app.bsky.feed.post"
                                      forDid:@"did:plc:user123"
                                       limit:50
                                      cursor:nil
                                       error:&error];

// For next page
if (records.count > 0) {
    NSString *nextCursor = records.lastObject[@"cursor"];
    NSArray *nextPage = [recordService listRecords:@"app.bsky.feed.post"
                                           forDid:@"did:plc:user123"
                                            limit:50
                                           cursor:nextCursor
                                            error:&error];
}
```

### Batch Writes

```objc
- (nullable NSDictionary *)applyWrites:(NSArray<NSDictionary *> *)writes
                                 forDid:(NSString *)did
                               actorDid:(NSString *)actorDid
                         validationMode:(PDSValidationMode)mode
                             swapCommit:(nullable NSString *)swapCommit
                                  error:(NSError **)error;
```

Atomically applies multiple write operations in a single transaction.

**Parameters:**
- `writes`: Array of write operations (each with action, collection, rkey, value)
- `did`: Repository owner DID
- `actorDid`: Authenticated actor's DID
- `mode`: Validation mode
- `swapCommit`: Expected current repo root CID (fails if doesn't match)
- `error`: Error pointer for failure details

**Returns:** Result dictionary with commit info or nil on failure

**Example:**
```objc
NSArray *writes = @[
    @{
        @"action": @"create",
        @"collection": @"app.bsky.feed.post",
        @"rkey": @"post1",
        @"value": @{@"text": @"First post"}
    },
    @{
        @"action": @"create",
        @"collection": @"app.bsky.feed.post",
        @"rkey": @"post2",
        @"value": @{@"text": @"Second post"}
    }
];

NSError *error = nil;
NSDictionary *result = [recordService applyWrites:writes
                                            forDid:@"did:plc:user123"
                                          actorDid:@"did:plc:user123"
                                    validationMode:PDSValidationModeOptimistic
                                        swapCommit:nil
                                             error:&error];
```

### Repository Statistics

```objc
- (nullable NSDictionary *)getRepoStatsForDid:(NSString *)did error:(NSError **)error;
```

Gets repository statistics including record and blob counts.

**Parameters:**
- `did`: Repository owner DID
- `error`: Error pointer for failure details

**Returns:** Dictionary with stats or nil on failure

## Validation Modes

The service supports three validation modes:

| Mode | Behavior | Use Case |
|------|----------|----------|
| `PDSValidationModeRequired` | Fail if lexicon unknown or validation fails | Strict validation |
| `PDSValidationModeOptimistic` | Validate if known, allow if unknown | Default mode |
| `PDSValidationModeOff` | Skip validation entirely | Performance-critical |

## Transaction Semantics

Batch writes are atomic:
- All writes succeed or all fail
- If any write fails, preceding writes are rolled back
- Database transaction ensures consistency
- Commit CID is updated only on complete success

## Notifications

The service posts notifications when records change:

```objc
extern NSNotificationName const PDSRecordDidChangeNotification;
```

Notification userInfo contains:
- `did`: Repository DID
- `collection`: Collection NSID
- `rkey`: Record key
- `action`: "create" or "delete"

## Error Handling

Common error scenarios:

| Error | Cause | Handling |
|-------|-------|----------|
| Unauthorized | actorDid != did | Reject with 403 |
| Not found | Record doesn't exist | Return 404 |
| Validation failed | Record doesn't match lexicon | Return 400 with details |
| Conflict | swapCommit doesn't match | Return 409 |
| Invalid collection | Collection NSID unknown | Return 400 |

## Best Practices

1. **Validation**
   - Use `PDSValidationModeOptimistic` by default
   - Use `PDSValidationModeRequired` for critical collections
   - Use `PDSValidationModeOff` only for performance-critical paths

2. **Batch Operations**
   - Group related writes together
   - Use swapCommit for optimistic concurrency control
   - Keep batch sizes reasonable (< 1000 writes)

3. **Pagination**
   - Always provide a limit
   - Store cursor for next page
   - Handle cursor expiration gracefully

4. **Authorization**
   - Always verify actorDid matches did for self-modification
   - Check permissions for delegated operations
   - Log authorization failures

## Common Patterns

### Creating a Post

```objc
NSDictionary *post = @{
    @"text": @"Hello world!",
    @"createdAt": @"2025-01-15T10:30:00Z",
    @"facets": @[]
};

NSError *error = nil;
BOOL success = [recordService putRecord:@"app.bsky.feed.post"
                                  rkey:@"abc123"
                                 value:post
                                forDid:userDid
                              actorDid:userDid
                        validationMode:PDSValidationModeOptimistic
                                 error:&error];
```

### Listing Posts with Pagination

```objc
NSMutableArray *allPosts = [NSMutableArray array];
NSString *cursor = nil;

while (YES) {
    NSError *error = nil;
    NSArray *posts = [recordService listRecords:@"app.bsky.feed.post"
                                        forDid:userDid
                                         limit:50
                                        cursor:cursor
                                         error:&error];
    
    if (!posts) break;
    
    [allPosts addObjectsFromArray:posts];
    
    if (posts.count < 50) break; // Last page
    cursor = posts.lastObject[@"cursor"];
}
```

### Batch Update with Swap Commit

```objc
// Get current commit
NSDictionary *commitInfo = [repositoryService getLatestCommitForDid:userDid
                                                               error:&error];
NSString *currentCid = commitInfo[@"cid"];

// Prepare writes
NSArray *writes = @[/* ... */];

// Apply with optimistic concurrency control
NSDictionary *result = [recordService applyWrites:writes
                                            forDid:userDid
                                          actorDid:userDid
                                    validationMode:PDSValidationModeOptimistic
                                        swapCommit:currentCid
                                             error:&error];

if (!result && error.code == 409) {
    // Conflict: repo was modified, retry
}
```

## See Also

- [Repository Service](./repository-service.md)
- [Services Overview](./services-overview.md)
- [Repository Basics](../07-repository-protocol/repository-basics.md)
