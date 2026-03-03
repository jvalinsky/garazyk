# SQLite Architecture

## Overview

The PDS uses SQLite for persistent storage with:
- **Service Database** — Shared data (users, DIDs, configuration)
- **Actor Databases** — Per-user repositories (one per user)
- **WAL Mode** — Write-Ahead Logging for concurrent access
- **Prepared Statements** — Prevent SQL injection and improve performance

## Database Design

### Service Database

The service database stores shared data:

```sql
-- Users table
CREATE TABLE users (
    id INTEGER PRIMARY KEY,
    did TEXT UNIQUE NOT NULL,
    handle TEXT UNIQUE NOT NULL,
    email TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- DID cache
CREATE TABLE did_cache (
    did TEXT PRIMARY KEY,
    document TEXT NOT NULL,  -- JSON
    expires_at DATETIME NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Sequencer (for firehose)
CREATE TABLE sequencer (
    seq INTEGER PRIMARY KEY,
    did TEXT NOT NULL,
    commit_cid TEXT NOT NULL,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Configuration
CREATE TABLE config (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

### Actor Database

Each user has a separate database containing their repository data:

```sql
-- Records
CREATE TABLE records (
    id INTEGER PRIMARY KEY,
    collection TEXT NOT NULL,
    rkey TEXT NOT NULL,
    cid TEXT NOT NULL,
    data BLOB NOT NULL,  -- CBOR encoded
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(collection, rkey)
);

-- Blobs
CREATE TABLE blobs (
    id INTEGER PRIMARY KEY,
    cid TEXT UNIQUE NOT NULL,
    data BLOB NOT NULL,
    size INTEGER NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- MST nodes
CREATE TABLE mst_nodes (
    id INTEGER PRIMARY KEY,
    key TEXT UNIQUE NOT NULL,
    value TEXT NOT NULL,  -- CID
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Commits
CREATE TABLE commits (
    id INTEGER PRIMARY KEY,
    cid TEXT UNIQUE NOT NULL,
    root_cid TEXT NOT NULL,
    prev_cid TEXT,
    signature TEXT NOT NULL,
    timestamp DATETIME NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

## WAL Mode

### What is WAL?

Write-Ahead Logging (WAL) is a technique that:
- Writes changes to a log file first
- Then applies changes to the main database
- Allows concurrent reads while writes are in progress
- Improves performance for write-heavy workloads

### Enabling WAL

```objc
// In PDSServiceDatabases.m
- (void)enableWALMode:(sqlite3 *)db error:(NSError **)error {
    const char *sql = "PRAGMA journal_mode=WAL;";
    char *errMsg = NULL;
    
    int rc = sqlite3_exec(db, sql, NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        *error = [NSError errorWithDomain:@"SQLite" code:rc 
            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:errMsg]}];
        sqlite3_free(errMsg);
        return;
    }
    
    // Set WAL checkpoint interval
    sqlite3_wal_autocheckpoint(db, 1000);
}
```

### WAL Checkpoint

```objc
// Checkpoint WAL periodically
- (void)checkpointWAL:(sqlite3 *)db {
    sqlite3_wal_checkpoint(db, SQLITE_CHECKPOINT_RESTART);
}
```

## Connection Management

### Database Pool

```objc
// In PDSDatabasePool.m
- (instancetype)initWithServiceDatabases:(PDSServiceDatabases *)serviceDatabases 
                                   error:(NSError **)error {
    self = [super init];
    if (!self) return nil;
    
    self.serviceDatabases = serviceDatabases;
    self.actorDatabases = [NSMutableDictionary dictionary];
    self.lock = [[NSLock alloc] init];
    
    return self;
}

- (PDSActorDatabase *)databaseForDID:(NSString *)did 
                               error:(NSError **)error {
    [self.lock lock];
    
    // Check if database is already open
    PDSActorDatabase *db = self.actorDatabases[did];
    if (db) {
        [self.lock unlock];
        return db;
    }
    
    // Create new database
    NSString *dbPath = [NSString stringWithFormat:@"%@/%@.db", self.basePath, did];
    db = [[PDSActorDatabase alloc] initWithPath:dbPath error:error];
    
    if (db) {
        self.actorDatabases[did] = db;
    }
    
    [self.lock unlock];
    return db;
}
```

## Prepared Statements

### Benefits

- **Security** — Prevent SQL injection
- **Performance** — Compiled once, executed many times
- **Type safety** — Automatic type conversion

### Using Prepared Statements

**Source:** `ATProtoPDS/Sources/Database/Service/ServiceDatabases.m` (Lines 169-189)

```objc
// Get account by DID with prepared statement
- (nullable PDSDatabaseAccount *)getAccountByDid:(NSString *)did error:(NSError **)error {
    PDSActorStore *store = [self.servicePool storeForDid:@"__service__" error:nil];
    if (!store) {
        return nil;
    }

    NSString *sql = @"SELECT * FROM accounts WHERE did = ?";
    __autoreleasing NSError *stmtError = nil;
    sqlite3_stmt *stmt = [store prepareStatement:sql error:&stmtError];
    if (!stmt) {
        if (error) *error = stmtError;
        return nil;
    }

    // Bind parameter
    sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);

    // Execute and fetch result
    PDSDatabaseAccount *account = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        account = [store accountFromStatement:stmt];
    }

    // Finalize statement
    [store finalizeStatement:stmt];
    return account;
}
```

### Parameter Binding Patterns

**Source:** `ATProtoPDS/Sources/Database/Service/ServiceDatabases.m` (Lines 245-270)

```objc
// Bind different parameter types
NSString *sql = @"INSERT INTO refresh_tokens (token, account_did, created_at, expires_at) VALUES (?, ?, ?, ?)";
PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [store prepareStatement:sql error:innerError];
if (!stmt) { success = NO; return; }

// Bind text parameter
sqlite3_bind_text(stmt, 1, token.UTF8String, -1, SQLITE_TRANSIENT);

// Bind text parameter
sqlite3_bind_text(stmt, 2, accountDid.UTF8String, -1, SQLITE_TRANSIENT);

// Bind double (timestamp)
sqlite3_bind_double(stmt, 3, [[NSDate date] timeIntervalSince1970]);

// Bind double (expiration timestamp)
PDSConfiguration *config = [PDSConfiguration sharedConfiguration];
NSUInteger refreshTokenTtl = config.refreshTokenTtlSeconds > 0 ? config.refreshTokenTtlSeconds : (30 * 24 * 60 * 60);
sqlite3_bind_double(stmt, 4, [[NSDate dateWithTimeIntervalSinceNow:refreshTokenTtl] timeIntervalSince1970]);

// Execute
success = (sqlite3_step(stmt) == SQLITE_DONE);
```

### Blob Parameter Binding

**Source:** `ATProtoPDS/Sources/Database/Service/ServiceDatabases.m` (Lines 430-485)

```objc
// Bind blob parameters (for hashes and salts)
NSString *sql = @"INSERT INTO app_passwords (id, account_did, name, password_hash, password_salt, privileged, created_at) "
                @"VALUES (?, ?, ?, ?, ?, ?, ?)";
PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [store prepareStatement:sql error:innerError];
if (!stmt) return;

NSString *uuid = [[NSUUID UUID] UUIDString];
sqlite3_bind_text(stmt, 1, uuid.UTF8String, -1, SQLITE_TRANSIENT);
sqlite3_bind_text(stmt, 2, accountDid.UTF8String, -1, SQLITE_TRANSIENT);
sqlite3_bind_text(stmt, 3, name.UTF8String, -1, SQLITE_TRANSIENT);

// Bind blob (password hash)
sqlite3_bind_blob(stmt, 4, hash.bytes, (int)hash.length, SQLITE_TRANSIENT);

// Bind blob (password salt)
sqlite3_bind_blob(stmt, 5, salt.bytes, (int)salt.length, SQLITE_TRANSIENT);

// Bind integer
sqlite3_bind_int(stmt, 6, privileged ? 1 : 0);

// Bind double
sqlite3_bind_double(stmt, 7, createdAt);

if (sqlite3_step(stmt) != SQLITE_DONE) {
    if (innerError) {
        *innerError = [NSError errorWithDomain:PDSServiceDatabasesErrorDomain
                                         code:sqlite3_errcode(store.db)
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to insert app password"}];
    }
    return;
}
```

### Iterating Query Results

**Source:** `ATProtoPDS/Sources/Database/Migration/PDSMigrationManager.m` (Lines 100-130)

```objc
// Iterate through query results
PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *accountStmt;
sqlite3_prepare_v2(sourceDb,
    "SELECT did, handle, email, password_hash, password_salt, access_jwt, refresh_jwt, created_at, updated_at "
    "FROM accounts", -1, &accountStmt, NULL);

while (sqlite3_step(accountStmt) == SQLITE_ROW) {
    PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
    
    // Extract text columns
    account.did = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(accountStmt, 0)];
    account.handle = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(accountStmt, 1)];

    // Check for NULL values
    int col = 2;
    if (sqlite3_column_type(accountStmt, col) != SQLITE_NULL) {
        account.email = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(accountStmt, col)];
    }
    col++;

    // Extract blob columns
    if (sqlite3_column_type(accountStmt, col) != SQLITE_NULL) {
        account.passwordHash = [NSData dataWithBytes:sqlite3_column_blob(accountStmt, col)
                                              length:sqlite3_column_bytes(accountStmt, col)];
    }
    col++;

    if (sqlite3_column_type(accountStmt, col) != SQLITE_NULL) {
        account.passwordSalt = [NSData dataWithBytes:sqlite3_column_blob(accountStmt, col)
                                              length:sqlite3_column_bytes(accountStmt, col)];
    }
    col++;

    // Extract double columns (timestamps)
    account.createdAt = sqlite3_column_double(accountStmt, col);
    col++;
    account.updatedAt = sqlite3_column_double(accountStmt, col);

    [allAccounts addObject:account];
}
```

### Counting Rows

**Source:** `ATProtoPDS/Sources/Database/Migration/PDSMigrationManager.m` (Lines 60-85)

```objc
// Count rows for progress tracking
{
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *countStmt = NULL;
    sqlite3_prepare_v2(sourceDb, "SELECT COUNT(*) FROM accounts", -1, &countStmt, NULL);
    if (sqlite3_step(countStmt) == SQLITE_ROW) {
        totalAccounts = sqlite3_column_int64(countStmt, 0);
    }
}

{
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *countStmt = NULL;
    sqlite3_prepare_v2(sourceDb, "SELECT COUNT(*) FROM repos", -1, &countStmt, NULL);
    if (sqlite3_step(countStmt) == SQLITE_ROW) {
        totalRepos = sqlite3_column_int64(countStmt, 0);
    }
}
```

## Transactions

### ACID Properties

SQLite provides ACID guarantees:
- **Atomicity** — All or nothing
- **Consistency** — Valid state before and after
- **Isolation** — Concurrent transactions don't interfere
- **Durability** — Committed data survives crashes

### Transaction Management

```objc
// In PDSRepositoryService.m
- (void)updateRepositoryWithChanges:(NSArray *)changes 
                                did:(NSString *)did
                         completion:(void (^)(NSError *error))completion {
    
    PDSActorDatabase *db = [self.app.databasePool databaseForDID:did error:nil];
    
    // 1. Begin transaction
    sqlite3_exec(db.connection, "BEGIN TRANSACTION", NULL, NULL, NULL);
    
    @try {
        // 2. Apply changes
        for (NSDictionary *change in changes) {
            NSString *collection = change[@"collection"];
            NSString *rkey = change[@"rkey"];
            NSDictionary *record = change[@"record"];
            
            [self insertRecord:record 
                   collection:collection 
                         rkey:rkey 
                           db:db];
        }
        
        // 3. Update MST
        NSString *rootCID = [self calculateMSTRootCID:db];
        
        // 4. Create commit
        [self createCommitWithRootCID:rootCID db:db];
        
        // 5. Commit transaction
        sqlite3_exec(db.connection, "COMMIT", NULL, NULL, NULL);
        
        completion(nil);
    } @catch (NSException *exception) {
        // 6. Rollback on error
        sqlite3_exec(db.connection, "ROLLBACK", NULL, NULL, NULL);
        
        NSError *error = [NSError errorWithDomain:@"Database" code:1 
            userInfo:@{NSLocalizedDescriptionKey: exception.reason}];
        completion(error);
    }
}
```

## Indexing

### Creating Indexes

```sql
-- Index for fast lookups by collection
CREATE INDEX idx_records_collection ON records(collection);

-- Index for fast lookups by DID (in service database)
CREATE INDEX idx_users_did ON users(did);

-- Index for fast lookups by handle
CREATE INDEX idx_users_handle ON users(handle);

-- Index for sequencer queries
CREATE INDEX idx_sequencer_timestamp ON sequencer(timestamp);
```

### Query Optimization

```objc
// Use indexes for efficient queries
const char *sql = "SELECT * FROM records WHERE collection = ? ORDER BY rkey LIMIT ?";
sqlite3_stmt *stmt;
sqlite3_prepare_v2(db.connection, sql, -1, &stmt, NULL);

sqlite3_bind_text(stmt, 1, [collection UTF8String], -1, SQLITE_TRANSIENT);
sqlite3_bind_int(stmt, 2, (int)limit);

// This query uses the idx_records_collection index
```

## Migrations

### Schema Versioning

```objc
// In PDSMigration.m
+ (void)runMigrations:(sqlite3 *)db error:(NSError **)error {
    // Get current schema version
    int currentVersion = [self getSchemaVersion:db];
    
    // Run migrations in order
    if (currentVersion < 1) {
        [self migration_001_CreateTables:db error:error];
    }
    
    if (currentVersion < 2) {
        [self migration_002_AddIndexes:db error:error];
    }
    
    // Update schema version
    [self setSchemaVersion:2 db:db];
}

- (void)migration_001_CreateTables:(sqlite3 *)db error:(NSError **)error {
    const char *sql = "CREATE TABLE records (...)";
    char *errMsg = NULL;
    
    int rc = sqlite3_exec(db, sql, NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        *error = [NSError errorWithDomain:@"Migration" code:1 userInfo:nil];
        sqlite3_free(errMsg);
    }
}
```

## Performance Tuning

### PRAGMA Settings

```objc
// In PDSServiceDatabases.m
- (void)optimizePerformance:(sqlite3 *)db {
    // Increase cache size
    sqlite3_exec(db, "PRAGMA cache_size = 10000", NULL, NULL, NULL);
    
    // Use memory-mapped I/O
    sqlite3_exec(db, "PRAGMA mmap_size = 30000000", NULL, NULL, NULL);
    
    // Synchronous mode (balance safety and performance)
    sqlite3_exec(db, "PRAGMA synchronous = NORMAL", NULL, NULL, NULL);
    
    // Temporary storage in memory
    sqlite3_exec(db, "PRAGMA temp_store = MEMORY", NULL, NULL, NULL);
}
```

## Backup and Recovery

### Backup

```objc
// In PDSBackup.m
- (void)backupDatabase:(sqlite3 *)sourceDB 
            toPath:(NSString *)backupPath
         completion:(void (^)(NSError *error))completion {
    
    sqlite3 *backupDB;
    sqlite3_open([backupPath UTF8String], &backupDB);
    
    sqlite3_backup *backup = sqlite3_backup_init(backupDB, "main", sourceDB, "main");
    
    int rc = sqlite3_backup_step(backup, -1);
    sqlite3_backup_finish(backup);
    
    sqlite3_close(backupDB);
    
    if (rc == SQLITE_OK) {
        completion(nil);
    } else {
        NSError *error = [NSError errorWithDomain:@"Backup" code:rc userInfo:nil];
        completion(error);
    }
}
```

## Next Steps

- **[Service Databases](./service-databases)** — Shared database details
- **[Actor Databases](./actor-databases)** — Per-user database details
- **[Migrations](./migrations)** — Schema versioning
