# Tutorial 1: Hello PDS

## Overview

In this tutorial, you'll build a minimal PDS with a single endpoint that responds to requests.

**Learning Objectives:**
- Understand PDS initialization
- Create a simple HTTP endpoint
- Handle XRPC requests
- Return responses

**Time:** 30 minutes

## Prerequisites

- Xcode 16.1 or later (macOS) or GNUstep (Linux)
- CMake 3.28 or later
- Basic Objective-C knowledge

## Step 1: Create Project Structure

```bash
mkdir hello-pds
cd hello-pds
mkdir -p src build
```

## Step 2: Create Main Entry Point

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
```

## Step 3: Create Configuration

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
```

## Step 4: Create HTTP Server

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
```

## Step 5: Create XRPC Handler

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
```

## Step 6: Build and Run

```bash
# Create build directory
mkdir -p build && cd build

# Configure
cmake ..

# Build
make

# Run
./hello-pds
```

## Step 7: Test the Server

In another terminal:

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
```

## Next Steps

- **[Tutorial 2: Account Management](./tutorial-2-accounts)** — Add account creation
- **[Tutorial 3: Record Operations](./tutorial-3-records)** — Add record CRUD
- **[Tutorial 4: Authentication](./tutorial-4-auth)** — Add JWT tokens

## Troubleshooting

**Port already in use:**
```bash
lsof -i :2583
kill -9 <PID>
```

**Build errors:**
```bash
# Clean and rebuild
rm -rf build
mkdir build && cd build
cmake ..
make
```

## Summary

You've successfully created a minimal PDS that:
- Initializes the application
- Starts an HTTP server
- Handles XRPC requests
- Returns responses

This is the foundation for building more complex PDS functionality.
