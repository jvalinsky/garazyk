# Service Databases

## Overview

Service databases are shared SQLite databases that store system-level data used across all users. Unlike per-user actor databases, service databases are centralized and contain account information, DID resolution caches, and repository sequencing data.

## Architecture

```
┌──────────────────────────────────────────┐
│   Service Databases (Shared)             │
├──────────────────────────────────────────┤
│                                          │
│  ┌──────────────────────────────────┐   │
│  │ service.sqlite                   │   │
│  │ - accounts                       │   │
│  │ - invite_codes                   │   │
│  │ - refresh_tokens                 │   │
│  │ - sessions                       │   │
│  └──────────────────────────────────┘   │
│                                          │
│  ┌──────────────────────────────────┐   │
│  │ did_cache.sqlite                 │   │
│  │ - DID resolution cache           │   │
│  │ - DID documents                  │   │
│  │ - Expiration tracking            │   │
│  └──────────────────────────────────┘   │
│                                          │
│  ┌──────────────────────────────────┐   │
│  │ sequencer.sqlite                 │   │
│  │ - Repository sequencing          │   │
│  │ - Commit ordering                │   │
│  │ - Sync state                     │   │
│  └──────────────────────────────────┘   │
│                                          │
└──────────────────────────────────────────┘
```

## Service Database Files

### service.sqlite

The main service database containing account and session data.

**Tables:**

```sql
CREATE TABLE accounts (
    did TEXT PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,
    handle TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    created_at DATETIME NOT NULL,
    updated_at DATETIME NOT NULL,
    status TEXT DEFAULT 'active'  -- active, suspended, deleted
);

CREATE TABLE invite_codes (
    code TEXT PRIMARY KEY,
    created_by TEXT NOT NULL,
    created_at DATETIME NOT NULL,
    used_by TEXT,
    used_at DATETIME,
    expires_at DATETIME
);

CREATE TABLE refresh_tokens (
    token_id TEXT PRIMARY KEY,
    did TEXT NOT NULL,
    token_hash TEXT NOT NULL,
    created_at DATETIME NOT NULL,
    expires_at DATETIME NOT NULL,
    revoked_at DATETIME,
    FOREIGN KEY (did) REFERENCES accounts(did)
);

CREATE TABLE sessions (
    session_id TEXT PRIMARY KEY,
    did TEXT NOT NULL,
    created_at DATETIME NOT NULL,
    expires_at DATETIME NOT NULL,
    last_activity DATETIME,
    FOREIGN KEY (did) REFERENCES accounts(did)
);
```

**Indexes:**

```sql
CREATE INDEX idx_accounts_email ON accounts(email);
CREATE INDEX idx_accounts_handle ON accounts(handle);
CREATE INDEX idx_invite_codes_created_by ON invite_codes(created_by);
CREATE INDEX idx_refresh_tokens_did ON refresh_tokens(did);
CREATE INDEX idx_refresh_tokens_expires_at ON refresh_tokens(expires_at);
CREATE INDEX idx_sessions_did ON sessions(did);
CREATE INDEX idx_sessions_expires_at ON sessions(expires_at);
```

### did_cache.sqlite

Caches DID resolution results to reduce PLC lookups.

**Tables:**

```sql
CREATE TABLE did_cache (
    did TEXT PRIMARY KEY,
    document BLOB NOT NULL,  -- JSON DID document
    resolved_at DATETIME NOT NULL,
    expires_at DATETIME NOT NULL
);

CREATE TABLE handle_to_did (
    handle TEXT PRIMARY KEY,
    did TEXT NOT NULL,
    resolved_at DATETIME NOT NULL,
    expires_at DATETIME NOT NULL,
    FOREIGN KEY (did) REFERENCES did_cache(did)
);
```

**Indexes:**

```sql
CREATE INDEX idx_did_cache_expires_at ON did_cache(expires_at);
CREATE INDEX idx_handle_to_did_expires_at ON handle_to_did(expires_at);
```

### sequencer.sqlite

Tracks repository update sequencing for sync operations.

**Tables:**

```sql
CREATE TABLE repo_sequence (
    sequence_num INTEGER PRIMARY KEY AUTOINCREMENT,
    did TEXT NOT NULL,
    root_cid BLOB NOT NULL,
    commit_cid BLOB NOT NULL,
    created_at DATETIME NOT NULL,
    UNIQUE(did, sequence_num)
);

CREATE TABLE sync_state (
    did TEXT PRIMARY KEY,
    last_sequence_num INTEGER,
    last_commit_cid BLOB,
    last_sync_at DATETIME
);
```

**Indexes:**

```sql
CREATE INDEX idx_repo_sequence_did ON repo_sequence(did);
CREATE INDEX idx_repo_sequence_created_at ON repo_sequence(created_at);
```

## PDSServiceDatabases Class

The `PDSServiceDatabases` class manages all service databases. It uses a pool-based architecture with separate pools for service, DID cache, and sequencer databases.

**Source:** `ATProtoPDS/Sources/Database/Service/ServiceDatabases.m`

### Initialization Pattern

```objc
// Lines 65-85: Initialization with database pools
- (instancetype)initWithDirectory:(NSString *)directory 
                     serviceMaxSize:(NSUInteger)serviceMaxSize
                   didCacheMaxSize:(NSUInteger)didCacheMaxSize
                 sequencerMaxSize:(NSUInteger)sequencerMaxSize {
    self = [super init];
    if (self) {
        PDSDataPaths *paths = [PDSDataPaths pathsForBaseDirectory:directory];
        [paths createDirectoriesWithError:nil];

        _serviceDbPath = paths.serviceDirectory;
        _didCacheDbPath = paths.didCacheDirectory;
        _sequencerDbPath = paths.sequencerDirectory;
        
        _servicePool = [[PDSDatabasePool alloc] initWithDbDirectory:_serviceDbPath maxSize:serviceMaxSize];
        _didCachePool = [[PDSDatabasePool alloc] initWithDbDirectory:_didCacheDbPath maxSize:didCacheMaxSize];
        _sequencerPool = [[PDSDatabasePool alloc] initWithDbDirectory:_sequencerDbPath maxSize:sequencerMaxSize];
        
        [self applyPerformancePragmasOnPool:_servicePool];
        [self applyPerformancePragmasOnPool:_didCachePool];
        [self applyPerformancePragmasOnPool:_sequencerPool];
        [self initializeServiceSchema:nil];
        [self initializeDidCacheSchema:nil];
        [self initializeSequencerSchema:nil];
    }
    return self;
}
```

### Performance Configuration

```objc
// Lines 88-95: Apply WAL and performance pragmas
- (void)applyPerformancePragmasOnPool:(PDSDatabasePool *)pool {
    static NSString *const pragmaSQL =
        @"PRAGMA journal_mode=WAL;"
        @"PRAGMA synchronous=NORMAL;"
        @"PRAGMA cache_size=-32000;"
        @"PRAGMA temp_store=MEMORY;";
    [self executeSQL:pragmaSQL onPool:pool error:nil];
}
```

### Account Creation Pattern

```objc
// Lines 130-145: Create single account with transaction
- (BOOL)createAccount:(PDSDatabaseAccount *)account error:(NSError **)error {
    __block BOOL success = NO;
    __block NSError *blockError = nil;

    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        success = [store createAccount:account error:innerError];
    } error:&blockError];

    if (!success && blockError) {
        if (error) *error = blockError;
    }

    return success;
}
```

### Batch Account Creation

```objc
// Lines 147-167: Create multiple accounts in batch
- (BOOL)createAccounts:(NSArray<PDSDatabaseAccount *> *)accounts error:(NSError **)error {
    __block BOOL success = YES;
    __block NSError *localError = nil;

    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)transactor;

        for (PDSDatabaseAccount *account in accounts) {
            BOOL accountSuccess = [store createAccount:account error:innerError];
            if (!accountSuccess) {
                success = NO;
                break;
            }
        }
    } error:&localError];

    if (!success && localError) {
        if (error) *error = localError;
    }

    return success;
}
```

### Account Retrieval Pattern

```objc
// Lines 169-189: Get account by DID with prepared statement
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

    sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);

    PDSDatabaseAccount *account = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        account = [store accountFromStatement:stmt];
    }

    [store finalizeStatement:stmt];
    return account;
}
```

### Refresh Token Management

```objc
// Lines 245-270: Store refresh token with expiration
- (BOOL)storeRefreshToken:(NSString *)token forAccount:(NSString *)accountDid error:(NSError **)error {
    __block BOOL success = NO;
    __block NSError *localError = nil;

    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        NSString *sql = @"INSERT INTO refresh_tokens (token, account_did, created_at, expires_at) VALUES (?, ?, ?, ?)";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [store prepareStatement:sql error:innerError];
        if (!stmt) { success = NO; return; }
        
        sqlite3_bind_text(stmt, 1, token.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, accountDid.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_double(stmt, 3, [[NSDate date] timeIntervalSince1970]);
        
        PDSConfiguration *config = [PDSConfiguration sharedConfiguration];
        NSUInteger refreshTokenTtl = config.refreshTokenTtlSeconds > 0 ? config.refreshTokenTtlSeconds : (30 * 24 * 60 * 60);
        sqlite3_bind_double(stmt, 4, [[NSDate dateWithTimeIntervalSinceNow:refreshTokenTtl] timeIntervalSince1970]);

        success = (sqlite3_step(stmt) == SQLITE_DONE);
    } error:&localError];

    if (!success && localError) {
        if (error) *error = localError;
    }

    return success;
}
```

### Invite Code Creation

```objc
// Lines 330-355: Create invite code with max uses
- (BOOL)createInviteCode:(NSString *)code
              forAccount:(NSString *)accountDid
               maxUses:(NSInteger)maxUses
                 error:(NSError **)error {
    __block BOOL success = NO;
    __block NSError *localError = nil;

    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        NSString *sql = @"INSERT INTO invite_codes (id, code, account_did, created_at, max_uses) "
                        @"VALUES (?, ?, ?, ?, ?)";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [store prepareStatement:sql error:innerError];
        if (!stmt) { success = NO; return; }
        
        NSString *uuid = [[NSUUID UUID] UUIDString];
        sqlite3_bind_text(stmt, 1, uuid.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, code.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 3, accountDid.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_double(stmt, 4, [[NSDate date] timeIntervalSince1970]);
        sqlite3_bind_int64(stmt, 5, maxUses);

        success = (sqlite3_step(stmt) == SQLITE_DONE);
    } error:&localError];

    if (!success && localError) {
        if (error) *error = localError;
    }

    return success;
}
```

### App Password Creation

```objc
// Lines 430-485: Create app password with PBKDF2 hashing
- (nullable NSDictionary *)createAppPasswordForAccount:(NSString *)accountDid
                                                 name:(NSString *)name
                                           privileged:(BOOL)privileged
                                                error:(NSError **)error {
    if (accountDid.length == 0 || name.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PDSServiceDatabasesErrorDomain
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing accountDid or name"}];
        }
        return nil;
    }

    __block NSDictionary *result = nil;
    __block NSError *localError = nil;

    [self.servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)transactor;

        NSString *password = appPasswordGenerateSecret();
        NSData *salt = appPasswordGenerateSalt();
        NSData *hash = appPasswordHash(password, salt);
        if (!hash) {
            if (innerError) {
                *innerError = [NSError errorWithDomain:PDSServiceDatabasesErrorDomain
                                                 code:-1
                                             userInfo:@{NSLocalizedDescriptionKey: @"Failed to hash app password"}];
            }
            return;
        }

        NSTimeInterval createdAt = [[NSDate date] timeIntervalSince1970];

        NSString *sql = @"INSERT INTO app_passwords (id, account_did, name, password_hash, password_salt, privileged, created_at) "
                        @"VALUES (?, ?, ?, ?, ?, ?, ?)";
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = [store prepareStatement:sql error:innerError];
        if (!stmt) return;

        NSString *uuid = [[NSUUID UUID] UUIDString];
        sqlite3_bind_text(stmt, 1, uuid.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, accountDid.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 3, name.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_blob(stmt, 4, hash.bytes, (int)hash.length, SQLITE_TRANSIENT);
        sqlite3_bind_blob(stmt, 5, salt.bytes, (int)salt.length, SQLITE_TRANSIENT);
        sqlite3_bind_int(stmt, 6, privileged ? 1 : 0);
        sqlite3_bind_double(stmt, 7, createdAt);

        if (sqlite3_step(stmt) != SQLITE_DONE) {
            if (innerError) {
                *innerError = [NSError errorWithDomain:PDSServiceDatabasesErrorDomain
                                                 code:sqlite3_errcode(store.db)
                                             userInfo:@{NSLocalizedDescriptionKey: @"Failed to insert app password"}];
            }
            return;
        }

        NSString *createdAtString = [NSDateFormatter atproto_stringFromDate:[NSDate dateWithTimeIntervalSince1970:createdAt]];
        result = @{
            @"name": name,
            @"password": password,
            @"createdAt": createdAtString ?: @"",
            @"privileged": @(privileged)
        };
    } error:&localError];

    if (!result && localError) {
        if (error) *error = localError;
    }

    return result;
}
```

## Account Management

### Creating an Account

```objc
NSDictionary *account = @{
    @"did": @"did:plc:user123",
    @"email": @"user@example.com",
    @"handle": @"alice",
    @"password_hash": hashedPassword,
    @"created_at": [NSDate date],
    @"status": @"active"
};

NSError *error = nil;
BOOL success = [serviceDatabases createAccount:account error:&error];
```

### Retrieving Account Information

```objc
// By DID
NSDictionary *account = [serviceDatabases getAccountForDid:@"did:plc:user123"
                                                     error:&error];

// By handle
NSDictionary *account = [serviceDatabases getAccountForHandle:@"alice"
                                                        error:&error];

// By email
NSDictionary *account = [serviceDatabases getAccountForEmail:@"user@example.com"
                                                       error:&error];
```

### Updating Account Status

```objc
// Suspend account
NSDictionary *account = @{
    @"did": @"did:plc:user123",
    @"status": @"suspended"
};

NSError *error = nil;
BOOL success = [serviceDatabases updateAccount:account error:&error];
```

## Invite Code Management

### Creating Invite Codes

```objc
NSError *error = nil;
NSString *code = [serviceDatabases createInviteCode:adminDid error:&error];

if (code) {
    NSLog(@"Invite code: %@", code);
}
```

### Using Invite Codes

```objc
NSError *error = nil;
BOOL success = [serviceDatabases useInviteCode:code forDid:newUserDid error:&error];

if (success) {
    // Account can now be created
}
```

## Refresh Token Management

### Storing Refresh Tokens

```objc
NSString *tokenHash = [self hashToken:refreshToken];

NSError *error = nil;
BOOL success = [serviceDatabases storeRefreshToken:tokenHash
                                            forDid:userDid
                                             error:&error];
```

### Validating Refresh Tokens

```objc
NSString *tokenHash = [self hashToken:refreshToken];

NSError *error = nil;
BOOL valid = [serviceDatabases validateRefreshToken:tokenHash
                                             forDid:userDid
                                              error:&error];

if (valid) {
    // Token is valid, can refresh access token
}
```

### Revoking Refresh Tokens

```objc
NSString *tokenHash = [self hashToken:refreshToken];

NSError *error = nil;
BOOL success = [serviceDatabases revokeRefreshToken:tokenHash error:&error];
```

## DID Cache Management

### Caching DID Documents

```objc
NSDictionary *didDocument = @{
    @"id": @"did:plc:user123",
    @"publicKey": @[/* ... */],
    @"service": @[/* ... */]
};

NSError *error = nil;
BOOL success = [serviceDatabases cacheDidDocument:didDocument
                                           forDid:@"did:plc:user123"
                                            error:&error];
```

### Retrieving Cached DID Documents

```objc
NSError *error = nil;
NSDictionary *document = [serviceDatabases getCachedDidDocument:@"did:plc:user123"
                                                          error:&error];

if (document) {
    // Use cached document
} else {
    // Fetch from PLC and cache
}
```

### Caching Handle Resolution

```objc
NSError *error = nil;
BOOL success = [serviceDatabases cacheHandle:@"alice"
                                      forDid:@"did:plc:user123"
                                       error:&error];

// Later, resolve from cache
NSString *did = [serviceDatabases resolveCachedHandle:@"alice" error:&error];
```

## Repository Sequencing

### Recording Repository Updates

```objc
NSError *error = nil;
BOOL success = [serviceDatabases recordRepoUpdate:userDid
                                          rootCid:rootCidData
                                            error:&error];
```

### Getting Sequence Numbers

```objc
NSError *error = nil;
NSInteger nextSeq = [serviceDatabases getNextSequenceNumber:&error];
```

## WAL Mode Configuration

All service databases use Write-Ahead Logging:

```sql
PRAGMA journal_mode=WAL;
PRAGMA synchronous=NORMAL;
PRAGMA wal_autocheckpoint=1000;
PRAGMA cache_size=-64000;  /* 64MB cache */
```

Benefits:
- Concurrent reads while writes are in progress
- Better performance for high-concurrency scenarios
- Automatic checkpointing

## Performance Considerations

### Indexes

Service databases use strategic indexes:

- **accounts**: email, handle (for lookups)
- **refresh_tokens**: did, expires_at (for cleanup)
- **did_cache**: expires_at (for cache expiration)
- **repo_sequence**: did, created_at (for sync)

### Cache Expiration

DID cache entries expire after 24 hours:

```objc
NSDate *expiresAt = [NSDate dateWithTimeIntervalSinceNow:24*3600];
```

Expired entries are cleaned up periodically:

```objc
[serviceDatabases cleanupExpiredCacheEntries:&error];
```

### Connection Pooling

Service databases use a single connection pool:

```objc
@property (nonatomic, strong) PDSDatabase *serviceDatabase;
```

All operations are serialized through this connection.

## Best Practices

1. **Account Management**
   - Always hash passwords before storing
   - Use unique constraints on email and handle
   - Track account status (active/suspended/deleted)

2. **Invite Codes**
   - Generate cryptographically secure codes
   - Set expiration times
   - Track usage

3. **Refresh Tokens**
   - Hash tokens before storage
   - Set expiration times
   - Implement token rotation

4. **DID Cache**
   - Cache for 24 hours
   - Implement cache invalidation
   - Fall back to PLC on cache miss

5. **Sequencing**
   - Use auto-incrementing sequence numbers
   - Track per-user sequence state
   - Use for sync ordering

## Common Patterns

### Account Creation Flow

```objc
// 1. Check if handle/email already exists
NSDictionary *existing = [serviceDatabases getAccountForHandle:handle error:&error];
if (existing) {
    // Handle already taken
    return;
}

// 2. Create account
NSDictionary *account = @{
    @"did": generatedDid,
    @"email": email,
    @"handle": handle,
    @"password_hash": hashedPassword,
    @"created_at": [NSDate date],
    @"status": @"active"
};

BOOL success = [serviceDatabases createAccount:account error:&error];

// 3. Initialize repository
[repositoryService initializeRepoForDid:generatedDid error:&error];
```

### Token Refresh Flow

```objc
// 1. Validate refresh token
NSString *tokenHash = [self hashToken:refreshToken];
BOOL valid = [serviceDatabases validateRefreshToken:tokenHash
                                             forDid:userDid
                                              error:&error];

if (!valid) {
    // Token invalid or expired
    return;
}

// 2. Generate new access token
NSString *newAccessToken = [jwtMinter generateAccessTokenForDid:userDid];

// 3. Optionally rotate refresh token
NSString *newRefreshToken = [self generateRefreshToken];
NSString *newTokenHash = [self hashToken:newRefreshToken];

[serviceDatabases revokeRefreshToken:tokenHash error:&error];
[serviceDatabases storeRefreshToken:newTokenHash forDid:userDid error:&error];

// 4. Return new tokens
return @{
    @"accessToken": newAccessToken,
    @"refreshToken": newRefreshToken
};
```

## See Also

- [Actor Databases](./actor-databases.md)
- [Migrations](./migrations.md)
- [WAL Mode](./wal-mode.md)
- [SQLite Architecture](./sqlite-architecture.md)
