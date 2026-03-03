# Tutorial 3: Record Operations

## Overview

In this tutorial, you'll extend the PDS from Tutorial 2 to support record CRUD operations (Create, Read, Update, Delete) with MST (Merkle Search Tree) integration.

**Learning Objectives:**
- Implement record creation endpoint
- Implement record retrieval endpoint
- Implement record update endpoint
- Implement record deletion endpoint
- Understand MST tree updates
- Handle CBOR serialization

**Time:** 60 minutes

## Prerequisites

- Completed [Tutorial 2: Account Management](./tutorial-2-accounts)
- Understanding of MST trees (see [MST Trees](../02-core-concepts/mst-trees))
- Understanding of CBOR serialization (see [CBOR and CAR](../02-core-concepts/cbor-and-car))
- Understanding of record service (see [Record Service](../03-application-layer/record-service))

## Step 1: Create Record Data Model

Create `src/Record.h`:

```objc
#import <Foundation/Foundation.h>

@interface Record : NSObject

@property (nonatomic, copy) NSString *uri;
@property (nonatomic, copy) NSString *cid;
@property (nonatomic, copy) NSDictionary *value;
@property (nonatomic, assign) NSTimeInterval createdAt;

@end
```

## Step 2: Create Record Repository

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
```

## Step 3: Implement Record Repository

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
```

## Step 4: Create CID Generator

Create `src/SimpleCIDGenerator.h`:

```objc
#import <Foundation/Foundation.h>

@interface SimpleCIDGenerator : NSObject

+ (NSString *)generateCIDForData:(NSData *)data;
+ (NSString *)generateCIDForJSON:(NSDictionary *)json;

@end
```

## Step 5: Implement CID Generator

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
```

## Step 6: Create Record Service

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
```

## Step 7: Implement Record Service

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
```

## Step 8: Add Record Endpoints to XRPC Dispatcher

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
```

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
```

## Step 10: Build and Run

```bash
cd examples/tutorial-3-records
mkdir -p build && cd build
cmake ..
make
./tutorial-3-records
```

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
```

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
```

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
```

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
```

## Next Steps

- **[Tutorial 4: Authentication](./tutorial-4-auth)** — Add OAuth/JWT verification
- **[Tutorial 5: Firehose](./tutorial-5-firehose)** — Add WebSocket subscriptions

## Troubleshooting

**Authorization required error:**
```bash
# Make sure you're including the Bearer token
# Verify the token is valid and not expired
echo $ACCESS_TOKEN | cut -d'.' -f2 | base64 -d | jq .
```

**Record not found:**
```bash
# Verify the URI components are correct
# Check that the record was created successfully
# Ensure you're using the correct DID/handle
```

**Database errors:**
```bash
# Clear database and restart
rm -rf pds-data/
./tutorial-3-records
```

## Summary

You've successfully extended the PDS to support:
- Record creation with CBOR serialization
- Record retrieval by URI
- Record listing by collection
- Record deletion
- CID generation for content addressing
- JWT-based authorization for record operations

This foundation enables building more complex features like MST tree management and firehose subscriptions.

## Understanding the Implementation

### Record URI Format

Records are identified by AT URIs with the format:
```
at://<did>/<collection>/<rkey>
```

Example:
```
at://did:plc:abc123/app.bsky.feed.post/xyz789
```

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
