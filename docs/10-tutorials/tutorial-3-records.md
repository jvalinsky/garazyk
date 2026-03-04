---
title: "Tutorial 3: Record Operations"
---

# Tutorial 3: Record Operations

## Overview

In this tutorial, you'll extend the PDS from Tutorial 2 to support record CRUD operations (Create, Read, Update, Delete) with proper content addressing and persistence. This is where your PDS becomes truly functional—able to store and retrieve user data in the AT Protocol's decentralized architecture.

By the end of this tutorial, you'll have a working implementation of the core repository protocol endpoints that allow clients to create posts, retrieve them, list collections, and delete records. You'll understand how AT URIs work, how content identifiers (CIDs) provide cryptographic verification, and how records are organized in collections.

### What You'll Build

A fully functional record management system that:
- Creates records with AT URIs and CIDs
- Stores records in SQLite with proper indexing
- Retrieves individual records by URI
- Lists records within collections with pagination
- Deletes records with authorization checks
- Generates content identifiers for data integrity

This tutorial bridges the gap between account management (Tutorial 2) and authentication (Tutorial 4). You'll implement the data layer that makes social applications possible on AT Protocol.

**Learning Objectives:**
- Implement the four core XRPC repository endpoints
- Understand AT URI structure and semantics
- Generate CIDs for content addressing
- Design efficient database schemas for records
- Handle JSON serialization and deserialization
- Parse and validate JWT tokens for authorization
- Implement proper error handling for record operations

**Estimated Time:** 60-75 minutes

## Prerequisites

Before starting this tutorial, you should have:

- **Completed Tutorials:**
  - [Tutorial 1: Hello PDS](tutorial-1-hello-pds) — Basic server setup
  - [Tutorial 2: Account Management](tutorial-2-accounts) — Account creation and JWT minting
  
- **Knowledge:**
  - Understanding of AT URIs and their components
  - Familiarity with content addressing concepts
  - Basic SQL and database design
  - Understanding of RESTful API patterns
  
- **Recommended Reading:**
  - [MST Trees](../02-core-concepts/mst-trees) — Merkle Search Tree fundamentals
  - [CBOR and CAR](../02-core-concepts/cbor-and-car) — Serialization formats
  - [Record Service](../03-application-layer/record-service) — Production patterns
  - [Repository Basics](../07-repository-protocol/repository-basics) — Protocol specification

## Step 1: Create Record Data Model

The Record model is the foundation of your data layer. It represents a single piece of content in the AT Protocol network—a post, a like, a follow, or any other user-generated data.

Create `src/Record.h`:

```objc
#import <Foundation/Foundation.h>

@interface Record : NSObject

@property (nonatomic, copy) NSString *uri;
@property (nonatomic, copy) NSString *cid;
@property (nonatomic, copy) NSDictionary *value;
@property (nonatomic, assign) NSTimeInterval createdAt;

@end
```objc

### Understanding the Record Model

**The `uri` property** is the record's unique identifier in AT Protocol. It follows the format `at://<did>/<collection>/<rkey>`, where:
- `did` — The DID of the repository owner
- `collection` — The NSID of the record type (e.g., `app.bsky.feed.post`)
- `rkey` — The record key, a unique identifier within the collection

**The `cid` property** is a Content Identifier—a cryptographic hash of the record's content. CIDs enable:
- **Content verification** — Detect if data has been tampered with
- **Deduplication** — Identify identical content across the network
- **Merkle tree construction** — Build verifiable data structures

**The `value` property** holds the actual record data as a dictionary. In production, this would be CBOR-encoded, but we're using JSON for simplicity. The value contains application-specific fields like post text, timestamps, or media references.

**The `createdAt` property** tracks when the record was created. Using `NSTimeInterval` (seconds since Unix epoch) makes it easy to sort records chronologically and implement pagination.

### Why This Design?

This model separates identity (`uri`), integrity (`cid`), and content (`value`). This separation is fundamental to AT Protocol's architecture—it allows records to be verified, replicated, and referenced independently of their storage location.

## Step 2: Create Record Repository

The repository layer handles all database interactions for records. It abstracts SQLite operations behind a clean interface, making it easy to swap storage backends later if needed.

Create `src/RecordRepository.h`:

```objc
#import <Foundation/Foundation.h>
#import "Record.h"

@interface RecordRepository : NSObject

- (instancetype)initWithDatabasePath:(NSString *)path;
- (BOOL)saveRecord:(Record *)record forDid:(NSString *)did error:(NSError **)error;
- (nullable Record *)getRecordAtURI:(NSString *)uri forDid:(NSString *)did error:(NSError **)error;
- (nullable NSArray<Record *> *)listRecords:(NSString *)collection forDid:(NSString *)did limit:(NSUInteger)limit error:(NSError **)error;
- (BOOL)deleteRecordAtURI:(NSString *)uri forDid:(NSString *)did error:(NSError **)error;

@end
```objc

### Understanding the Repository Interface

**The `initWithDatabasePath:` method** sets up the SQLite database. Taking a path parameter makes testing easier—you can use temporary directories for tests and a persistent location for production.

**The `saveRecord:forDid:error:` method** implements "upsert" semantics—insert if new, update if exists. This is crucial for AT Protocol's eventual consistency model, where records might be synced multiple times.

**The `getRecordAtURI:forDid:error:` method** retrieves a single record. The `forDid:` parameter ensures users can only access their own records (in this simplified version). Production systems would implement more sophisticated access control.

**The `listRecords:collection:forDid:limit:error:` method** supports pagination with the `limit` parameter. This prevents memory exhaustion when users have thousands of records. The method returns records in reverse chronological order (newest first), which is what most social applications need.

**The `deleteRecordAtURI:forDid:error:` method** permanently removes a record. In production, you might implement soft deletes (marking records as deleted without removing them) to support sync protocols.

### Why This Abstraction?

Separating the repository layer from business logic (the service layer) follows the Repository Pattern. This makes your code:
- **Testable** — Mock the repository for unit tests
- **Maintainable** — Change storage without touching business logic
- **Flexible** — Support multiple storage backends (SQLite, PostgreSQL, etc.)

## Step 3: Implement Record Repository

Now let's implement the repository with SQLite. This is where we handle the nitty-gritty of database operations, prepared statements, and error handling.

Create `src/RecordRepository.m`:

```objc
#import "RecordRepository.h"
#import <sqlite3.h>

@interface RecordRepository ()
@property (nonatomic, assign) sqlite3 *database;
@end

@implementation RecordRepository

- (instancetype)initWithDatabasePath:(NSString *)path {
    self = [super init];
    if (!self) return nil;
    
    NSString *dbPath = [path stringByAppendingPathComponent:@"records.db"];
    int rc = sqlite3_open([dbPath UTF8String], &_database);
    
    if (rc != SQLITE_OK) {
        NSLog(@"Failed to open database: %s", sqlite3_errmsg(_database));
        return nil;
    }
    
    [self createTablesIfNeeded];
    
    return self;
}

- (void)createTablesIfNeeded {
    const char *sql = "CREATE TABLE IF NOT EXISTS records ("
        "uri TEXT PRIMARY KEY,"
        "did TEXT NOT NULL,"
        "collection TEXT NOT NULL,"
        "rkey TEXT NOT NULL,"
        "cid TEXT NOT NULL,"
        "value TEXT NOT NULL,"
        "created_at REAL NOT NULL,"
        "UNIQUE(did, collection, rkey)"
        ");";
    
    char *errMsg = NULL;
    int rc = sqlite3_exec(_database, sql, NULL, NULL, &errMsg);
    
    if (rc != SQLITE_OK) {
        NSLog(@"Failed to create table: %s", errMsg);
        sqlite3_free(errMsg);
    }
}

- (BOOL)saveRecord:(Record *)record forDid:(NSString *)did error:(NSError **)error {
    // Parse URI to extract collection and rkey
    NSArray *parts = [record.uri componentsSeparatedByString:@"/"];
    if (parts.count < 4) {
        if (error) {
            *error = [NSError errorWithDomain:@"Record" code:1 
                userInfo:@{NSLocalizedDescriptionKey: @"Invalid URI format"}];
        }
        return NO;
    }
    
    NSString *collection = parts[parts.count - 2];
    NSString *rkey = parts[parts.count - 1];
    
    // Serialize value to JSON
    NSData *valueData = [NSJSONSerialization dataWithJSONObject:record.value options:0 error:error];
    if (!valueData) return NO;
    
    NSString *valueJson = [[NSString alloc] initWithData:valueData encoding:NSUTF8StringEncoding];
    
    const char *sql = "INSERT OR REPLACE INTO records "
        "(uri, did, collection, rkey, cid, value, created_at) "
        "VALUES (?, ?, ?, ?, ?, ?, ?)";
    
    sqlite3_stmt *stmt;
    int rc = sqlite3_prepare_v2(_database, sql, -1, &stmt, NULL);
    
    if (rc != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:@"Database" code:rc userInfo:nil];
        }
        return NO;
    }
    
    sqlite3_bind_text(stmt, 1, [record.uri UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, [did UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 3, [collection UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 4, [rkey UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 5, [record.cid UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 6, [valueJson UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_double(stmt, 7, record.createdAt);
    
    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    
    if (rc != SQLITE_DONE) {
        if (error) {
            *error = [NSError errorWithDomain:@"Database" code:rc userInfo:nil];
        }
        return NO;
    }
    
    return YES;
}

- (nullable Record *)getRecordAtURI:(NSString *)uri forDid:(NSString *)did error:(NSError **)error {
    const char *sql = "SELECT uri, cid, value, created_at FROM records WHERE uri = ? AND did = ?";
    
    sqlite3_stmt *stmt;
    int rc = sqlite3_prepare_v2(_database, sql, -1, &stmt, NULL);
    
    if (rc != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:@"Database" code:rc userInfo:nil];
        }
        return nil;
    }
    
    sqlite3_bind_text(stmt, 1, [uri UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, [did UTF8String], -1, SQLITE_TRANSIENT);
    
    Record *record = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        record = [[Record alloc] init];
        record.uri = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 0)];
        record.cid = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 1)];
        
        NSString *valueJson = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 2)];
        NSData *valueData = [valueJson dataUsingEncoding:NSUTF8StringEncoding];
        record.value = [NSJSONSerialization JSONObjectWithData:valueData options:0 error:nil];
        
        record.createdAt = sqlite3_column_double(stmt, 3);
    }
    
    sqlite3_finalize(stmt);
    return record;
}

- (nullable NSArray<Record *> *)listRecords:(NSString *)collection 
                                     forDid:(NSString *)did 
                                      limit:(NSUInteger)limit 
                                      error:(NSError **)error {
    const char *sql = "SELECT uri, cid, value, created_at FROM records "
        "WHERE did = ? AND collection = ? ORDER BY created_at DESC LIMIT ?";
    
    sqlite3_stmt *stmt;
    int rc = sqlite3_prepare_v2(_database, sql, -1, &stmt, NULL);
    
    if (rc != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:@"Database" code:rc userInfo:nil];
        }
        return nil;
    }
    
    sqlite3_bind_text(stmt, 1, [did UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, [collection UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_int64(stmt, 3, limit);
    
    NSMutableArray *records = [NSMutableArray array];
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        Record *record = [[Record alloc] init];
        record.uri = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 0)];
        record.cid = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 1)];
        
        NSString *valueJson = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 2)];
        NSData *valueData = [valueJson dataUsingEncoding:NSUTF8StringEncoding];
        record.value = [NSJSONSerialization JSONObjectWithData:valueData options:0 error:nil];
        
        record.createdAt = sqlite3_column_double(stmt, 3);
        [records addObject:record];
    }
    
    sqlite3_finalize(stmt);
    return records;
}

- (BOOL)deleteRecordAtURI:(NSString *)uri forDid:(NSString *)did error:(NSError **)error {
    const char *sql = "DELETE FROM records WHERE uri = ? AND did = ?";
    
    sqlite3_stmt *stmt;
    int rc = sqlite3_prepare_v2(_database, sql, -1, &stmt, NULL);
    
    if (rc != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:@"Database" code:rc userInfo:nil];
        }
        return NO;
    }
    
    sqlite3_bind_text(stmt, 1, [uri UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, [did UTF8String], -1, SQLITE_TRANSIENT);
    
    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    
    if (rc != SQLITE_DONE) {
        if (error) {
            *error = [NSError errorWithDomain:@"Database" code:rc userInfo:nil];
        }
        return NO;
    }
    
    return YES;
}

- (void)dealloc {
    if (_database) {
        sqlite3_close(_database);
    }
}

@end
```objc

### Understanding the Implementation

**Database initialization** uses `sqlite3_open()` to create or open the database file. The `CREATE TABLE IF NOT EXISTS` pattern ensures the schema exists without failing if the table already exists—essential for applications that restart frequently during development.

**The schema design** includes several important features:
- `uri TEXT PRIMARY KEY` — Ensures each record is unique
- `UNIQUE(did, collection, rkey)` — Prevents duplicate records within a collection
- `created_at REAL` — Enables chronological sorting
- Separate `collection` and `rkey` columns — Allows efficient queries by collection

**Prepared statements** (`sqlite3_prepare_v2`) protect against SQL injection and improve performance. The `SQLITE_TRANSIENT` flag tells SQLite to copy the string data immediately, which is necessary because Objective-C strings might be deallocated before SQLite uses them.

**URI parsing** extracts the collection and rkey from the AT URI. The format is `at://<did>/<collection>/<rkey>`, so we split on `/` and take the last two components. This is simplified—production code would use a proper URI parser.

**JSON serialization** converts the record value dictionary to a string for storage. Using `NSJSONSerialization` ensures proper escaping and encoding. In production, you'd use CBOR encoding for efficiency and spec compliance.

**Error handling** follows Objective-C conventions: return `NO`/`nil` on failure and populate the `error` parameter with details. Always check return codes from SQLite functions—database operations can fail for many reasons (disk full, permissions, corruption).

**The `dealloc` method** closes the database connection when the repository is deallocated. This is crucial for preventing file descriptor leaks in long-running servers.

### Common Pitfalls

**Not finalizing statements** — Always call `sqlite3_finalize()` even if the query fails. Failing to finalize leaks memory and can prevent the database from closing properly.

**Ignoring return codes** — SQLite functions return error codes for a reason. Check them! Silent failures lead to data corruption and hard-to-debug issues.

**Using string concatenation for SQL** — Never build SQL queries with string concatenation. Always use prepared statements with parameter binding to prevent SQL injection.

**Storing binary data as text** — We're using JSON for simplicity, but production systems should use BLOB columns for CBOR-encoded data to avoid encoding overhead.

```objc
#import "RecordRepository.h"
#import <sqlite3.h>

@interface RecordRepository ()
@property (nonatomic, assign) sqlite3 *database;
@end

@implementation RecordRepository

- (instancetype)initWithDatabasePath:(NSString *)path {
    self = [super init];
    if (!self) return nil;
    
    NSString *dbPath = [path stringByAppendingPathComponent:@"records.db"];
    int rc = sqlite3_open([dbPath UTF8String], &_database);
    
    if (rc != SQLITE_OK) {
        NSLog(@"Failed to open database: %s", sqlite3_errmsg(_database));
        return nil;
    }
    
    [self createTablesIfNeeded];
    
    return self;
}

- (void)createTablesIfNeeded {
    const char *sql = "CREATE TABLE IF NOT EXISTS records ("
        "uri TEXT PRIMARY KEY,"
        "did TEXT NOT NULL,"
        "collection TEXT NOT NULL,"
        "rkey TEXT NOT NULL,"
        "cid TEXT NOT NULL,"
        "value TEXT NOT NULL,"
        "created_at REAL NOT NULL,"
        "UNIQUE(did, collection, rkey)"
        ");";
    
    char *errMsg = NULL;
    int rc = sqlite3_exec(_database, sql, NULL, NULL, &errMsg);
    
    if (rc != SQLITE_OK) {
        NSLog(@"Failed to create table: %s", errMsg);
        sqlite3_free(errMsg);
    }
}

- (BOOL)saveRecord:(Record *)record forDid:(NSString *)did error:(NSError **)error {
    // Parse URI to extract collection and rkey
    NSArray *parts = [record.uri componentsSeparatedByString:@"/"];
    if (parts.count < 4) {
        if (error) {
            *error = [NSError errorWithDomain:@"Record" code:1 
                userInfo:@{NSLocalizedDescriptionKey: @"Invalid URI format"}];
        }
        return NO;
    }
    
    NSString *collection = parts[parts.count - 2];
    NSString *rkey = parts[parts.count - 1];
    
    // Serialize value to JSON
    NSData *valueData = [NSJSONSerialization dataWithJSONObject:record.value options:0 error:error];
    if (!valueData) return NO;
    
    NSString *valueJson = [[NSString alloc] initWithData:valueData encoding:NSUTF8StringEncoding];
    
    const char *sql = "INSERT OR REPLACE INTO records "
        "(uri, did, collection, rkey, cid, value, created_at) "
        "VALUES (?, ?, ?, ?, ?, ?, ?)";
    
    sqlite3_stmt *stmt;
    int rc = sqlite3_prepare_v2(_database, sql, -1, &stmt, NULL);
    
    if (rc != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:@"Database" code:rc userInfo:nil];
        }
        return NO;
    }
    
    sqlite3_bind_text(stmt, 1, [record.uri UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, [did UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 3, [collection UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 4, [rkey UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 5, [record.cid UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 6, [valueJson UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_double(stmt, 7, record.createdAt);
    
    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    
    if (rc != SQLITE_DONE) {
        if (error) {
            *error = [NSError errorWithDomain:@"Database" code:rc userInfo:nil];
        }
        return NO;
    }
    
    return YES;
}

- (nullable Record *)getRecordAtURI:(NSString *)uri forDid:(NSString *)did error:(NSError **)error {
    const char *sql = "SELECT uri, cid, value, created_at FROM records WHERE uri = ? AND did = ?";
    
    sqlite3_stmt *stmt;
    int rc = sqlite3_prepare_v2(_database, sql, -1, &stmt, NULL);
    
    if (rc != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:@"Database" code:rc userInfo:nil];
        }
        return nil;
    }
    
    sqlite3_bind_text(stmt, 1, [uri UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, [did UTF8String], -1, SQLITE_TRANSIENT);
    
    Record *record = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        record = [[Record alloc] init];
        record.uri = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 0)];
        record.cid = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 1)];
        
        NSString *valueJson = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 2)];
        NSData *valueData = [valueJson dataUsingEncoding:NSUTF8StringEncoding];
        record.value = [NSJSONSerialization JSONObjectWithData:valueData options:0 error:nil];
        
        record.createdAt = sqlite3_column_double(stmt, 3);
    }
    
    sqlite3_finalize(stmt);
    return record;
}

- (nullable NSArray<Record *> *)listRecords:(NSString *)collection 
                                     forDid:(NSString *)did 
                                      limit:(NSUInteger)limit 
                                      error:(NSError **)error {
    const char *sql = "SELECT uri, cid, value, created_at FROM records "
        "WHERE did = ? AND collection = ? ORDER BY created_at DESC LIMIT ?";
    
    sqlite3_stmt *stmt;
    int rc = sqlite3_prepare_v2(_database, sql, -1, &stmt, NULL);
    
    if (rc != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:@"Database" code:rc userInfo:nil];
        }
        return nil;
    }
    
    sqlite3_bind_text(stmt, 1, [did UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, [collection UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_int64(stmt, 3, limit);
    
    NSMutableArray *records = [NSMutableArray array];
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        Record *record = [[Record alloc] init];
        record.uri = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 0)];
        record.cid = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 1)];
        
        NSString *valueJson = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 2)];
        NSData *valueData = [valueJson dataUsingEncoding:NSUTF8StringEncoding];
        record.value = [NSJSONSerialization JSONObjectWithData:valueData options:0 error:nil];
        
        record.createdAt = sqlite3_column_double(stmt, 3);
        [records addObject:record];
    }
    
    sqlite3_finalize(stmt);
    return records;
}

- (BOOL)deleteRecordAtURI:(NSString *)uri forDid:(NSString *)did error:(NSError **)error {
    const char *sql = "DELETE FROM records WHERE uri = ? AND did = ?";
    
    sqlite3_stmt *stmt;
    int rc = sqlite3_prepare_v2(_database, sql, -1, &stmt, NULL);
    
    if (rc != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:@"Database" code:rc userInfo:nil];
        }
        return NO;
    }
    
    sqlite3_bind_text(stmt, 1, [uri UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, [did UTF8String], -1, SQLITE_TRANSIENT);
    
    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    
    if (rc != SQLITE_DONE) {
        if (error) {
            *error = [NSError errorWithDomain:@"Database" code:rc userInfo:nil];
        }
        return NO;
    }
    
    return YES;
}

- (void)dealloc {
    if (_database) {
        sqlite3_close(_database);
    }
}

@end
```objc

## Step 4: Create CID Generator

Content Identifiers (CIDs) are the backbone of AT Protocol's content addressing system. They provide cryptographic proof that data hasn't been tampered with and enable efficient deduplication across the network.

Create `src/SimpleCIDGenerator.h`:

```objc
#import <Foundation/Foundation.h>

@interface SimpleCIDGenerator : NSObject

+ (NSString *)generateCIDForData:(NSData *)data;
+ (NSString *)generateCIDForJSON:(NSDictionary *)json;

@end
```objc

### Understanding CID Generation

**The `generateCIDForData:` method** takes raw bytes and produces a CID. This is the fundamental operation—all content addressing starts with hashing binary data.

**The `generateCIDForJSON:` method** is a convenience wrapper that serializes a dictionary to JSON, then generates a CID. This is what we'll use for record values in this tutorial.

### Why CIDs Matter

CIDs enable several critical features:
- **Integrity verification** — Detect if records have been modified
- **Content deduplication** — Identify identical records across repositories
- **Merkle tree construction** — Build verifiable data structures (MSTs)
- **Efficient sync** — Only transfer records that have changed

In production AT Protocol systems, CIDs are used everywhere: records, commits, blobs, and even DID documents all have CIDs.

## Step 5: Implement CID Generator

This implementation uses SHA-256 hashing with a simplified base32 encoding. Production systems use proper CIDv1 encoding with multibase, multihash, and multicodec prefixes.

Create `src/SimpleCIDGenerator.m`:

```objc
#import "SimpleCIDGenerator.h"
#import <CommonCrypto/CommonDigest.h>

@implementation SimpleCIDGenerator

+ (NSString *)generateCIDForData:(NSData *)data {
    // SHA-256 hash
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    
    // Convert to base32 (simplified - in production use proper CID encoding)
    NSMutableString *cid = [NSMutableString stringWithString:@"bafyrei"];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [cid appendFormat:@"%02x", digest[i]];
    }
    
    return cid;
}

+ (NSString *)generateCIDForJSON:(NSDictionary *)json {
    NSData *data = [NSJSONSerialization dataWithJSONObject:json options:NSJSONWritingSortedKeys error:nil];
    return [self generateCIDForData:data];
}

@end
```objc

### Understanding the Implementation

**SHA-256 hashing** is performed by CommonCrypto's `CC_SHA256()` function. This produces a 32-byte (256-bit) cryptographic hash of the input data. SHA-256 is collision-resistant, meaning it's computationally infeasible to find two different inputs that produce the same hash.

**The `bafyrei` prefix** is a simplified version of the CIDv1 multibase prefix. In production:
- `b` indicates base32 encoding
- `afy` is the multicodec for dag-pb (though we should use dag-cbor)
- `rei` would be followed by the actual base32-encoded hash

**Hexadecimal encoding** (`%02x`) converts each byte to two hex characters. This is simpler than proper base32 encoding but less efficient (64 characters vs 52 for base32).

**Sorted keys** (`NSJSONWritingSortedKeys`) ensures deterministic serialization. Without this, the same dictionary could serialize differently on different runs, producing different CIDs for identical content. This is crucial for content addressing!

### Production Considerations

Real AT Protocol implementations must:
- Use **DAG-CBOR encoding** instead of JSON for canonical serialization
- Implement **proper CIDv1 format** with multibase/multihash/multicodec
- Use **base32** encoding for URL-safe, case-insensitive identifiers
- Support **CID validation** to detect malformed or invalid CIDs

The September PDS production code uses the `CID` class in `ATProtoPDS/Sources/Core/` which implements the full specification.

### Common Pitfalls

**Non-deterministic serialization** — If you don't sort JSON keys, the same data can produce different CIDs. Always use `NSJSONWritingSortedKeys` or switch to CBOR.

**Wrong hash function** — AT Protocol specifies SHA-256. Don't use MD5, SHA-1, or other hash functions.

**Encoding mistakes** — CIDs must be URL-safe. Hexadecimal works but is inefficient. Base32 is the standard.

## Step 6: Create Record Service

The service layer sits between the HTTP endpoints and the repository. It implements business logic: validation, URI generation, CID computation, and authorization checks.

Create `src/RecordService.h`:

```objc
#import <Foundation/Foundation.h>
#import "Record.h"
#import "RecordRepository.h"

@interface RecordService : NSObject

- (instancetype)initWithRepository:(RecordRepository *)repository;

- (nullable NSDictionary *)createRecord:(NSString *)collection
                                   rkey:(NSString *)rkey
                                  value:(NSDictionary *)value
                                 forDid:(NSString *)did
                                  error:(NSError **)error;

- (nullable NSDictionary *)getRecord:(NSString *)uri
                              forDid:(NSString *)did
                               error:(NSError **)error;

- (nullable NSArray *)listRecords:(NSString *)collection
                           forDid:(NSString *)did
                            limit:(NSUInteger)limit
                            error:(NSError **)error;

- (BOOL)deleteRecord:(NSString *)uri
              forDid:(NSString *)did
               error:(NSError **)error;

@end
```objc

### Understanding the Service Layer

**Dependency injection** — The service takes a repository in its initializer. This makes testing easy: inject a mock repository to test business logic without touching the database.

**Return types** — Methods return dictionaries instead of Record objects. This matches the XRPC response format and makes serialization straightforward. The dictionaries contain `uri`, `cid`, and optionally `value`.

**The `forDid:` parameter** appears in every method. This is crucial for multi-tenant systems where one PDS hosts multiple users. The DID identifies which user's repository we're operating on.

**Error handling** — All methods that can fail take an `NSError **` parameter. This allows detailed error reporting: invalid input, database failures, authorization errors, etc.

### Why a Service Layer?

Separating business logic from HTTP handling and database access provides:
- **Testability** — Test business logic without HTTP or database
- **Reusability** — Use the same service from XRPC, CLI tools, or background jobs
- **Maintainability** — Change business rules without touching HTTP or database code
- **Security** — Centralize authorization checks in one place

## Step 7: Implement Record Service

The service implementation orchestrates URI generation, CID computation, and repository operations. This is where the AT Protocol's record model comes together.

Create `src/RecordService.m`:

```objc
#import "RecordService.h"
#import "SimpleCIDGenerator.h"

@interface RecordService ()
@property (nonatomic, strong) RecordRepository *repository;
@end

@implementation RecordService

- (instancetype)initWithRepository:(RecordRepository *)repository {
    self = [super init];
    if (!self) return nil;
    
    self.repository = repository;
    
    return self;
}

- (nullable NSDictionary *)createRecord:(NSString *)collection
                                   rkey:(NSString *)rkey
                                  value:(NSDictionary *)value
                                 forDid:(NSString *)did
                                  error:(NSError **)error {
    // Validate inputs
    if (!collection || !rkey || !value || !did) {
        if (error) {
            *error = [NSError errorWithDomain:@"Record" code:1 
                userInfo:@{NSLocalizedDescriptionKey: @"Missing required fields"}];
        }
        return nil;
    }
    
    // Generate URI
    NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];
    
    // Generate CID
    NSString *cid = [SimpleCIDGenerator generateCIDForJSON:value];
    
    // Create record
    Record *record = [[Record alloc] init];
    record.uri = uri;
    record.cid = cid;
    record.value = value;
    record.createdAt = [[NSDate date] timeIntervalSince1970];
    
    // Save record
    NSError *dbError = nil;
    if (![self.repository saveRecord:record forDid:did error:&dbError]) {
        if (error) *error = dbError;
        return nil;
    }
    
    return @{
        @"uri": uri,
        @"cid": cid
    };
}

- (nullable NSDictionary *)getRecord:(NSString *)uri
                              forDid:(NSString *)did
                               error:(NSError **)error {
    NSError *dbError = nil;
    Record *record = [self.repository getRecordAtURI:uri forDid:did error:&dbError];
    
    if (!record) {
        if (error) {
            *error = [NSError errorWithDomain:@"Record" code:2 
                userInfo:@{NSLocalizedDescriptionKey: @"Record not found"}];
        }
        return nil;
    }
    
    return @{
        @"uri": record.uri,
        @"cid": record.cid,
        @"value": record.value
    };
}

- (nullable NSArray *)listRecords:(NSString *)collection
                           forDid:(NSString *)did
                            limit:(NSUInteger)limit
                            error:(NSError **)error {
    NSError *dbError = nil;
    NSArray<Record *> *records = [self.repository listRecords:collection 
                                                       forDid:did 
                                                        limit:limit 
                                                        error:&dbError];
    
    if (!records) {
        if (error) *error = dbError;
        return nil;
    }
    
    NSMutableArray *result = [NSMutableArray array];
    for (Record *record in records) {
        [result addObject:@{
            @"uri": record.uri,
            @"cid": record.cid,
            @"value": record.value
        }];
    }
    
    return result;
}

- (BOOL)deleteRecord:(NSString *)uri
              forDid:(NSString *)did
               error:(NSError **)error {
    return [self.repository deleteRecordAtURI:uri forDid:did error:error];
}

@end
```objc

### Understanding the Service Implementation

**Input validation** happens first. Never trust input from HTTP endpoints—always validate that required fields are present and well-formed. This prevents database errors and provides clear error messages to clients.

**URI generation** follows the AT Protocol format: `at://<did>/<collection>/<rkey>`. This creates a globally unique identifier for the record. The URI is:
- **Portable** — Works across different PDS instances
- **Hierarchical** — Organizes records by owner and type
- **Resolvable** — Can be used to fetch the record from any PDS

**CID generation** happens before saving. The CID is computed from the record value, not from the URI or metadata. This ensures the CID represents the content, not the location.

**Timestamp generation** uses `[[NSDate date] timeIntervalSince1970]` to get the current Unix timestamp. This is stored as a double (NSTimeInterval) for precision and easy sorting.

**Error propagation** follows a pattern: catch errors from the repository layer, wrap them in domain-specific errors if needed, and propagate them to the caller. This provides context at each layer.

**Response formatting** converts Record objects to dictionaries. This matches the XRPC response format and makes JSON serialization trivial. The dictionaries contain only the fields clients need.

### Why This Design?

**Separation of concerns** — The service doesn't know about HTTP or SQL. It only knows about records, URIs, and CIDs. This makes it easy to:
- Test business logic independently
- Reuse the service in different contexts (HTTP, CLI, background jobs)
- Change storage or transport without touching business logic

**Explicit error handling** — Every operation that can fail returns an error. This forces callers to handle failures explicitly, preventing silent data loss.

**Immutable records** — Once created, a record's CID never changes (unless the content changes). This is fundamental to content addressing and enables efficient caching and sync.

### Common Pitfalls

**Generating CIDs after saving** — Always compute the CID before saving. If CID generation fails, you don't want a record with a missing or invalid CID in your database.

**Not validating collection NSIDs** — Production code should validate that collection names are valid NSIDs (e.g., `app.bsky.feed.post`). Invalid NSIDs can break sync and federation.

**Ignoring timestamp precision** — Using integer timestamps loses sub-second precision. Use `NSTimeInterval` (double) to preserve millisecond accuracy for ordering.

```objc
#import "RecordService.h"
#import "SimpleCIDGenerator.h"

@interface RecordService ()
@property (nonatomic, strong) RecordRepository *repository;
@end

@implementation RecordService

- (instancetype)initWithRepository:(RecordRepository *)repository {
    self = [super init];
    if (!self) return nil;
    
    self.repository = repository;
    
    return self;
}

- (nullable NSDictionary *)createRecord:(NSString *)collection
                                   rkey:(NSString *)rkey
                                  value:(NSDictionary *)value
                                 forDid:(NSString *)did
                                  error:(NSError **)error {
    // Validate inputs
    if (!collection || !rkey || !value || !did) {
        if (error) {
            *error = [NSError errorWithDomain:@"Record" code:1 
                userInfo:@{NSLocalizedDescriptionKey: @"Missing required fields"}];
        }
        return nil;
    }
    
    // Generate URI
    NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];
    
    // Generate CID
    NSString *cid = [SimpleCIDGenerator generateCIDForJSON:value];
    
    // Create record
    Record *record = [[Record alloc] init];
    record.uri = uri;
    record.cid = cid;
    record.value = value;
    record.createdAt = [[NSDate date] timeIntervalSince1970];
    
    // Save record
    NSError *dbError = nil;
    if (![self.repository saveRecord:record forDid:did error:&dbError]) {
        if (error) *error = dbError;
        return nil;
    }
    
    return @{
        @"uri": uri,
        @"cid": cid
    };
}

- (nullable NSDictionary *)getRecord:(NSString *)uri
                              forDid:(NSString *)did
                               error:(NSError **)error {
    NSError *dbError = nil;
    Record *record = [self.repository getRecordAtURI:uri forDid:did error:&dbError];
    
    if (!record) {
        if (error) {
            *error = [NSError errorWithDomain:@"Record" code:2 
                userInfo:@{NSLocalizedDescriptionKey: @"Record not found"}];
        }
        return nil;
    }
    
    return @{
        @"uri": record.uri,
        @"cid": record.cid,
        @"value": record.value
    };
}

- (nullable NSArray *)listRecords:(NSString *)collection
                           forDid:(NSString *)did
                            limit:(NSUInteger)limit
                            error:(NSError **)error {
    NSError *dbError = nil;
    NSArray<Record *> *records = [self.repository listRecords:collection 
                                                       forDid:did 
                                                        limit:limit 
                                                        error:&dbError];
    
    if (!records) {
        if (error) *error = dbError;
        return nil;
    }
    
    NSMutableArray *result = [NSMutableArray array];
    for (Record *record in records) {
        [result addObject:@{
            @"uri": record.uri,
            @"cid": record.cid,
            @"value": record.value
        }];
    }
    
    return result;
}

- (BOOL)deleteRecord:(NSString *)uri
              forDid:(NSString *)did
               error:(NSError **)error {
    return [self.repository deleteRecordAtURI:uri forDid:did error:error];
}

@end
```objc

## Step 8: Add Record Endpoints to XRPC Dispatcher

Now we integrate the record service with the XRPC dispatcher. This is where HTTP requests become record operations, and where we implement authorization checks.

Update `src/XrpcDispatcher.m` to add record endpoints:

```objc
- (void)dispatchRequest:(HttpRequest *)request 
               response:(HttpResponse *)response {
    
    NSString *path = request.path;
    NSString *nsid = [path stringByReplacingOccurrencesOfString:@"/xrpc/" withString:@""];
    
    if ([nsid isEqualToString:@"com.atproto.server.describeServer"]) {
        [self handleDescribeServer:request response:response];
    } else if ([nsid isEqualToString:@"com.atproto.server.createAccount"]) {
        [self handleCreateAccount:request response:response];
    } else if ([nsid isEqualToString:@"com.atproto.server.createSession"]) {
        [self handleCreateSession:request response:response];
    } else if ([nsid isEqualToString:@"com.atproto.repo.createRecord"]) {
        [self handleCreateRecord:request response:response];
    } else if ([nsid isEqualToString:@"com.atproto.repo.getRecord"]) {
        [self handleGetRecord:request response:response];
    } else if ([nsid isEqualToString:@"com.atproto.repo.listRecords"]) {
        [self handleListRecords:request response:response];
    } else if ([nsid isEqualToString:@"com.atproto.repo.deleteRecord"]) {
        [self handleDeleteRecord:request response:response];
    } else {
        response.statusCode = 404;
        response.body = [@{@"error": @"MethodNotFound"} JSONData];
    }
}

- (void)handleCreateRecord:(HttpRequest *)request 
                  response:(HttpResponse *)response {
    
    // Extract DID from Authorization header
    NSString *authHeader = [request headerForKey:@"Authorization"];
    NSString *did = [self extractDIDFromAuthHeader:authHeader];
    
    if (!did) {
        response.statusCode = 401;
        response.body = [@{@"error": @"AuthRequired"} JSONData];
        return;
    }
    
    NSError *parseError = nil;
    NSDictionary *params = [NSJSONSerialization JSONObjectWithData:request.body 
                                                            options:0 
                                                              error:&parseError];
    
    if (!params) {
        response.statusCode = 400;
        response.body = [@{@"error": @"InvalidRequest"} JSONData];
        return;
    }
    
    NSString *collection = params[@"collection"];
    NSString *rkey = params[@"rkey"];
    NSDictionary *record = params[@"record"];
    
    // Generate rkey if not provided
    if (!rkey) {
        rkey = [[NSUUID UUID] UUIDString];
    }
    
    NSError *error = nil;
    NSDictionary *result = [self.recordService createRecord:collection
                                                       rkey:rkey
                                                      value:record
                                                     forDid:did
                                                      error:&error];
    
    if (!result) {
        response.statusCode = 400;
        response.body = [@{@"error": error.localizedDescription} JSONData];
        return;
    }
    
    response.statusCode = 200;
    response.body = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
}

- (void)handleGetRecord:(HttpRequest *)request 
               response:(HttpResponse *)response {
    
    NSString *repo = [request queryParamForKey:@"repo"];
    NSString *collection = [request queryParamForKey:@"collection"];
    NSString *rkey = [request queryParamForKey:@"rkey"];
    
    if (!repo || !collection || !rkey) {
        response.statusCode = 400;
        response.body = [@{@"error": @"InvalidRequest"} JSONData];
        return;
    }
    
    // Resolve repo to DID
    NSString *did = repo;  // Simplified - in production, resolve handle to DID
    
    NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];
    
    NSError *error = nil;
    NSDictionary *result = [self.recordService getRecord:uri forDid:did error:&error];
    
    if (!result) {
        response.statusCode = 404;
        response.body = [@{@"error": @"RecordNotFound"} JSONData];
        return;
    }
    
    response.statusCode = 200;
    response.body = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
}

- (void)handleListRecords:(HttpRequest *)request 
                 response:(HttpResponse *)response {
    
    NSString *repo = [request queryParamForKey:@"repo"];
    NSString *collection = [request queryParamForKey:@"collection"];
    NSString *limitStr = [request queryParamForKey:@"limit"];
    
    if (!repo || !collection) {
        response.statusCode = 400;
        response.body = [@{@"error": @"InvalidRequest"} JSONData];
        return;
    }
    
    // Resolve repo to DID
    NSString *did = repo;  // Simplified - in production, resolve handle to DID
    
    NSUInteger limit = limitStr ? [limitStr integerValue] : 50;
    if (limit > 100) limit = 100;
    
    NSError *error = nil;
    NSArray *records = [self.recordService listRecords:collection 
                                                forDid:did 
                                                 limit:limit 
                                                 error:&error];
    
    if (!records) {
        response.statusCode = 400;
        response.body = [@{@"error": error.localizedDescription} JSONData];
        return;
    }
    
    response.statusCode = 200;
    response.body = [NSJSONSerialization dataWithJSONObject:@{@"records": records} options:0 error:nil];
}

- (void)handleDeleteRecord:(HttpRequest *)request 
                  response:(HttpResponse *)response {
    
    // Extract DID from Authorization header
    NSString *authHeader = [request headerForKey:@"Authorization"];
    NSString *did = [self extractDIDFromAuthHeader:authHeader];
    
    if (!did) {
        response.statusCode = 401;
        response.body = [@{@"error": @"AuthRequired"} JSONData];
        return;
    }
    
    NSError *parseError = nil;
    NSDictionary *params = [NSJSONSerialization JSONObjectWithData:request.body 
                                                            options:0 
                                                              error:&parseError];
    
    if (!params) {
        response.statusCode = 400;
        response.body = [@{@"error": @"InvalidRequest"} JSONData];
        return;
    }
    
    NSString *collection = params[@"collection"];
    NSString *rkey = params[@"rkey"];
    
    NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];
    
    NSError *error = nil;
    BOOL success = [self.recordService deleteRecord:uri forDid:did error:&error];
    
    if (!success) {
        response.statusCode = 400;
        response.body = [@{@"error": error.localizedDescription} JSONData];
        return;
    }
    
    response.statusCode = 200;
    response.body = [@{@"success": @YES} JSONData];
}

- (NSString *)extractDIDFromAuthHeader:(NSString *)authHeader {
    // Simplified JWT parsing - in production, verify signature
    if (![authHeader hasPrefix:@"Bearer "]) return nil;
    
    NSString *token = [authHeader substringFromIndex:7];
    NSArray *parts = [token componentsSeparatedByString:@"."];
    if (parts.count != 3) return nil;
    
    // Decode payload
    NSString *payload = parts[1];
    payload = [payload stringByReplacingOccurrencesOfString:@"-" withString:@"+"];
    payload = [payload stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    
    while (payload.length % 4 != 0) {
        payload = [payload stringByAppendingString:@"="];
    }
    
    NSData *data = [[NSData alloc] initWithBase64EncodedString:payload options:0];
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    
    return json[@"sub"];
}
```objc

### Understanding the XRPC Endpoints

**The dispatcher pattern** routes requests based on the NSID (method name). Each NSID maps to a handler method. This is the foundation of XRPC—methods are identified by reverse-DNS names like `com.atproto.repo.createRecord`.

**Authorization extraction** happens in `extractDIDFromAuthHeader:`. This simplified implementation:
1. Extracts the JWT from the `Authorization: Bearer <token>` header
2. Splits the JWT into header, payload, and signature parts
3. Base64-decodes the payload (with URL-safe character substitution)
4. Parses the JSON to extract the `sub` (subject) claim, which contains the DID

**Production JWT verification** would also:
- Verify the signature using the issuer's public key
- Check the expiration time (`exp` claim)
- Validate the issuer (`iss` claim)
- Check the audience (`aud` claim)

**The `createRecord` endpoint** requires authentication because users can only create records in their own repositories. The flow:
1. Extract DID from JWT
2. Parse request body to get collection, rkey, and record value
3. Generate rkey if not provided (using UUID)
4. Call service to create record
5. Return URI and CID to client

**The `getRecord` endpoint** is public (no auth required) because records are generally readable by anyone. The flow:
1. Extract repo, collection, and rkey from query parameters
2. Construct AT URI
3. Call service to retrieve record
4. Return record with URI, CID, and value

**The `listRecords` endpoint** supports pagination with the `limit` parameter. We cap it at 100 to prevent abuse. The flow:
1. Extract repo and collection from query parameters
2. Parse limit (default 50, max 100)
3. Call service to list records
4. Return array of records

**The `deleteRecord` endpoint** requires authentication because only the owner can delete records. The flow:
1. Extract DID from JWT
2. Parse request body to get collection and rkey
3. Construct AT URI
4. Call service to delete record
5. Return success indicator

### Why This Architecture?

**Thin HTTP layer** — The XRPC handlers do minimal work: parse input, call service, format output. All business logic lives in the service layer.

**Consistent error handling** — All endpoints follow the same pattern: validate input, call service, handle errors, return response. This makes the code predictable and maintainable.

**Authorization at the edge** — Auth checks happen in the HTTP layer, before calling services. This prevents unauthorized operations from reaching the business logic.

### Common Pitfalls

**Not validating query parameters** — Always check that required parameters are present. Missing parameters should return 400 Bad Request, not crash.

**Trusting JWT without verification** — This tutorial skips signature verification for simplicity, but production code MUST verify JWT signatures. Unverified JWTs are security vulnerabilities.

**Not capping pagination limits** — Always enforce maximum limits on list operations. Unbounded queries can exhaust memory and database resources.

**Inconsistent error responses** — All errors should return JSON with an `error` field. Consistent error format makes client code simpler.

```objc
- (void)dispatchRequest:(HttpRequest *)request 
               response:(HttpResponse *)response {
    
    NSString *path = request.path;
    NSString *nsid = [path stringByReplacingOccurrencesOfString:@"/xrpc/" withString:@""];
    
    if ([nsid isEqualToString:@"com.atproto.server.describeServer"]) {
        [self handleDescribeServer:request response:response];
    } else if ([nsid isEqualToString:@"com.atproto.server.createAccount"]) {
        [self handleCreateAccount:request response:response];
    } else if ([nsid isEqualToString:@"com.atproto.server.createSession"]) {
        [self handleCreateSession:request response:response];
    } else if ([nsid isEqualToString:@"com.atproto.repo.createRecord"]) {
        [self handleCreateRecord:request response:response];
    } else if ([nsid isEqualToString:@"com.atproto.repo.getRecord"]) {
        [self handleGetRecord:request response:response];
    } else if ([nsid isEqualToString:@"com.atproto.repo.listRecords"]) {
        [self handleListRecords:request response:response];
    } else if ([nsid isEqualToString:@"com.atproto.repo.deleteRecord"]) {
        [self handleDeleteRecord:request response:response];
    } else {
        response.statusCode = 404;
        response.body = [@{@"error": @"MethodNotFound"} JSONData];
    }
}

- (void)handleCreateRecord:(HttpRequest *)request 
                  response:(HttpResponse *)response {
    
    // Extract DID from Authorization header
    NSString *authHeader = [request headerForKey:@"Authorization"];
    NSString *did = [self extractDIDFromAuthHeader:authHeader];
    
    if (!did) {
        response.statusCode = 401;
        response.body = [@{@"error": @"AuthRequired"} JSONData];
        return;
    }
    
    NSError *parseError = nil;
    NSDictionary *params = [NSJSONSerialization JSONObjectWithData:request.body 
                                                            options:0 
                                                              error:&parseError];
    
    if (!params) {
        response.statusCode = 400;
        response.body = [@{@"error": @"InvalidRequest"} JSONData];
        return;
    }
    
    NSString *collection = params[@"collection"];
    NSString *rkey = params[@"rkey"];
    NSDictionary *record = params[@"record"];
    
    // Generate rkey if not provided
    if (!rkey) {
        rkey = [[NSUUID UUID] UUIDString];
    }
    
    NSError *error = nil;
    NSDictionary *result = [self.recordService createRecord:collection
                                                       rkey:rkey
                                                      value:record
                                                     forDid:did
                                                      error:&error];
    
    if (!result) {
        response.statusCode = 400;
        response.body = [@{@"error": error.localizedDescription} JSONData];
        return;
    }
    
    response.statusCode = 200;
    response.body = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
}

- (void)handleGetRecord:(HttpRequest *)request 
               response:(HttpResponse *)response {
    
    NSString *repo = [request queryParamForKey:@"repo"];
    NSString *collection = [request queryParamForKey:@"collection"];
    NSString *rkey = [request queryParamForKey:@"rkey"];
    
    if (!repo || !collection || !rkey) {
        response.statusCode = 400;
        response.body = [@{@"error": @"InvalidRequest"} JSONData];
        return;
    }
    
    // Resolve repo to DID
    NSString *did = repo;  // Simplified - in production, resolve handle to DID
    
    NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];
    
    NSError *error = nil;
    NSDictionary *result = [self.recordService getRecord:uri forDid:did error:&error];
    
    if (!result) {
        response.statusCode = 404;
        response.body = [@{@"error": @"RecordNotFound"} JSONData];
        return;
    }
    
    response.statusCode = 200;
    response.body = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
}

- (void)handleListRecords:(HttpRequest *)request 
                 response:(HttpResponse *)response {
    
    NSString *repo = [request queryParamForKey:@"repo"];
    NSString *collection = [request queryParamForKey:@"collection"];
    NSString *limitStr = [request queryParamForKey:@"limit"];
    
    if (!repo || !collection) {
        response.statusCode = 400;
        response.body = [@{@"error": @"InvalidRequest"} JSONData];
        return;
    }
    
    // Resolve repo to DID
    NSString *did = repo;  // Simplified - in production, resolve handle to DID
    
    NSUInteger limit = limitStr ? [limitStr integerValue] : 50;
    if (limit > 100) limit = 100;
    
    NSError *error = nil;
    NSArray *records = [self.recordService listRecords:collection 
                                                forDid:did 
                                                 limit:limit 
                                                 error:&error];
    
    if (!records) {
        response.statusCode = 400;
        response.body = [@{@"error": error.localizedDescription} JSONData];
        return;
    }
    
    response.statusCode = 200;
    response.body = [NSJSONSerialization dataWithJSONObject:@{@"records": records} options:0 error:nil];
}

- (void)handleDeleteRecord:(HttpRequest *)request 
                  response:(HttpResponse *)response {
    
    // Extract DID from Authorization header
    NSString *authHeader = [request headerForKey:@"Authorization"];
    NSString *did = [self extractDIDFromAuthHeader:authHeader];
    
    if (!did) {
        response.statusCode = 401;
        response.body = [@{@"error": @"AuthRequired"} JSONData];
        return;
    }
    
    NSError *parseError = nil;
    NSDictionary *params = [NSJSONSerialization JSONObjectWithData:request.body 
                                                            options:0 
                                                              error:&parseError];
    
    if (!params) {
        response.statusCode = 400;
        response.body = [@{@"error": @"InvalidRequest"} JSONData];
        return;
    }
    
    NSString *collection = params[@"collection"];
    NSString *rkey = params[@"rkey"];
    
    NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];
    
    NSError *error = nil;
    BOOL success = [self.recordService deleteRecord:uri forDid:did error:&error];
    
    if (!success) {
        response.statusCode = 400;
        response.body = [@{@"error": error.localizedDescription} JSONData];
        return;
    }
    
    response.statusCode = 200;
    response.body = [@{@"success": @YES} JSONData];
}

- (NSString *)extractDIDFromAuthHeader:(NSString *)authHeader {
    // Simplified JWT parsing - in production, verify signature
    if (![authHeader hasPrefix:@"Bearer "]) return nil;
    
    NSString *token = [authHeader substringFromIndex:7];
    NSArray *parts = [token componentsSeparatedByString:@"."];
    if (parts.count != 3) return nil;
    
    // Decode payload
    NSString *payload = parts[1];
    payload = [payload stringByReplacingOccurrencesOfString:@"-" withString:@"+"];
    payload = [payload stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    
    while (payload.length % 4 != 0) {
        payload = [payload stringByAppendingString:@"="];
    }
    
    NSData *data = [[NSData alloc] initWithBase64EncodedString:payload options:0];
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    
    return json[@"sub"];
}
```objc

## Step 9: Update Main Entry Point

Update `src/main.m` to initialize record service:

```objc
#import <Foundation/Foundation.h>
#import "PDSApplication.h"
#import "AccountService.h"
#import "AccountRepository.h"
#import "RecordService.h"
#import "RecordRepository.h"
#import "SimpleJWTMinter.h"
#import "XrpcDispatcher.h"

int main(int argc, char *argv[]) {
    @autoreleasepool {
        // 1. Create configuration
        PDSConfiguration *config = [[PDSConfiguration alloc] init];
        config.serverPort = 2583;
        config.issuer = @"did:web:localhost:2583";
        config.databasePath = @"./pds-data/db";
        
        // 2. Create account service
        AccountRepository *accountRepo = [[AccountRepository alloc] 
            initWithDatabasePath:config.databasePath];
        SimpleJWTMinter *minter = [[SimpleJWTMinter alloc] 
            initWithIssuer:config.issuer];
        AccountService *accountService = [[AccountService alloc] 
            initWithRepository:accountRepo minter:minter];
        
        // 3. Create record service
        RecordRepository *recordRepo = [[RecordRepository alloc] 
            initWithDatabasePath:config.databasePath];
        RecordService *recordService = [[RecordService alloc] 
            initWithRepository:recordRepo];
        
        // 4. Initialize PDS
        NSError *error = nil;
        PDSApplication *app = [[PDSApplication alloc] 
            initWithConfiguration:config error:&error];
        
        if (!app) {
            NSLog(@"Failed to initialize PDS: %@", error);
            return 1;
        }
        
        // 5. Setup XRPC dispatcher with services
        XrpcDispatcher *dispatcher = [[XrpcDispatcher alloc] init];
        dispatcher.accountService = accountService;
        dispatcher.recordService = recordService;
        [app.httpServer registerRoute:@"/xrpc/*" handler:^(HttpRequest *req, HttpResponse *res) {
            [dispatcher dispatchRequest:req response:res];
        }];
        
        // 6. Start server
        [app.httpServer startWithCompletion:^(NSError *error) {
            if (error) {
                NSLog(@"Failed to start server: %@", error);
                exit(1);
            }
            
            NSLog(@"PDS started on port %ld", (long)config.serverPort);
            NSLog(@"Account service ready");
            NSLog(@"Record service ready");
        }];
        
        // 7. Keep running
        [[NSRunLoop mainRunLoop] run];
    }
    
    return 0;
}
```objc

## Step 10: Build and Run

```bash
cd examples/tutorial-3-records
mkdir -p build && cd build
cmake ..
make
./tutorial-3-records
```objc

## Step 11: Test Record Creation

In another terminal, first create an account and get the access token:

```bash
# Create an account
RESPONSE=$(curl -s -X POST http://localhost:2583/xrpc/com.atproto.server.createAccount \
  -H "Content-Type: application/json" \
  -d '{
    "email": "alice@example.com",
    "password": "secure_password",
    "handle": "alice"
  }')

# Extract access token
ACCESS_TOKEN=$(echo $RESPONSE | jq -r '.accessJwt')
echo "Access Token: $ACCESS_TOKEN"

# Create a record
curl -X POST http://localhost:2583/xrpc/com.atproto.repo.createRecord \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -d '{
    "collection": "app.bsky.feed.post",
    "record": {
      "text": "Hello from Tutorial 3!",
      "createdAt": "2024-01-01T00:00:00Z"
    }
  }' | jq .

# Expected output:
# {
#   "uri": "at://did:plc:.../app.bsky.feed.post/...",
#   "cid": "bafyrei..."
# }
```objc

## Step 12: Test Record Retrieval

```bash
# Get the record (replace with actual values from creation)
curl -s "http://localhost:2583/xrpc/com.atproto.repo.getRecord?repo=alice&collection=app.bsky.feed.post&rkey=<RKEY>" | jq .

# Expected output:
# {
#   "uri": "at://did:plc:.../app.bsky.feed.post/...",
#   "cid": "bafyrei...",
#   "value": {
#     "text": "Hello from Tutorial 3!",
#     "createdAt": "2024-01-01T00:00:00Z"
#   }
# }
```objc

## Step 13: Test Record Listing

```bash
# List all posts for alice
curl -s "http://localhost:2583/xrpc/com.atproto.repo.listRecords?repo=alice&collection=app.bsky.feed.post" | jq .

# Expected output:
# {
#   "records": [
#     {
#       "uri": "at://did:plc:.../app.bsky.feed.post/...",
#       "cid": "bafyrei...",
#       "value": {
#         "text": "Hello from Tutorial 3!",
#         "createdAt": "2024-01-01T00:00:00Z"
#       }
#     }
#   ]
# }
```objc

## Step 14: Test Record Deletion

```bash
# Delete the record
curl -X POST http://localhost:2583/xrpc/com.atproto.repo.deleteRecord \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -d '{
    "collection": "app.bsky.feed.post",
    "rkey": "<RKEY>"
  }' | jq .

# Expected output:
# {
#   "success": true
# }

# Verify deletion
curl -s "http://localhost:2583/xrpc/com.atproto.repo.getRecord?repo=alice&collection=app.bsky.feed.post&rkey=<RKEY>" | jq .

# Expected output:
# {
#   "error": "RecordNotFound"
# }
```objc

## Next Steps

- **[Tutorial 4: Authentication](tutorial-4-auth)** — Add OAuth/JWT verification
- **[Tutorial 5: Firehose](tutorial-5-firehose)** — Add WebSocket subscriptions

## Troubleshooting

### Authorization Required Error

**Symptom:**
```json
{
  "error": "AuthRequired"
}
```objc

**Causes and Solutions:**

1. **Missing Authorization header**
   ```bash
   # Wrong - no auth header
   curl -X POST http://localhost:2583/xrpc/com.atproto.repo.createRecord
   
   # Right - include Bearer token
   curl -X POST http://localhost:2583/xrpc/com.atproto.repo.createRecord \
     -H "Authorization: Bearer $ACCESS_TOKEN"
   ```objc

2. **Malformed JWT token**
   ```bash
   # Verify token structure (should have 3 parts separated by dots)
   echo $ACCESS_TOKEN | tr '.' '\n' | wc -l  # Should output 3
   
   # Decode and inspect payload
   echo $ACCESS_TOKEN | cut -d'.' -f2 | base64 -d | jq .
   ```objc

3. **Expired token**
   - Check the `exp` claim in the JWT payload
   - Create a new session to get a fresh token
   - In production, implement token refresh

### Record Not Found Error

**Symptom:**
```json
{
  "error": "RecordNotFound"
}
```objc

**Causes and Solutions:**

1. **Wrong URI components**
   ```bash
   # Verify the URI was constructed correctly
   # Format: at://<did>/<collection>/<rkey>
   
   # Check that you're using the exact rkey from creation
   # rkeys are case-sensitive and must match exactly
   ```objc

2. **Wrong DID/handle**
   ```bash
   # Make sure you're querying the right repository
   # The repo parameter should match the account that created the record
   ```objc

3. **Record was deleted**
   ```bash
   # List all records to see what exists
   curl -s "http://localhost:2583/xrpc/com.atproto.repo.listRecords?repo=alice&collection=app.bsky.feed.post" | jq .
   ```objc

### Database Errors

**Symptom:**
```objc
Failed to open database: unable to open database file
```objc

**Causes and Solutions:**

1. **Missing data directory**
   ```bash
   # Create the directory before starting the server
   mkdir -p ./pds-data/db
   ```objc

2. **Permission issues**
   ```bash
   # Check directory permissions
   ls -la ./pds-data/
   
   # Fix permissions if needed
   chmod 755 ./pds-data/
   ```objc

3. **Database corruption**
   ```bash
   # Clear database and restart (WARNING: deletes all data)
   rm -rf pds-data/
   mkdir -p pds-data/db
   ./tutorial-3-records
   ```objc

### Invalid Request Errors

**Symptom:**
```json
{
  "error": "InvalidRequest"
}
```objc

**Causes and Solutions:**

1. **Missing required fields**
   ```bash
   # createRecord requires: collection, record
   # getRecord requires: repo, collection, rkey
   # listRecords requires: repo, collection
   # deleteRecord requires: collection, rkey
   
   # Check your request includes all required fields
   ```objc

2. **Malformed JSON**
   ```bash
   # Validate JSON syntax
   echo '{"collection":"app.bsky.feed.post","record":{"text":"test"}}' | jq .
   ```objc

3. **Wrong HTTP method**
   ```bash
   # createRecord and deleteRecord use POST
   # getRecord and listRecords use GET
   ```objc

### CID Mismatch Issues

**Symptom:** Records have different CIDs for identical content

**Causes and Solutions:**

1. **Non-deterministic serialization**
   - Ensure you're using `NSJSONWritingSortedKeys`
   - Dictionary key order must be consistent
   - In production, use CBOR for canonical encoding

2. **Timestamp in record value**
   ```bash
   # Don't include timestamps in the record value if you want stable CIDs
   # Timestamps should be metadata, not content
   ```objc

### Performance Issues

**Symptom:** Slow record listing or creation

**Causes and Solutions:**

1. **Missing database indexes**
   ```sql
   -- Add indexes for common queries
   CREATE INDEX idx_records_did_collection ON records(did, collection);
   CREATE INDEX idx_records_created_at ON records(created_at);
   ```objc

2. **Large result sets**
   ```bash
   # Always use pagination
   # Limit results to reasonable sizes (50-100 records)
   curl -s "http://localhost:2583/xrpc/com.atproto.repo.listRecords?repo=alice&collection=app.bsky.feed.post&limit=50"
   ```objc

3. **No connection pooling**
   - This tutorial uses a single database connection
   - Production systems should use connection pools
   - See `PDSDatabasePool` in September PDS for examples

## Summary

Congratulations! You've successfully built a functional record management system for AT Protocol. This tutorial covered the essential components of a PDS's data layer.

### What You've Accomplished

**Core Functionality:**
- ✅ Record creation with AT URIs and CIDs
- ✅ Record retrieval by URI
- ✅ Record listing with pagination
- ✅ Record deletion with authorization
- ✅ SQLite persistence with proper schema design
- ✅ JWT-based authorization (simplified)

**Architecture Patterns:**
- ✅ Repository pattern for data access
- ✅ Service layer for business logic
- ✅ XRPC endpoint implementation
- ✅ Proper error handling throughout
- ✅ Content addressing with CIDs

**Key Concepts Learned:**
- **AT URIs** — How records are uniquely identified across the network
- **Content Identifiers** — Cryptographic hashing for data integrity
- **Collections** — Organizing records by type (NSID)
- **Record Keys** — Unique identifiers within collections
- **Authorization** — Extracting DIDs from JWTs for access control

### Understanding the Record Model

The AT Protocol's record model is elegant in its simplicity:

1. **Identity** — Every record has a URI that identifies it globally
2. **Integrity** — Every record has a CID that verifies its content
3. **Organization** — Records are grouped into collections by type
4. **Ownership** — Records belong to repositories identified by DIDs

This model enables:
- **Decentralization** — Records can be hosted anywhere
- **Verification** — Content can be cryptographically verified
- **Portability** — Users can move their data between servers
- **Interoperability** — Different applications can share data

### Production Considerations

This tutorial simplified several aspects for learning. Production systems need:

**CBOR Encoding:**
- Use DAG-CBOR instead of JSON for canonical serialization
- Implement proper CIDv1 format with multibase/multihash
- See `ATProtoCBORSerialization` in September PDS

**MST Integration:**
- Records should be organized in Merkle Search Trees
- MSTs enable efficient sync and verification
- See [MST Trees](../02-core-concepts/mst-trees) for details

**Commit Objects:**
- Record changes should be wrapped in commit objects
- Commits reference the MST root CID
- Commits are signed by the repository owner

**JWT Verification:**
- Always verify JWT signatures in production
- Check expiration, issuer, and audience claims
- Implement token refresh for long-lived sessions

**Handle Resolution:**
- Resolve handles to DIDs using DNS or HTTP
- Cache resolutions to reduce latency
- See [Identity Resolution](../02-core-concepts/plc-directory)

**Schema Validation:**
- Validate record values against lexicon schemas
- Reject records that don't match their collection's schema
- See the `lexicons/` directory for schema definitions

**Blob Support:**
- Records can reference blobs (images, videos)
- Blobs are stored separately and referenced by CID
- See [Blob Storage](../07-repository-protocol/blob-storage)

### Next Steps

Now that you understand record operations, you're ready to tackle authentication and real-time sync:

**[Tutorial 4: Authentication](tutorial-4-auth)**
- Implement OAuth 2.0 with DPoP
- Add proper JWT signature verification
- Implement token refresh flow
- Add authorization checks for all operations

**[Tutorial 5: Firehose](tutorial-5-firehose)**
- Implement WebSocket server for real-time updates
- Broadcast record changes to subscribers
- Handle backpressure and reconnection
- Implement the `com.atproto.sync.subscribeRepos` endpoint

**Further Reading:**
- [Record Service](../03-application-layer/record-service) — Production patterns
- [Repository Basics](../07-repository-protocol/repository-basics) — Protocol details
- [CBOR Serialization](../07-repository-protocol/cbor-serialization) — Canonical encoding
- [MST Trees](../02-core-concepts/mst-trees) — Merkle Search Tree implementation

### Reflection

This tutorial demonstrated the core of what makes AT Protocol powerful: a simple, verifiable record model that enables decentralized social applications. Every post, like, follow, and profile on Bluesky is just a record in someone's repository, identified by a URI and verified by a CID.

The patterns you've learned here—repository abstraction, service layers, content addressing—scale from this simple tutorial to production systems handling millions of records. The September PDS codebase uses these same patterns, just with more sophisticated implementations of MSTs, CBOR encoding, and sync protocols.

You now have the foundation to build AT Protocol applications. The next tutorials will add the remaining pieces: secure authentication and real-time synchronization.

## Understanding the Implementation

### Record URI Format

Records are identified by AT URIs with the format:
```objc
at://<did>/<collection>/<rkey>
```objc

Example:
```objc
at://did:plc:abc123/app.bsky.feed.post/xyz789
```objc

### CID Generation

Content Identifiers (CIDs) are generated by:
1. Serializing the record value to JSON
2. Computing SHA-256 hash
3. Encoding as base32 with multibase prefix

In production, use proper DAG-CBOR serialization and CIDv1 encoding.

### Authorization Flow

1. Client sends JWT in Authorization header
2. Server extracts DID from JWT payload
3. Server verifies DID matches record owner
4. Server allows or denies operation

### Database Schema

Records are stored with:
- `uri` — AT URI (primary key)
- `did` — Owner DID
- `collection` — Collection NSID
- `rkey` — Record key
- `cid` — Content identifier
- `value` — JSON-serialized record
- `created_at` — Timestamp

### Next Tutorial Preview

Tutorial 4 will add:
- JWT signature verification
- OAuth 2.0 with DPoP
- Token refresh flow
- Proper authorization checks
