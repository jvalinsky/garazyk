#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/RateLimiter.h"
#import "Network/PDSNetworkTransport.h"

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
@property (nonatomic, strong) NSMutableSet<id<PDSNetworkConnection>> *activeConnections;

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
            case PDSNetworkConnectionStateCancelled:
                @synchronized (strongSelf.activeConnections) {
                    [strongSelf.activeConnections removeObject:strongConnection];
                }
                [strongConnection cancel];
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

    __weak typeof(self) weakSelf = self;
    BOOL shouldKeepAlive = response.keepAlive;
    
    [connection sendData:responseData completion:^(NSError * _Nullable error) {
        if (error) {
            NSLog(@"Failed to send response");
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
    if (self.listener) {
        [self.listener cancel];
        self.listener = nil;
    }
    self.running = NO;
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
