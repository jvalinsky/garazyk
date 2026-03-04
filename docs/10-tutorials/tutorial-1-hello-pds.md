---
title: "Tutorial 1: Hello PDS"
---

# Tutorial 1: Hello PDS

## Overview

In this tutorial, you'll build a minimal Personal Data Server (PDS) from scratch. This hands-on introduction will guide you through creating a working server that responds to AT Protocol XRPC requests, giving you a solid foundation for understanding how September PDS works internally.

By the end of this tutorial, you'll have a running server that implements the `com.atproto.server.describeServer` endpoint—the fundamental discovery mechanism that clients use to learn about a PDS's capabilities.

### What You'll Build

A minimal but functional PDS that:
- Listens for HTTP connections on port 2583
- Handles AT Protocol XRPC requests
- Responds with server metadata
- Uses proper Objective-C patterns with ARC

This tutorial focuses on the core mechanics without the complexity of authentication, database persistence, or full protocol compliance. Think of it as "Hello World" for AT Protocol servers.

**Learning Objectives:**
- Understand PDS initialization and lifecycle
- Create a simple HTTP server from scratch
- Implement XRPC request routing
- Return properly formatted JSON responses
- Use Foundation framework networking primitives

**Estimated Time:** 30-45 minutes

## Prerequisites

Before starting this tutorial, you should have:

- **Development Environment:**
  - macOS with Xcode 16.1+ (recommended), or
  - Linux with GNUstep 2.2+ runtime
  - CMake 3.28 or later
  
- **Knowledge:**
  - Basic Objective-C syntax (classes, methods, properties)
  - Familiarity with command-line tools
  - Understanding of HTTP request/response cycle
  
- **Optional but Helpful:**
  - Experience with socket programming
  - Understanding of JSON data format
  - Familiarity with REST/RPC concepts

## Step 1: Create Project Structure

First, let's set up the basic directory structure for our minimal PDS:

```bash
mkdir hello-pds
cd hello-pds
mkdir -p src build
```objc

### Why This Structure?

This follows the standard CMake convention of separating source code (`src/`) from build artifacts (`build/`). Out-of-source builds keep your source directory clean and make it easy to rebuild from scratch by simply deleting the `build/` directory.

## Step 2: Create Main Entry Point

The entry point is where your PDS comes to life. This is where we initialize the server, configure it, and start listening for requests.

Create `src/main.m`:

```objc
#import <Foundation/Foundation.h>
#import "PDSApplication.h"

int main(int argc, char *argv[]) {
    @autoreleasepool {
        // 1. Create configuration
        PDSConfiguration *config = [[PDSConfiguration alloc] init];
        config.serverPort = 2583;
        config.issuer = @"did:web:localhost:2583";
        config.databasePath = @"./pds-data/db";
        
        // 2. Initialize PDS
        NSError *error = nil;
        PDSApplication *app = [[PDSApplication alloc] 
            initWithConfiguration:config error:&error];
        
        if (!app) {
            NSLog(@"Failed to initialize PDS: %@", error);
            return 1;
        }
        
        // 3. Start server
        [app.httpServer startWithCompletion:^(NSError *error) {
            if (error) {
                NSLog(@"Failed to start server: %@", error);
                exit(1);
            }
            
            NSLog(@"PDS started on port %ld", (long)config.serverPort);
        }];
        
        // 4. Keep running
        [[NSRunLoop mainRunLoop] run];
    }
    
    return 0;
}
```objc

### Understanding the Code

**The `@autoreleasepool` block** is essential in Objective-C programs. It manages memory for autoreleased objects—objects that are marked for deferred cleanup. Without this, your program would leak memory. In a long-running server, proper memory management is critical.

**Configuration setup** defines three key parameters:
- `serverPort: 2583` — The standard AT Protocol PDS port
- `issuer` — Your server's DID (Decentralized Identifier), which uniquely identifies this PDS in the AT Protocol network
- `databasePath` — Where to store persistent data (we're not using it yet, but it's required)

**Error handling** follows Objective-C conventions: methods that can fail take an `NSError **` parameter. Always check if initialization succeeded before proceeding.

**The run loop** (`[[NSRunLoop mainRunLoop] run]`) keeps your program alive. Without it, `main()` would return immediately after starting the server, terminating the process. The run loop processes events (like incoming HTTP connections) indefinitely.

### Why This Matters

This pattern—configure, initialize, start, run—is the foundation of every September PDS instance. Understanding it here makes it easier to work with the full production server later.

## Step 3: Create Configuration

Configuration objects encapsulate all the settings your PDS needs. This keeps your code clean and makes it easy to change settings without hunting through the codebase.

Create `src/PDSConfiguration.m`:

```objc
#import "PDSConfiguration.h"

@implementation PDSConfiguration

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    
    self.serverHost = @"0.0.0.0";
    self.serverPort = 2583;
    self.databasePath = @"./pds-data/db";
    
    return self;
}

@end
```objc

### Understanding the Configuration

**`serverHost = @"0.0.0.0"`** means "listen on all network interfaces." This allows connections from localhost, your local network, and external networks (if your firewall permits). In production, you'd typically put nginx or another reverse proxy in front of your PDS.

**Port 2583** is the conventional AT Protocol PDS port. Using standard ports makes it easier for clients to discover and connect to your server.

**The initialization pattern** (`self = [super init]; if (!self) return nil;`) is standard Objective-C. Always call the superclass initializer first, and always check if it succeeded before continuing.

## Step 4: Create HTTP Server

Now for the interesting part: a basic HTTP server built on BSD sockets. This is simplified compared to September's production `HttpServer`, but it demonstrates the core concepts.

Create `src/HttpServer.m`:

```objc
#import "HttpServer.h"

@implementation HttpServer

- (instancetype)initWithPort:(NSInteger)port error:(NSError **)error {
    self = [super init];
    if (!self) return nil;
    
    self.port = port;
    self.routes = [NSMutableDictionary dictionary];
    
    return self;
}

- (void)registerRoute:(NSString *)path 
              handler:(HttpRequestHandler)handler {
    self.routes[path] = [handler copy];
}

- (void)startWithCompletion:(void (^)(NSError *error))completion {
    // Create socket
    int serverSocket = socket(AF_INET, SOCK_STREAM, 0);
    if (serverSocket < 0) {
        NSError *error = [NSError errorWithDomain:@"HTTP" code:1 userInfo:nil];
        completion(error);
        return;
    }
    
    // Set socket options
    int optval = 1;
    setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &optval, sizeof(optval));
    
    // Bind to port
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
    addr.sin_port = htons(self.port);
    
    if (bind(serverSocket, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        NSError *error = [NSError errorWithDomain:@"HTTP" code:2 userInfo:nil];
        completion(error);
        return;
    }
    
    // Listen
    listen(serverSocket, SOMAXCONN);
    
    self.serverSocket = serverSocket;
    self.isRunning = YES;
    
    // Accept connections in background
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self acceptConnections];
    });
    
    completion(nil);
}

- (void)acceptConnections {
    while (self.isRunning) {
        struct sockaddr_in clientAddr;
        socklen_t clientAddrLen = sizeof(clientAddr);
        
        int clientSocket = accept(self.serverSocket, 
                                 (struct sockaddr *)&clientAddr, 
                                 &clientAddrLen);
        
        if (clientSocket < 0) continue;
        
        // Handle client in background
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self handleClient:clientSocket];
        });
    }
}

- (void)handleClient:(int)clientSocket {
    // Read request
    char buffer[4096];
    ssize_t n = read(clientSocket, buffer, sizeof(buffer));
    
    if (n <= 0) {
        close(clientSocket);
        return;
    }
    
    NSString *requestStr = [[NSString alloc] initWithBytes:buffer 
                                                    length:n 
                                                  encoding:NSUTF8StringEncoding];
    
    // Parse request
    NSArray *lines = [requestStr componentsSeparatedByString:@"\r\n"];
    NSArray *requestLine = [lines[0] componentsSeparatedByString:@" "];
    NSString *path = requestLine[1];
    
    // Find handler
    HttpRequestHandler handler = self.routes[path];
    if (!handler) {
        handler = self.routes[@"/xrpc/*"];
    }
    
    // Create response
    NSString *response = @"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{\"status\":\"ok\"}";
    
    // Send response
    write(clientSocket, [response UTF8String], response.length);
    close(clientSocket);
}

@end
```objc

### Understanding the HTTP Server

This server uses **BSD sockets**, the low-level POSIX API for network programming. While Foundation provides higher-level networking APIs, understanding sockets helps you appreciate what's happening under the hood.

**Key socket operations:**
1. `socket()` — Creates a new socket file descriptor
2. `setsockopt()` — Configures socket options (SO_REUSEADDR lets you restart quickly without "address already in use" errors)
3. `bind()` — Associates the socket with a specific port
4. `listen()` — Marks the socket as passive, ready to accept connections
5. `accept()` — Blocks until a client connects, then returns a new socket for that client

**Concurrency with Grand Central Dispatch (GCD):** The server uses `dispatch_async` to handle connections in background threads. This prevents one slow client from blocking others. The pattern is:
- Main thread: accepts connections
- Background threads: handle individual requests

**Route registration** uses a dictionary to map paths to handler blocks. This is a simple routing mechanism—production servers use more sophisticated pattern matching.

### Why This Approach?

September's production `HttpServer` is more sophisticated (HTTP/1.1 pipelining, chunked encoding, WebSocket upgrade), but this simplified version illustrates the core pattern: listen, accept, dispatch, respond.

## Step 5: Create XRPC Handler

XRPC (Cross-organizational RPC) is AT Protocol's RPC mechanism. Each method is identified by an NSID (Namespaced Identifier) like `com.atproto.server.describeServer`.

Create `src/XrpcDispatcher.m`:

```objc
#import "XrpcDispatcher.h"

@implementation XrpcDispatcher

- (void)dispatchRequest:(HttpRequest *)request 
               response:(HttpResponse *)response {
    
    // Extract NSID from path
    NSString *path = request.path;
    NSString *nsid = [path stringByReplacingOccurrencesOfString:@"/xrpc/" withString:@""];
    
    // Handle specific methods
    if ([nsid isEqualToString:@"com.atproto.server.describeServer"]) {
        [self handleDescribeServer:request response:response];
    } else {
        response.statusCode = 404;
        response.body = [@{@"error": @"MethodNotFound"} JSONData];
    }
}

- (void)handleDescribeServer:(HttpRequest *)request 
                    response:(HttpResponse *)response {
    
    NSDictionary *result = @{
        @"did": @"did:web:localhost:2583",
        @"availableUserDomains": @[@"localhost"],
        @"inviteCodeRequired": @NO,
        @"phoneNumberRequired": @NO
    };
    
    response.statusCode = 200;
    response.body = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
}

@end
```objc

### Understanding XRPC Dispatch

**The NSID extraction** strips `/xrpc/` from the path, leaving just the method identifier. In production, you'd validate the NSID format and handle query parameters.

**`com.atproto.server.describeServer`** is the discovery endpoint. Clients call this first to learn about your server's capabilities:
- `did` — Your server's identity
- `availableUserDomains` — Which domains can be used for handles
- `inviteCodeRequired` — Whether new users need an invite
- `phoneNumberRequired` — Whether phone verification is required

**Error handling** returns a 404 with a `MethodNotFound` error for unknown NSIDs. AT Protocol defines standard error codes that clients expect.

### Why This Matters

XRPC is how clients communicate with your PDS. Every operation—creating accounts, posting records, fetching data—goes through XRPC endpoints. Understanding the dispatch pattern here prepares you for implementing more complex endpoints later.

## Step 6: Build and Run

Now let's compile and run your PDS:

```bash
# Create build directory
mkdir -p build && cd build

# Configure with CMake
cmake ..

# Build
make

# Run
./hello-pds
```objc

## What's Happening During the Build?

CMake generates platform-specific build files (Makefiles on Linux/macOS, Visual Studio projects on Windows). The `make` command then compiles your Objective-C source files and links them into an executable.

If you see compilation errors, double-check that:
- You have all the header files (`.h`) matching your implementation files (`.m`)
- Your `CMakeLists.txt` includes all source files
- Foundation framework is properly linked

## Step 7: Test the Server

With your server running, open another terminal and test it:

```bash
# Test the server
curl -s http://localhost:2583/xrpc/com.atproto.server.describeServer | jq .

# Expected output:
# {
#   "did": "did:web:localhost:2583",
#   "availableUserDomains": ["localhost"],
#   "inviteCodeRequired": false,
#   "phoneNumberRequired": false
# }
```objc

## Understanding the Response

This JSON response tells clients:
- **`did`** — Your server's decentralized identifier. The `did:web` method uses DNS for identity.
- **`availableUserDomains`** — Users can create handles like `alice.localhost`
- **`inviteCodeRequired: false`** — Anyone can create an account (in production, you'd typically require invites)
- **`phoneNumberRequired: false`** — No phone verification needed

**Success!** You've just implemented your first AT Protocol endpoint.

## Common Pitfalls

**Memory Management:** Even with ARC, you can create retain cycles with blocks. In this tutorial, we're careful to avoid capturing `self` strongly in completion handlers.

**Socket Errors:** If `bind()` fails with "Address already in use," another process is using port 2583. Either kill that process or change your port.

**Thread Safety:** Our simple server isn't thread-safe. Production servers need locks or serial queues to protect shared state.

## Next Steps

- **[Tutorial 2: Account Management](tutorial-2-accounts)** — Add account creation
- **[Tutorial 3: Record Operations](tutorial-3-records)** — Add record CRUD
- **[Tutorial 4: Authentication](tutorial-4-auth)** — Add JWT tokens


## Summary

You've successfully created a minimal PDS that initializes the application, starts an HTTP server, handles XRPC requests, and returns responses.

## Next Steps

- **[Tutorial 2: Account Management](tutorial-2-accounts)** — Add account creation and storage
