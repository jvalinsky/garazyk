#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/RateLimiter.h"
#import "Network/PDSNetworkTransport.h"
#import "Debug/PDSLogger.h"

@interface HttpServer ()

@property (nonatomic, readwrite) NSUInteger port;
@property (nonatomic, readwrite, getter=isRunning) BOOL running;
@property (nonatomic, strong) id<PDSNetworkListener> listener;
@property (nonatomic, strong) dispatch_queue_t serverQueue;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<RequestHandler> *> *routeHandlers;
@property (nonatomic, strong) NSMutableDictionary<NSString *, RequestHandler> *pathHandlers;
@property (nonatomic, copy) void (^requestHandler)(HttpRequest *, HttpResponse *);
@property (nonatomic, strong) dispatch_semaphore_t readySemaphore;
@property (nonatomic, strong) dispatch_semaphore_t stopSemaphore;
@property (nonatomic, strong) dispatch_group_t taskGroup;
@property (nonatomic, assign) BOOL listenerReady;
@property (nonatomic, assign) BOOL startupFinished;
@property (nonatomic, strong) NSMutableSet<id<PDSNetworkConnection>> *activeConnections;
@property (nonatomic, strong) dispatch_queue_t connectionQueue;
@property (nonatomic, strong) NSMutableData *requestData;

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
        _connectionQueue = dispatch_queue_create("com.atproto.pds.httpserver.connections", DISPATCH_QUEUE_SERIAL);
        _readySemaphore = dispatch_semaphore_create(0);
        _stopSemaphore = dispatch_semaphore_create(0);
        _taskGroup = dispatch_group_create();
        _requestData = [NSMutableData data];
        _listenerReady = NO;
        _startupFinished = NO;
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
                strongSelf.listenerReady = YES;
                strongSelf.running = YES;
                strongSelf.port = strongSelf.listener.port;
                strongSelf.startupFinished = YES;
                PDS_LOG_HTTP_INFO(@"HTTPServer listening on port %lu", (unsigned long)strongSelf.port);
                dispatch_semaphore_signal(strongSelf.readySemaphore);
                break;
            case PDSNetworkListenerStateFailed:
                strongSelf.listenerReady = NO;
                strongSelf.running = NO;
                strongSelf.startupFinished = YES;
                PDS_LOG_HTTP_ERROR(@"HTTPServer failed to start: %@", error);
                dispatch_semaphore_signal(strongSelf.readySemaphore);
                break;
            case PDSNetworkListenerStateCancelled:
                strongSelf.listenerReady = NO;
                strongSelf.running = NO;
                strongSelf.startupFinished = YES;
                PDS_LOG_HTTP_INFO(@"HTTPServer cancelled");
                dispatch_semaphore_signal(strongSelf.readySemaphore);
                dispatch_semaphore_signal(strongSelf.stopSemaphore);
                break;
            default:
                break;
        }
    };

    self.listener.newConnectionHandler = ^(id<PDSNetworkConnection> connection) {
        [weakSelf handleNewConnection:connection];
    };

    self.startupFinished = NO;
    self.running = YES; // Optimistically set running to YES so the main loop can start
    
    [self.listener startWithQueue:self.serverQueue];
    
    // Wait for READY state with 5s timeout
    dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC));
    if (dispatch_semaphore_wait(self.readySemaphore, timeout) != 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.pds.httpserver"
                                         code:-2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Timed out waiting for server to start"}];
        }
        return NO;
    }
    
    if (!self.listenerReady) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.pds.httpserver"
                                         code:-3
                                     userInfo:@{NSLocalizedDescriptionKey: @"Server failed to start"}];
        }
        return NO;
    }
    
    return YES;
}

- (void)handleNewConnection:(id<PDSNetworkConnection>)connection {
    dispatch_async(_connectionQueue, ^{
        [self->_activeConnections addObject:connection];
    });

    __weak typeof(self) weakSelf = self;
    __weak id<PDSNetworkConnection> weakConnection = connection;

    connection.stateChangedHandler = ^(PDSNetworkConnectionState state, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        __strong typeof(weakConnection) strongConnection = weakConnection;
        if (!strongSelf || !strongConnection) return;

        switch (state) {
            case PDSNetworkConnectionStateReady: {
                [strongSelf readRequestFromConnection:strongConnection];
                break;
            }
            case PDSNetworkConnectionStateFailed:
            case PDSNetworkConnectionStateCancelled: {
                dispatch_async(strongSelf.connectionQueue, ^{
                    [strongSelf.activeConnections removeObject:strongConnection];
                });
                [strongConnection cancel];
                break;
            }
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

    dispatch_group_enter(self.taskGroup);
    [connection receiveWithMinimumLength:1 maximumLength:UINT32_MAX completion:^(NSData * _Nullable content, BOOL isComplete, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        
        if (error) {
            [connection cancel];
            dispatch_group_leave(strongSelf.taskGroup);
            return;
        }
        
        if (content && content.length > 0) {
            [strongSelf parseRequest:content fromConnection:connection];
        } else if (isComplete) {
            [connection cancel];
        } else {
            [strongSelf readRequestFromConnection:connection];
        }
        dispatch_group_leave(strongSelf.taskGroup);
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

    // Dispatch request processing to background queue to avoid blocking network I/O
    __weak typeof(self) weakSelf = self;
    __weak id<PDSNetworkConnection> weakConnection = connection;
    HttpRequest *requestRef = request; // Capture request in block

    dispatch_group_enter(self.taskGroup);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        __strong typeof(weakConnection) strongConnection = weakConnection;
        if (!strongSelf) {
            dispatch_group_leave(weakSelf.taskGroup);
            return;
        }

        // Set correlation ID for logs on this thread
        [[PDSLogger sharedLogger] setCorrelationID:requestRef.correlationID];

        HttpResponse *response = [strongSelf dispatchRequest:requestRef];

        // Send response back on the network queue
        dispatch_async(strongSelf.serverQueue, ^{
            [strongSelf sendResponse:response onConnection:strongConnection];
            dispatch_group_leave(strongSelf.taskGroup);
        });

        // Clear correlation ID after dispatch
        [[PDSLogger sharedLogger] clearCorrelationID];
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
    
    // Check path handlers first (registered via addHandlerForPath)
    // These handle any method for a given path
    RequestHandler handler = self.pathHandlers[path];

    // Then check route handlers (registered via addRoute)
    // These are specific to Method + Path
    if (!handler) {
        NSMutableArray *handlers = self.routeHandlers[routeKey];
        if (handlers && handlers.count > 0) {
            handler = handlers[0];
        }
    }

    // Then check wildcard/pattern matching for path handlers
    if (!handler) {
        for (NSString *registeredPath in self.pathHandlers) {
            if ([self path:path matchesPattern:registeredPath]) {
                handler = self.pathHandlers[registeredPath];
                break;
            }
        }
    }
    
    // Finally check pattern matching for route handlers
    if (!handler) {
        NSString *matchingKey = [self findMatchingPathForRoute:path method:methodString handlers:self.routeHandlers];
        if (matchingKey) {
            handler = self.routeHandlers[matchingKey][0];
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

- (NSString *)findMatchingPathForRoute:(NSString *)path method:(NSString *)method handlers:(NSDictionary *)handlers {
    for (NSString *routeKey in handlers) {
        // routeKey is "METHOD PATTERN"
        NSArray *parts = [routeKey componentsSeparatedByString:@" "];
        if (parts.count < 2) continue;
        
        NSString *routeMethod = parts[0];
        NSString *routePattern = [parts subarrayWithRange:NSMakeRange(1, parts.count - 1)].firstObject; // Simplified join?
        if (parts.count > 2) {
            routePattern = [[parts subarrayWithRange:NSMakeRange(1, parts.count - 1)] componentsJoinedByString:@" "];
        }
        
        if (![routeMethod isEqualToString:method]) continue;
        
        if ([self path:path matchesPattern:routePattern]) {
            return routeKey;
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

    __weak typeof(self) weakSelf = self;
    BOOL shouldKeepAlive = response.keepAlive;
    
    [connection sendData:responseData completion:^(NSError * _Nullable error) {
        if (error) {
            PDS_LOG_HTTP_ERROR(@"Failed to send response: %@", error);
            [connection cancel];
            return;
        }

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
    self.running = NO;
    if (self.listener) {
        [self.listener cancel];
        
        // Wait for CANCELLED state with 2s timeout
        dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC));
        dispatch_semaphore_wait(self.stopSemaphore, timeout);
        
        self.listener = nil;
    }
    
    // Wait for all active tasks to complete
    dispatch_group_wait(self.taskGroup, DISPATCH_TIME_FOREVER);
    
    dispatch_sync(_connectionQueue, ^{
        for (id<PDSNetworkConnection> conn in self->_activeConnections) {
            [conn cancel];
        }
        [self->_activeConnections removeAllObjects];
    });
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

@end
