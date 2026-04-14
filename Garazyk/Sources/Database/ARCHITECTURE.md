# ATProto PDS Database Architecture - Single-Tenant SQLite Implementation

## Overview

This document describes the new single-tenant SQLite database architecture based on the Bluesky PDS reference implementation. The architecture provides isolation, scalability, and performance for an ATProto Personal Data Server.

## Architecture Changes

### Before (Monolithic)
```
┌─────────────────────────────────────┐
│         Single SQLite File          │
│  ┌─────┬─────┬─────┬─────┬─────┐   │
│  │accounts│repos│recs │blocks│blobs│   │
│  └─────┴─────┴─────┴─────┴─────┘   │
└─────────────────────────────────────┘
```

### After (Single-Tenant)
```
┌─────────────────────────────────────────────────────────────────────┐
│                         Service Databases                            │
│  ┌─────────────────┬─────────────────────┬─────────────────────┐    │
│  │ service.sqlite  │  did_cache.sqlite   │  sequencer.sqlite   │    │
│  │ - accounts      │  - DID resolution    │  - repo sequencing  │
│  │ - invite_codes  │    caching           │                     │
│  │ - refresh_tokens│                     │                     │
│  └─────────────────┴─────────────────────┴─────────────────────┘    │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                       User Databases (Per DID)                       │
│                                                                         │
│  ${dbDirectory}/                                                   │
│  ├── ${didPrefix2}/                                                │
│  │   └── ${did}/                                                   │
│  │       ├── data.sqlite           (user data, records, blocks)      │
│  │       └── ${did}_signing_key.pem (signing key)                    │
│  ├── service.sqlite                                                 │
│  ├── did_cache.sqlite                                               │
│  └── sequencer.sqlite                                               │
└─────────────────────────────────────────────────────────────────────┘
```

## Directory Structure

```
Garazyk/Sources/Database/
├── ActorStore/           # Single-tenant store with Reader/Transactor pattern
│   ├── ActorStore.h
│   └── ActorStore.m
├── Pool/                 # Database pool with LRU caching
│   ├── DatabasePool.h
│   └── DatabasePool.m
├── Service/              # Service-level databases
│   ├── ServiceDatabases.h
│   └── ServiceDatabases.m
├── Migration/            # Migration from monolithic to single-tenant
│   ├── PDSMigrationManager.h
│   └── PDSMigrationManager.m
├── Monitoring/           # Health checks and monitoring
│   ├── PDSHealthCheck.h
│   └── PDSHealthCheck.m
├── PDSDatabase.h         # Legacy (to be deprecated)
└── PDSDatabase.m         # Legacy (to be deprecated)
```

## Key Components

### 1. ActorStore

The `ActorStore` class manages a single user's SQLite database with:

**Reader Interface** (`PDSActorStoreReader`):
- `getAccountForDid:error:`
- `getRepoForDid:error:`
- `getRecord:forDid:error:`
- `listRecordsForDid:collection:limit:offset:error:`
- `getBlockForCID:forDid:error:`

**Transactor Interface** (`PDSActorStoreTransactor`):
- `createAccount:error:`
- `updateAccount:error:`
- `deleteAccount:error:`
- `putRecord:forDid:error:`
- `putBlock:forDid:error:`

**Transaction Support**:
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

### 3. Service Databases

Three separate SQLite databases for service state:

| Database | Purpose | Contents |
|----------|---------|----------|
| `service.sqlite` | Account management | accounts, invite_codes, refresh_tokens |
| `did_cache.sqlite` | DID resolution cache | did_cache (document, expires_at) |
| `sequencer.sqlite` | Repo sequencing | repo_sequence (did, root_cid, sequence_num) |

### 4. Signing Key Management

Each user's signing key is stored as a PEM file alongside their database:

```objc
// Generate a new signing key
[store generateSigningKeyWithError:&error];

// Get the signing key for repo operations
SecKeyRef key = [store signingKeyWithError:&error];
```

### 5. WAL Mode Configuration

All databases use Write-Ahead Logging for concurrent reads:

```sql
PRAGMA journal_mode=WAL;
PRAGMA synchronous=NORMAL;
PRAGMA wal_autocheckpoint=1000;
PRAGMA cache_size=-64000;  /* 64MB cache */
```

## User Database Schema

```sql
-- Per-user database (stored in ${didPrefix}/${did}/data.sqlite)

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

The `PDSMigrationManager` handles migration from the old monolithic database:

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

The `PDSHealthCheck` class provides system health information:

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

## Next Steps

1. **Update HTTP handlers** to use `PDSDatabasePool` instead of `PDSDatabase`
2. **Integrate signing key operations** with repo signing
3. **Add rate limiting** to the service database layer
4. **Implement sequencer** for repo update ordering
5. **Add backup/recovery** using SQLite backup API

## Dependencies

- **macOS SDK**: `sqlite3.h`, `Security.framework`
- **No external dependencies**
- **Apple-first-party only**
