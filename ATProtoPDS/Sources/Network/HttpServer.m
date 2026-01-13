#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/RateLimiter.h"
#import "Network/PDSNetworkTransport.h"
#import <CommonCrypto/CommonDigest.h>

@class HttpRoute;

@interface HttpServer ()

@property (nonatomic, readwrite) NSUInteger port;
@property (nonatomic, readwrite, getter=isRunning) BOOL running;
#if defined(__linux__) || defined(__GNUstep__)
@property (nonatomic, assign) dispatch_queue_t serverQueue;
@property (nonatomic, assign) dispatch_semaphore_t readySemaphore;
#else
@property (nonatomic, strong) dispatch_queue_t serverQueue;
@property (nonatomic, strong) dispatch_semaphore_t readySemaphore;
#endif
@property (nonatomic, strong) NSMutableArray<HttpRoute *> *routes;
@property (nonatomic, strong) NSMutableArray *middlewares;
@property (nonatomic, assign) int socketFileDescriptor;
@property (nonatomic, assign) BOOL listenerReady;
@property (nonatomic, strong) id<PDSNetworkListener> listener;
@property (nonatomic, copy) RequestHandler requestHandler;
@property (nonatomic, strong) NSMutableDictionary *pathHandlers;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<RequestHandler> *> *routeHandlers;
@property (nonatomic, strong) NSMutableSet<id<PDSNetworkConnection>> *activeConnections;
@property (nonatomic, strong) NSMutableDictionary<NSString *, WebSocketUpgradeHandler> *webSocketHandlers;

@end

@implementation HttpServer

+ (instancetype)serverWithPort:(NSUInteger)port {
    return [[self alloc] initWithPort:port];
}

- (instancetype)initWithPort:(NSUInteger)port {
    self = [super init];
    if (self) {
        _port = port;
        _serverQueue = dispatch_queue_create("com.atproto.pds.httpserver", DISPATCH_QUEUE_SERIAL);
        _routeHandlers = [NSMutableDictionary dictionary];
        _pathHandlers = [NSMutableDictionary dictionary];
        _activeConnections = [NSMutableSet set];
        _webSocketHandlers = [NSMutableDictionary dictionary];
        _readySemaphore = dispatch_semaphore_create(0);
        _listenerReady = NO;
        _running = NO;
    }
    return self;
}

- (BOOL)startWithError:(NSError * _Nullable *)error {
    if (self.running) {
        return YES;
    }

    self.listener = [PDSNetworkTransportFactory createListenerWithPort:self.port];

    if (!self.listener) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.pds.httpserver"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to create listener"}];
        }
        return NO;
    }

    __weak typeof(self) weakSelf = self;
    self.listener.stateChangedHandler = ^(PDSNetworkListenerState state, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        switch (state) {
            case PDSNetworkListenerStateReady:
                strongSelf.running = YES;
                strongSelf.listenerReady = YES;
                strongSelf.port = strongSelf.listener.port;
                dispatch_semaphore_signal(strongSelf.readySemaphore);
                NSLog(@"HTTPServer listening on port %lu", (unsigned long)strongSelf.port);
                break;
            case PDSNetworkListenerStateFailed:
                strongSelf.running = NO;
                strongSelf.listenerReady = NO;
                dispatch_semaphore_signal(strongSelf.readySemaphore);
                NSLog(@"HTTPServer failed to start: %@", error);
                break;
            case PDSNetworkListenerStateCancelled:
                strongSelf.running = NO;
                strongSelf.listenerReady = NO;
                dispatch_semaphore_signal(strongSelf.readySemaphore);
                NSLog(@"HTTPServer cancelled");
                break;
            default:
                break;
        }
    };

    self.listener.newConnectionHandler = ^(id<PDSNetworkConnection> connection) {
        [weakSelf handleNewConnection:connection];
    };

    [self.listener startWithQueue:self.serverQueue];

    // Wait for the listener to become ready or fail
    dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC);
    long result = dispatch_semaphore_wait(self.readySemaphore, timeout);

    if (result != 0) {
        // Timeout - listener didn't become ready
        [self.listener cancel];
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.pds.httpserver"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Listener failed to start within timeout"}];
        }
        return NO;
    }

    if (!self.listenerReady) {
        // Listener failed to start
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.pds.httpserver"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Listener failed to start"}];
        }
        return NO;
    }

    return YES;
}

- (void)handleNewConnection:(id<PDSNetworkConnection>)connection {
    @synchronized (self.activeConnections) {
        [self.activeConnections addObject:connection];
    }

    __weak typeof(self) weakSelf = self;
    __weak id<PDSNetworkConnection> weakConnection = connection;

    connection.stateChangedHandler = ^(PDSNetworkConnectionState state, NSError * _Nullable error) {
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
            default:
                break;
        }
    };

    [connection startWithQueue:self.serverQueue];
}

- (void)readMoreDataInto:(NSMutableData *)requestData connection:(id<PDSNetworkConnection>)connection {
    [connection receiveWithMinimumLength:1 maximumLength:UINT32_MAX completion:^(NSData * _Nullable newContent, BOOL isComplete, NSError * _Nullable receiveError) {
        if (newContent && newContent.length > 0) {
            [requestData appendData:newContent];
            [self parseRequest:requestData fromConnection:connection];
        } else if (isComplete) {
            // Connection closed by peer
            [connection cancel];
        } else if (receiveError) {
            [connection cancel];
        } else {
            [self readMoreDataInto:requestData connection:connection];
        }
    }];
}

- (void)readRequestFromConnection:(id<PDSNetworkConnection>)connection {
    __weak typeof(self) weakSelf = self;

    [connection receiveWithMinimumLength:1 maximumLength:UINT32_MAX completion:^(NSData * _Nullable content, BOOL isComplete, NSError * _Nullable error) {
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
    NSMutableData *requestData = [NSMutableData dataWithData:data];

    NSString *requestString = [[NSString alloc] initWithData:requestData encoding:NSUTF8StringEncoding];
    if (!requestString) {
        requestString = [[NSString alloc] initWithData:requestData encoding:NSISOLatin1StringEncoding];
    }

    if (!requestString) {
        HttpResponse *response = [HttpResponse responseWithStatusCode:HttpStatusBadRequest];
        [response setBodyString:@"Invalid request"];
        [self sendResponse:response onConnection:connection];
        return;
    }

    NSRange headerEndRange = [requestString rangeOfString:@"\r\n\r\n"];
    if (headerEndRange.location == NSNotFound) {
        if (data.length < 16384) {
            // Headers not fully received yet
            [self readMoreDataInto:requestData connection:connection];
            return;
        } else {
            // Request too large or malformed
            HttpResponse *response = [HttpResponse responseWithStatusCode:HttpStatusBadRequest];
            [response setBodyString:@"Request too large"];
            [self sendResponse:response onConnection:connection];
            return;
        }
    }

    // Check for Content-Length
    NSString *headersPart = [requestString substringToIndex:headerEndRange.location];
    NSUInteger contentLength = 0;
    
    // Simple case-insensitive search for Content-Length
    NSRange clRange = [headersPart rangeOfString:@"Content-Length:" options:NSCaseInsensitiveSearch];
    if (clRange.location != NSNotFound) {
        NSUInteger valueStart = clRange.location + clRange.length;
        NSRange lineEnd = [headersPart rangeOfString:@"\r\n" options:0 range:NSMakeRange(valueStart, headersPart.length - valueStart)];
        if (lineEnd.location != NSNotFound) {
            NSString *valueString = [headersPart substringWithRange:NSMakeRange(valueStart, lineEnd.location - valueStart)];
            contentLength = (NSUInteger)[valueString longLongValue];
        } else {
            // End of headers string
            NSString *valueString = [headersPart substringFromIndex:valueStart];
            contentLength = (NSUInteger)[valueString longLongValue];
        }
    }
    
    NSUInteger expectedLength = headerEndRange.location + 4 + contentLength;
    
    if (data.length < expectedLength) {
        // Need more body data
        [self readMoreDataInto:requestData connection:connection];
        return;
    }

    // Get remote address from connection
    NSString *remoteAddress = connection.remoteAddress;

    HttpRequest *request = [HttpRequest requestWithData:requestData remoteAddress:remoteAddress];

    if (!request) {
        HttpResponse *response = [HttpResponse responseWithStatusCode:HttpStatusBadRequest];
        [response setBodyString:@"Invalid request"];
        [self sendResponse:response onConnection:connection];
        return;
    }

    // Check for WebSocket upgrade request
    if ([self isWebSocketUpgradeRequest:request]) {
        WebSocketUpgradeHandler wsHandler = [self webSocketHandlerForPath:request.path];
        if (wsHandler) {
            // Remove connection from active set - the handler takes ownership
            @synchronized (self.activeConnections) {
                [self.activeConnections removeObject:connection];
            }
            
            // Call the WebSocket handler with the request and connection
            BOOL handled = wsHandler(request, connection);
            if (!handled) {
                // Handler rejected the upgrade, send error response
                HttpResponse *response = [HttpResponse responseWithStatusCode:400];
                [response setBodyString:@"WebSocket upgrade rejected"];
                [self sendResponse:response onConnection:connection];
            }
            return;
        } else {
            // No WebSocket handler for this path
            HttpResponse *response = [HttpResponse responseWithStatusCode:404];
            [response setJsonBody:@{@"error": @"NotFound", @"message": @"No WebSocket handler for this path"}];
            [self sendResponse:response onConnection:connection];
            return;
        }
    }

    // Dispatch request processing to background queue to avoid blocking network I/O
    __weak typeof(self) weakSelf = self;
    __weak id<PDSNetworkConnection> weakConnection = connection;
    HttpRequest *requestRef = request; // Capture request in block

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        __strong typeof(weakConnection) strongConnection = weakConnection;
        if (!strongSelf || !strongConnection) return;

        HttpResponse *response = [strongSelf dispatchRequest:requestRef];

        // Send response back on the network queue
        dispatch_async(strongSelf.serverQueue, ^{
            [strongSelf sendResponse:response onConnection:strongConnection];
        });
    });
}

- (HttpResponse *)dispatchRequest:(HttpRequest *)request {
    HttpResponse *response = [HttpResponse response];

    // Apply rate limiting for OAuth endpoints
    if ([request.path hasPrefix:@"/oauth/"]) {
        RateLimitResult *result = [[RateLimiter sharedLimiter] checkRateLimitForIP:request.remoteAddress];
        if (!result.allowed) {
            response.statusCode = 429;
            [response setJsonBody:@{@"error": @"too_many_requests", @"message": @"Rate limit exceeded"}];
            return response;
        }
    }

    if (self.requestHandler) {
        self.requestHandler(request, response);
        return response;
    }

    NSString *methodString = request.methodString;
    NSString *path = request.path;

    NSString *routeKey = [NSString stringWithFormat:@"%@ %@", methodString, path];
    RequestHandler handler = self.pathHandlers[routeKey];
    
    if (!handler) {
        NSArray *handlers = self.routeHandlers[routeKey];
        if (handlers.count > 0) {
            handler = handlers[0];
        }
    }

    if (!handler) {
        handler = self.pathHandlers[path];
    }

    if (!handler) {
        NSString *genericPath = [self findMatchingPathForRoute:path handlers:self.routeHandlers];
        if (genericPath) {
            handler = self.routeHandlers[genericPath][0];
        }
    }

    if (!handler) {
        for (NSString *registeredPath in self.pathHandlers) {
            if ([self path:path matchesPattern:registeredPath]) {
                handler = self.pathHandlers[registeredPath];
                break;
            }
        }
    }

    if (handler) {
        handler(request, response);
    } else {
        response.statusCode = HttpStatusNotFound;
        [response setJsonBody:@{@"error": @"Not Found", @"message": [NSString stringWithFormat:@"No handler for %@ %@", methodString, path]}];
    }

    return response;
}

- (NSString *)findMatchingPathForRoute:(NSString *)path handlers:(NSDictionary *)handlers {
    for (NSString *route in handlers) {
        if ([self path:path matchesPattern:route]) {
            return route;
        }
    }
    return nil;
}

- (BOOL)path:(NSString *)path matchesPattern:(NSString *)pattern {
    if ([path isEqualToString:pattern]) {
        return YES;
    }

    if ([pattern hasSuffix:@"/"]) {
        pattern = [pattern substringToIndex:pattern.length - 1];
    }

    if ([path hasPrefix:pattern] && [path length] > [pattern length] && [[path substringFromIndex:[pattern length]] hasPrefix:@"/"]) {
        return YES;
    }

    NSArray<NSString *> *pathParts = [path componentsSeparatedByString:@"/"];
    NSArray<NSString *> *patternParts = [pattern componentsSeparatedByString:@"/"];

    if (pathParts.count != patternParts.count) {
        return NO;
    }

    for (NSUInteger i = 0; i < pathParts.count; i++) {
        NSString *pathPart = pathParts[i];
        NSString *patternPart = patternParts[i];

        if ([patternPart hasPrefix:@"{"] && [patternPart hasSuffix:@"}"]) {
            continue;
        }

        if (![pathPart isEqualToString:patternPart]) {
            return NO;
        }
    }

    return YES;
}

- (void)sendResponse:(HttpResponse *)response onConnection:(id<PDSNetworkConnection>)connection {
    NSData *responseData = [response serialize];
    // NSLog(@"[HttpServer] Sending response: %lu bytes to %@", (unsigned long)responseData.length, connection.remoteAddress);

    __weak typeof(self) weakSelf = self;
    BOOL shouldKeepAlive = response.keepAlive;
    
    [connection sendData:responseData completion:^(NSError * _Nullable error) {
        if (error) {
            NSLog(@"[HttpServer] Failed to send response: %@", error);
            [connection cancel];
            return;
        }
        // NSLog(@"[HttpServer] Response sent successfully");

        if (shouldKeepAlive) {
            // HTTP/1.1 keep-alive: read the next request on this connection
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf) {
                [strongSelf readRequestFromConnection:connection];
            }
        } else {
            // Close connection after response
            [connection cancel];
        }
    }];
}

- (void)stop {
    if (!self.running) {
        return;
    }

    dispatch_semaphore_t drainSemaphore = dispatch_semaphore_create(0);

    dispatch_async(self.serverQueue, ^{
        if (self.listener) {
            [self.listener cancel];
            self.listener = nil;
        }
        self.running = NO;

        NSUInteger activeCount = 0;
        NSMutableArray *connectionsToCancel = nil;
        @synchronized (self.activeConnections) {
            activeCount = self.activeConnections.count;
            if (activeCount > 0) {
                connectionsToCancel = [[self.activeConnections allObjects] mutableCopy];
            }
        }

        if (activeCount > 0) {
            NSLog(@"[HttpServer] Cancelling %lu active connections...", (unsigned long)activeCount);

            __block NSUInteger remaining = activeCount;
            @synchronized (self.activeConnections) {
                for (id<PDSNetworkConnection> connection in connectionsToCancel) {
                    __weak typeof(self) weakSelf = self;
                    __weak id<PDSNetworkConnection> weakConnection = connection;
                    connection.stateChangedHandler = ^(PDSNetworkConnectionState state, NSError * _Nullable error) {
                        __strong typeof(weakSelf) strongSelf = weakSelf;
                        __strong typeof(weakConnection) strongConnection = weakConnection;
                        if (!strongSelf || !strongConnection) return;

                        if (state == PDSNetworkConnectionStateCancelled) {
                            @synchronized (strongSelf.activeConnections) {
                                [strongSelf.activeConnections removeObject:strongConnection];
                            }
                            remaining--;
                            if (remaining == 0) {
                                dispatch_semaphore_signal(drainSemaphore);
                            }
                        }
                    };
                    [connection cancel];
                }
            }

            dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC);
            long waitResult = dispatch_semaphore_wait(drainSemaphore, timeout);
            if (waitResult != 0) {
                NSLog(@"[HttpServer] Warning: Timeout waiting for connections to drain, %lu remaining", (unsigned long)remaining);
            }
        }

        dispatch_semaphore_signal(drainSemaphore);
    });

    dispatch_semaphore_wait(drainSemaphore, DISPATCH_TIME_FOREVER);
}

- (void)addRoute:(NSString *)method path:(NSString *)path handler:(RequestHandler)handler {
    NSString *key = [NSString stringWithFormat:@"%@ %@", method, path];

    NSMutableArray<RequestHandler> *handlers = self.routeHandlers[key];
    if (!handlers) {
        handlers = [NSMutableArray array];
        self.routeHandlers[key] = handlers;
    }
    [handlers addObject:[handler copy]];
}

- (void)addHandlerForPath:(NSString *)path handler:(RequestHandler)handler {
    self.pathHandlers[path] = [handler copy];
}

- (void)setWebSocketUpgradeHandler:(WebSocketUpgradeHandler)handler forPath:(NSString *)path {
    if (handler) {
        self.webSocketHandlers[path] = [handler copy];
    } else {
        [self.webSocketHandlers removeObjectForKey:path];
    }
}

#pragma mark - WebSocket Upgrade Handling

// WebSocket GUID per RFC 6455
static NSString * const kWebSocketGUID = @"258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

+ (NSString *)createWebSocketAcceptKeyForKey:(NSString *)clientKey {
    // Concatenate client key with WebSocket GUID
    NSString *combined = [NSString stringWithFormat:@"%@%@", clientKey, kWebSocketGUID];
    
    // SHA-1 hash
    NSData *data = [combined dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(data.bytes, (CC_LONG)data.length, digest);
    
    // Base64 encode
    NSData *hashData = [NSData dataWithBytes:digest length:CC_SHA1_DIGEST_LENGTH];
    return [hashData base64EncodedStringWithOptions:0];
}

+ (NSData *)webSocketHandshakeResponseDataForRequest:(HttpRequest *)request {
    NSString *clientKey = [request headerForKey:@"Sec-WebSocket-Key"];
    if (!clientKey) {
        return nil;
    }
    
    NSString *acceptKey = [self createWebSocketAcceptKeyForKey:clientKey];
    
    // Build HTTP 101 response
    NSMutableString *response = [NSMutableString string];
    [response appendString:@"HTTP/1.1 101 Switching Protocols\r\n"];
    [response appendString:@"Upgrade: websocket\r\n"];
    [response appendString:@"Connection: Upgrade\r\n"];
    [response appendFormat:@"Sec-WebSocket-Accept: %@\r\n", acceptKey];
    
    // Include protocol if requested
    NSString *protocol = [request headerForKey:@"Sec-WebSocket-Protocol"];
    if (protocol) {
        // Just echo back the first requested protocol for now
        NSArray *protocols = [protocol componentsSeparatedByString:@","];
        if (protocols.count > 0) {
            NSString *selectedProtocol = [protocols[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            [response appendFormat:@"Sec-WebSocket-Protocol: %@\r\n", selectedProtocol];
        }
    }
    
    [response appendString:@"\r\n"];
    
    return [response dataUsingEncoding:NSUTF8StringEncoding];
}

- (BOOL)isWebSocketUpgradeRequest:(HttpRequest *)request {
    // Check for required WebSocket upgrade headers
    NSString *upgrade = [request headerForKey:@"Upgrade"];
    NSString *connection = [request headerForKey:@"Connection"];
    NSString *wsKey = [request headerForKey:@"Sec-WebSocket-Key"];
    
    if (!upgrade || !connection || !wsKey) {
        return NO;
    }
    
    // Case-insensitive check for "websocket" upgrade
    if ([upgrade caseInsensitiveCompare:@"websocket"] != NSOrderedSame) {
        return NO;
    }
    
    // Connection header must contain "Upgrade"
    if ([connection rangeOfString:@"Upgrade" options:NSCaseInsensitiveSearch].location == NSNotFound) {
        return NO;
    }
    
    return YES;
}

- (WebSocketUpgradeHandler)webSocketHandlerForPath:(NSString *)path {
    // Direct match first
    WebSocketUpgradeHandler handler = self.webSocketHandlers[path];
    if (handler) {
        return handler;
    }
    
    // Check for prefix matches (e.g., /xrpc/com.atproto.sync.subscribeRepos?cursor=...)
    for (NSString *registeredPath in self.webSocketHandlers) {
        if ([path hasPrefix:registeredPath]) {
            return self.webSocketHandlers[registeredPath];
        }
    }
    
    return nil;
}

@end
