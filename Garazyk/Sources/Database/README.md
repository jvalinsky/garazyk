# ATProto PDS Single-Tenant SQLite Architecture

## Overview

This document describes the single-tenant SQLite database architecture for the ATProto Personal Data Server (PDS), based on the Bluesky PDS reference implementation.

## Architecture

### Before (Monolithic - Legacy)
```
┌─────────────────────────────────────┐
│         Single SQLite File          │
│  accounts | repos | records | blocks│
└─────────────────────────────────────┘
```

### After (Single-Tenant - New)
```
┌─────────────────────────────────────────────────────────────────┐
│                      Service Databases                           │
│  ┌─────────────────┬─────────────────────┬───────────────────┐  │
│  │ service.sqlite  │  did_cache.sqlite   │  sequencer.sqlite │  │
│  │ - accounts      │  - DID caching      │  - repo sequencing│  │
│  │ - invite_codes  │                     │                   │  │
│  └─────────────────┴─────────────────────┴───────────────────┘  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                    User Databases (Per DID)                      │
│                                                                 │
│  ${dataDirectory}/                                              │
│  ├── ${didPrefix}/                                              │
│  │   └── ${did}/                                                │
│  │       ├── data.sqlite           (user data, records, blocks)│
│  │       └── ${did}_signing_key.pem (signing key)               │
│  ├── service.sqlite                                               │
│  ├── did_cache.sqlite                                             │
│  └── sequencer.sqlite                                             │
└─────────────────────────────────────────────────────────────────┘
```

## Directory Structure

```
Garazyk/Sources/Database/
├── ActorStore/           # Single-tenant store (Reader/Transactor pattern)
│   ├── ActorStore.h
│   └── ActorStore.m
├── Pool/                 # Database pool with LRU caching
│   ├── DatabasePool.h
│   └── DatabasePool.m
├── Service/              # Service-level databases
│   ├── ServiceDatabases.h
│   └── ServiceDatabases.m
├── Migration/            # Migration from monolithic
│   ├── PDSMigrationManager.h
│   └── PDSMigrationManager.m
├── Monitoring/           # Health checks and monitoring
│   ├── PDSHealthCheck.h
│   └── PDSHealthCheck.m
├── PDSDatabase.h/m       # Legacy (deprecated)
├── Schema.h/m            # Legacy schema definitions
└── ARCHITECTURE.md       # This document
```

## Key Components

### 1. ActorStore

The `ActorStore` class manages a single user's SQLite database:

**Reader Interface** (`PDSActorStoreReader`):
- `getAccountForDid:error:` - Get account by DID
- `getRepoForDid:error:` - Get repository info
- `getRecord:forDid:error:` - Get record by URI
- `listRecordsForDid:collection:limit:offset:error:` - List records
- `getBlockForCID:forDid:error:` - Get block by CID

**Transactor Interface** (`PDSActorStoreTransactor`):
- `createAccount:error:` / `updateAccount:error:` / `deleteAccount:error:`
- `createRepo:error:` / `updateRepoRoot:error:` / `deleteRepo:error:`
- `putRecord:forDid:error:` / `deleteRecord:error:` / `putRecords:forDid:error:`
- `putBlock:forDid:error:` / `deleteBlock:error:` / `putBlocks:forDid:error:`

**Transaction Usage**:
```objc
[store transactWithBlock:^(id<PDSActorStoreTransactor> transactor) {
    [transactor createAccount:account error:nil];
    [transactor updateRepoRoot:did rootCid:rootCid error:nil];
} error:&error];
```

### 2. DatabasePool

Manages multiple ActorStore instances with LRU caching:

- **Max size**: 30,000 open connections (matches Bluesky reference)
- **File handle limit**: 30,000
- **Auto-eviction**: 5-minute timeout for unused stores
- **Hierarchical storage**: `${dbDirectory}/${didPrefix}/${did}`

**Usage**:
```objc
PDSDatabasePool *pool = [[PDSDatabasePool alloc] initWithDbDirectory:dir maxSize:30000];

PDSActorStore *store = [pool storeForDid:did error:&error];
[pool transactWithDid:did block:^(id<PDSActorStoreTransactor> t) {
    // operations
} error:&error];
```

### 3. Service Databases

Three separate SQLite databases for service state:

| Database | Purpose | Contents |
|----------|---------|----------|
| `service.sqlite` | Account management | accounts, invite_codes, refresh_tokens |
| `did_cache.sqlite` | DID resolution cache | did_cache (document, expires_at) |
| `sequencer.sqlite` | Repo sequencing | repo_sequence (did, root_cid, sequence_num) |

**Usage**:
```objc
PDSServiceDatabases *serviceDb = [[PDSServiceDatabases alloc] initWithDirectory:@"/var/lib/pds" serviceMaxSize:10 didCacheMaxSize:5 sequencerMaxSize:5];
[serviceDb createAccount:account error:&error];
[serviceDb getAccountByDid:did error:&error];
[serviceDb cacheDID:did document:doc expiresAt:expires];
```

### 4. Signing Key Management

Each user's signing key is stored as a PEM file:

```objc
// Generate a new signing key
[store generateSigningKeyWithError:&error];

// Get the signing key for repo operations
SecKeyRef key = [store signingKeyWithError:&error];
```

### 5. WAL Mode Configuration

All databases use Write-Ahead Logging:

```sql
PRAGMA journal_mode=WAL;
PRAGMA synchronous=NORMAL;
PRAGMA wal_autocheckpoint=1000;
PRAGMA cache_size=-64000;  -- 64MB cache
```

## User Database Schema

```sql
-- Per-user database (${didPrefix}/${did}/data.sqlite)

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

CREATE TABLE ipld_blocks (
    cid BLOB PRIMARY KEY,
    block BLOB NOT NULL,  -- CAR format block data
    size INTEGER NOT NULL
);

-- Indexes
CREATE INDEX idx_records_collection_rkey ON records(collection, rkey);
CREATE INDEX idx_records_uri ON records(uri);
CREATE INDEX idx_ipld_blocks_cid ON ipld_blocks(cid);
```

## Migration from Monolithic

The `PDSMigrationManager` handles migration:

```objc
PDSMigrationManager *manager = [PDSMigrationManager sharedManager];
manager.progressBlock = ^(double progress, NSString *status) {
    NSLog(@"Migration: %.0f%% - %@", progress * 100, status);
};

NSError *error = nil;
[manager migrateFromMonolithicDatabase:@"/path/to/old.db"
                    toSingleTenantDirectory:@"/path/to/new/"
                                  error:&error];
```

## Health Monitoring

The `PDSHealthCheck` class provides health information:

```objc
NSDictionary *health = [[PDSHealthCheck sharedInstance] performHealthCheck];
NSLog(@"Status: %@", health[@"status"]);
NSLog(@"Warnings: %@", health[@"warnings"]);
NSLog(@"Errors: %@", health[@"errors"]);
```

## Performance Characteristics

| Operation | Complexity | Notes |
|-----------|------------|-------|
| Account lookup by DID | O(1) | Primary key index |
| Record lookup by URI | O(1) | Primary key index |
| Collection query | O(log n) | B-tree index on collection+rkey |
| Block lookup by CID | O(1) | Primary key index |
| Concurrent reads | Unlimited | WAL mode enables parallel reads |
| Writes | Serialized | Per-user transaction queue |

## Model Classes

The same model classes are used in both architectures:

- `PDSDatabaseAccount` - Account data (DID, handle, email, JWT tokens)
- `PDSDatabaseRepo` - Repository info (owner DID, root CID)
- `PDSDatabaseRecord` - Record metadata (URI, collection, rkey, CID)
- `PDSDatabaseBlock` - Block data (CID, content, size)
- `PDSDatabaseBlob` - Blob metadata (CID, MIME type, size)

## Initialization

```objc
// Initialize the controller with new architecture
PDSController *controller = [[PDSController alloc] initWithDirectory:@"/path/to/data"
                                                      serviceMaxSize:100
                                                    userDatabaseSize:30000];

[controller startServerWithError:&error];
```

## Next Steps

1. **HTTP handler integration** - Update HTTP handlers to use `PDSDatabasePool`
2. **Sequencer implementation** - Implement repo update sequencing
3. **Rate limiting** - Add rate limiting to service database layer
4. **Backup/recovery** - Implement using SQLite backup API
5. **Testing** - Add unit and integration tests

## Dependencies

- **macOS SDK**: `sqlite3.h`, `Security.framework`
- **No external dependencies**
- **Apple-first-party only**
