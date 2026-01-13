# Chapter 11: HTTP Server with BSD Sockets & GCD

Welcome to Part IV: Networking! This chapter covers building an HTTP server using Apple's Grand Central Dispatch (GCD) for concurrent request handling. The server forms the foundation for our XRPC endpoint implementation.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                      HttpServer                              │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐    ┌──────────────┐    ┌───────────────┐  │
│  │   Listener  │───▶│  Connection  │───▶│  Request      │  │
│  │   (Port)    │    │   Handler    │    │  Parser       │  │
│  └─────────────┘    └──────────────┘    └───────────────┘  │
│         │                  │                    │           │
│         ▼                  ▼                    ▼           │
│  ┌─────────────┐    ┌──────────────┐    ┌───────────────┐  │
│  │ serverQueue │    │  GCD Async   │    │   Route       │  │
│  │  (Serial)   │    │  Dispatch    │    │   Dispatch    │  │
│  └─────────────┘    └──────────────┘    └───────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## The HttpServer Interface

```objc
// HttpServer.h
typedef void (^RequestHandler)(HttpRequest *request, HttpResponse *response);

@interface HttpServer : NSObject

@property (nonatomic, readonly) NSUInteger port;
@property (nonatomic, readonly, getter=isRunning) BOOL running;

+ (instancetype)serverWithPort:(NSUInteger)port;
- (BOOL)startWithError:(NSError **)error;
- (void)stop;

- (void)addRoute:(NSString *)method path:(NSString *)path handler:(RequestHandler)handler;

@end
```

## Server Initialization

```objc
- (instancetype)initWithPort:(NSUInteger)port {
    self = [super init];
    if (self) {
        _port = port;
        
        // Create serial queue for network operations
        _serverQueue = dispatch_queue_create(
            "com.atproto.pds.httpserver", 
            DISPATCH_QUEUE_SERIAL
        );
        
        _routeHandlers = [NSMutableDictionary dictionary];
        _pathHandlers = [NSMutableDictionary dictionary];
        _activeConnections = [NSMutableSet set];
        _readySemaphore = dispatch_semaphore_create(0);
    }
    return self;
}
```

## Starting the Server

```objc
- (BOOL)startWithError:(NSError **)error {
    if (self.running) return YES;

    // Create network listener (abstracted for cross-platform)
    self.listener = [PDSNetworkTransportFactory createListenerWithPort:self.port];
    if (!self.listener) {
        if (error) {
            *error = [NSError errorWithDomain:@"HttpServer" code:-1
                userInfo:@{NSLocalizedDescriptionKey: @"Failed to create listener"}];
        }
        return NO;
    }

    __weak typeof(self) weakSelf = self;
    
    // Handle state changes
    self.listener.stateChangedHandler = ^(PDSNetworkListenerState state, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        switch (state) {
            case PDSNetworkListenerStateReady:
                strongSelf.running = YES;
                strongSelf.port = strongSelf.listener.port;
                dispatch_semaphore_signal(strongSelf.readySemaphore);
                NSLog(@"HTTP Server listening on port %lu", (unsigned long)strongSelf.port);
                break;
                
            case PDSNetworkListenerStateFailed:
            case PDSNetworkListenerStateCancelled:
                strongSelf.running = NO;
                dispatch_semaphore_signal(strongSelf.readySemaphore);
                break;
        }
    };

    // Handle new connections
    self.listener.newConnectionHandler = ^(id<PDSNetworkConnection> connection) {
        [weakSelf handleNewConnection:connection];
    };

    [self.listener startWithQueue:self.serverQueue];

    // Wait for ready or timeout
    dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC);
    if (dispatch_semaphore_wait(self.readySemaphore, timeout) != 0) {
        [self.listener cancel];
        if (error) {
            *error = [NSError errorWithDomain:@"HttpServer" code:-1
                userInfo:@{NSLocalizedDescriptionKey: @"Listener timeout"}];
        }
        return NO;
    }

    return self.running;
}
```

## Handling Connections

```objc
- (void)handleNewConnection:(id<PDSNetworkConnection>)connection {
    @synchronized (self.activeConnections) {
        [self.activeConnections addObject:connection];
    }

    __weak typeof(self) weakSelf = self;
    __weak id<PDSNetworkConnection> weakConnection = connection;

    connection.stateChangedHandler = ^(PDSNetworkConnectionState state, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        __strong typeof(weakConnection) strongConnection = weakConnection;
        if (!strongSelf || !strongConnection) return;

        switch (state) {
            case PDSNetworkConnectionStateReady:
                [strongSelf readRequestFromConnection:strongConnection];
                break;
                
            case PDSNetworkConnectionStateFailed:
                [strongConnection cancel];
                break;
                
            case PDSNetworkConnectionStateCancelled:
                @synchronized (strongSelf.activeConnections) {
                    [strongSelf.activeConnections removeObject:strongConnection];
                }
                break;
        }
    };

    [connection startWithQueue:self.serverQueue];
}
```

## Reading and Parsing Requests

```objc
- (void)readRequestFromConnection:(id<PDSNetworkConnection>)connection {
    __weak typeof(self) weakSelf = self;

    [connection receiveWithMinimumLength:1 
                           maximumLength:UINT32_MAX 
                              completion:^(NSData *content, BOOL isComplete, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || error) {
            [connection cancel];
            return;
        }

        if (content && content.length > 0) {
            [strongSelf parseRequest:content fromConnection:connection];
        } else if (isComplete) {
            [connection cancel];
        } else {
            [strongSelf readRequestFromConnection:connection];
        }
    }];
}

- (void)parseRequest:(NSData *)data fromConnection:(id<PDSNetworkConnection>)connection {
    NSString *requestString = [[NSString alloc] initWithData:data 
                                                    encoding:NSUTF8StringEncoding];
    
    // Find header end
    NSRange headerEnd = [requestString rangeOfString:@"\r\n\r\n"];
    if (headerEnd.location == NSNotFound && data.length < 16384) {
        // Headers incomplete, read more
        NSMutableData *requestData = [NSMutableData dataWithData:data];
        [self readMoreDataInto:requestData connection:connection];
        return;
    }

    // Parse Content-Length for body
    NSString *headers = [requestString substringToIndex:headerEnd.location];
    NSUInteger contentLength = [self parseContentLength:headers];
    NSUInteger expectedLength = headerEnd.location + 4 + contentLength;
    
    if (data.length < expectedLength) {
        // Body incomplete, read more
        NSMutableData *requestData = [NSMutableData dataWithData:data];
        [self readMoreDataInto:requestData connection:connection];
        return;
    }

    // Create request object
    HttpRequest *request = [HttpRequest requestWithData:data 
                                          remoteAddress:connection.remoteAddress];

    // Dispatch to background queue for processing
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        HttpResponse *response = [weakSelf dispatchRequest:request];
        
        dispatch_async(weakSelf.serverQueue, ^{
            [weakSelf sendResponse:response onConnection:connection];
        });
    });
}
```

## Route Dispatch

```objc
- (HttpResponse *)dispatchRequest:(HttpRequest *)request {
    HttpResponse *response = [HttpResponse response];

    // Rate limiting for OAuth endpoints
    if ([request.path hasPrefix:@"/oauth/"]) {
        RateLimitResult *result = [[RateLimiter sharedLimiter] 
            checkRateLimitForIP:request.remoteAddress];
        if (!result.allowed) {
            response.statusCode = 429;
            [response setJsonBody:@{@"error": @"too_many_requests"}];
            return response;
        }
    }

    // Find matching route
    NSString *routeKey = [NSString stringWithFormat:@"%@ %@", 
        request.methodString, request.path];
    
    RequestHandler handler = self.pathHandlers[routeKey];
    
    if (!handler) {
        // Try pattern matching
        handler = [self findHandlerForPath:request.path method:request.methodString];
    }

    if (handler) {
        handler(request, response);
    } else {
        response.statusCode = 404;
        [response setJsonBody:@{
            @"error": @"Not Found",
            @"message": [NSString stringWithFormat:@"No handler for %@ %@", 
                request.methodString, request.path]
        }];
    }

    return response;
}
```

## Pattern Matching for Routes

```objc
- (BOOL)path:(NSString *)path matchesPattern:(NSString *)pattern {
    if ([path isEqualToString:pattern]) return YES;

    // Split into components
    NSArray *pathParts = [path componentsSeparatedByString:@"/"];
    NSArray *patternParts = [pattern componentsSeparatedByString:@"/"];

    if (pathParts.count != patternParts.count) return NO;

    for (NSUInteger i = 0; i < pathParts.count; i++) {
        NSString *pathPart = pathParts[i];
        NSString *patternPart = patternParts[i];

        // {param} matches any value
        if ([patternPart hasPrefix:@"{"] && [patternPart hasSuffix:@"}"]) {
            continue;
        }

        if (![pathPart isEqualToString:patternPart]) {
            return NO;
        }
    }

    return YES;
}
```

## Sending Responses

```objc
- (void)sendResponse:(HttpResponse *)response 
         onConnection:(id<PDSNetworkConnection>)connection {
    NSData *responseData = [response serialize];
    BOOL shouldKeepAlive = response.keepAlive;
    
    __weak typeof(self) weakSelf = self;
    [connection sendData:responseData completion:^(NSError *error) {
        if (error) {
            NSLog(@"Failed to send response: %@", error);
            [connection cancel];
            return;
        }

        if (shouldKeepAlive) {
            // HTTP/1.1 keep-alive: read next request
            [weakSelf readRequestFromConnection:connection];
        } else {
            [connection cancel];
        }
    }];
}
```

## Registering Routes

```objc
- (void)addRoute:(NSString *)method path:(NSString *)path handler:(RequestHandler)handler {
    NSString *key = [NSString stringWithFormat:@"%@ %@", method, path];
    
    NSMutableArray<RequestHandler> *handlers = self.routeHandlers[key];
    if (!handlers) {
        handlers = [NSMutableArray array];
        self.routeHandlers[key] = handlers;
    }
    [handlers addObject:[handler copy]];
}

// Usage example:
[server addRoute:@"GET" path:@"/health" handler:^(HttpRequest *req, HttpResponse *resp) {
    resp.statusCode = 200;
    [resp setJsonBody:@{@"status": @"ok"}];
}];

[server addRoute:@"GET" path:@"/xrpc/{lexicon}" handler:^(HttpRequest *req, HttpResponse *resp) {
    NSString *lexicon = [req pathParameter:@"lexicon"];
    // Handle XRPC query...
}];
```

## Summary

In this chapter, you learned:

- ✅ HTTP server architecture with GCD
- ✅ Listener and connection handling
- ✅ Request parsing and Content-Length handling
- ✅ Route registration and pattern matching
- ✅ Async response sending with keep-alive

## Next Steps

In **Chapter 12**, we'll implement **XRPC endpoints**—the AT Protocol's RPC layer built on top of this HTTP server.

---

**Files Referenced in This Chapter:**
- [HttpServer.h](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Network/HttpServer.h)
- [HttpServer.m](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Network/HttpServer.m)
