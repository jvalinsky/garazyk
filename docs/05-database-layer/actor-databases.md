# Actor Databases

## Overview

Actor databases are per-user SQLite databases that store all data specific to a single user's repository. Each user has their own isolated database containing records, blocks, and repository state. This isolation provides data privacy, scalability, and independent backup/recovery.

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│   Database Directory Structure                           │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  ${dbDirectory}/                                         │
│  ├── service.sqlite          (shared)                    │
│  ├── did_cache.sqlite        (shared)                    │
│  ├── sequencer.sqlite        (shared)                    │
│  │                                                       │
│  └── ${didPrefix2}/          (DID prefix for sharding)   │
│      ├── did:plc:user1/                                  │
│      │   ├── data.sqlite     (user's repository data)    │
│      │   └── signing_key.pem (user's signing key)        │
│      │                                                   │
│      ├── did:plc:user2/                                  │
│      │   ├── data.sqlite                                 │
│      │   └── signing_key.pem                             │
│      │                                                   │
│      └── did:plc:userN/                                  │
│          ├── data.sqlite                                 │
│          └── signing_key.pem                             │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

## Per-User Database Schema

Each user's `data.sqlite` contains:

```sql
CREATE TABLE repo_root (
    cid BLOB PRIMARY KEY,
    updated_at DATETIME NOT NULL
);

CREATE TABLE records (
    uri TEXT PRIMARY KEY,
    collection TEXT NOT NULL,
    rkey TEXT NOT NULL,
    cid BLOB NOT NULL,
    value BLOB,           -- CBOR-encoded record content
    indexed_at DATETIME NOT NULL
);

CREATE INDEX idx_records_collection_rkey ON records(collection, rkey);
CREATE INDEX idx_records_uri ON records(uri);

CREATE TABLE ipld_blocks (
    cid BLOB PRIMARY KEY,
    block BLOB NOT NULL,  -- CAR format block data
    size INTEGER NOT NULL
);

CREATE INDEX idx_ipld_blocks_cid ON ipld_blocks(cid);
```

## Database Pool

The `PDSDatabasePool` manages multiple actor databases with LRU caching and automatic eviction.

**Source:** `ATProtoPDS/Sources/Database/Pool/DatabasePool.m`

### Pool Initialization

```objc
// Lines 18-40: Initialize pool with directory and max size
- (instancetype)initWithDbDirectory:(NSString *)dbDirectory maxSize:(NSUInteger)maxSize {
    self = [super init];
    if (self) {
        _dbDirectory = [dbDirectory copy];
        _maxSize = maxSize;
        _stores = [NSMutableDictionary dictionary];
        _lastAccessTime = [NSMutableDictionary dictionary];
        _poolQueue = dispatch_queue_create("com.atproto.pds.databasepool", DISPATCH_QUEUE_SERIAL);
        _evictionQueue = dispatch_queue_create("com.atproto.pds.databasepool.eviction", DISPATCH_QUEUE_SERIAL);
        _openFileHandleCount = 0;
        
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:dbDirectory]) {
            NSError *error = nil;
            [fm createDirectoryAtPath:dbDirectory withIntermediateDirectories:YES attributes:nil error:&error];
            if (error) {
                PDS_LOG_DB_ERROR(@"Failed to create database directory: %@ (error: %@)", dbDirectory, error);
            }
        }
        
        _evictionTimer = [NSTimer scheduledTimerWithTimeInterval:60.0
                                                          target:self
                                                        selector:@selector(evictionTimerFired:)
                                                        userInfo:nil
                                                         repeats:YES];
    }
    return self;
}
```

### DID-Based Database Path Sharding

```objc
// Lines 50-80: Shard databases by DID method and prefix
- (NSString *)dbPathForDid:(NSString *)did {
    if ([did isEqualToString:@"__service__"]) {
        return [self.dbDirectory stringByAppendingPathComponent:@"service.db"];
    }

    // Shard by DID method and 2-char prefix of the method-specific identifier:
    // did:plc:z72i7h... → {dbDir}/plc/z7/did:plc:z72i7h...
    NSString *method = nil;
    NSString *identifier = nil;
    NSRange firstColon = [did rangeOfString:@":"];
    if (firstColon.location != NSNotFound) {
        NSRange rest = NSMakeRange(firstColon.location + 1, did.length - firstColon.location - 1);
        NSRange secondColon = [did rangeOfString:@":" options:0 range:rest];
        if (secondColon.location != NSNotFound) {
            method = [did substringWithRange:NSMakeRange(firstColon.location + 1,
                                                         secondColon.location - firstColon.location - 1)];
            identifier = [did substringFromIndex:secondColon.location + 1];
        }
    }

    NSString *prefixDir;
    if (method.length > 0 && identifier.length > 0) {
        NSString *prefix = [identifier substringToIndex:MIN(2, identifier.length)];
        NSString *methodDir = [self.dbDirectory stringByAppendingPathComponent:method];
        prefixDir = [methodDir stringByAppendingPathComponent:prefix];
    } else {
        NSString *prefix = [did substringToIndex:MIN(2, did.length)];
        prefixDir = [self.dbDirectory stringByAppendingPathComponent:prefix];
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:prefixDir]) {
        [fm createDirectoryAtPath:prefixDir withIntermediateDirectories:YES attributes:nil error:nil];
    }

    return [prefixDir stringByAppendingPathComponent:did];
}
```

### Store Retrieval with LRU Caching

```objc
// Lines 82-115: Get or create store with LRU eviction
- (nullable PDSActorStore *)storeForDid:(NSString *)did error:(NSError **)error {
    __block PDSActorStore *store = nil;
    __block NSError *blockError = nil;
    __block NSString *dbPath = nil;

    dispatch_sync(self.poolQueue, ^{
        store = self.stores[did];

        if (store) {
            self.lastAccessTime[did] = [NSDate date];
            return;
        }

        if (self.stores.count >= self.maxSize) {
            [self evictLRUStore];
        }

        dbPath = [self dbPathForDid:did];
        PDS_LOG_DB_DEBUG(@"Opening store at path: %@ (exists: %d)", dbPath,
                         [[NSFileManager defaultManager] fileExistsAtPath:dbPath]);

        store = [PDSActorStore storeWithDid:did dbPath:dbPath error:&blockError];

        if (store) {
            self.stores[did] = store;
            self.lastAccessTime[did] = [NSDate date];
            self.openFileHandleCount++;
        } else {
            PDS_LOG_DB_ERROR(@"Failed to open store for %@: %@", did, blockError);
        }
    });

    if (error && blockError) {
        *error = blockError;
    }

    return store;
}
```

### LRU Eviction

```objc
// Lines 130-145: Evict least recently used store
- (void)evictLRUStore {
    if (self.lastAccessTime.count == 0) {
        return;
    }
    
    NSString *lruDid = nil;
    NSDate *lruTime = [NSDate distantFuture];
    
    for (NSString *did in self.lastAccessTime) {
        NSDate *accessTime = self.lastAccessTime[did];
        if ([accessTime compare:lruTime] == NSOrderedAscending) {
            lruTime = accessTime;
            lruDid = did;
        }
    }
    
    if (lruDid) {
        [self evictStoreForDidInternal:lruDid];
    }
}
```

### Transaction Support

```objc
// Lines 165-180: Execute transaction on actor store
- (void)transactWithDid:(NSString *)did 
                  block:(void (^)(id<PDSActorStoreTransactor> transactor, NSError **error))block 
                  error:(NSError **)error {
    PDSActorStore *store = [self storeForDid:did error:error];
    if (!store) {
        return;
    }
    
    [store transactWithBlock:block error:error];
}

- (void)readWithDid:(NSString *)did 
              block:(void (^)(id<PDSActorStoreReader> reader, NSError **error))block 
              error:(NSError **)error {
    PDSActorStore *store = [self storeForDid:did error:error];
    if (!store) {
        return;
    }
    
    [store readWithBlock:block error:error];
}
```

### Pool Metrics

```objc
// Lines 210-235: Collect pool metrics for monitoring
- (NSDictionary<NSString *, id> *)collectMetrics {
    __block NSDictionary *metrics = nil;
    
    dispatch_sync(self.poolQueue, ^{
        NSMutableDictionary *m = [NSMutableDictionary dictionary];
        m[@"max_size"] = @(self.maxSize);
        m[@"current_size"] = @(self.stores.count);
        m[@"open_file_handles"] = @(self.openFileHandleCount);
        
        NSMutableDictionary *stores = [NSMutableDictionary dictionary];
        for (NSString *did in self.stores) {
            PDSActorStore *store = self.stores[did];
            NSDate *lastAccess = self.lastAccessTime[did];
            stores[did] = @{
                @"is_open": @(store.isOpen),
                @"db_path": store.dbPath ?: @"",
                @"last_access": lastAccess ?: [NSDate distantPast]
            };
        }
        m[@"stores"] = stores;
        
        metrics = [m copy];
    });
    
    return metrics;
}
```

## PDSActorDatabase Class

Each actor database is represented by `PDSActorDatabase`:

```objc
@interface PDSActorDatabase : NSObject

// Properties
@property (nonatomic, strong, readonly) NSString *did;
@property (nonatomic, strong, readonly) NSString *databasePath;
@property (nonatomic, strong, readonly) NSString *signingKeyPath;

// Initialization
- (instancetype)initWithDid:(NSString *)did databasePath:(NSString *)path;

// Reader interface
- (nullable NSDictionary *)getRepoRootWithError:(NSError **)error;
- (nullable NSDictionary *)getRecord:(NSString *)uri error:(NSError **)error;
- (nullable NSArray *)listRecords:(NSString *)collection
                            limit:(NSUInteger)limit
                           offset:(NSUInteger)offset
                            error:(NSError **)error;
- (nullable NSData *)getBlockForCID:(NSData *)cid error:(NSError **)error;

// Writer interface (transactions)
- (BOOL)transactWithBlock:(void (^)(id<PDSActorStoreTransactor> transactor))block
                    error:(NSError **)error;

// Signing key management
- (nullable SecKeyRef)signingKeyWithError:(NSError **)error;
- (BOOL)generateSigningKeyWithError:(NSError **)error;

@end
```

## Transaction Pattern

Actor databases support transactions for atomic operations:

```objc
NSError *error = nil;
BOOL success = [actorDatabase transactWithBlock:^(id<PDSActorStoreTransactor> transactor) {
    // 1. Update records
    [transactor putRecord:record forDid:did error:&error];
    
    // 2. Update blocks
    [transactor putBlock:block forDid:did error:&error];
    
    // 3. Update repo root
    [transactor updateRepoRoot:newRootCid forDid:did error:&error];
    
} error:&error];

if (success) {
    // All operations committed atomically
}
```

## Record Storage

### Storing Records

```objc
NSDictionary *record = @{
    @"uri": @"at://did:plc:user123/app.bsky.feed.post/abc123",
    @"collection": @"app.bsky.feed.post",
    @"rkey": @"abc123",
    @"cid": cidData,
    @"value": cborEncodedValue,
    @"indexed_at": [NSDate date]
};

NSError *error = nil;
BOOL success = [actorDatabase transactWithBlock:^(id<PDSActorStoreTransactor> transactor) {
    [transactor putRecord:record forDid:did error:&error];
} error:&error];
```

### Retrieving Records

```objc
// Get single record
NSError *error = nil;
NSDictionary *record = [actorDatabase getRecord:@"at://did:plc:user123/app.bsky.feed.post/abc123"
                                          error:&error];

// List records in collection
NSArray *records = [actorDatabase listRecords:@"app.bsky.feed.post"
                                       limit:50
                                      offset:0
                                       error:&error];
```

## Block Storage

### Storing Blocks

Blocks are IPLD blocks (DAG-CBOR or DAG-JSON encoded):

```objc
NSDictionary *block = @{
    @"cid": cidData,
    @"block": blockData,
    @"size": @(blockData.length)
};

NSError *error = nil;
BOOL success = [actorDatabase transactWithBlock:^(id<PDSActorStoreTransactor> transactor) {
    [transactor putBlock:block forDid:did error:&error];
} error:&error];
```

### Retrieving Blocks

```objc
NSError *error = nil;
NSData *blockData = [actorDatabase getBlockForCID:cidData error:&error];

if (blockData) {
    // Parse and use block
}
```

## Repository Root Management

### Updating Repository Root

```objc
NSError *error = nil;
BOOL success = [actorDatabase transactWithBlock:^(id<PDSActorStoreTransactor> transactor) {
    [transactor updateRepoRoot:newRootCid forDid:did error:&error];
} error:&error];
```

### Getting Repository Root

```objc
NSError *error = nil;
NSDictionary *root = [actorDatabase getRepoRootWithError:&error];

if (root) {
    NSData *rootCid = root[@"cid"];
    NSDate *updatedAt = root[@"updated_at"];
}
```

## Signing Key Management

### Generating Signing Keys

```objc
NSError *error = nil;
BOOL success = [actorDatabase generateSigningKeyWithError:&error];

if (success) {
    // Key is now stored at signingKeyPath
}
```

### Retrieving Signing Keys

```objc
NSError *error = nil;
SecKeyRef signingKey = [actorDatabase signingKeyWithError:&error];

if (signingKey) {
    // Use key for signing operations
}
```

## Database Pool Management

### Getting a Database

```objc
NSError *error = nil;
PDSActorDatabase *db = [databasePool databaseForDid:@"did:plc:user123" error:&error];

if (db) {
    // Use database
}
```

### Batch Operations

```objc
NSError *error = nil;
BOOL success = [databasePool executeForDid:@"did:plc:user123"
                                    block:^(PDSActorDatabase *db, NSError **error) {
    // Perform operations on db
    NSDictionary *record = [db getRecord:uri error:error];
    return record != nil;
} error:&error];
```

### Pool Eviction

```objc
// Evict single database
[databasePool evictDatabase:@"did:plc:user123"];

// Evict all databases
[databasePool evictAllDatabases];

// Check pool size
NSUInteger size = [databasePool currentPoolSize];
```

## Directory Structure

### DID Prefix Sharding

DIDs are sharded by their first 2 characters to distribute databases:

```
did:plc:user1 → ${dbDirectory}/di/did:plc:user1/data.sqlite
did:plc:user2 → ${dbDirectory}/di/did:plc:user2/data.sqlite
did:web:example.com → ${dbDirectory}/di/did:web:example.com/data.sqlite
```

Benefits:
- Distributes databases across directories
- Prevents single directory with too many files
- Improves filesystem performance

### Signing Key Storage

Signing keys are stored as PEM files alongside databases:

```
${dbDirectory}/di/did:plc:user1/
├── data.sqlite
└── signing_key.pem
```

## Performance Characteristics

| Operation | Complexity | Notes |
|-----------|-----------|-------|
| Get record by URI | O(1) | Primary key index |
| List records by collection | O(log n) | B-tree index |
| Get block by CID | O(1) | Primary key index |
| Transaction commit | O(n) | n = number of changes |
| Database open | O(1) | Cached in pool |

## WAL Mode Configuration

Each actor database uses WAL mode:

```sql
PRAGMA journal_mode=WAL;
PRAGMA synchronous=NORMAL;
PRAGMA wal_autocheckpoint=1000;
PRAGMA cache_size=-64000;  /* 64MB cache */
```

## Best Practices

1. **Database Access**
   - Always use the pool, not direct database access
   - Handle database not found errors gracefully
   - Implement retry logic for transient failures

2. **Transactions**
   - Keep transactions short
   - Batch related operations
   - Handle transaction failures

3. **Signing Keys**
   - Generate keys during account creation
   - Store securely (file permissions)
   - Cache in memory for performance

4. **Pool Management**
   - Monitor pool size
   - Implement eviction policies
   - Clean up unused databases

5. **Performance**
   - Use indexes for common queries
   - Batch operations in transactions
   - Monitor database file sizes

## Common Patterns

### Creating a New User Database

```objc
// 1. Create database directory
NSString *didPrefix = [did substringToIndex:2];
NSString *userDir = [NSString stringWithFormat:@"%@/%@/%@", 
                     dbDirectory, didPrefix, did];
[[NSFileManager defaultManager] createDirectoryAtPath:userDir
                          withIntermediateDirectories:YES
                                           attributes:nil
                                                error:&error];

// 2. Initialize database
PDSActorDatabase *db = [[PDSActorDatabase alloc] initWithDid:did
                                                databasePath:[userDir stringByAppendingPathComponent:@"data.sqlite"]];

// 3. Generate signing key
[db generateSigningKeyWithError:&error];

// 4. Initialize repository
NSError *error = nil;
BOOL success = [db transactWithBlock:^(id<PDSActorStoreTransactor> transactor) {
    [transactor updateRepoRoot:initialRootCid forDid:did error:&error];
} error:&error];
```

### Storing a Record

```objc
NSError *error = nil;
BOOL success = [databasePool executeForDid:userDid
                                    block:^(PDSActorDatabase *db, NSError **error) {
    return [db transactWithBlock:^(id<PDSActorStoreTransactor> transactor) {
        NSDictionary *record = @{
            @"uri": uri,
            @"collection": collection,
            @"rkey": rkey,
            @"cid": recordCid,
            @"value": cborValue,
            @"indexed_at": [NSDate date]
        };
        [transactor putRecord:record forDid:userDid error:error];
    } error:error];
} error:&error];
```

### Listing Records

```objc
NSError *error = nil;
NSArray *records = [databasePool executeForDid:userDid
                                        block:^(PDSActorDatabase *db, NSError **error) {
    return [db listRecords:collection
                    limit:50
                   offset:0
                    error:error];
} error:&error];
```

## See Also

- [Service Databases](./service-databases.md)
- [Migrations](./migrations.md)
- [WAL Mode](./wal-mode.md)
- [SQLite Architecture](./sqlite-architecture.md)
