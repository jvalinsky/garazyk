#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import <Network/Network.h>

@interface HttpServer ()

@property (nonatomic, readwrite) NSUInteger port;
@property (nonatomic, readwrite, getter=isRunning) BOOL running;
@property (nonatomic, assign) nw_listener_t listener;
@property (nonatomic, strong) dispatch_queue_t serverQueue;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<RequestHandler> *> *routeHandlers;
@property (nonatomic, strong) NSMutableDictionary<NSString *, RequestHandler> *pathHandlers;
@property (nonatomic, copy) void (^requestHandler)(HttpRequest *, HttpResponse *);
@property (nonatomic, strong) dispatch_semaphore_t readySemaphore;
@property (nonatomic, assign) BOOL listenerReady;

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

    nw_parameters_t parameters = nw_parameters_create_secure_tcp(
        NW_PARAMETERS_DISABLE_PROTOCOL,
        NW_PARAMETERS_DEFAULT_CONFIGURATION
    );

    if (!parameters) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.pds.httpserver"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to create parameters"}];
        }
        return NO;
    }

    char portStr[16];
    snprintf(portStr, sizeof(portStr), "%lu", (unsigned long)self.port);

    nw_listener_t listener = nw_listener_create_with_port(portStr, parameters);

    if (!listener) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.pds.httpserver"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to create listener"}];
        }
        return NO;
    }

    self.listener = listener;

    nw_listener_set_queue(self.listener, self.serverQueue);

    __weak typeof(self) weakSelf = self;
    nw_listener_set_state_changed_handler(self.listener, ^(nw_listener_state_t state, nw_error_t error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        switch (state) {
            case nw_listener_state_ready:
                strongSelf.running = YES;
                strongSelf.listenerReady = YES;
                strongSelf.port = nw_listener_get_port(strongSelf.listener);
                dispatch_semaphore_signal(strongSelf.readySemaphore);
                NSLog(@"HTTPServer listening on port %lu", (unsigned long)strongSelf.port);
                break;
            case nw_listener_state_failed:
                strongSelf.running = NO;
                strongSelf.listenerReady = NO;
                dispatch_semaphore_signal(strongSelf.readySemaphore);
                NSLog(@"HTTPServer failed to start: %@", error);
                break;
            case nw_listener_state_cancelled:
                strongSelf.running = NO;
                strongSelf.listenerReady = NO;
                dispatch_semaphore_signal(strongSelf.readySemaphore);
                NSLog(@"HTTPServer cancelled");
                break;
            default:
                break;
        }
    });

    nw_listener_set_new_connection_handler(self.listener, ^(nw_connection_t connection) {
        [weakSelf handleNewConnection:connection];
    });

    nw_listener_start(self.listener);

    // Wait for the listener to become ready or fail
    dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC);
    long result = dispatch_semaphore_wait(self.readySemaphore, timeout);

    if (result != 0) {
        // Timeout - listener didn't become ready
        nw_listener_cancel(self.listener);
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

- (void)handleNewConnection:(nw_connection_t)connection {
    __weak typeof(self) weakSelf = self;

    nw_connection_set_queue(connection, self.serverQueue);

    nw_connection_set_state_changed_handler(connection, ^(nw_connection_state_t state, nw_error_t error) {
        switch (state) {
            case nw_connection_state_ready:
                [weakSelf readRequestFromConnection:connection];
                break;
            case nw_connection_state_failed:
                nw_connection_cancel(connection);
                break;
            case nw_connection_state_cancelled:
                break;
            default:
                break;
        }
    });

    nw_connection_start(connection);
}

- (void)readMoreDataInto:(NSMutableData *)requestData connection:(nw_connection_t)connection {
    nw_connection_receive(connection, 1, UINT32_MAX, ^(dispatch_data_t newContent, nw_content_context_t context, bool isComplete, nw_error_t receiveError) {
        if (newContent && dispatch_data_get_size(newContent) > 0) {
            NSData *newData = [self dataFromDispatchData:newContent];
            [requestData appendData:newData];
            [self parseRequest:requestData fromConnection:connection];
        } else if (isComplete) {
            // Connection closed by peer
            nw_connection_cancel(connection);
        } else if (receiveError) {
            nw_connection_cancel(connection);
        } else {
            // No data read, try again? Or maybe this means we should wait.
            // nw_connection_receive should call back when there IS data or error.
            // But if min=1, it should wait.
            [self readMoreDataInto:requestData connection:connection];
        }
    });
}

- (void)readRequestFromConnection:(nw_connection_t)connection {
    __weak typeof(self) weakSelf = self;

    nw_connection_receive(connection, 1, UINT32_MAX, ^(dispatch_data_t content, nw_content_context_t context, bool isComplete, nw_error_t error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || error) {
            nw_connection_cancel(connection);
            return;
        }

        if (content && dispatch_data_get_size(content) > 0) {
            NSData *data = [strongSelf dataFromDispatchData:content];
            [strongSelf parseRequest:data fromConnection:connection];
        } else if (isComplete) {
            nw_connection_cancel(connection);
        } else {
            [strongSelf readRequestFromConnection:connection];
        }
    });
}

- (NSData *)dataFromDispatchData:(dispatch_data_t)data {
    __block const void *buffer = NULL;
    __block size_t size = 0;

    dispatch_data_apply(data, ^bool(dispatch_data_t region, size_t offset, const void *buf, size_t len) {
        buffer = buf;
        size = len;
        return false;
    });

    if (buffer && size > 0) {
        return [NSData dataWithBytes:buffer length:size];
    }
    return [NSData data];
}

- (void)parseRequest:(NSData *)data fromConnection:(nw_connection_t)connection {
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

    HttpRequest *request = [HttpRequest requestWithData:requestData];

    if (!request) {
        HttpResponse *response = [HttpResponse responseWithStatusCode:HttpStatusBadRequest];
        [response setBodyString:@"Invalid request"];
        [self sendResponse:response onConnection:connection];
        return;
    }

    // Dispatch request processing to background queue to avoid blocking network I/O
    __weak typeof(self) weakSelf = self;
    nw_connection_t connectionRef = connection; // Capture connection in block
    HttpRequest *requestRef = request; // Capture request in block

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        HttpResponse *response = [strongSelf dispatchRequest:requestRef];

        // Send response back on the network queue
        dispatch_async(strongSelf.serverQueue, ^{
            [strongSelf sendResponse:response onConnection:connectionRef];
        });
    });
}

- (HttpResponse *)dispatchRequest:(HttpRequest *)request {
    HttpResponse *response = [HttpResponse response];

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

- (void)sendResponse:(HttpResponse *)response onConnection:(nw_connection_t)connection {
    NSData *responseData = [response serialize];

    dispatch_data_t dispatchData = dispatch_data_create(responseData.bytes, responseData.length, self.serverQueue, DISPATCH_DATA_DESTRUCTOR_DEFAULT);

    __weak typeof(self) weakSelf = self;
    BOOL shouldKeepAlive = response.keepAlive;
    
    nw_connection_send(connection, dispatchData, _nw_content_context_default_message, true, ^(nw_error_t error) {
        if (error) {
            NSLog(@"Failed to send response");
            nw_connection_cancel(connection);
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
            nw_connection_cancel(connection);
        }
    });
}

- (void)stop {
    if (self.listener) {
        nw_listener_cancel(self.listener);
        self.listener = NULL;
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
