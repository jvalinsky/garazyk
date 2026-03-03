# Services Overview

## Service Architecture

The PDS implements a service-oriented architecture where each service handles a specific domain:

```
PDSApplication
├── PDSAccountService      — User accounts, authentication
├── PDSRecordService       — Record CRUD operations
├── PDSBlobService         — File upload/retrieval
├── PDSRepositoryService   — MST, commits, sync
├── PDSAdminController     — Moderation, takedowns
└── PDSRelayService        — External relay notifications
```

### Service Initialization Flow

See [Service Initialization Flow Diagram](./service-initialization-flow.svg) for a detailed visual representation of how PDSApplication initializes all services during startup.

**Initialization Sequence:**
1. Load PDSConfiguration from config.json
2. Initialize PDSServiceDatabases (shared service DB, DID cache, sequencer)
3. Initialize PDSDatabasePool (per-user database pool)
4. Create PDSApplication instance
5. Initialize all services (Account, Record, Blob, Repository, Admin, Relay)
6. Initialize HttpServer and register XRPC routes
7. Server ready to accept requests

### Service Interaction During Requests

See [Service Interaction Flow Diagram](./service-interaction-flow.svg) for a detailed visual representation of how services interact during typical request processing.

**Request Processing Flow:**
1. HttpServer receives HTTP request
2. XrpcDispatcher routes by NSID and verifies authentication
3. XrpcMethodRegistry looks up appropriate handler
4. Domain handler (e.g., XrpcRepoMethods) calls primary service
5. Primary service may call supporting services (Repository, Blob, Admin)
6. Services access shared and per-user databases
7. PDSRelayService notifies external relays asynchronously
8. Response is serialized and returned to client

## Service Responsibilities

### PDSAccountService

**Responsibilities:**
- Account creation and registration
- Authentication (password verification)
- Token generation and refresh
- Account deletion
- Email verification

**Key Methods:**
```objc
- (void)createAccountWithEmail:(NSString *)email
                        handle:(NSString *)handle
                      password:(NSString *)password
                    completion:(void (^)(NSString *did, NSError *error))completion;

- (void)authenticateWithHandle:(NSString *)handle
                      password:(NSString *)password
                    completion:(void (^)(NSString *accessToken, NSString *refreshToken, NSError *error))completion;

- (void)refreshTokenWithRefreshToken:(NSString *)refreshToken
                          completion:(void (^)(NSString *accessToken, NSError *error))completion;
```

### PDSRecordService

**Responsibilities:**
- Create records
- Read records
- Update records
- Delete records
- List records by collection

**Key Methods:**
```objc
- (void)createRecord:(NSDictionary *)record
          collection:(NSString *)collection
                 did:(NSString *)did
          completion:(void (^)(NSString *uri, NSError *error))completion;

- (void)getRecord:(NSString *)did
       collection:(NSString *)collection
             rkey:(NSString *)rkey
       completion:(void (^)(NSDictionary *record, NSError *error))completion;

- (void)updateRecord:(NSDictionary *)record
          collection:(NSString *)collection
                rkey:(NSString *)rkey
                 did:(NSString *)did
          completion:(void (^)(NSString *uri, NSError *error))completion;

- (void)deleteRecord:(NSString *)did
          collection:(NSString *)collection
                rkey:(NSString *)rkey
          completion:(void (^)(NSError *error))completion;

- (void)listRecords:(NSString *)did
         collection:(NSString *)collection
             limit:(NSInteger)limit
            cursor:(NSString *)cursor
        completion:(void (^)(NSArray *records, NSString *nextCursor, NSError *error))completion;
```

### PDSBlobService

**Responsibilities:**
- Upload blobs (images, videos, etc.)
- Retrieve blobs
- Delete blobs
- Verify blob integrity

**Key Methods:**
```objc
- (void)uploadBlob:(NSData *)data
        completion:(void (^)(NSString *blobCID, NSError *error))completion;

- (void)getBlob:(NSString *)blobCID
     completion:(void (^)(NSData *data, NSError *error))completion;

- (void)deleteBlob:(NSString *)blobCID
        completion:(void (^)(NSError *error))completion;
```

### PDSRepositoryService

**Responsibilities:**
- Manage Merkle Search Trees
- Create commits
- Process repository updates
- Sync repositories between PDS instances
- Export/import repositories

**Key Methods:**
```objc
- (void)updateMSTWithRecord:(NSDictionary *)record
                 collection:(NSString *)collection
                      rkey:(NSString *)rkey
                       did:(NSString *)did
                completion:(void (^)(NSString *rootCID, NSError *error))completion;

- (void)createCommitWithRootCID:(NSString *)rootCID
                            did:(NSString *)did
                     completion:(void (^)(NSString *commitCID, NSError *error))completion;

- (void)syncRepository:(NSString *)remoteDID
            completion:(void (^)(NSError *error))completion;

- (void)exportRepository:(NSString *)did
              completion:(void (^)(NSData *carData, NSError *error))completion;
```

### PDSAdminController

**Responsibilities:**
- Takedown records
- Suspend accounts
- Apply labels
- Moderate content
- Generate reports

**Key Methods:**
```objc
- (void)takedownRecord:(NSString *)uri
            completion:(void (^)(NSError *error))completion;

- (void)suspendAccount:(NSString *)did
            completion:(void (^)(NSError *error))completion;

- (void)applyLabel:(NSString *)label
            toURI:(NSString *)uri
       completion:(void (^)(NSError *error))completion;
```

### PDSRelayService

**Responsibilities:**
- Notify external relays of updates
- Handle relay subscriptions
- Manage relay connections
- Retry failed notifications

**Key Methods:**
```objc
- (void)notifyRelaysOfCommit:(NSDictionary *)commit
                         did:(NSString *)did
                  completion:(void (^)(NSError *error))completion;

- (void)subscribeToRelay:(NSString *)relayURL
              completion:(void (^)(NSError *error))completion;
```

## Service Interaction Patterns

### Record Creation Flow

```
1. Client calls com.atproto.repo.createRecord
   ↓
2. XrpcRepoMethods.handleCreateRecord
   ↓
3. PDSRecordService.createRecord
   ├─ Validate record against lexicon
   ├─ Encode record to CBOR
   ├─ Calculate CID
   └─ Store in database
   ↓
4. PDSRepositoryService.updateMST
   ├─ Insert record into MST
   ├─ Calculate new root CID
   └─ Create commit
   ↓
5. PDSRelayService.notifyRelays
   └─ Broadcast to external relays
   ↓
6. Response to client
```

### Authentication Flow

```
1. Client calls com.atproto.server.createSession
   ↓
2. XrpcServerMethods.handleCreateSession
   ↓
3. PDSAccountService.authenticate
   ├─ Look up account by handle
   ├─ Verify password
   └─ Generate tokens
   ↓
4. JWTMinter.mintAccessToken
   ├─ Create JWT payload
   ├─ Sign with server key
   └─ Return token
   ↓
5. Response with access and refresh tokens
```

## Error Handling

### Service Error Codes

Each service defines standard error codes:

```objc
// PDSAccountService errors
typedef NS_ENUM(NSInteger, PDSAccountServiceError) {
    PDSAccountServiceErrorInvalidEmail = 1,
    PDSAccountServiceErrorHandleAlreadyTaken = 2,
    PDSAccountServiceErrorInvalidPassword = 3,
    PDSAccountServiceErrorAccountNotFound = 4,
    PDSAccountServiceErrorInvalidCredentials = 5
};

// PDSRecordService errors
typedef NS_ENUM(NSInteger, PDSRecordServiceError) {
    PDSRecordServiceErrorInvalidRecord = 1,
    PDSRecordServiceErrorRecordNotFound = 2,
    PDSRecordServiceErrorUnauthorized = 3,
    PDSRecordServiceErrorCollectionNotFound = 4
};
```

### Error Propagation

```objc
// Services propagate errors through completion blocks
[service.recordService createRecord:record
                        collection:@"app.bsky.feed.post"
                               did:userDID
                        completion:^(NSString *uri, NSError *error) {
    if (error) {
        // Handle error
        NSLog(@"Error: %@", error.localizedDescription);
        return;
    }
    
    // Success
    NSLog(@"Record created: %@", uri);
}];
```

## Concurrency and Thread Safety

### Thread-Safe Operations

All service methods are thread-safe:
- Database access is synchronized
- Completion blocks are called on main thread
- No shared mutable state

### Async Operations

All service methods are asynchronous:
- Use completion blocks for results
- Never block the main thread
- Support cancellation where appropriate

## Testing Services

### Unit Testing

```objc
// In PDSRecordServiceTests.m
- (void)testCreateRecord {
    PDSRecordService *service = [[PDSRecordService alloc] initWithApplication:self.app];
    
    NSDictionary *record = @{@"text": @"Hello"};
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"Record created"];
    
    [service createRecord:record
              collection:@"app.bsky.feed.post"
                     did:@"did:plc:test123"
              completion:^(NSString *uri, NSError *error) {
        XCTAssertNil(error);
        XCTAssertNotNil(uri);
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:5 handler:nil];
}
```

### Integration Testing

```objc
// In PDSIntegrationTests.m
- (void)testRecordCreationAndRetrieval {
    // 1. Create account
    [self.app.accountService createAccountWithEmail:@"test@example.com"
                                             handle:@"test.example.com"
                                           password:@"password"
                                         completion:^(NSString *did, NSError *error) {
        // 2. Create record
        [self.app.recordService createRecord:@{@"text": @"Hello"}
                                 collection:@"app.bsky.feed.post"
                                        did:did
                                 completion:^(NSString *uri, NSError *error) {
            // 3. Retrieve record
            [self.app.recordService getRecord:did
                                  collection:@"app.bsky.feed.post"
                                        rkey:@"abc123"
                                  completion:^(NSDictionary *record, NSError *error) {
                XCTAssertEqualObjects(record[@"text"], @"Hello");
            }];
        }];
    }];
}
```

## Performance Considerations

### Caching

Services can cache frequently accessed data:
- Cache user accounts by DID
- Cache records by URI
- Cache MST nodes

### Batching

Operations can be batched for efficiency:
- Batch record inserts
- Batch blob uploads
- Batch relay notifications

### Connection Pooling

Database connections are pooled:
- Reuse connections
- Limit concurrent connections
- Monitor pool utilization

## ASCII Art: Service Initialization Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    START                                    │
└────────────────────┬────────────────────────────────────────┘
                     │
        ┌────────────▼────────────────────┐
        │ 1. Load PDSConfiguration        │
        │    (config.json)                │
        └────────────┬─────────────────────┘
                     │
        ┌────────────▼────────────────────────────────────┐
        │ 2. Initialize PDSServiceDatabases               │
        │    - Shared service DB                          │
        │    - DID cache, sequencer tables                │
        │    - Run migrations                             │
        └────────────┬─────────────────────────────────────┘
                     │
        ┌────────────▼────────────────────────────────────┐
        │ 3. Initialize PDSDatabasePool                   │
        │    - Per-user database pool                     │
        │    - Connection limits, cache size              │
        │    - Database templates                         │
        └────────────┬─────────────────────────────────────┘
                     │
        ┌────────────▼────────────────────────────────────┐
        │ 4. Create PDSApplication Instance               │
        │    (with config and database pools)             │
        └────────────┬─────────────────────────────────────┘
                     │
        ┌────────────▼────────────────────────────────────┐
        │ 5. Initialize Services (in sequence):           │
        │    ├─ PDSAccountService                         │
        │    ├─ PDSRecordService                          │
        │    ├─ PDSBlobService                            │
        │    ├─ PDSRepositoryService                      │
        │    ├─ PDSAdminController                        │
        │    └─ PDSRelayService                           │
        └────────────┬─────────────────────────────────────┘
                     │
        ┌────────────▼────────────────────────────────────┐
        │ 6. Initialize HttpServer                        │
        │    - Register XRPC routes                       │
        │    - Bind to port (default 2583)                │
        └────────────┬─────────────────────────────────────┘
                     │
        ┌────────────▼────────────────────────────────────┐
        │ 7. Register XRPC Methods                        │
        │    - XrpcServerMethods                          │
        │    - XrpcRepoMethods                            │
        │    - XrpcSyncMethods, etc.                      │
        └────────────┬─────────────────────────────────────┘
                     │
        ┌────────────▼────────────────────────────────────┐
        │ 8. Server Ready                                 │
        │    Listening for HTTP requests                  │
        └────────────┬─────────────────────────────────────┘
                     │
        ┌────────────▼────────────────────────────────────┐
        │                    READY                        │
        └─────────────────────────────────────────────────┘
```

## ASCII Art: Service Interaction During Request

```
┌──────────────────────────────────────────────────────────┐
│              HTTP Client Request                         │
└────────────────────┬─────────────────────────────────────┘
                     │
        ┌────────────▼────────────────────┐
        │ 1. HttpServer                   │
        │    Route matching, TLS          │
        └────────────┬─────────────────────┘
                     │
        ┌────────────▼────────────────────┐
        │ 2. XrpcDispatcher               │
        │    Route by NSID, verify auth   │
        └────────────┬─────────────────────┘
                     │
        ┌────────────▼────────────────────┐
        │ 3. XrpcMethodRegistry           │
        │    Look up handler              │
        └────────────┬─────────────────────┘
                     │
        ┌────────────▼────────────────────┐
        │ 4. Domain Handler               │
        │    (e.g., XrpcRepoMethods)      │
        │    Parse & validate request     │
        └────────────┬─────────────────────┘
                     │
        ┌────────────▼────────────────────────────────────┐
        │ 5. Primary Service                              │
        │    (e.g., PDSRecordService)                     │
        │    Business logic, prepare data                 │
        └────────────┬─────────────────────────────────────┘
                     │
        ├────────────┼────────────┬────────────┐
        │            │            │            │
        ▼            ▼            ▼            ▼
    ┌────────┐  ┌────────┐  ┌────────┐  ┌────────┐
    │ Repo   │  │ Blob   │  │ Admin  │  │ Relay  │
    │Service │  │Service │  │Service │  │Service │
    └────┬───┘  └────┬───┘  └────┬───┘  └────┬───┘
         │           │           │           │
         └───────────┼───────────┴───────────┘
                     │
        ┌────────────▼────────────────────────────────────┐
        │ 6. Database Access                              │
        │    ├─ PDSServiceDatabases (shared)              │
        │    └─ PDSDatabasePool (per-user)                │
        └────────────┬─────────────────────────────────────┘
                     │
        ┌────────────▼────────────────────────────────────┐
        │ 7. Services Process Results                     │
        │    Aggregate data, prepare response             │
        └────────────┬─────────────────────────────────────┘
                     │
        ┌────────────▼────────────────────────────────────┐
        │ 8. PDSRelayService (async)                      │
        │    Notify external relays of updates            │
        └────────────┬─────────────────────────────────────┘
                     │
        ┌────────────▼────────────────────────────────────┐
        │ 9. Response Serialization                       │
        │    Encode to CBOR/JSON, add headers             │
        └────────────┬─────────────────────────────────────┘
                     │
        ┌────────────▼────────────────────────────────────┐
        │         HTTP Response to Client                 │
        └─────────────────────────────────────────────────┘
```

## Next Steps

- **[Account Service](./account-service.md)** — Account management details
- **[Record Service](./record-service.md)** — Record operations details
- **[Network Layer](../04-network-layer/http-server.md)** — HTTP and XRPC
