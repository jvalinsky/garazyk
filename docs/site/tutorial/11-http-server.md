# Chapter 11: HTTP Server with Grand Central Dispatch

After building all the data structures (CIDs, CBOR, MSTs) and cryptographic primitives (secp256k1, DIDs), we need a way to expose our PDS functionality over the network. This chapter teaches you how to build a production-ready HTTP server using BSD sockets and Grand Central Dispatch (GCD) for concurrent request handling.

## What You'll Learn

By the end of this chapter, you'll be able to:
- Understand Grand Central Dispatch (GCD) and its concurrency model
- Build an HTTP server using network sockets
- Parse HTTP requests and generate responses
- Handle multiple concurrent connections safely
- Implement route matching and request dispatching
- Manage connection lifecycles with keep-alive

## Prerequisites

This chapter assumes you understand:
- Objective-C classes and blocks - covered in Chapters 1-2
- Error handling patterns - covered in Chapter 1
- Basic networking concepts (HTTP, TCP/IP)

---

## The Problem: Handling Many Users

### Why We Need Concurrency

Imagine our PDS serving 1,000 users simultaneously:
- User A is uploading a photo (slow, 5 seconds)
- User B is fetching their timeline (fast, 0.1 seconds)
- User C is creating a post (medium, 0.5 seconds)

**Without concurrency**: User B waits 5 seconds for User A's upload to finish
**With concurrency**: All users are served simultaneously

We need a way to handle many operations at once without blocking.

### Traditional Threading vs GCD

**Traditional threading** (manually create threads):
```
❌ Complex: Create, manage, and destroy threads
❌ Expensive: Each thread uses ~1MB of memory
❌ Error-prone: Race conditions, deadlocks
```

**Grand Central Dispatch** (Apple's solution):
```
✅ Simple: Just submit tasks to queues
✅ Efficient: Thread pool managed automatically
✅ Safe: Serial queues prevent race conditions
```

💡 **Key Insight**: GCD lets you think about "what work to do" rather than "how to manage threads."

---

## Understanding Grand Central Dispatch

### The Restaurant Analogy

Think of GCD like a restaurant:

**Dispatch Queue** = The kitchen's order system
- **Serial Queue**: Single-file line - one order processed at a time, in order
- **Concurrent Queue**: Multiple chefs - many orders cooked simultaneously

**Tasks (Blocks)** = Individual orders
- Customers submit orders (tasks)
- Kitchen (queue) processes them
- Orders can be sync (wait for dish) or async (call you when ready)

### Serial vs Concurrent Queues

**Serial Queue**: Like a single-file line at a bank
```
Customer 1 → Customer 2 → Customer 3
    ↓           ↓           ↓
  Task 1     Task 2      Task 3
(finishes   (waits)     (waits)
 first)
```

**Concurrent Queue**: Like multiple bank tellers
```
Customer 1 → Teller 1 → Task 1 (running)
Customer 2 → Teller 2 → Task 2 (running)
Customer 3 → Teller 3 → Task 3 (running)
    All happening simultaneously!
```

### Why Use a Serial Queue for Network Operations?

Our HTTP server uses a **serial queue** for socket operations. Why?

**Thread Safety**: Network sockets aren't thread-safe
- Multiple threads writing to same socket = corrupted data
- Multiple threads accepting connections = race conditions

**Ordering**: Network operations need sequencing
- Accept connection → Read request → Parse → Send response
- Must happen in order for each connection

**Simplicity**: Serial queue = no locks needed
- No mutexes, semaphores, or complex synchronization
- GCD guarantees one task at a time

💡 **Key Insight**: Serial queues are like single-file lines - simple, safe, predictable. Perfect for coordinating I/O operations.

### Creating a Serial Queue

```objc
// Create a serial queue for network operations
dispatch_queue_t serverQueue = dispatch_queue_create(
    "com.atproto.pds.httpserver",  // Unique reverse-DNS name
    DISPATCH_QUEUE_SERIAL           // Serial (one task at a time)
);
```

### Dispatching Tasks

**Async Dispatch** (most common - don't wait):
```objc
dispatch_async(serverQueue, ^{
    // This block runs on serverQueue
    // Code here executes later, not immediately
    NSLog(@"Task running on serial queue");
});
// Execution continues here immediately!
```

**Sync Dispatch** (wait for completion):
```objc
dispatch_sync(serverQueue, ^{
    // This block runs on serverQueue
    // Caller waits until this finishes
});
// Execution pauses until block completes
```

⚠️ **Warning**: Never call `dispatch_sync` on the queue you're already running on - it causes deadlock!

---

## Server Architecture Overview

Our HTTP server has three main components:

```
┌────────────────────────────────────────────────────────┐
│                   HttpServer                            │
├────────────────────────────────────────────────────────┤
│                                                         │
│  1. LISTENER (Accepts new connections)                 │
│     ┌──────────────┐                                   │
│     │   Socket     │──┐                                │
│     │  Port 3000   │  │ New connection                 │
│     └──────────────┘  ↓                                │
│                    ┌──────────────┐                    │
│  2. CONNECTION     │  Connection  │                    │
│     HANDLER        │   Handler    │                    │
│                    └──────────────┘                    │
│                        ↓                                │
│                    Read Request                         │
│                        ↓                                │
│  3. REQUEST        ┌──────────────┐                    │
│     DISPATCHER     │    Router    │→ Handler           │
│                    └──────────────┘                    │
│                        ↓                                │
│                    Send Response                        │
│                                                         │
│  All coordinated by: serverQueue (serial)              │
└────────────────────────────────────────────────────────┘
```

### Request Flow Sequence

```
Client                  Server
  │                       │
  ├──── TCP Connect ─────→│ 1. Listener accepts
  │                       │ 2. Create connection handler
  ├──── HTTP Request ────→│ 3. Read data from socket
  │                       │ 4. Parse HTTP headers/body
  │                       │ 5. Match route
  │                       │ 6. Execute handler
  │                       │ 7. Generate response
  │←─── HTTP Response ────┤ 8. Write to socket
  │                       │ 9. Keep-alive or close
```

---

## The HttpServer Interface

### Public API

```objc
// HttpServer.h
typedef void (^RequestHandler)(HttpRequest *request, HttpResponse *response);

@interface HttpServer : NSObject

@property (nonatomic, readonly) NSUInteger port;
@property (nonatomic, readonly, getter=isRunning) BOOL running;

+ (instancetype)serverWithPort:(NSUInteger)port;

- (BOOL)startWithError:(NSError **)error;
- (void)stop;

- (void)addRoute:(NSString *)method
            path:(NSString *)path
         handler:(RequestHandler)handler;

@end
```

**Why blocks for handlers?**
- Flexible: Can capture context from surrounding scope
- Concise: Define handlers inline where they're registered
- Type-safe: Compiler checks parameter types

### Internal State

```objc
@interface HttpServer ()

@property (nonatomic, strong) dispatch_queue_t serverQueue;
@property (nonatomic, strong) id<PDSNetworkListener> listener;
@property (nonatomic, strong) NSMutableSet *activeConnections;
@property (nonatomic, strong) NSMutableDictionary *pathHandlers;
@property (nonatomic, assign) BOOL running;

@end
```

---

## Initialization

```objc
- (instancetype)initWithPort:(NSUInteger)port {
    self = [super init];
    if (self) {
        _port = port;

        // Create serial queue for all network operations
        _serverQueue = dispatch_queue_create(
            "com.atproto.pds.httpserver",
            DISPATCH_QUEUE_SERIAL
        );

        // Route handlers: "GET /health" → handler block
        _pathHandlers = [NSMutableDictionary dictionary];

        // Track active connections for cleanup
        _activeConnections = [NSMutableSet set];

        // Semaphore for waiting until listener is ready
        _readySemaphore = dispatch_semaphore_create(0);
    }
    return self;
}
```

**Breaking this down:**

1. **Serial queue**: All socket operations happen here, one at a time
2. **Path handlers**: Map routes to handler blocks
3. **Active connections**: Track open connections for graceful shutdown
4. **Semaphore**: Synchronization primitive to wait for listener ready state

---

## Starting the Server

### The Start Flow

```
startWithError:
    ↓
Create listener socket
    ↓
Set up state change handler
    ↓
Set up new connection handler
    ↓
Start listener on serverQueue
    ↓
Wait for "ready" signal (or timeout)
    ↓
Return success/failure
```

### Implementation

```objc
- (BOOL)startWithError:(NSError **)error {
    if (self.running) return YES;  // Already running

    // Create network listener (abstracted for Mac/Linux portability)
    self.listener = [PDSNetworkTransportFactory createListenerWithPort:self.port];
    if (!self.listener) {
        if (error) {
            *error = [NSError errorWithDomain:@"HttpServer"
                                         code:-1
                                     userInfo:@{
                NSLocalizedDescriptionKey: @"Failed to create listener"
            }];
        }
        return NO;
    }

    __weak typeof(self) weakSelf = self;

    // Handler for listener state changes (ready, failed, cancelled)
    self.listener.stateChangedHandler = ^(PDSNetworkListenerState state, NSError *err) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;  // Server deallocated

        switch (state) {
            case PDSNetworkListenerStateReady:
                // Listener successfully bound to port and listening
                strongSelf->_running = YES;
                strongSelf->_port = strongSelf.listener.port;  // Actual port (if 0 was passed)
                dispatch_semaphore_signal(strongSelf.readySemaphore);  // Wake up starter
                NSLog(@"HTTP Server listening on port %lu", (unsigned long)strongSelf.port);
                break;

            case PDSNetworkListenerStateFailed:
            case PDSNetworkListenerStateCancelled:
                strongSelf->_running = NO;
                dispatch_semaphore_signal(strongSelf.readySemaphore);  // Wake up starter
                break;
        }
    };

    // Handler for new incoming connections
    self.listener.newConnectionHandler = ^(id<PDSNetworkConnection> connection) {
        [weakSelf handleNewConnection:connection];
    };

    // Start listener on our serial queue
    [self.listener startWithQueue:self.serverQueue];

    // Wait for ready signal (or timeout after 5 seconds)
    dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC);
    long result = dispatch_semaphore_wait(self.readySemaphore, timeout);

    if (result != 0) {  // Timeout occurred
        [self.listener cancel];
        if (error) {
            *error = [NSError errorWithDomain:@"HttpServer"
                                         code:-1
                                     userInfo:@{
                NSLocalizedDescriptionKey: @"Listener failed to start within 5 seconds"
            }];
        }
        return NO;
    }

    return self.running;
}
```

### Understanding Weak/Strong References

**The Problem**: Retain cycles with blocks

```objc
// ❌ BAD: Creates retain cycle
self.listener.handler = ^{
    [self doSomething];  // Block retains self
};                       // self retains listener
                         // listener retains block
                         // → Cycle! Memory leak!
```

**The Solution**: Weak-strong dance

```objc
// ✅ GOOD: Break the cycle
__weak typeof(self) weakSelf = self;  // Weak reference (can become nil)

self.listener.handler = ^{
    __strong typeof(weakSelf) strongSelf = weakSelf;  // Promote to strong
    if (!strongSelf) return;  // Self was deallocated, bail out

    [strongSelf doSomething];  // Safe to use
};
```

**Why this pattern?**
1. `weakSelf` doesn't prevent deallocation → breaks cycle
2. `strongSelf` ensures self stays alive during block execution
3. `if (!strongSelf)` guards against self being deallocated between weak and strong

💡 **Key Insight**: Think of weak references like a safety rope that lets go if the object falls - prevents you from being pulled down too.

---

## Handling New Connections

### Connection Lifecycle States

```
NEW → READY → READING → PROCESSING → WRITING → READY (keep-alive)
                                                  ↓
                                              CANCELLED → REMOVED
```

### Implementation

```objc
- (void)handleNewConnection:(id<PDSNetworkConnection>)connection {
    // Track connection for lifecycle management
    @synchronized (self.activeConnections) {
        [self.activeConnections addObject:connection];
    }

    __weak typeof(self) weakSelf = self;
    __weak id<PDSNetworkConnection> weakConnection = connection;

    // Set up state change handler
    connection.stateChangedHandler = ^(PDSNetworkConnectionState state, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        __strong typeof(weakConnection) strongConnection = weakConnection;
        if (!strongSelf || !strongConnection) return;

        switch (state) {
            case PDSNetworkConnectionStateReady:
                // Connection established, start reading request
                [strongSelf readRequestFromConnection:strongConnection];
                break;

            case PDSNetworkConnectionStateFailed:
                // Network error, close connection
                NSLog(@"Connection failed: %@", error);
                [strongConnection cancel];
                break;

            case PDSNetworkConnectionStateCancelled:
                // Connection closed, remove from tracking
                @synchronized (strongSelf.activeConnections) {
                    [strongSelf.activeConnections removeObject:strongConnection];
                }
                break;
        }
    };

    // Start connection on serial queue
    [connection startWithQueue:self.serverQueue];
}
```

**Why `@synchronized`?**

The `activeConnections` set is accessed from multiple queues:
- Main queue (during shutdown)
- Server queue (during normal operation)

`@synchronized` ensures only one thread modifies the set at a time.

---

## Reading and Parsing HTTP Requests

### HTTP Request Format

```
GET /health HTTP/1.1\r\n
Host: localhost:3000\r\n
User-Agent: curl/7.85.0\r\n
\r\n

POST /xrpc/com.atproto.repo.createRecord HTTP/1.1\r\n
Host: localhost:3000\r\n
Content-Type: application/json\r\n
Content-Length: 45\r\n
\r\n
{"collection":"app.bsky.feed.post","record":{...}}
```

**Structure:**
1. **Request line**: `METHOD PATH HTTP/VERSION`
2. **Headers**: `Key: Value` (one per line)
3. **Empty line**: `\r\n\r\n` (marks end of headers)
4. **Body**: Optional, length specified by `Content-Length`

### Reading Strategy

```
Read data → Check for complete headers (\r\n\r\n)
    ↓ Yes
Parse Content-Length
    ↓
Check if body complete
    ↓ Yes
Create HttpRequest object
    ↓
Dispatch to handler
```

### Implementation

```objc
- (void)readRequestFromConnection:(id<PDSNetworkConnection>)connection {
    __weak typeof(self) weakSelf = self;

    [connection receiveWithMinimumLength:1
                           maximumLength:UINT32_MAX
                              completion:^(NSData *content, BOOL isComplete, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;

        if (!strongSelf) return;

        if (error) {
            NSLog(@"Read error: %@", error);
            [connection cancel];
            return;
        }

        if (content && content.length > 0) {
            // Parse what we've received
            [strongSelf parseRequest:content fromConnection:connection];
        } else if (isComplete) {
            // Client closed connection
            [connection cancel];
        } else {
            // No data yet, keep reading
            [strongSelf readRequestFromConnection:connection];
        }
    }];
}
```

### Parsing the Request

```objc
- (void)parseRequest:(NSData *)data fromConnection:(id<PDSNetworkConnection>)connection {
    NSString *requestString = [[NSString alloc] initWithData:data
                                                    encoding:NSUTF8StringEncoding];

    // Find header/body separator
    NSRange headerEnd = [requestString rangeOfString:@"\r\n\r\n"];

    if (headerEnd.location == NSNotFound) {
        // Headers not complete yet
        if (data.length < 16384) {  // 16KB max header size
            // Read more data
            [self continueReadingRequest:data connection:connection];
        } else {
            // Headers too large, reject
            HttpResponse *response = [HttpResponse response];
            response.statusCode = 413;  // Payload Too Large
            [self sendResponse:response onConnection:connection];
        }
        return;
    }

    // Parse Content-Length from headers
    NSString *headers = [requestString substringToIndex:headerEnd.location];
    NSUInteger contentLength = [self parseContentLength:headers];

    // Calculate expected total length
    NSUInteger headerLength = headerEnd.location + 4;  // +4 for \r\n\r\n
    NSUInteger expectedLength = headerLength + contentLength;

    if (data.length < expectedLength) {
        // Body not complete yet, read more
        [self continueReadingRequest:data connection:connection];
        return;
    }

    // Request is complete! Create request object
    HttpRequest *request = [HttpRequest requestWithData:data
                                          remoteAddress:connection.remoteAddress];

    // Dispatch to handler on background queue (don't block network operations)
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        HttpResponse *response = [weakSelf dispatchRequest:request];

        // Send response back on server queue
        dispatch_async(weakSelf.serverQueue, ^{
            [weakSelf sendResponse:response onConnection:connection];
        });
    });
}
```

**Why dispatch to background queue?**

Handler execution might be slow (database queries, file I/O). We don't want to block the serial `serverQueue` - it needs to accept new connections and handle other I/O.

**Flow:**
1. Network I/O → `serverQueue` (serial)
2. Handler execution → global queue (concurrent)
3. Response send → `serverQueue` (serial)

---

## Route Matching and Dispatch

### Route Registration

```objc
- (void)addRoute:(NSString *)method
            path:(NSString *)path
         handler:(RequestHandler)handler {
    // Create unique key: "GET /health"
    NSString *key = [NSString stringWithFormat:@"%@ %@", method, path];

    self.pathHandlers[key] = [handler copy];  // Store handler
}
```

### Simple Route Matching

```objc
- (HttpResponse *)dispatchRequest:(HttpRequest *)request {
    HttpResponse *response = [HttpResponse response];

    // Build route key
    NSString *routeKey = [NSString stringWithFormat:@"%@ %@",
        request.method, request.path];

    // Look up exact match
    RequestHandler handler = self.pathHandlers[routeKey];

    if (handler) {
        // Found handler, execute it
        handler(request, response);
    } else {
        // No handler found
        response.statusCode = 404;
        [response setJsonBody:@{
            @"error": @"Not Found",
            @"message": [NSString stringWithFormat:@"No handler for %@ %@",
                request.method, request.path]
        }];
    }

    return response;
}
```

### Pattern Matching with Parameters

For routes like `/users/{id}` or `/xrpc/{lexicon}`:

```objc
- (RequestHandler)findHandlerForPath:(NSString *)path method:(NSString *)method {
    // Check all registered patterns
    for (NSString *patternKey in self.pathHandlers) {
        NSArray *parts = [patternKey componentsSeparatedByString:@" "];
        NSString *patternMethod = parts[0];
        NSString *patternPath = parts[1];

        if ([method isEqualToString:patternMethod] &&
            [self path:path matchesPattern:patternPath]) {
            return self.pathHandlers[patternKey];
        }
    }
    return nil;
}

- (BOOL)path:(NSString *)path matchesPattern:(NSString *)pattern {
    NSArray *pathParts = [path componentsSeparatedByString:@"/"];
    NSArray *patternParts = [pattern componentsSeparatedByString:@"/"];

    if (pathParts.count != patternParts.count) return NO;

    for (NSUInteger i = 0; i < pathParts.count; i++) {
        NSString *pathPart = pathParts[i];
        NSString *patternPart = patternParts[i];

        // {param} matches any value
        if ([patternPart hasPrefix:@"{"] && [patternPart hasSuffix:@"}"]) {
            continue;  // Wildcard match
        }

        // Exact match required
        if (![pathPart isEqualToString:patternPart]) {
            return NO;
        }
    }

    return YES;
}
```

**Example matching:**

```
Pattern: /users/{id}/posts
Path:    /users/123/posts  ✅ Match! {id} = "123"
Path:    /users/123/likes  ❌ No match (posts ≠ likes)
Path:    /users/123        ❌ No match (different length)
```

---

## Sending Responses

### HTTP Response Format

```
HTTP/1.1 200 OK\r\n
Content-Type: application/json\r\n
Content-Length: 15\r\n
Connection: keep-alive\r\n
\r\n
{"status":"ok"}
```

### Implementation

```objc
- (void)sendResponse:(HttpResponse *)response
         onConnection:(id<PDSNetworkConnection>)connection {
    // Serialize response to bytes
    NSData *responseData = [response serialize];
    BOOL shouldKeepAlive = response.keepAlive;

    __weak typeof(self) weakSelf = self;

    // Send data asynchronously
    [connection sendData:responseData completion:^(NSError *error) {
        if (error) {
            NSLog(@"Failed to send response: %@", error);
            [connection cancel];
            return;
        }

        if (shouldKeepAlive) {
            // HTTP/1.1 keep-alive: connection stays open for next request
            [weakSelf readRequestFromConnection:connection];
        } else {
            // Close connection
            [connection cancel];
        }
    }];
}
```

### HTTP Keep-Alive

**Without keep-alive** (HTTP/1.0 default):
```
Client                    Server
   │─────── Request 1 ─────→│
   │←────── Response 1 ─────│
   │  (close connection)
   │─────── Request 2 ─────→│  (new connection)
   │←────── Response 2 ─────│
   │  (close connection)
```

**With keep-alive** (HTTP/1.1 default):
```
Client                    Server
   │─────── Request 1 ─────→│
   │←────── Response 1 ─────│
   │─────── Request 2 ─────→│  (same connection)
   │←────── Response 2 ─────│
   │  (eventually close)
```

**Benefits:**
- Fewer TCP handshakes (faster)
- Lower CPU usage (fewer connections)
- Better throughput

---

## Example Usage

### Basic Server Setup

```objc
// Create server
HttpServer *server = [HttpServer serverWithPort:3000];

// Register health check endpoint
[server addRoute:@"GET" path:@"/health" handler:^(HttpRequest *req, HttpResponse *resp) {
    resp.statusCode = 200;
    [resp setJsonBody:@{
        @"status": @"ok",
        @"timestamp": @([[NSDate date] timeIntervalSince1970])
    }];
}];

// Register echo endpoint
[server addRoute:@"POST" path:@"/echo" handler:^(HttpRequest *req, HttpResponse *resp) {
    NSDictionary *body = [req jsonBody];
    resp.statusCode = 200;
    [resp setJsonBody:@{
        @"echo": body,
        @"headers": req.headers
    }];
}];

// Register parameterized route
[server addRoute:@"GET" path:@"/users/{id}" handler:^(HttpRequest *req, HttpResponse *resp) {
    NSString *userId = [req pathParameter:@"id"];
    resp.statusCode = 200;
    [resp setJsonBody:@{
        @"userId": userId,
        @"message": [NSString stringWithFormat:@"User %@ details", userId]
    }];
}];

// Start server
NSError *error = nil;
if ([server startWithError:&error]) {
    NSLog(@"Server running on port %lu", (unsigned long)server.port);
} else {
    NSLog(@"Failed to start: %@", error);
}
```

<script setup>
const mockHttpServerCode = `#import <Foundation/Foundation.h>

// --- Mock Classes for Simulation ---

@interface HttpRequest : NSObject
@property (nonatomic, copy) NSString *method;
@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy) NSString *remoteAddress;
@property (nonatomic, copy) NSDictionary *headers;
+ (instancetype)requestWithMethod:(NSString *)m path:(NSString *)p;
@end

@implementation HttpRequest
+ (instancetype)requestWithMethod:(NSString *)m path:(NSString *)p {
    HttpRequest *r = [HttpRequest new];
    r.method = m; r.path = p; r.remoteAddress = @"127.0.0.1";
    return r;
}
@end

@interface HttpResponse : NSObject
@property (nonatomic, assign) NSInteger statusCode;
@property (nonatomic, strong) NSMutableDictionary *headers;
@property (nonatomic, copy) NSDictionary *body;
@end

@implementation HttpResponse
- (instancetype)init { if(self=[super init]) _headers = [NSMutableDictionary dictionary]; return self; }
@end

typedef void (^RequestHandler)(HttpRequest *, HttpResponse *);
typedef BOOL (^MiddlewareHandler)(HttpRequest *, HttpResponse *);

@interface HttpServer : NSObject
@property (nonatomic, strong) NSMutableArray<MiddlewareHandler> *middlewares;
@property (nonatomic, strong) NSMutableDictionary *routes;
- (void)addRoute:(NSString *)method path:(NSString *)path handler:(RequestHandler)handler;
- (void)addMiddleware:(MiddlewareHandler)middleware;
- (HttpResponse *)dispatch:(HttpRequest *)req;
@end

@implementation HttpServer
- (instancetype)init {
    if(self=[super init]) {
        _middlewares = [NSMutableArray array];
        _routes = [NSMutableDictionary dictionary];
    }
    return self;
}
- (void)addRoute:(NSString *)method path:(NSString *)path handler:(RequestHandler)handler {
    NSString *key = [NSString stringWithFormat:@"%@ %@", method, path];
    self.routes[key] = [handler copy];
}
- (void)addMiddleware:(MiddlewareHandler)middleware {
    [self.middlewares addObject:[middleware copy]];
}
- (HttpResponse *)dispatch:(HttpRequest *)req {
    HttpResponse *resp = [HttpResponse new];
    
    // 1. Run Middleware
    for (MiddlewareHandler mw in self.middlewares) {
        if (!mw(req, resp)) return resp; // Middleware intercepted
    }
    
    // 2. Route Dispatch
    NSString *key = [NSString stringWithFormat:@"%@ %@", req.method, req.path];
    RequestHandler h = self.routes[key];
    if (h) {
        h(req, resp);
    } else {
        resp.statusCode = 404;
    }
    return resp;
}
@end
`;

const exercise1Code = mockHttpServerCode + `
// --- EXERCISE 1: Logger Middleware ---

void runDemo() {
    HttpServer *server = [HttpServer new];
    
    // Setup a route
    [server addRoute:@"GET" path:@"/health" handler:^(HttpRequest *req, HttpResponse *resp) {
        resp.statusCode = 200;
        resp.body = @{@"status": @"ok"};
    }];
    
    // TODO: Add Logger Middleware
    // Should log: "METHOD PATH from IP"
    [server addMiddleware:^BOOL(HttpRequest *req, HttpResponse *resp) {
        // Implement logger here
        // Return YES to continue, NO to stop
        return YES;
    }];
    
    // Simulate Request
    printf("Simulating GET /health...\\n");
    [server dispatch:[HttpRequest requestWithMethod:@"GET" path:@"/health"]];
}

int main() {
    @autoreleasepool {
        runDemo();
    }
    return 0;
}`;

const exercise3Code = mockHttpServerCode + `
// --- EXERCISE 3: CORS Middleware ---

void runDemo() {
    HttpServer *server = [HttpServer new];
    
    [server addRoute:@"GET" path:@"/api/data" handler:^(HttpRequest *req, HttpResponse *resp) {
        resp.statusCode = 200;
        resp.body = @{@"data": @123};
    }];
    
    // TODO: Add CORS Middleware
    // Set headers: Access-Control-Allow-Origin: *
    [server addMiddleware:^BOOL(HttpRequest *req, HttpResponse *resp) {
        // Implement CORS here
        return YES;
    }];
    
    // Simulate Request
    HttpResponse *resp = [server dispatch:[HttpRequest requestWithMethod:@"GET" path:@"/api/data"]];
    
    printf("Status: %ld\\n", resp.statusCode);
    printf("CORS Header: %s\\n", [resp.headers[@"Access-Control-Allow-Origin"] UTF8String]);
    
    if ([resp.headers[@"Access-Control-Allow-Origin"] isEqualToString:@"*"]) {
        printf("PASS: CORS header present.\\n");
    } else {
        printf("FAIL: Missing CORS header.\\n");
    }
}

int main() {
    @autoreleasepool {
        runDemo();
    }
    return 0;
}`;
</script>

### Testing with curl

```bash
# Health check
curl http://localhost:3000/health

# Echo request
curl -X POST http://localhost:3000/echo \
  -H "Content-Type: application/json" \
  -d '{"message":"Hello, PDS!"}'

# Parameterized route
curl http://localhost:3000/users/alice123
```

---

## Common Mistakes

### Mistake 1: Forgetting Weak-Strong Dance

❌ **WRONG:**
```objc
self.listener.handler = ^{
    [self doSomething];  // Retain cycle!
};
```

✅ **CORRECT:**
```objc
__weak typeof(self) weakSelf = self;
self.listener.handler = ^{
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) return;
    [strongSelf doSomething];
};
```

### Mistake 2: Blocking the Serial Queue

❌ **WRONG:**
```objc
// Handler executes on serverQueue - blocks other connections!
[server addRoute:@"GET" path:@"/slow" handler:^(HttpRequest *req, HttpResponse *resp) {
    sleep(10);  // Blocks serverQueue for 10 seconds!
    resp.statusCode = 200;
}];
```

✅ **CORRECT:**
```objc
// Dispatch slow work to background queue
[server addRoute:@"GET" path:@"/slow" handler:^(HttpRequest *req, HttpResponse *resp) {
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        sleep(10);  // Doesn't block serverQueue
        resp.statusCode = 200;
    });
}];
```

### Mistake 3: Not Checking Content-Length

❌ **WRONG:**
```objc
// Assume all data arrived at once
HttpRequest *request = [HttpRequest requestWithData:data];
// Might only have partial body!
```

✅ **CORRECT:**
```objc
// Check Content-Length and accumulate data until complete
NSUInteger contentLength = [self parseContentLength:headers];
if (data.length < expectedLength) {
    [self continueReadingRequest:data connection:connection];
    return;
}
```

### Mistake 4: Calling `dispatch_sync` on Same Queue

❌ **WRONG:**
```objc
dispatch_async(serverQueue, ^{
    dispatch_sync(serverQueue, ^{
        // DEADLOCK! Can't run because outer block holds queue
    });
});
```

✅ **CORRECT:**
```objc
dispatch_async(serverQueue, ^{
    // Just call directly if you're already on the queue
    [self doSomething];
});
```

---

## Exercises

📝 **Exercise 1: Add a Logger Middleware**

Create middleware that logs every request:

<ObjcRunner :initialCode="exercise1Code" />


---

📝 **Exercise 2: Implement Request Timeout**

Add a timeout that cancels requests taking longer than 30 seconds.

<details>
<summary>Hint</summary>

Use `dispatch_after` to schedule a cancellation block, and cancel it if the response completes first.

</details>

---

📝 **Exercise 3: Add CORS Headers**

Add middleware that sets CORS headers for all responses:

<ObjcRunner :initialCode="exercise3Code" />

---

## Summary

In this chapter, you learned:

- ✅ **Grand Central Dispatch**: Serial vs concurrent queues, async dispatch
- ✅ **HTTP server architecture**: Listener, connections, routing
- ✅ **Request lifecycle**: Accept, read, parse, dispatch, respond
- ✅ **Thread safety**: Serial queues, weak-strong dance, @synchronized
- ✅ **Route matching**: Exact and pattern matching with parameters
- ✅ **Keep-alive**: Connection reuse for efficiency

## Key Takeaways

1. **Serial queues simplify concurrency**: One task at a time = no race conditions
2. **Weak-strong dance prevents retain cycles**: Essential for blocks capturing self
3. **Dispatch slow work to background**: Don't block the serial network queue
4. **HTTP is stateless**: Each request is independent (unless using keep-alive)
5. **Always check Content-Length**: Requests might arrive in multiple chunks

## Looking Ahead

In **Chapter 12**, we'll implement **XRPC endpoints** on top of this HTTP server. You'll learn how to:
- Define XRPC methods (queries and procedures)
- Validate request parameters
- Handle AT Protocol-specific features (did:key auth, lexicon validation)
- Implement the full PDS API surface

Everything you learned about HTTP handling forms the foundation for XRPC!

---

**Files Referenced in This Chapter:**
- [HttpServer.h](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Network/HttpServer.h)
- [HttpServer.m](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Network/HttpServer.m)
- [PDSNetworkTransport.h](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Compat/PDSNetworkTransport.h)

**Further Reading:**
- [Grand Central Dispatch In-Depth](https://developer.apple.com/library/archive/documentation/General/Conceptual/ConcurrencyProgrammingGuide/)
- [HTTP/1.1 Specification (RFC 7230)](https://tools.ietf.org/html/rfc7230)
- [Network Programming Guide](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/NetworkingOverview/)
