---
title: Services Overview
---

# Services Overview

## Introduction

The September PDS implements a service-oriented architecture where functionality is organized into specialized services, each responsible for a specific domain. This architectural pattern provides clear separation of concerns, making the codebase maintainable, testable, and extensible.

### Why Service-Oriented Architecture Matters

The service layer is the heart of the PDS implementation. It provides:

- **Clear Boundaries**: Each service has well-defined responsibilities, reducing coupling and complexity
- **Testability**: Services can be tested in isolation with mock dependencies
- **Reusability**: Services are accessed through `PDSApplication`, enabling consistent usage across XRPC endpoints
- **Maintainability**: Changes to one service don't ripple through the entire codebase
- **Scalability**: Services can be optimized or replaced independently

Understanding the service architecture is essential for implementing new features, debugging issues, and maintaining the PDS effectively.

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

See [Service Initialization Flow Diagram](service-initialization-flow.svg) for a detailed visual representation of how PDSApplication initializes all services during startup.

**Initialization Sequence:**
1. Load PDSConfiguration from config.json
2. Initialize PDSServiceDatabases (shared service DB, DID cache, sequencer)
3. Initialize PDSDatabasePool (per-user database pool)
4. Create PDSApplication instance
5. Initialize all services (Account, Record, Blob, Repository, Admin, Relay)
6. Initialize HttpServer and register XRPC routes
7. Server ready to accept requests

### Service Interaction During Requests

See [Service Interaction Flow Diagram](service-interaction-flow.svg) for a detailed visual representation of how services interact during typical request processing.

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

## When to Use Which Service

Understanding which service to use for different operations is crucial for correct implementation:

### Use Account Service When:
- Creating new user accounts
- Authenticating users (login/logout)
- Managing JWT tokens (access and refresh)
- Implementing account deletion
- Handling email verification

### Use Record Service When:
- Creating, reading, updating, or deleting individual records
- Listing records in a collection
- Performing batch write operations
- Validating records against lexicons
- Implementing `com.atproto.repo.*` endpoints

### Use Blob Service When:
- Uploading images, videos, or other binary data
- Retrieving blobs by CID
- Managing blob metadata
- Implementing storage quotas
- Handling media in posts or profiles

### Use Repository Service When:
- Exporting repositories as CAR files
- Computing repository root CIDs
- Implementing sync endpoints (`com.atproto.sync.*`)
- Managing MST structure
- Performing repository-level operations

### Use Admin Service When:
- Moderating content (takedowns, labels)
- Suspending or deleting accounts
- Implementing admin endpoints (`com.atproto.admin.*`)
- Handling moderation reports
- Maintaining audit logs

### Use Relay Service When:
- Notifying external relays of repository changes
- Participating in the ATProto network
- Broadcasting commits to aggregators
- Implementing federation

## Common Pitfalls and Troubleshooting

### Pitfall 1: Bypassing PDSApplication

**Problem**: Directly instantiating services instead of accessing through `PDSApplication`.

**Why it happens**: Not understanding that `PDSApplication` is the primary facade.

**Solution**: Always access services through the application instance:
```objc
// Bad: Direct instantiation
PDSAccountService *accountService = [[PDSAccountService alloc] init];

// Good: Access through PDSApplication
PDSApplication *app = [PDSApplication sharedApplication];
PDSAccountService *accountService = app.accountService;
```

### Pitfall 2: Service Initialization Order

**Problem**: Services fail because dependencies aren't initialized yet.

**Why it happens**: Not following the correct initialization sequence.

**Solution**: Follow the documented initialization order:
```objc
// Correct order (from PDSApplication.m)
1. Load configuration
2. Initialize databases (PDSServiceDatabases, PDSDatabasePool)
3. Initialize JWT minter
4. Initialize services (Account, Record, Blob, Repository, Admin, Relay)
5. Initialize HTTP server
6. Register XRPC methods
```

### Pitfall 3: Circular Service Dependencies

**Problem**: Services depend on each other, creating circular references.

**Why it happens**: Not understanding service boundaries and responsibilities.

**Solution**: Design services with clear dependencies:
```objc
// Good: Clear dependency hierarchy
PDSApplication
├── PDSAccountService (no service dependencies)
├── PDSRecordService (depends on Repository)
├── PDSBlobService (no service dependencies)
├── PDSRepositoryService (no service dependencies)
├── PDSAdminService (depends on Account, Record)
└── PDSRelayService (no service dependencies)

// Bad: Circular dependency
PDSRecordService → PDSAccountService → PDSRecordService  // Circular!
```

### Pitfall 4: Not Using Transactions

**Problem**: Multi-step operations leave data in inconsistent state on failure.

**Why it happens**: Not wrapping related operations in database transactions.

**Solution**: Use transactions for atomic operations:
```objc
// Bad: No transaction
[recordService putRecord:record1 /* ... */];
[recordService putRecord:record2 /* ... */];  // If this fails, record1 is orphaned

// Good: Atomic transaction
[recordService applyWrites:@[write1, write2] /* ... */];  // All or nothing
```

### Pitfall 5: Synchronous Service Calls Blocking Requests

**Problem**: Long-running service operations block HTTP request threads.

**Why it happens**: Not using async patterns for I/O-bound operations.

**Solution**: Use completion blocks and background queues:
```objc
// Bad: Blocks request thread
NSData *carData = [repositoryService getRepoContents:did since:nil error:&error];
[self sendResponse:carData];

// Good: Async with completion
dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    NSError *error = nil;
    NSData *carData = [repositoryService getRepoContents:did since:nil error:&error];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self sendResponse:carData];
    });
});
```

### Troubleshooting Guide

#### Issue: Service returns nil unexpectedly

**Symptoms**: Service method returns nil with no error.

**Possible causes**:
1. Service not initialized
2. Database connection failed
3. Invalid parameters

**Diagnosis**:
```objc
// Check service initialization
if (!app.accountService) {
    PDS_LOG_ERROR(@"Account service not initialized");
}

// Check database connectivity
if (![app.serviceDatabases isConnected]) {
    PDS_LOG_ERROR(@"Service databases not connected");
}

// Enable verbose logging
app.configuration.debug.verbose = YES;
```

#### Issue: Services performing slowly

**Symptoms**: Service operations take longer than expected.

**Possible causes**:
1. Database not using WAL mode
2. Missing indexes
3. N+1 query problem

**Diagnosis**:
```objc
// Check WAL mode
PRAGMA journal_mode;  // Should return "wal"

// Profile slow queries
- (void)profileServiceOperation:(NSString *)operation block:(void (^)(void))block {
    NSDate *start = [NSDate date];
    block();
    NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:start];
    
    if (elapsed > 1.0) {
        PDS_LOG_WARN(@"Slow operation: %@ took %.2f seconds", operation, elapsed);
    }
}
```

## Best Practices

### Service Design

1. **Single Responsibility**: Each service should have one clear purpose
2. **Dependency Injection**: Pass dependencies through initializers, not globals
3. **Error Handling**: Always provide detailed error information
4. **Logging**: Log important operations with context
5. **Testing**: Write unit tests for each service in isolation

### Service Usage

1. **Access Through PDSApplication**: Never instantiate services directly
2. **Check Errors**: Always check error pointers after service calls
3. **Use Transactions**: Wrap multi-step operations in transactions
4. **Async Operations**: Use background queues for I/O-bound work
5. **Resource Cleanup**: Close connections and release resources properly

### Performance

1. **Connection Pooling**: Reuse database connections
2. **Caching**: Cache frequently accessed data (with invalidation)
3. **Batch Operations**: Combine multiple operations when possible
4. **Lazy Loading**: Load data only when needed
5. **Monitoring**: Track service operation latency and throughput

### Security

1. **Authorization**: Verify user permissions before operations
2. **Input Validation**: Validate all inputs before processing
3. **Audit Logging**: Log security-relevant operations
4. **Rate Limiting**: Prevent abuse with rate limits
5. **Secrets Management**: Never log sensitive data

## Service Interaction Patterns

### Pattern 1: Create Account and Initial Profile

```objc
// 1. Create account
NSError *error = nil;
NSDictionary *account = [app.accountService createAccountForEmail:@"user@example.com"
                                                          password:@"password"
                                                            handle:@"alice"
                                                               did:nil
                                                             error:&error];

if (!account) {
    PDS_LOG_ERROR(@"Account creation failed: %@", error);
    return;
}

NSString *did = account[@"did"];

// 2. Initialize repository
[app.repositoryService initializeRepoForDid:did error:&error];

// 3. Create profile record
NSDictionary *profile = @{
    @"displayName": @"Alice",
    @"description": @"Hello world!"
};

[app.recordService putRecord:@"app.bsky.actor.profile"
                        rkey:@"self"
                       value:profile
                      forDid:did
                    actorDid:did
              validationMode:PDSValidationModeOptimistic
                       error:&error];

// 4. Notify relays
[app.relayService notifyRelaysAsync:did];
```

### Pattern 2: Create Post with Image

```objc
// 1. Upload image blob
NSData *imageData = [NSData dataWithContentsOfFile:imagePath];
NSError *error = nil;

NSDictionary *blob = [app.blobService uploadBlob:imageData
                                          forDid:userDid
                                        mimeType:@"image/jpeg"
                                           error:&error];

if (!blob) {
    PDS_LOG_ERROR(@"Blob upload failed: %@", error);
    return;
}

// 2. Create post record with image embed
NSDictionary *post = @{
    @"text": @"Check out this photo!",
    @"createdAt": [[NSDate date] ISO8601String],
    @"embed": @{
        @"$type": @"app.bsky.embed.images",
        @"images": @[@{
            @"image": blob[@"blob"],
            @"alt": @"A beautiful sunset"
        }]
    }
};

TID *tid = [TID tid];
[app.recordService putRecord:@"app.bsky.feed.post"
                        rkey:tid.stringValue
                       value:post
                      forDid:userDid
                    actorDid:userDid
              validationMode:PDSValidationModeOptimistic
                       error:&error];

// 3. Relay notification happens automatically via notification
```

### Pattern 3: Moderate Content

```objc
// 1. Review reported content
NSString *reportedUri = @"at://did:plc:user123/app.bsky.feed.post/abc123";
NSError *error = nil;

NSDictionary *record = [app.recordService getRecord:reportedUri
                                             forDid:@"did:plc:user123"
                                              error:&error];

// 2. Apply warning label
[app.adminService addLabel:@"!warn"
                  toTarget:reportedUri
                    reason:@"Potentially sensitive content"
                     error:&error];

// 3. If severe, takedown
if ([self isSevereViolation:record]) {
    [app.adminService takedownRecord:reportedUri
                              reason:@"Violation of terms"
                               error:&error];
}

// 4. Log moderation action
[self logModerationAction:@"takedown" target:reportedUri reason:@"Violation of terms"];
```

### Pattern 4: Export and Sync Repository

```objc
// 1. Get last synced commit
NSDictionary *lastSync = [self getLastSyncedCommit:userDid];
NSString *sinceRev = lastSync[@"rev"];

// 2. Export changes since last sync
NSError *error = nil;
PDSRepoChunkProducer producer = [app.repositoryService repoContentsChunkProducer:userDid
                                                                            since:sinceRev
                                                                            error:&error];

// 3. Stream to destination
if (producer) {
    while (YES) {
        NSError *chunkError = nil;
        NSData *chunk = producer(&chunkError);
        
        if (!chunk) break;
        
        // Send chunk to destination PDS
        [self sendChunkToDestination:chunk];
    }
}

// 4. Update last synced commit
NSDictionary *newCommit = [app.repositoryService getLatestCommitForDid:userDid error:&error];
[self saveLastSyncedCommit:newCommit forDid:userDid];
```

## Monitoring and Observability

### Key Metrics to Track

**Per-Service Metrics:**
- Request count (total, success, failure)
- Request latency (p50, p95, p99)
- Error rate
- Active requests (concurrency)

**Database Metrics:**
- Connection pool utilization
- Query latency
- Transaction duration
- Deadlock count

**System Metrics:**
- Memory usage per service
- CPU usage per service
- Thread count
- Queue depth

### Logging Best Practices

```objc
// Use structured logging with context
PDS_LOG_INFO(@"[AccountService] Account created: did=%@, handle=%@", did, handle);

// Log errors with full context
PDS_LOG_ERROR(@"[RecordService] Record creation failed: did=%@, collection=%@, error=%@",
              did, collection, error.localizedDescription);

// Log performance issues
if (elapsed > 1.0) {
    PDS_LOG_WARN(@"[RepositoryService] Slow export: did=%@, duration=%.2fs", did, elapsed);
}

// Log security events
PDS_LOG_SECURITY(@"[AdminService] Account suspended: did=%@, admin=%@, reason=%@",
                 targetDid, adminDid, reason);
```

### Health Checks

```objc
- (NSDictionary *)getServiceHealth {
    return @{
        @"accountService": @{
            @"status": [self.accountService isHealthy] ? @"healthy" : @"unhealthy",
            @"requestCount": @(self.accountService.requestCount),
            @"errorRate": @(self.accountService.errorRate)
        },
        @"recordService": @{
            @"status": [self.recordService isHealthy] ? @"healthy" : @"unhealthy",
            @"requestCount": @(self.recordService.requestCount),
            @"errorRate": @(self.recordService.errorRate)
        },
        // ... other services
        @"databases": @{
            @"status": [self.serviceDatabases isConnected] ? @"healthy" : @"unhealthy",
            @"poolUtilization": @(self.databasePool.utilizationPercent)
        }
    };
}
```

## Next Steps

- **[PDSApplication](pds-application)** — Application facade and lifecycle management
- **[Account Service](account-service)** — Account management details
- **[Record Service](record-service)** — Record operations details
- **[Blob Service](blob-service)** — Binary blob storage
- **[Repository Service](repository-service)** — MST and repository operations
- **[Admin Service](admin-service)** — Moderation and administration
- **[Relay Service](relay-service)** — Network participation and federation
- **[Network Layer](../04-network-layer/http-server)** — HTTP and XRPC
- **[Database Layer](../05-database-layer/sqlite-architecture)** — Data persistence
