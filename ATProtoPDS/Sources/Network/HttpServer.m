#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/RateLimiter.h"
#import "Network/PDSNetworkTransport.h"
#import "Debug/PDSLogger.h"
#import <CoreFoundation/CoreFoundation.h>

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
@property (nonatomic, strong) NSMapTable<id<PDSNetworkConnection>, id> *connectionStates;

@end

static const NSUInteger kHttpMaxHeaderBytes = 16 * 1024;
static const NSUInteger kHttpMaxBodyBytes = 50 * 1024 * 1024;
static const NSTimeInterval kHttpHeaderTimeout = 5.0;

@interface HttpConnectionState : NSObject

@property (nonatomic, strong) NSMutableData *buffer;
@property (nonatomic, assign) CFHTTPMessageRef message;
@property (nonatomic, assign) BOOL headersComplete;
@property (nonatomic, assign) NSUInteger expectedBodyLength;
@property (nonatomic, assign) NSTimeInterval headerStartTime;
@property (nonatomic, assign) BOOL requestInFlight;
@property (nonatomic, assign) NSUInteger headerEndOffset;

@end

@implementation HttpConnectionState

- (instancetype)init {
    self = [super init];
    if (self) {
        _buffer = [NSMutableData data];
        _message = CFHTTPMessageCreateEmpty(kCFAllocatorDefault, true);
        _headersComplete = NO;
        _expectedBodyLength = 0;
        _headerStartTime = [NSDate timeIntervalSinceReferenceDate];
        _requestInFlight = NO;
        _headerEndOffset = 0;
    }
    return self;
}

- (void)dealloc {
    if (_message) {
        CFRelease(_message);
        _message = NULL;
    }
}

- (void)resetForNextRequest {
    if (_message) {
        CFRelease(_message);
    }
    _message = CFHTTPMessageCreateEmpty(kCFAllocatorDefault, true);
    _headersComplete = NO;
    _expectedBodyLength = 0;
    _headerStartTime = [NSDate timeIntervalSinceReferenceDate];
    _requestInFlight = NO;
    _headerEndOffset = 0;
}

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
        _connectionStates = [NSMapTable strongToStrongObjectsMapTable];
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
                    [strongSelf.connectionStates removeObjectForKey:strongConnection];
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

- (void)readRequestFromConnection:(id<PDSNetworkConnection>)connection {
    HttpConnectionState *state = [self connectionStateForConnection:connection];
    if ([self tryProcessRequestFromState:state connection:connection]) {
        return;
    }
    if (state.requestInFlight) {
        return;
    }

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
            [strongSelf appendData:content toConnection:connection];
        } else if (isComplete) {
            [connection cancel];
        }
        dispatch_group_leave(strongSelf.taskGroup);
    }];
}

- (void)appendData:(NSData *)data toConnection:(id<PDSNetworkConnection>)connection {
    HttpConnectionState *state = [self connectionStateForConnection:connection];
    [state.buffer appendData:data];
    if (![self tryProcessRequestFromState:state connection:connection] && !state.requestInFlight) {
        [self readRequestFromConnection:connection];
    }
}

- (HttpConnectionState *)connectionStateForConnection:(id<PDSNetworkConnection>)connection {
    __block HttpConnectionState *state = nil;
    dispatch_sync(self.connectionQueue, ^{
        state = [self.connectionStates objectForKey:connection];
        if (!state) {
            state = [[HttpConnectionState alloc] init];
            [self.connectionStates setObject:state forKey:connection];
        }
    });
    return state;
}

- (BOOL)tryProcessRequestFromState:(HttpConnectionState *)state connection:(id<PDSNetworkConnection>)connection {
    if (state.requestInFlight) {
        return YES;
    }

    if ([NSDate timeIntervalSinceReferenceDate] - state.headerStartTime > kHttpHeaderTimeout) {
        [connection cancel];
        return YES;
    }

    if (!state.headersComplete) {
        if (state.buffer.length > kHttpMaxHeaderBytes) {
            HttpResponse *response = [HttpResponse responseWithStatusCode:HttpStatusPayloadTooLarge];
            response.keepAlive = NO;
            [response setJsonBody:@{@"error": @"RequestTooLarge", @"message": @"Request headers too large"}];
            state.requestInFlight = YES;
            [self sendResponse:response onConnection:connection];
            return YES;
        }

        NSRange headerEndRange = [self headerEndRangeInData:state.buffer];
        if (headerEndRange.location == NSNotFound) {
            return NO;
        }

        NSData *headerData = [state.buffer subdataWithRange:NSMakeRange(0, headerEndRange.location + headerEndRange.length)];
        if (!CFHTTPMessageAppendBytes(state.message, headerData.bytes, headerData.length)) {
            HttpResponse *response = [HttpResponse responseWithStatusCode:HttpStatusBadRequest];
            response.keepAlive = NO;
            [response setBodyString:@"Invalid request"];
            state.requestInFlight = YES;
            [self sendResponse:response onConnection:connection];
            return YES;
        }

        if (!CFHTTPMessageIsHeaderComplete(state.message)) {
            return NO;
        }

        state.headersComplete = YES;
        state.headerEndOffset = headerEndRange.location + headerEndRange.length;
        state.expectedBodyLength = [self contentLengthForMessage:state.message];

        if (state.expectedBodyLength > kHttpMaxBodyBytes) {
            HttpResponse *response = [HttpResponse responseWithStatusCode:HttpStatusPayloadTooLarge];
            response.keepAlive = NO;
            [response setJsonBody:@{@"error": @"RequestTooLarge", @"message": @"Request body too large"}];
            state.requestInFlight = YES;
            [self sendResponse:response onConnection:connection];
            return YES;
        }
    }

    NSUInteger bodyStart = state.headerEndOffset;
    if (state.buffer.length < bodyStart + state.expectedBodyLength) {
        return NO;
    }

    NSData *bodyData = [state.buffer subdataWithRange:NSMakeRange(bodyStart, state.expectedBodyLength)];

    CFHTTPMessageRef message = state.message;
    NSString *method = (__bridge_transfer NSString *)CFHTTPMessageCopyRequestMethod(message);
    CFURLRef urlRef = CFHTTPMessageCopyRequestURL(message);
    NSURL *url = urlRef ? CFBridgingRelease(urlRef) : nil;
    NSString *version = (__bridge_transfer NSString *)CFHTTPMessageCopyVersion(message);
    NSDictionary *headers = [self headersFromMessage:message];

    if (![self isSupportedTransferEncoding:headers]) {
        HttpResponse *response = [HttpResponse responseWithStatusCode:HttpStatusNotImplemented];
        response.keepAlive = NO;
        [response setJsonBody:@{@"error": @"UnsupportedTransferEncoding", @"message": @"Transfer-Encoding not supported"}];
        state.requestInFlight = YES;
        [self sendResponse:response onConnection:connection];
        return YES;
    }

    NSString *path = url.path ?: @"/";
    NSString *queryString = url.query ?: @"";
    NSDictionary<NSString *, NSString *> *queryParams = [self parseQueryParamsFromString:queryString];
    HttpMethod methodEnum = [self httpMethodFromString:method ?: @""];

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:methodEnum
                                                   methodString:method ?: @""
                                                           path:path
                                                    queryString:queryString
                                                    queryParams:queryParams ?: @{}
                                                        version:version ?: @"HTTP/1.1"
                                                        headers:headers ?: @{}
                                                           body:bodyData
                                                   remoteAddress:connection.remoteAddress ?: @""];

    if (!request) {
        HttpResponse *response = [HttpResponse responseWithStatusCode:HttpStatusBadRequest];
        response.keepAlive = NO;
        [response setBodyString:@"Invalid request"];
        state.requestInFlight = YES;
        [self sendResponse:response onConnection:connection];
        return YES;
    }

    NSUInteger consumedLength = bodyStart + state.expectedBodyLength;
    NSUInteger remainingLength = state.buffer.length - consumedLength;
    NSData *remainingData = remainingLength > 0 ? [state.buffer subdataWithRange:NSMakeRange(consumedLength, remainingLength)] : nil;

    [state.buffer setData:remainingData ?: [NSData data]];
    [state resetForNextRequest];

    state.requestInFlight = YES;
    [self dispatchRequest:request onConnection:connection];
    return YES;
}

- (void)dispatchRequest:(HttpRequest *)request onConnection:(id<PDSNetworkConnection>)connection {
    __weak typeof(self) weakSelf = self;
    __weak id<PDSNetworkConnection> weakConnection = connection;
    HttpRequest *requestRef = request;

    dispatch_group_enter(self.taskGroup);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        __strong typeof(weakConnection) strongConnection = weakConnection;
        if (!strongSelf) {
            dispatch_group_leave(weakSelf.taskGroup);
            return;
        }

        [[PDSLogger sharedLogger] setCorrelationID:requestRef.correlationID];

        HttpResponse *response = [strongSelf dispatchRequest:requestRef];

        dispatch_async(strongSelf.serverQueue, ^{
            [strongSelf sendResponse:response onConnection:strongConnection];
            dispatch_group_leave(strongSelf.taskGroup);
        });

        [[PDSLogger sharedLogger] clearCorrelationID];
    });
}

- (NSRange)headerEndRangeInData:(NSData *)data {
    const uint8_t *bytes = data.bytes;
    for (NSUInteger i = 0; i + 3 < data.length; i++) {
        if (bytes[i] == '\r' && bytes[i + 1] == '\n' && bytes[i + 2] == '\r' && bytes[i + 3] == '\n') {
            return NSMakeRange(i, 4);
        }
    }
    return NSMakeRange(NSNotFound, 0);
}

- (NSUInteger)contentLengthForMessage:(CFHTTPMessageRef)message {
    NSString *contentLengthString = (__bridge_transfer NSString *)CFHTTPMessageCopyHeaderFieldValue(message, CFSTR("Content-Length"));
    if (!contentLengthString) {
        return 0;
    }
    return (NSUInteger)[contentLengthString longLongValue];
}

- (NSDictionary<NSString *, NSString *> *)headersFromMessage:(CFHTTPMessageRef)message {
    NSDictionary *rawHeaders = (__bridge_transfer NSDictionary *)CFHTTPMessageCopyAllHeaderFields(message);
    if (!rawHeaders) {
        return @{};
    }
    NSMutableDictionary<NSString *, NSString *> *headers = [NSMutableDictionary dictionaryWithCapacity:rawHeaders.count];
    for (NSString *key in rawHeaders) {
        NSString *value = rawHeaders[key];
        if (key && value) {
            headers[key.lowercaseString] = value;
        }
    }
    return [headers copy];
}

- (BOOL)isSupportedTransferEncoding:(NSDictionary<NSString *, NSString *> *)headers {
    NSString *transferEncoding = headers[@"transfer-encoding"];
    if (!transferEncoding || transferEncoding.length == 0) {
        return YES;
    }
    NSString *lowercased = transferEncoding.lowercaseString;
    return [lowercased isEqualToString:@"identity"];
}

- (NSDictionary<NSString *, NSString *> *)parseQueryParamsFromString:(NSString *)queryString {
    if (queryString.length == 0) {
        return @{};
    }

    NSMutableDictionary<NSString *, NSString *> *params = [NSMutableDictionary dictionary];
    NSArray<NSString *> *pairs = [queryString componentsSeparatedByString:@"&"];

    for (NSString *pair in pairs) {
        NSRange eqRange = [pair rangeOfString:@"="];
        if (eqRange.location != NSNotFound) {
            NSString *key = [self urlDecode:[pair substringToIndex:eqRange.location]];
            NSString *value = [self urlDecode:[pair substringFromIndex:eqRange.location + 1]];
            params[key] = value;
        } else {
            params[[self urlDecode:pair]] = @"";
        }
    }

    return [params copy];
}

- (NSString *)urlDecode:(NSString *)string {
    NSString *result = [string stringByReplacingOccurrencesOfString:@"+" withString:@" "];
    result = [result stringByRemovingPercentEncoding];
    return result ?: string;
}

- (HttpMethod)httpMethodFromString:(NSString *)methodString {
    if ([methodString isEqualToString:@"GET"]) return HttpMethodGET;
    if ([methodString isEqualToString:@"POST"]) return HttpMethodPOST;
    if ([methodString isEqualToString:@"PUT"]) return HttpMethodPUT;
    if ([methodString isEqualToString:@"DELETE"]) return HttpMethodDELETE;
    if ([methodString isEqualToString:@"PATCH"]) return HttpMethodPATCH;
    if ([methodString isEqualToString:@"OPTIONS"]) return HttpMethodOPTIONS;
    if ([methodString isEqualToString:@"HEAD"]) return HttpMethodHEAD;
    return HttpMethodUnknown;
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

        HttpConnectionState *state = [weakSelf connectionStateForConnection:connection];
        state.requestInFlight = NO;

        if (shouldKeepAlive) {
            // HTTP/1.1 keep-alive: read the next request on this connection
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf) {
                if (![strongSelf tryProcessRequestFromState:state connection:connection]) {
                    [strongSelf readRequestFromConnection:connection];
                }
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
        [self.connectionStates removeAllObjects];
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
