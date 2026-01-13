# Chapter 13: SQLite Database Layer

In the previous chapters, we implemented content-addressed storage using CIDs and CAR files. But we still need a way to persistently store accounts, track block locations, and efficiently query records. This chapter introduces **SQLite**—a lightweight, embedded database that's perfect for single-user servers like a PDS.

## What You'll Learn

By the end of this chapter, you'll be able to:
- Use SQLite's C API directly from Objective-C
- Implement database migrations for schema evolution
- Write safe, parameterized queries
- Handle transactions for atomic operations
- Build CRUD operations for accounts and blocks

## Prerequisites

This chapter assumes you understand:
- **Foundation Framework** - `NSError`, `NSData`, `NSURL` (Chapter 2)
- **Content Identifiers** - How CIDs work (Chapter 4)

---

## SQLite C API Basics

```objc
#import <sqlite3.h>

// Key functions:
sqlite3_open()       // Open database connection
sqlite3_prepare_v2() // Compile SQL statement
sqlite3_bind_*()     // Bind parameters
sqlite3_step()       // Execute statement
sqlite3_column_*()   // Read result columns
sqlite3_finalize()   // Clean up statement
sqlite3_close()      // Close connection
```

## Database Interface

```objc
// PDSDatabase.h
@interface PDSDatabase : NSObject

@property (nonatomic, readonly) NSURL *databaseURL;
@property (nonatomic, readonly) BOOL isOpen;

+ (instancetype)databaseAtURL:(NSURL *)url;
- (BOOL)openWithError:(NSError **)error;
- (void)close;

// Account operations
- (BOOL)createAccount:(NSString *)did 
               handle:(NSString *)handle 
                error:(NSError **)error;
- (NSString *)getDIDForHandle:(NSString *)handle error:(NSError **)error;

// Repository operations
- (BOOL)storeBlock:(NSData *)data 
           withCID:(CID *)cid 
            forDID:(NSString *)did 
             error:(NSError **)error;
- (NSData *)getBlock:(CID *)cid forDID:(NSString *)did error:(NSError **)error;

@end
```

## Opening and Closing

```objc
@implementation PDSDatabase {
    sqlite3 *_db;
}

- (BOOL)openWithError:(NSError **)error {
    if (_db) return YES;
    
    int result = sqlite3_open(self.databaseURL.path.UTF8String, &_db);
    if (result != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:PDSDatabaseErrorDomain
                                         code:result
                                     userInfo:@{NSLocalizedDescriptionKey: 
                                         @(sqlite3_errmsg(_db))}];
        }
        return NO;
    }
    
    // Enable WAL mode for better concurrency
    [self executeSQL:@"PRAGMA journal_mode=WAL" error:nil];
    
    // Run migrations
    return [self runMigrationsWithError:error];
}

- (void)close {
    if (_db) {
        sqlite3_close(_db);
        _db = NULL;
    }
}
```

## Schema Migrations

```objc
- (BOOL)runMigrationsWithError:(NSError **)error {
    NSArray *migrations = @[
        @"CREATE TABLE IF NOT EXISTS accounts ("
         "  did TEXT PRIMARY KEY,"
         "  handle TEXT UNIQUE NOT NULL,"
         "  created_at TEXT NOT NULL"
         ")",
        
        @"CREATE TABLE IF NOT EXISTS blocks ("
         "  cid TEXT NOT NULL,"
         "  did TEXT NOT NULL,"
         "  data BLOB NOT NULL,"
         "  PRIMARY KEY (cid, did)"
         ")",
        
        @"CREATE TABLE IF NOT EXISTS records ("
         "  uri TEXT PRIMARY KEY,"
         "  did TEXT NOT NULL,"
         "  collection TEXT NOT NULL,"
         "  rkey TEXT NOT NULL,"
         "  cid TEXT NOT NULL,"
         "  created_at TEXT NOT NULL"
         ")",
        
        @"CREATE INDEX IF NOT EXISTS idx_records_did ON records(did)",
        @"CREATE INDEX IF NOT EXISTS idx_records_collection ON records(did, collection)"
    ];
    
    for (NSString *sql in migrations) {
        if (![self executeSQL:sql error:error]) {
            return NO;
        }
    }
    return YES;
}
```

## Prepared Statements

```objc
- (sqlite3_stmt *)prepareStatement:(NSString *)sql error:(NSError **)error {
    sqlite3_stmt *stmt = NULL;
    int result = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    
    if (result != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:PDSDatabaseErrorDomain
                                         code:result
                                     userInfo:@{NSLocalizedDescriptionKey: 
                                         @(sqlite3_errmsg(_db))}];
        }
        return NULL;
    }
    return stmt;
}

- (BOOL)executeSQL:(NSString *)sql error:(NSError **)error {
    char *errmsg = NULL;
    int result = sqlite3_exec(_db, sql.UTF8String, NULL, NULL, &errmsg);
    
    if (result != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:PDSDatabaseErrorDomain
                                         code:result
                                     userInfo:@{NSLocalizedDescriptionKey: 
                                         errmsg ? @(errmsg) : @"Unknown error"}];
        }
        if (errmsg) sqlite3_free(errmsg);
        return NO;
    }
    return YES;
}
```

## Account Operations

```objc
- (BOOL)createAccount:(NSString *)did 
               handle:(NSString *)handle 
                error:(NSError **)error {
    NSString *sql = @"INSERT INTO accounts (did, handle, created_at) VALUES (?, ?, ?)";
    sqlite3_stmt *stmt = [self prepareStatement:sql error:error];
    if (!stmt) return NO;
    
    NSString *now = [self iso8601Now];
    
    sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, handle.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 3, now.UTF8String, -1, SQLITE_TRANSIENT);
    
    int result = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    
    if (result != SQLITE_DONE) {
        if (error) {
            *error = [NSError errorWithDomain:PDSDatabaseErrorDomain
                                         code:result
                                     userInfo:@{NSLocalizedDescriptionKey: 
                                         @(sqlite3_errmsg(_db))}];
        }
        return NO;
    }
    return YES;
}

- (NSString *)getDIDForHandle:(NSString *)handle error:(NSError **)error {
    NSString *sql = @"SELECT did FROM accounts WHERE handle = ?";
    sqlite3_stmt *stmt = [self prepareStatement:sql error:error];
    if (!stmt) return nil;
    
    sqlite3_bind_text(stmt, 1, handle.UTF8String, -1, SQLITE_TRANSIENT);
    
    NSString *did = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        const char *text = (const char *)sqlite3_column_text(stmt, 0);
        if (text) {
            did = @(text);
        }
    }
    
    sqlite3_finalize(stmt);
    return did;
}
```

## Block Storage

```objc
- (BOOL)storeBlock:(NSData *)data 
           withCID:(CID *)cid 
            forDID:(NSString *)did 
             error:(NSError **)error {
    NSString *sql = @"INSERT OR REPLACE INTO blocks (cid, did, data) VALUES (?, ?, ?)";
    sqlite3_stmt *stmt = [self prepareStatement:sql error:error];
    if (!stmt) return NO;
    
    sqlite3_bind_text(stmt, 1, cid.stringValue.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, did.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_blob(stmt, 3, data.bytes, (int)data.length, SQLITE_TRANSIENT);
    
    int result = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    
    return result == SQLITE_DONE;
}

- (NSData *)getBlock:(CID *)cid forDID:(NSString *)did error:(NSError **)error {
    NSString *sql = @"SELECT data FROM blocks WHERE cid = ? AND did = ?";
    sqlite3_stmt *stmt = [self prepareStatement:sql error:error];
    if (!stmt) return nil;
    
    sqlite3_bind_text(stmt, 1, cid.stringValue.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, did.UTF8String, -1, SQLITE_TRANSIENT);
    
    NSData *data = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        const void *bytes = sqlite3_column_blob(stmt, 0);
        int length = sqlite3_column_bytes(stmt, 0);
        if (bytes && length > 0) {
            data = [NSData dataWithBytes:bytes length:length];
        }
    }
    
    sqlite3_finalize(stmt);
    return data;
}
```

## Transactions

```objc
- (BOOL)inTransaction:(BOOL (^)(NSError **error))block error:(NSError **)error {
    if (![self executeSQL:@"BEGIN TRANSACTION" error:error]) {
        return NO;
    }
    
    BOOL success = block(error);
    
    if (success) {
        return [self executeSQL:@"COMMIT" error:error];
    } else {
        [self executeSQL:@"ROLLBACK" error:nil];
        return NO;
    }
}

// Usage:
[db inTransaction:^BOOL(NSError **error) {
    if (![self storeBlock:block1 withCID:cid1 forDID:did error:error]) return NO;
    if (![self storeBlock:block2 withCID:cid2 forDID:did error:error]) return NO;
    return YES;
} error:&error];
```

## The SQLite Lifecycle

Understanding the pattern for every database operation:

```
┌─────────────────────────────────────────────────────────────┐
│                    SQLite Operation Flow                    │
├─────────────────────────────────────────────────────────────┤
│  1. Prepare Statement   →   sqlite3_prepare_v2()            │
│  2. Bind Parameters     →   sqlite3_bind_*()                │
│  3. Execute             →   sqlite3_step()                  │
│  4. Read Results        →   sqlite3_column_*() (if SELECT)  │
│  5. Clean Up            →   sqlite3_finalize()              │
└─────────────────────────────────────────────────────────────┘
```

**Memory ownership rules:**
- `sqlite3_prepare_v2()` allocates statement memory → you must `sqlite3_finalize()`
- `sqlite3_column_text/blob()` returns pointers to internal storage → copy data before `finalize()`

---

## Common Mistakes

### Mistake 1: Forgetting to Finalize Statements

❌ **What people do:**
```objc
- (NSString *)getHandle:(NSString *)did {
    sqlite3_stmt *stmt = [self prepareStatement:sql error:nil];
    sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);
    
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        return @((const char *)sqlite3_column_text(stmt, 0));
    }
    return nil;  // LEAKED! Never called finalize
}
```

**Why this fails:**
- Each unfinalizestatement leaks memory
- Eventually exhausts database resources
- May cause "too many open statements" errors

✅ **Correct approach:**
```objc
- (NSString *)getHandle:(NSString *)did {
    sqlite3_stmt *stmt = [self prepareStatement:sql error:nil];
    sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);
    
    NSString *handle = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        handle = @((const char *)sqlite3_column_text(stmt, 0));
    }
    sqlite3_finalize(stmt);  // ALWAYS finalize!
    return handle;
}
```

### Mistake 2: String Interpolation Instead of Binding

❌ **What people do:**
```objc
// SQL INJECTION VULNERABILITY!
NSString *sql = [NSString stringWithFormat:
    @"SELECT * FROM accounts WHERE handle = '%@'", userInput];
sqlite3_exec(_db, sql.UTF8String, NULL, NULL, NULL);
```

**Why this fails:**
- User can input: `'; DROP TABLE accounts; --`
- Allows arbitrary SQL execution
- Security nightmare

✅ **Correct approach:**
```objc
NSString *sql = @"SELECT * FROM accounts WHERE handle = ?";
sqlite3_stmt *stmt = [self prepareStatement:sql error:nil];
sqlite3_bind_text(stmt, 1, userInput.UTF8String, -1, SQLITE_TRANSIENT);
// Parameters are escaped automatically
```

### Mistake 3: Reading Column Data After Finalize

❌ **What people do:**
```objc
const char *text = NULL;
if (sqlite3_step(stmt) == SQLITE_ROW) {
    text = (const char *)sqlite3_column_text(stmt, 0);
}
sqlite3_finalize(stmt);
NSString *result = @(text);  // CRASH: text pointer is invalid!
```

**Why this fails:**
- `sqlite3_column_*` returns pointers to internal SQLite storage
- After `finalize()`, that memory is freed
- Results in use-after-free crash

✅ **Correct approach:**
```objc
NSString *result = nil;
if (sqlite3_step(stmt) == SQLITE_ROW) {
    const char *text = (const char *)sqlite3_column_text(stmt, 0);
    if (text) {
        result = @(text);  // Copy BEFORE finalize
    }
}
sqlite3_finalize(stmt);
return result;  // Safe: we own this NSString
```

---

<script setup>
const mockSQLiteCode = `#import <Foundation/Foundation.h>

// --- Mock SQLite C API ---

typedef void* sqlite3;
typedef void* sqlite3_stmt;
#define SQLITE_OK 0
#define SQLITE_ROW 100
#define SQLITE_DONE 101
#define SQLITE_TRANSIENT (void*)-1

// Mock State
static NSString *lastPreparedSQL = nil;
static NSMutableDictionary *currentBindings = nil;

int sqlite3_prepare_v2(sqlite3 *db, const char *zSql, int nByte, sqlite3_stmt **ppStmt, const char **pzTail) {
    lastPreparedSQL = @(zSql);
    currentBindings = [NSMutableDictionary dictionary];
    *ppStmt = (void*)123; // Fake pointer
    return SQLITE_OK;
}

int sqlite3_bind_text(sqlite3_stmt* stmt, int idx, const char* val, int len, void(*d)(void*)) {
    if (val) currentBindings[@(idx)] = @(val);
    return SQLITE_OK;
}

int sqlite3_bind_int(sqlite3_stmt* stmt, int idx, int val) {
    currentBindings[@(idx)] = @(val);
    return SQLITE_OK;
}

int sqlite3_step(sqlite3_stmt* stmt) {
    return SQLITE_DONE;
}

int sqlite3_finalize(sqlite3_stmt* stmt) {
    return SQLITE_OK;
}

int sqlite3_changes(sqlite3 *db) {
    return 1; // Simulate 1 row changed
}

// Helper for Mock DB Class
@interface PDSDatabase : NSObject {
    sqlite3 *_db;
}
- (sqlite3_stmt *)prepareStatement:(NSString *)sql error:(NSError **)error;
@end

@implementation PDSDatabase
- (instancetype)init { if(self=[super init]) _db = (void*)1; return self; }
- (sqlite3_stmt *)prepareStatement:(NSString *)sql error:(NSError **)error {
    sqlite3_stmt *stmt = NULL;
    sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    return stmt;
}
@end
`;

const exercise1Code = mockSQLiteCode + `
// --- EXERCISE 1: Update Handle ---

@implementation PDSDatabase (Exercise1)
- (BOOL)updateHandle:(NSString *)newHandle forDID:(NSString *)did error:(NSError **)error {
    // TODO: Write SQL: "UPDATE accounts SET handle = ? WHERE did = ?"
    // Prepare, Bind (1=handle, 2=did), Step, Finalize
    
    // Example:
    // NSString *sql = @"...";
    // sqlite3_stmt *stmt = [self prepareStatement:sql error:error];
    // ...
    // sqlite3_finalize(stmt);
    
    return NO;
}
@end

void runDemo() {
    PDSDatabase *db = [PDSDatabase new];
    [db updateHandle:@"bob.bsky.social" forDID:@"did:plc:123" error:nil];
    
    printf("SQL: %s\\n", lastPreparedSQL.UTF8String);
    printf("Bind 1: %s\\n", [currentBindings[@1] UTF8String]);
    printf("Bind 2: %s\\n", [currentBindings[@2] UTF8String]);
    
    if ([lastPreparedSQL containsString:@"UPDATE accounts"] && 
        [currentBindings[@1] isEqualToString:@"bob.bsky.social"]) {
        printf("PASS: Correct SQL and bindings.\\n");
    } else {
        printf("FAIL.\\n");
    }
}

int main() {
    @autoreleasepool {
        runDemo();
    }
    return 0;
}`;

const exercise2Code = mockSQLiteCode + `
// --- EXERCISE 2: Block Count ---

@implementation PDSDatabase (Exercise2)
- (NSInteger)blockCountForDID:(NSString *)did {
    // TODO: Select Count ("SELECT COUNT(*) FROM blocks WHERE did = ?")
    // Bind DID to 1
    // Step, if SQLITE_ROW, read column 0 (mocked return 0 for now)
    
    return 0;
}
@end

void runDemo() {
    PDSDatabase *db = [PDSDatabase new];
    [db blockCountForDID:@"did:plc:123"];
    
    printf("SQL: %s\\n", lastPreparedSQL.UTF8String);
    if ([lastPreparedSQL containsString:@"SELECT COUNT(*)"] && 
        [lastPreparedSQL containsString:@"blocks"]) {
        printf("PASS: Correct SQL.\\n");
    } else {
        printf("FAIL.\\n");
    }
}

int main() {
    @autoreleasepool {
        runDemo();
    }
    return 0;
}`;

const exercise3Code = mockSQLiteCode + `
// --- EXERCISE 3: Pagination ---

@implementation PDSDatabase (Exercise3)
- (void)listRecords:(NSString *)did {
    // TODO: Just write the SQL string for "WHERE rkey > cursor"
    // To simplify: we'll check if your SQL includes cursor logic.
    NSString *sql = @"SELECT * FROM records WHERE did = ? AND collection = ? AND rkey > ? ORDER BY rkey ASC LIMIT ?";
    
    // Call prepare (mocking the check)
    [self prepareStatement:sql error:nil];
}
@end

void runDemo() {
    PDSDatabase *db = [PDSDatabase new];
    [db listRecords:@"did:plc:123"];
    
    printf("SQL: %s\\n", lastPreparedSQL.UTF8String);
    if ([lastPreparedSQL containsString:@"rkey > ?"] && 
        [lastPreparedSQL containsString:@"ORDER BY rkey"]) {
        printf("PASS: Correct pagination clauses.\\n");
    } else {
        printf("FAIL.\\n");
    }
}

int main() {
    @autoreleasepool {
        runDemo();
    }
    return 0;
}`;
</script>

```objc
- (BOOL)updateHandle:(NSString *)newHandle 
              forDID:(NSString *)did 
               error:(NSError **)error;
```

- Hint: Use `UPDATE accounts SET handle = ? WHERE did = ?`
- Bonus: Return NO if no rows were affected (DID doesn't exist)

<ObjcRunner :initialCode="exercise1Code" />


📝 **Exercise 2: Implement Block Count**

Write a method to count blocks for a specific DID:

<ObjcRunner :initialCode="exercise2Code" />


📝 **Exercise 3: Add Record Listing with Pagination**

Implement paginated record listing:

<ObjcRunner :initialCode="exercise3Code" />


---

## Visual Reference: Bind Parameter Types

| Function | Parameter Type | Objective-C Type |
|----------|---------------|------------------|
| `sqlite3_bind_text` | String | `NSString.UTF8String` |
| `sqlite3_bind_blob` | Binary data | `NSData.bytes` |
| `sqlite3_bind_int` | 32-bit integer | `int`, `NSInteger` (32-bit) |
| `sqlite3_bind_int64` | 64-bit integer | `int64_t`, `NSInteger` (64-bit) |
| `sqlite3_bind_double` | Floating point | `double` |
| `sqlite3_bind_null` | NULL value | `nil` (conceptually) |

**The SQLITE_TRANSIENT flag:**
- Tells SQLite to make its own copy of the data
- Safe for temporary strings (like `UTF8String` on stack)
- Alternative: `SQLITE_STATIC` if you guarantee data lifetime

---

## Summary

In this chapter, you learned:

- ✅ **SQLite C API:** `prepare_v2` → `bind_*` → `step` → `column_*` → `finalize`
- ✅ **Database setup:** Opening connections and enabling WAL mode
- ✅ **Schema migrations:** `CREATE TABLE IF NOT EXISTS` for safe evolution
- ✅ **Prepared statements:** Parameterized queries prevent SQL injection
- ✅ **CRUD operations:** Insert, select, update patterns for accounts/blocks
- ✅ **Transactions:** `BEGIN`/`COMMIT`/`ROLLBACK` for atomic operations

## Key Takeaways

1. **Always finalize statements** - Memory leaks accumulate silently until they don't.

2. **Never interpolate user input into SQL** - Always use parameter binding with `sqlite3_bind_*`.

3. **Copy column data before finalizing** - SQLite owns that memory until you copy it.

## Looking Ahead

With persistence in place, we have all the building blocks for a complete PDS:
- **Identity** (Chapters 9-10): DIDs and PLC operations
- **Storage** (Chapters 5-7): CBOR, MST, CAR files
- **Authentication** (Chapter 14): OAuth and JWT
- **Persistence** (this chapter): SQLite database

In **Chapter 14**, we'll implement **OAuth 2.1 and JWT authentication**—the security layer that protects all these operations.

---

**Files Referenced in This Chapter:**
- [PDSDatabase.h](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Database/PDSDatabase.h)
- [PDSDatabase.m](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Database/PDSDatabase.m)
