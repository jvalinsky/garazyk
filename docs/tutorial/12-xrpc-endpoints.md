# Chapter 12: XRPC Endpoints

In Chapter 11, we implemented an HTTP server that can receive requests. But raw HTTP isn't enough—we need a structured way to expose our PDS functionality as an API. This chapter implements **XRPC**, the AT Protocol's RPC layer built on HTTP.

## What You'll Learn

By the end of this chapter, you'll be able to:
- Understand XRPC's design philosophy and URL conventions
- Implement a dispatcher pattern for routing RPC methods
- Build query handlers (GET) for reading data
- Build procedure handlers (POST) for writing data
- Handle pagination with cursors
- Implement proper error responses

## Prerequisites

This chapter assumes you understand:
- **HTTP Server** - Request handling with GCD (Chapter 11)
- **Merkle Search Trees** - Repository data structure (Chapter 6)
- **Content Identifiers** - CIDs for content addressing (Chapter 4)
- **DIDs** - Decentralized identifiers (Chapter 9)

---

## What is XRPC?

### The Problem: RPC Over HTTP

Most APIs need to expose procedures like "create a record" or "get a user profile." We could design a REST API, but AT Protocol chose a simpler model: **XRPC (HTTP + RPC semantics)**.

```
Traditional REST:
  POST /repos/{did}/collections/{collection}/records
  
XRPC Approach:
  POST /xrpc/com.atproto.repo.createRecord
```

**Why XRPC?**
- **Namespaced**: Methods are organized by reverse-DNS identifiers (NSIDs)
- **Simple mapping**: GET = query (read), POST = procedure (write)
- **Lexicon-defined**: Schemas define inputs/outputs (we'll cover lexicons later)
- **Consistent errors**: Standard error format across all methods

### XRPC Conventions

| Convention | Description | Example |
|------------|-------------|---------|
| **URL format** | `/xrpc/{nsid}` | `/xrpc/com.atproto.repo.getRecord` |
| **GET** | Query (read operation) | Fetch records, resolve handles |
| **POST** | Procedure (write operation) | Create records, upload blobs |
| **Query params** | For GET methods | `?repo=did:plc:abc&rkey=123` |
| **JSON body** | For POST methods | `{"repo": "did:plc:abc", ...}` |
| **JSON response** | All responses | `{"did": "did:plc:abc"}` |
| **Error format** | Standardized | `{"error": "InvalidRequest", "message": "..."}` |

### The NSID Structure

Method names use **Namespaced Identifiers (NSIDs)**:

```
com.atproto.repo.createRecord
│   │       │    └── Method name
│   │       └────── Namespace segment
│   └────────────── Organization segment
└────────────────── TLD (reverse DNS)
```

**Common NSID prefixes:**
- `com.atproto.server.*` - Server operations (auth, sessions)
- `com.atproto.repo.*` - Repository operations (records)
- `com.atproto.identity.*` - Identity resolution
- `com.atproto.sync.*` - Synchronization (CAR files)
- `app.bsky.*` - Bluesky app-specific methods

---

## Core XRPC Endpoints

Here are the essential endpoints a PDS must implement:

### Server Methods

| Method | Type | Description |
|--------|------|-------------|
| `com.atproto.server.describeServer` | GET | Server capabilities |
| `com.atproto.server.createSession` | POST | Login (get tokens) |
| `com.atproto.server.refreshSession` | POST | Refresh access token |
| `com.atproto.server.createAccount` | POST | Register new account |

### Repository Methods

| Method | Type | Description |
|--------|------|-------------|
| `com.atproto.repo.getRecord` | GET | Fetch single record |
| `com.atproto.repo.listRecords` | GET | List records (paginated) |
| `com.atproto.repo.createRecord` | POST | Create new record |
| `com.atproto.repo.putRecord` | POST | Update/upsert record |
| `com.atproto.repo.deleteRecord` | POST | Delete record |
| `com.atproto.repo.uploadBlob` | POST | Upload binary blob |

### Identity Methods

| Method | Type | Description |
|--------|------|-------------|
| `com.atproto.identity.resolveHandle` | GET | Handle → DID |
| `com.atproto.identity.resolveDid` | GET | DID → Document |

### Sync Methods

| Method | Type | Description |
|--------|------|-------------|
| `com.atproto.sync.getRepo` | GET | Export repository as CAR |
| `com.atproto.sync.getBlob` | GET | Fetch blob by CID |

---

## The Dispatcher Pattern

### Why a Dispatcher?

With many endpoints, we need organized routing. The **dispatcher pattern** separates:
1. **Routing logic** - Map URL → handler
2. **Handler logic** - Process request → response

```
Request URL: /xrpc/com.atproto.repo.createRecord
                      │
                      ▼
              ┌───────────────┐
              │  XrpcDispatcher │◄─ Registered handlers
              └───────┬───────┘
                      │
                      ▼
        ┌─────────────────────────────┐
        │  createRecord handler        │
        │  (in PDSController)          │
        └─────────────────────────────┘
```

### XrpcDispatcher Interface

```objc
// XrpcHandler.h
typedef void (^XrpcMethodHandler)(HttpRequest *request, HttpResponse *response);

@interface XrpcDispatcher : NSObject

@property (nonatomic, copy) void (^defaultHandler)(HttpRequest *, HttpResponse *);

+ (instancetype)sharedDispatcher;

// Generic registration
- (void)registerMethod:(NSString *)methodId handler:(XrpcMethodHandler)handler;

// Dispatch request to handler
- (void)handleRequest:(HttpRequest *)request response:(HttpResponse *)response;

// Convenience methods for standard endpoints
- (void)registerComAtprotoServerDescribeServer:(XrpcMethodHandler)handler;
- (void)registerComAtprotoRepoCreateRecord:(XrpcMethodHandler)handler;
- (void)registerComAtprotoRepoGetRecord:(XrpcMethodHandler)handler;
// ... more convenience methods

@end
```

### Implementation

```objc
@implementation XrpcDispatcher {
    NSMutableDictionary<NSString *, XrpcMethodHandler> *_handlers;
}

+ (instancetype)sharedDispatcher {
    static XrpcDispatcher *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[XrpcDispatcher alloc] init];
    });
    return shared;
}

- (instancetype)init {
    if (self = [super init]) {
        _handlers = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)registerMethod:(NSString *)methodId handler:(XrpcMethodHandler)handler {
    _handlers[methodId] = [handler copy];
}

- (void)handleRequest:(HttpRequest *)request response:(HttpResponse *)response {
    // Extract method NSID from path: /xrpc/com.atproto.repo.createRecord
    NSString *path = request.path;
    
    if (![path hasPrefix:@"/xrpc/"]) {
        [self sendError:@"MethodNotFound" 
                message:@"Not an XRPC endpoint" 
                   code:404 
               response:response];
        return;
    }
    
    NSString *methodId = [path substringFromIndex:6];  // Remove "/xrpc/"
    
    // Lookup handler
    XrpcMethodHandler handler = _handlers[methodId];
    
    if (!handler) {
        if (self.defaultHandler) {
            self.defaultHandler(request, response);
        } else {
            [self sendError:@"MethodNotFound"
                    message:[NSString stringWithFormat:@"Unknown method: %@", methodId]
                       code:400
                   response:response];
        }
        return;
    }
    
    // Invoke handler
    handler(request, response);
}

- (void)sendError:(NSString *)error
          message:(NSString *)message
             code:(NSInteger)code
         response:(HttpResponse *)response {
    response.statusCode = code;
    [response setJsonBody:@{@"error": error, @"message": message ?: @""}];
}

@end
```

**Key design choices:**
- Singleton dispatcher for easy access
- Block-based handlers for flexibility
- Default handler for unknown methods
- Standard error format

---

## Implementing Query Handlers (GET)

### resolveHandle

Resolves a handle (like `alice.bsky.social`) to a DID:

```objc
- (void)handleResolveHandle:(HttpRequest *)request response:(HttpResponse *)response {
    // 1. Extract query parameter
    NSString *handle = request.queryParams[@"handle"];
    
    if (!handle) {
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"InvalidRequest",
            @"message": @"handle parameter required"
        }];
        return;
    }
    
    // 2. Look up in database
    NSError *error = nil;
    NSString *did = [self.database getDIDForHandle:handle error:&error];
    
    if (!did) {
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"InvalidHandle",
            @"message": @"Unable to resolve handle"
        }];
        return;
    }
    
    // 3. Return success response
    response.statusCode = 200;
    [response setJsonBody:@{@"did": did}];
}
```

**Request flow:**
```
GET /xrpc/com.atproto.identity.resolveHandle?handle=alice.bsky.social
                                                      │
                                                      ▼
                                        ┌─────────────────────────┐
                                        │  Database lookup        │
                                        │  handle → did:plc:xyz   │
                                        └─────────────────────────┘
                                                      │
                                                      ▼
                                        Response: {"did": "did:plc:xyz"}
```

### getRecord

Fetches a single record by AT-URI components:

```objc
- (void)handleGetRecord:(HttpRequest *)request response:(HttpResponse *)response {
    // 1. Extract required parameters
    NSString *repo = request.queryParams[@"repo"];        // DID
    NSString *collection = request.queryParams[@"collection"];
    NSString *rkey = request.queryParams[@"rkey"];
    
    if (!repo || !collection || !rkey) {
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"InvalidRequest",
            @"message": @"repo, collection, and rkey required"
        }];
        return;
    }
    
    // 2. Build MST key: {collection}/{rkey}
    NSString *mstKey = [NSString stringWithFormat:@"%@/%@", collection, rkey];
    
    // 3. Get record from repository
    NSError *error = nil;
    NSDictionary *record = [self.repositoryManager getRecord:mstKey
                                                      forDID:repo
                                                       error:&error];
    
    if (!record) {
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"RecordNotFound",
            @"message": [NSString stringWithFormat:@"Could not locate record: %@", mstKey]
        }];
        return;
    }
    
    // 4. Return with AT-URI and CID
    NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", repo, collection, rkey];
    
    response.statusCode = 200;
    [response setJsonBody:@{
        @"uri": uri,
        @"cid": record[@"cid"],
        @"value": record[@"value"]
    }];
}
```

**The AT-URI format:**
```
at://did:plc:abc123/app.bsky.feed.post/3k5h7gbc8nr2c
     │             │                    │
     │             │                    └── Record key (rkey)
     │             └── Collection
     └── Repository (DID)
```

### listRecords with Pagination

For large result sets, use **cursor-based pagination**:

```objc
- (void)handleListRecords:(HttpRequest *)request response:(HttpResponse *)response {
    // 1. Extract parameters
    NSString *repo = request.queryParams[@"repo"];
    NSString *collection = request.queryParams[@"collection"];
    NSString *cursor = request.queryParams[@"cursor"];  // Optional
    NSInteger limit = [request.queryParams[@"limit"] integerValue] ?: 50;
    
    // Enforce limits
    if (limit > 100) limit = 100;
    if (limit < 1) limit = 1;
    
    if (!repo || !collection) {
        response.statusCode = 400;
        [response setJsonBody:@{@"error": @"InvalidRequest"}];
        return;
    }
    
    // 2. Query records
    NSError *error = nil;
    NSArray<NSDictionary *> *records = [self.repositoryManager listRecords:collection
                                                                    forDID:repo
                                                                    cursor:cursor
                                                                     limit:limit + 1
                                                                     error:&error];
    
    // 3. Determine if there are more results
    NSString *nextCursor = nil;
    if (records.count > limit) {
        // More records exist - use last rkey as cursor
        NSDictionary *lastRecord = records[limit - 1];
        nextCursor = lastRecord[@"rkey"];
        records = [records subarrayWithRange:NSMakeRange(0, limit)];
    }
    
    // 4. Format response
    NSMutableArray *formattedRecords = [NSMutableArray array];
    for (NSDictionary *record in records) {
        NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@",
                         repo, collection, record[@"rkey"]];
        [formattedRecords addObject:@{
            @"uri": uri,
            @"cid": record[@"cid"],
            @"value": record[@"value"]
        }];
    }
    
    NSMutableDictionary *responseBody = [NSMutableDictionary dictionary];
    responseBody[@"records"] = formattedRecords;
    if (nextCursor) {
        responseBody[@"cursor"] = nextCursor;
    }
    
    response.statusCode = 200;
    [response setJsonBody:responseBody];
}
```

**Cursor-based pagination:**
```
Page 1: GET /xrpc/.../listRecords?collection=posts&limit=10
        Response: {records: [...], cursor: "3k5h7gbc8nr2c"}

Page 2: GET /xrpc/.../listRecords?collection=posts&limit=10&cursor=3k5h7gbc8nr2c
        Response: {records: [...], cursor: "3k5h7def9mr3d"}

Last:   GET /xrpc/.../listRecords?...&cursor=3k5h7xyz
        Response: {records: [...]}  ← No cursor = no more pages
```

**Why cursors over offset/limit?**
- Stable results (new inserts don't shift pages)
- Efficient database queries (no OFFSET)
- Works with sorted data (MST is sorted by key)

---

## Implementing Procedure Handlers (POST)

### createRecord

Creates a new record, returning the AT-URI and CID:

```objc
- (void)handleCreateRecord:(HttpRequest *)request response:(HttpResponse *)response {
    // 1. Verify authentication
    if (![self verifyAuthForRequest:request response:response]) {
        return;  // Auth handler already set error response
    }
    
    // 2. Parse JSON body
    NSDictionary *body = [request jsonBody];
    NSString *repo = body[@"repo"];
    NSString *collection = body[@"collection"];
    NSString *rkey = body[@"rkey"];  // Optional - generated if not provided
    NSDictionary *record = body[@"record"];
    
    if (!repo || !collection || !record) {
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"InvalidRequest",
            @"message": @"repo, collection, and record required"
        }];
        return;
    }
    
    // 3. Verify caller owns the repo
    NSString *authedDID = [self getAuthenticatedDID:request];
    if (![authedDID isEqualToString:repo]) {
        response.statusCode = 403;
        [response setJsonBody:@{
            @"error": @"RepoNotWritable",
            @"message": @"Cannot write to another user's repository"
        }];
        return;
    }
    
    // 4. Generate rkey if not provided
    if (!rkey) {
        rkey = [TID tid].stringValue;  // Timestamp-based ID
    }
    
    // 5. Create record in repository
    NSError *error = nil;
    NSDictionary *result = [self.repositoryManager createRecord:record
                                                     collection:collection
                                                           rkey:rkey
                                                         forDID:repo
                                                          error:&error];
    
    if (!result) {
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"InvalidRequest",
            @"message": error.localizedDescription ?: @"Failed to create record"
        }];
        return;
    }
    
    // 6. Return success
    NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", repo, collection, rkey];
    
    response.statusCode = 200;
    [response setJsonBody:@{
        @"uri": uri,
        @"cid": result[@"cid"]
    }];
}
```

**Security checks:**
1. **Authentication** - Is there a valid JWT?
2. **Authorization** - Does the JWT's subject match the repo?
3. **Validation** - Is the record schema valid? (for Bluesky lexicons)

### deleteRecord

Removes a record from the repository:

```objc
- (void)handleDeleteRecord:(HttpRequest *)request response:(HttpResponse *)response {
    // 1. Verify authentication
    if (![self verifyAuthForRequest:request response:response]) {
        return;
    }
    
    // 2. Parse request
    NSDictionary *body = [request jsonBody];
    NSString *repo = body[@"repo"];
    NSString *collection = body[@"collection"];
    NSString *rkey = body[@"rkey"];
    
    if (!repo || !collection || !rkey) {
        response.statusCode = 400;
        [response setJsonBody:@{@"error": @"InvalidRequest"}];
        return;
    }
    
    // 3. Verify ownership
    NSString *authedDID = [self getAuthenticatedDID:request];
    if (![authedDID isEqualToString:repo]) {
        response.statusCode = 403;
        [response setJsonBody:@{@"error": @"RepoNotWritable"}];
        return;
    }
    
    // 4. Delete from repository
    NSError *error = nil;
    BOOL success = [self.repositoryManager deleteRecord:collection
                                                   rkey:rkey
                                                 forDID:repo
                                                  error:&error];
    
    if (!success) {
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"RecordNotFound",
            @"message": @"Record does not exist"
        }];
        return;
    }
    
    // 5. Return empty success (no content)
    response.statusCode = 200;
    [response setJsonBody:@{}];
}
```

---

## Error Handling

### Standard Error Format

All XRPC errors follow this format:

```json
{
  "error": "ErrorCode",
  "message": "Human-readable description"
}
```

### Common Error Codes

| Error | HTTP Status | When Used |
|-------|-------------|-----------|
| `InvalidRequest` | 400 | Missing/invalid parameters |
| `AuthenticationRequired` | 401 | No valid JWT |
| `InvalidToken` | 401 | Expired or malformed JWT |
| `ExpiredToken` | 401 | JWT past expiry |
| `RepoNotWritable` | 403 | User doesn't own repo |
| `RecordNotFound` | 400 | Record doesn't exist |
| `RateLimitExceeded` | 429 | Too many requests |
| `MethodNotFound` | 400 | Unknown XRPC method |
| `UpstreamFailure` | 502 | Dependency failed |

### Error Helper

```objc
typedef NS_ENUM(NSInteger, XRPCErrorCode) {
    XRPCErrorInvalidRequest,
    XRPCErrorAuthenticationRequired,
    XRPCErrorInvalidToken,
    XRPCErrorExpiredToken,
    XRPCErrorRepoNotWritable,
    XRPCErrorRecordNotFound,
    XRPCErrorRateLimitExceeded,
    XRPCErrorMethodNotFound
};

- (void)sendXRPCError:(XRPCErrorCode)errorCode
              message:(NSString *)message
             response:(HttpResponse *)response {
    NSString *errorName;
    NSInteger statusCode;
    
    switch (errorCode) {
        case XRPCErrorInvalidRequest:
            errorName = @"InvalidRequest";
            statusCode = 400;
            break;
        case XRPCErrorAuthenticationRequired:
            errorName = @"AuthenticationRequired";
            statusCode = 401;
            break;
        case XRPCErrorInvalidToken:
            errorName = @"InvalidToken";
            statusCode = 401;
            break;
        case XRPCErrorExpiredToken:
            errorName = @"ExpiredToken";
            statusCode = 401;
            break;
        case XRPCErrorRepoNotWritable:
            errorName = @"RepoNotWritable";
            statusCode = 403;
            break;
        case XRPCErrorRecordNotFound:
            errorName = @"RecordNotFound";
            statusCode = 400;
            break;
        case XRPCErrorRateLimitExceeded:
            errorName = @"RateLimitExceeded";
            statusCode = 429;
            break;
        case XRPCErrorMethodNotFound:
            errorName = @"MethodNotFound";
            statusCode = 400;
            break;
    }
    
    response.statusCode = statusCode;
    [response setJsonBody:@{
        @"error": errorName,
        @"message": message ?: @""
    }];
}
```

---

## Wiring It All Together

### XrpcMethodRegistry

Register all handlers in one place:

```objc
@implementation XrpcMethodRegistry

+ (void)registerMethodsWithDispatcher:(XrpcDispatcher *)dispatcher
                           controller:(PDSController *)controller {
    __weak PDSController *weakController = controller;
    
    // Server methods
    [dispatcher registerComAtprotoServerDescribeServer:^(HttpRequest *req, HttpResponse *resp) {
        [weakController handleDescribeServer:req response:resp];
    }];
    
    // Identity methods
    [dispatcher registerComAtprotoIdentityResolveHandle:^(HttpRequest *req, HttpResponse *resp) {
        [weakController handleResolveHandle:req response:resp];
    }];
    
    // Repository methods
    [dispatcher registerComAtprotoRepoGetRecord:^(HttpRequest *req, HttpResponse *resp) {
        [weakController handleGetRecord:req response:resp];
    }];
    
    [dispatcher registerComAtprotoRepoListRecords:^(HttpRequest *req, HttpResponse *resp) {
        [weakController handleListRecords:req response:resp];
    }];
    
    [dispatcher registerComAtprotoRepoCreateRecord:^(HttpRequest *req, HttpResponse *resp) {
        [weakController handleCreateRecord:req response:resp];
    }];
    
    [dispatcher registerComAtprotoRepoDeleteRecord:^(HttpRequest *req, HttpResponse *resp) {
        [weakController handleDeleteRecord:req response:resp];
    }];
    
    // Sync methods
    [dispatcher registerComAtprotoSyncGetRepo:^(HttpRequest *req, HttpResponse *resp) {
        [weakController handleGetRepo:req response:resp];
    }];
}

@end
```

### Integration in HTTP Server

```objc
- (void)startServer {
    // Create components
    PDSDatabase *db = [PDSDatabase databaseAtURL:self.config.databaseURL];
    [db openWithError:nil];
    
    PDSController *controller = [[PDSController alloc] init];
    controller.database = db;
    
    // Setup dispatcher
    XrpcDispatcher *dispatcher = [XrpcDispatcher sharedDispatcher];
    [XrpcMethodRegistry registerMethodsWithDispatcher:dispatcher
                                           controller:controller];
    
    // Create HTTP server with XRPC handler
    HttpServer *server = [HttpServer serverWithPort:self.config.port];
    
    [server addRoute:@"*" path:@"/xrpc/*" handler:^(HttpRequest *req, HttpResponse *resp) {
        [dispatcher handleRequest:req response:resp];
    }];
    
    [server startWithError:nil];
}
```

---

## Common Mistakes

### Mistake 1: Forgetting Authentication on Write Operations

❌ **What people do:**
```objc
- (void)handleCreateRecord:(HttpRequest *)request response:(HttpResponse *)response {
    // No auth check!
    NSDictionary *body = [request jsonBody];
    [self.repository createRecord:body[@"record"] ...];  // Anyone can write!
}
```

**Why this fails:**
- Anyone can create records in any repository
- No ownership verification
- Complete security bypass

✅ **Correct approach:**
```objc
- (void)handleCreateRecord:(HttpRequest *)request response:(HttpResponse *)response {
    // Always verify auth first
    if (![self verifyAuthForRequest:request response:response]) {
        return;
    }
    
    // Then verify ownership
    NSString *authedDID = [self getAuthenticatedDID:request];
    if (![authedDID isEqualToString:body[@"repo"]]) {
        [self sendXRPCError:XRPCErrorRepoNotWritable message:nil response:response];
        return;
    }
    // Now proceed...
}
```

### Mistake 2: Returning Wrong HTTP Status Codes

❌ **What people do:**
```objc
// WRONG: Using 404 for record not found
if (!record) {
    response.statusCode = 404;
    [response setJsonBody:@{@"error": @"RecordNotFound"}];
}
```

**Why this fails:**
- AT Protocol spec uses 400 for `RecordNotFound`
- 404 is reserved for path-level "not found" (unknown endpoint)
- Clients may handle status codes differently

✅ **Correct approach:**
```objc
// RIGHT: Use 400 for business logic errors
if (!record) {
    response.statusCode = 400;  // Not 404!
    [response setJsonBody:@{@"error": @"RecordNotFound"}];
}
```

### Mistake 3: Not Handling Pagination Properly

❌ **What people do:**
```objc
// WRONG: Return all records at once
NSArray *records = [self.repository getAllRecords:collection];
response.statusCode = 200;
[response setJsonBody:@{@"records": records}];  // Could be millions!
```

**Why this fails:**
- Unbounded memory usage
- Timeout for large collections
- Poor client experience

✅ **Correct approach:**
```objc
// RIGHT: Always paginate
NSInteger limit = MIN([params[@"limit"] integerValue] ?: 50, 100);
NSArray *records = [self.repository getRecords:collection
                                        cursor:params[@"cursor"]
                                         limit:limit + 1];

NSString *nextCursor = nil;
if (records.count > limit) {
    nextCursor = records[limit - 1][@"rkey"];
    records = [records subarrayWithRange:NSMakeRange(0, limit)];
}

[response setJsonBody:@{@"records": records, @"cursor": nextCursor}];
```

---

## Exercises

📝 **Exercise 1: Implement describeServer**

Create the `describeServer` handler that returns server capabilities:

```objc
- (void)handleDescribeServer:(HttpRequest *)req response:(HttpResponse *)resp;
// Should return: availableUserDomains, inviteCodeRequired, did, links
```

- Hint: This is a read-only endpoint, no auth required
- Bonus: Add `privacyPolicy` and `termsOfService` to links

📝 **Exercise 2: Add Blob Upload**

Implement the uploadBlob endpoint:

```objc
// POST /xrpc/com.atproto.repo.uploadBlob
// Content-Type: image/jpeg (or other mime type)
// Body: raw binary data

// Response: {"blob": {"$type": "blob", "ref": {...}, "mimeType": "image/jpeg", "size": 12345}}
```

- Hint: Store blob data with its CID, return reference
- Consider: How to validate mime type matches content?

📝 **Exercise 3: Rate Limiting**

Add rate limiting to your XRPC dispatcher:

```objc
@interface RateLimiter : NSObject
- (BOOL)allowRequest:(HttpRequest *)request;
@property (nonatomic, assign) NSInteger requestsPerMinute;
@end
```

- Hint: Track requests per IP with sliding window
- Challenge: Different limits for authenticated vs unauthenticated

---

## Summary

In this chapter, you learned:

- ✅ **XRPC design**: RPC-over-HTTP with NSID-based method routing
- ✅ **Dispatcher pattern**: Centralized routing to handler blocks
- ✅ **Query handlers**: GET methods for reading (resolveHandle, getRecord, listRecords)
- ✅ **Procedure handlers**: POST methods for writing (createRecord, deleteRecord)
- ✅ **Pagination**: Cursor-based paging for scalable lists
- ✅ **Error handling**: Standard error format and codes

## Key Takeaways

1. **GET = Query, POST = Procedure** - Simple mapping for all AT Protocol operations.

2. **Use cursors, not offsets** - Stable pagination that works with sorted data.

3. **Always authenticate writes** - No procedure should modify data without auth.

4. **Standard error format** - `{error: "ErrorCode", message: "..."}` for all errors.

## Looking Ahead

With XRPC endpoints in place, our PDS is nearly complete:
- **Identity** (Chapters 9-10): DIDs, PLC operations
- **Storage** (Chapters 5-7): CBOR, MST, CAR files  
- **Network** (Chapters 11-12): HTTP server, XRPC endpoints
- **Authentication** (Chapter 14): OAuth, JWT

In **Chapter 13**, we'll implement the **SQLite Database Layer**—the persistence backend that stores all our accounts and blocks.

---

**Files Referenced in This Chapter:**
- [XrpcHandler.h](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Network/XrpcHandler.h)
- [XrpcHandler.m](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Network/XrpcHandler.m)
- [XrpcMethodRegistry.h](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Network/XrpcMethodRegistry.h)
- [XrpcMethodRegistry.m](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Network/XrpcMethodRegistry.m)
- [PDSController.m](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/App/PDSController.m)

**Further Reading:**
- [AT Protocol XRPC Specification](https://atproto.com/specs/xrpc)
- [Lexicon Schema Language](https://atproto.com/specs/lexicon)
