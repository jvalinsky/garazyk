# Database Layer Patterns

## Table of Contents

- [Service Database](#service-database)
- [Migration Protocol](#migration-protocol)
- [Adding a Migration](#adding-a-migration)
- [Actor Store](#actor-store)
- [Connection Pool](#connection-pool)

## Service Database

The service database (`PDSDatabase`) is the shared database for account metadata, session state, and configuration. It uses WAL mode and is managed by `PDSServiceDatabases`.

```objc
PDSServiceDatabases *serviceDBs = [[PDSServiceDatabases alloc] initWithDataDirectory:dataDir];
PDSDatabase *serviceDB = serviceDBs.serviceDatabase;
```

For a new service that needs its own database:
1. Create a new `PDSDatabase` subclass or use `PDSDatabase` directly
2. Add migrations for schema creation
3. Register the database in the runtime class

## Migration Protocol

All migrations conform to `PDSMigration`:

```objc
@protocol PDSMigration <NSObject>

@property (nonatomic, readonly) NSInteger version;
@property (nonatomic, readonly) NSString *description;

- (BOOL)applyToDatabase:(PDSDatabase *)database error:(NSError **)error;

@end
```

Migrations are executed in version order by `PDSMigrationManager`. The `schema_version` table tracks applied migrations.

### Migration Template

**Header:**
```objc
// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PDSMigrationNNN : NSObject
@end

NS_ASSUME_NONNULL_END
```

**Implementation:**
```objc
// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSMigration.h"
#import "Database/PDSDatabase.h"
#import "Debug/GZLogger.h"

@interface PDSMigrationNNN : NSObject <PDSMigration>
@end

@implementation PDSMigrationNNN

- (NSInteger)version {
    return NNN;
}

- (NSString *)description {
    return @"Description of this migration";
}

- (BOOL)applyToDatabase:(PDSDatabase *)database error:(NSError **)error {
    NSString *sql = @"CREATE TABLE IF NOT EXISTS new_table ("
                     "id INTEGER PRIMARY KEY AUTOINCREMENT, "
                     "did TEXT NOT NULL, "
                     "data TEXT NOT NULL, "
                     "created_at INTEGER DEFAULT (strftime('%s', 'now'))"
                     ")";

    BOOL success = [database executeParameterizedUpdate:sql params:@[] error:error];

    if (success) {
        GZ_LOG_DB_INFO(@"Created new_table for migration NNN");
    } else {
        GZ_LOG_DB_ERROR(@"Failed migration NNN: %@", *error);
    }

    return success;
}

@end
```

## Adding a Migration

1. Create `PDSMigrationNNN.{h,m}` in `Sources/Database/Migrations/`
2. Use the next sequential version number (check existing migrations)
3. Add to `PDSMigrationManager.m`'s migration list
4. Add source file to `ATProtoStorage` sources in CMake (it matches `Database/*.m`)

### Migration Numbering

- Migrations are numbered sequentially: 001, 002, 003, ...
- The version number in the `-version` method must match the file number
- Never modify an existing migration — only add new ones

### SQL Patterns

```objc
// Create table
NSString *sql = @"CREATE TABLE IF NOT EXISTS table_name ("
                 "id INTEGER PRIMARY KEY AUTOINCREMENT, "
                 "column_name TEXT NOT NULL, "
                 "created_at INTEGER DEFAULT (strftime('%s', 'now'))"
                 ")";

// Add column
NSString *sql = @"ALTER TABLE existing_table ADD COLUMN new_column TEXT DEFAULT ''";

// Create index
NSString *sql = @"CREATE INDEX IF NOT EXISTS idx_table_column "
                 "ON table_name(column_name)";

// Execute parameterized query
[database executeParameterizedUpdate:sql params:@[value1, value2] error:&error];

// Query with results
PDSDatabaseResultSet *rs = [database executeParameterizedQuery:sql params:@[value] error:&error];
while ([rs next]) {
    NSString *col = [rs stringForColumn:@"column_name"];
}
```

## Actor Store

Actor stores are per-user SQLite databases managed by `PDSDatabasePool` and accessed via `PDSActorStore`.

```objc
// Get or create an actor store
PDSActorStore *actorStore = [databasePool actorStoreForDID:did error:&error];

// Use the actor store's database
PDSDatabase *db = actorStore.database;
```

The actor store handles:
- Per-user schema bootstrapping via `PDSMigrationManager`
- Connection lifecycle (open/close)
- Eviction from the pool when not recently used

### When to Use Actor Store vs Service DB

| Data | Store |
|------|-------|
| Account metadata, sessions, invites | Service DB |
| Per-user records, MST, blobs | Actor Store |
| Cross-user indexes, search | Service DB or AppView DB |

## Connection Pool

`PDSDatabasePool` manages per-DID actor store connections:

```objc
PDSDatabasePool *pool = [[PDSDatabasePool alloc]
    initWithBaseDirectory:dataDir
             serviceDatabases:serviceDBs
                      plcUrl:plcUrl];

// Get actor store (creates if needed)
PDSActorStore *store = [pool actorStoreForDID:did error:&error];

// Evict idle connections
[pool evictIdleStores];
```

Pool configuration:
- `service_pool_max_size` — max connections in the service DB pool
- `user_pool_max_size` — max per-user databases kept open
- WAL mode on all databases
