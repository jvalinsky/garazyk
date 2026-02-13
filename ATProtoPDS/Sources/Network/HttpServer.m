/*!
 @file HttpServer.m

 @abstract HTTP server implementation for the PDS.

 @discussion This file implements the HTTP server that handles incoming
 requests, routes them to handlers, and sends responses. It supports
 route registration, keep-alive connections, and request parsing.

 @copyright Copyright (c) 2024 Jack Myers
 */

#import "Network/HttpServer.h"
#import "Compat/PDSTypes.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/RateLimiter.h"
#import "Network/PDSNetworkTransport.h"
#import "Network/HttpBufferPool.h"
#import "Network/HttpChunkedBodyParser.h"
#import "Debug/PDSLogger.h"
#import <CoreFoundation/CoreFoundation.h>
#import "Network/HttpRouteTrie.h"
#import "Network/WebSocketUpgradeHandler.h"

@class HttpRouteTrie;

@interface HttpServer ()

@property (nonatomic, readwrite, nullable) NSString *host;
@property (nonatomic, readwrite) NSUInteger port;
@property (nonatomic, readwrite, getter=isRunning) BOOL running;
@property (nonatomic, strong) id<PDSNetworkListener> listener;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t serverQueue;
@property (nonatomic, strong) NSMutableDictionary<NSString *, HttpRouteTrie *> *routeTries;
@property (nonatomic, strong) NSMutableDictionary<NSString *, RequestHandler> *pathHandlers;
@property (nonatomic, copy) void (^requestHandler)(HttpRequest *, HttpResponse *);
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_semaphore_t readySemaphore;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_semaphore_t stopSemaphore;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_group_t taskGroup;
@property (nonatomic, assign) BOOL listenerReady;
@property (nonatomic, assign) BOOL startupFinished;
@property (nonatomic, strong, nullable) NSError *startupError;
@property (nonatomic, strong) NSMutableSet<id<PDSNetworkConnection>> *activeConnections;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t connectionQueue;
@property (nonatomic, strong) NSMapTable<id<PDSNetworkConnection>, id> *connectionStates;

@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_semaphore_t concurrencySemaphore;
@property (nonatomic, strong) WebSocketUpgradeHandler *webSocketUpgradeHandler;
@property (nonatomic, strong) NSMutableDictionary<NSString *, WebSocketRequestHandler> *webSocketHandlers;

@end

static const NSUInteger kHttpMaxHeaderBytes = 16 * 1024;
static const NSUInteger kHttpMaxBodyBytes = 50 * 1024 * 1024;
static const NSUInteger kHttpOutputQueueHighWaterMark = 10 * 1024 * 1024; // 10MB
static const NSTimeInterval kHttpHeaderTimeout = 5.0;
static const NSUInteger kMaxConcurrentRequests = 64; // Limit concurrent threads
static const NSUInteger kHttpFileSendChunkSize = 64 * 1024;

@interface HttpQueuedResponse : NSObject
@property (nonatomic, strong) NSData *headerData;
@property (nonatomic, strong, nullable) NSData *bodyData;
@property (nonatomic, copy, nullable) NSString *bodyFilePath;
@property (nonatomic, assign) BOOL deleteBodyFileAfterSend;
@property (nonatomic, assign) NSUInteger queueByteSize;
@end

@implementation HttpQueuedResponse
@end

@interface HttpConnectionState : NSObject

@property (nonatomic, strong) NSMutableData *buffer;
@property (nonatomic, assign) CFHTTPMessageRef message;
@property (nonatomic, assign) BOOL headersComplete;
@property (nonatomic, assign) NSUInteger expectedBodyLength;
@property (nonatomic, assign) NSTimeInterval headerStartTime;
@property (nonatomic, assign) BOOL requestInFlight;
@property (nonatomic, assign) NSUInteger headerEndOffset;
@property (nonatomic, strong) NSMutableArray<HttpQueuedResponse *> *outputQueue;
@property (nonatomic, assign) BOOL readingPaused;
@property (nonatomic, assign) NSUInteger outputQueueSize;
@property (nonatomic, strong, nullable) HttpChunkedBodyParser *chunkedBodyParser;
@property (nonatomic, assign) BOOL isChunkedEncoding;
@property (nonatomic, strong) NSMutableArray<HttpRequest *> *pendingRequests;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *pendingRequestOffsets;
@property (nonatomic, assign) NSUInteger pendingDispatchCount;
@property (nonatomic, assign) NSUInteger maxPipelinedRequests;
@property (nonatomic, assign) BOOL sendingActive;
@property (nonatomic, assign) BOOL upgradedToWebSocket;

@end

@implementation HttpConnectionState

static const NSUInteger kDefaultMaxPipelinedRequests = 4;

- (instancetype)init {
    self = [super init];
    if (self) {
        _buffer = [[HttpBufferPool sharedPool] acquireBufferOfSize:1024];
        _message = CFHTTPMessageCreateEmpty(kCFAllocatorDefault, true);
        _headersComplete = NO;
        _expectedBodyLength = 0;
        _headerStartTime = [NSDate timeIntervalSinceReferenceDate];
        _requestInFlight = NO;
        _headerEndOffset = 0;
        _outputQueue = [NSMutableArray array];
        _readingPaused = NO;
        _outputQueueSize = 0;
        _pendingRequests = [NSMutableArray array];
        _pendingRequestOffsets = [NSMutableArray array];
        _pendingDispatchCount = 0;
        _maxPipelinedRequests = kDefaultMaxPipelinedRequests;
        _sendingActive = NO;
        _upgradedToWebSocket = NO;
    }
    return self;
}

- (void)dealloc {
    if (_message) {
        CFRelease(_message);
        _message = NULL;
    }
    [[HttpBufferPool sharedPool] releaseBuffer:_buffer];
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
    [_outputQueue removeAllObjects];
    _outputQueueSize = 0;
    _readingPaused = NO;
    [_buffer setLength:0];
    _isChunkedEncoding = NO;
    _chunkedBodyParser = nil;
}

@end

@implementation HttpServer

+ (instancetype)serverWithPort:(NSUInteger)port {
    return [[self alloc] initWithHost:nil port:port];
}

+ (instancetype)serverWithHost:(NSString *)host port:(NSUInteger)port {
    return [[self alloc] initWithHost:host port:port];
}

/*!
 @method initWithPort:

 @abstract Initializes an HTTP server on the specified port.

 @discussion The server is configured but not started. Call startWithError:
 to begin listening for connections.

 @param port The port number to listen on.
 @return An initialized server instance.
 */
- (instancetype)initWithHost:(NSString * _Nullable)host port:(NSUInteger)port {
    self = [super init];
    if (self) {
        _host = [host copy];
        _port = port;
        _serverQueue = dispatch_queue_create("com.atproto.pds.httpserver", DISPATCH_QUEUE_SERIAL);
        _routeTries = [NSMutableDictionary dictionary];
        _pathHandlers = [NSMutableDictionary dictionary];
        _activeConnections = [NSMutableSet set];
        _connectionQueue = dispatch_queue_create("com.atproto.pds.httpserver.connections", DISPATCH_QUEUE_SERIAL);
        _readySemaphore = dispatch_semaphore_create(0);
        _stopSemaphore = dispatch_semaphore_create(0);
        _concurrencySemaphore = dispatch_semaphore_create(kMaxConcurrentRequests);
        _taskGroup = dispatch_group_create();
        _connectionStates = [NSMapTable strongToStrongObjectsMapTable];
        _webSocketUpgradeHandler = [[WebSocketUpgradeHandler alloc] init];
        _webSocketHandlers = [NSMutableDictionary dictionary];
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

    if (self.host.length > 0) {
        self.listener = [PDSNetworkTransportFactory createListenerWithHost:self.host port:self.port];
    } else {
        self.listener = [PDSNetworkTransportFactory createListenerWithPort:self.port];
    }

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
                strongSelf.startupError = error;
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
            NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObject:@"Server failed to start"
                                                                               forKey:NSLocalizedDescriptionKey];
            if (self.startupError) {
                userInfo[NSUnderlyingErrorKey] = self.startupError;
            }
            *error = [NSError errorWithDomain:@"com.atproto.pds.httpserver"
                                         code:-3
                                     userInfo:userInfo];
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
            case PDSNetworkConnectionStateFailed: {
                dispatch_async(strongSelf.connectionQueue, ^{
                    [strongSelf.activeConnections removeObject:strongConnection];
                    [strongSelf.connectionStates removeObjectForKey:strongConnection];
                });
                [strongConnection cancel];
                break;
            }
            case PDSNetworkConnectionStateCancelled: {
                // Already cancelled, just clean up
                dispatch_async(strongSelf.connectionQueue, ^{
                    [strongSelf.activeConnections removeObject:strongConnection];
                    [strongSelf.connectionStates removeObjectForKey:strongConnection];
                });
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
    if (state.upgradedToWebSocket) {
        return;
    }

    if (state.pendingDispatchCount > 0 || state.outputQueue.count > 0 || state.pendingRequests.count > 0) {
        return;
    }

    if ([NSDate timeIntervalSinceReferenceDate] - state.headerStartTime > kHttpHeaderTimeout) {
        [connection cancel];
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
            if (strongSelf) {
                [strongSelf handleReceivedData:content onConnection:connection];
            }
        } else if (isComplete) {
            [connection cancel];
        }
        dispatch_group_leave(strongSelf.taskGroup);
    }];
}

- (void)handleReceivedData:(NSData *)data onConnection:(id<PDSNetworkConnection>)connection {
    HttpConnectionState *state = [self connectionStateForConnection:connection];
    [state.buffer appendData:data];

    [self tryProcessRequestFromState:state connection:connection];

    if (state.pendingDispatchCount == 0 && state.outputQueue.count == 0) {
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
    if ([NSDate timeIntervalSinceReferenceDate] - state.headerStartTime > kHttpHeaderTimeout) {
        [connection cancel];
        return YES;
    }

    if (!state.headersComplete) {
        if (state.buffer.length > kHttpMaxHeaderBytes) {
            HttpResponse *response = [HttpResponse responseWithStatusCode:HttpStatusPayloadTooLarge];
            response.keepAlive = NO;
            [response setJsonBody:@{@"error": @"RequestTooLarge", @"message": @"Request headers too large"}];
            [self queueResponse:response forState:state connection:connection];
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
            [self queueResponse:response forState:state connection:connection];
            return YES;
        }

        if (!CFHTTPMessageIsHeaderComplete(state.message)) {
            return NO;
        }

        state.headersComplete = YES;
        state.headerEndOffset = headerEndRange.location + headerEndRange.length;
        state.expectedBodyLength = [self contentLengthForMessage:state.message];

        NSDictionary *headers = [self headersFromMessage:state.message];
        NSString *transferEncoding = [[headers objectForKey:@"transfer-encoding"] lowercaseString];
        state.isChunkedEncoding = [transferEncoding containsString:@"chunked"];

        if (state.isChunkedEncoding) {
            state.chunkedBodyParser = [[HttpChunkedBodyParser alloc] initWithMaxSize:kHttpMaxBodyBytes];
            state.expectedBodyLength = 0;
        } else if (state.expectedBodyLength > kHttpMaxBodyBytes) {
            HttpResponse *response = [HttpResponse responseWithStatusCode:HttpStatusPayloadTooLarge];
            response.keepAlive = NO;
            [response setJsonBody:@{@"error": @"RequestTooLarge", @"message": @"Request body too large"}];
            [self queueResponse:response forState:state connection:connection];
            return YES;
        }
        
        NSString *method = (__bridge_transfer NSString *)CFHTTPMessageCopyRequestMethod(state.message);
        HttpMethod methodEnum = [self httpMethodFromString:method ?: @""];
        BOOL expectsBody = (methodEnum == HttpMethodPOST || methodEnum == HttpMethodPUT || methodEnum == HttpMethodPATCH);
        
        if (expectsBody && !state.isChunkedEncoding && state.expectedBodyLength == 0) {
            HttpResponse *response = [HttpResponse responseWithStatusCode:HttpStatusLengthRequired];
            response.keepAlive = NO;
            [response setJsonBody:@{@"error": @"LengthRequired", @"message": @"Content-Length or Transfer-Encoding: chunked required"}];
            [self queueResponse:response forState:state connection:connection];
            return YES;
        }
    }

    NSData *bodyData = nil;
    NSUInteger consumedOffset = 0;

    if (state.isChunkedEncoding) {
        NSUInteger bodyStart = state.headerEndOffset;
        NSUInteger availableBodyLength = state.buffer.length > bodyStart ? state.buffer.length - bodyStart : 0;

        if (availableBodyLength > 0) {
            NSData *bodyChunk = [state.buffer subdataWithRange:NSMakeRange(bodyStart, availableBodyLength)];
            NSError *parseError = nil;
            BOOL shouldContinue = [state.chunkedBodyParser appendData:bodyChunk error:&parseError];

            if (parseError) {
                HttpResponse *response = [HttpResponse responseWithStatusCode:HttpStatusBadRequest];
                response.keepAlive = NO;
                [response setBodyString:@"Invalid chunked body"];
                [self queueResponse:response forState:state connection:connection];
                return YES;
            }

            if (!shouldContinue) {
                return NO;
            }

            if (!state.chunkedBodyParser.isComplete) {
                return NO;
            }

            bodyData = state.chunkedBodyParser.parsedData;
            consumedOffset = state.buffer.length;
        } else {
            return NO;
        }
    } else {
        NSUInteger bodyStart = state.headerEndOffset;
        if (state.buffer.length < bodyStart + state.expectedBodyLength) {
            return NO;
        }

        bodyData = [state.buffer subdataWithRange:NSMakeRange(bodyStart, state.expectedBodyLength)];
        consumedOffset = bodyStart + state.expectedBodyLength;
    }

    CFHTTPMessageRef message = state.message;
    NSString *method = (__bridge_transfer NSString *)CFHTTPMessageCopyRequestMethod(message);
    CFURLRef urlRef = CFHTTPMessageCopyRequestURL(message);
#if defined(__APPLE__)
    NSURL *url = urlRef ? CFBridgingRelease(urlRef) : nil;
#else
    NSURL *url = CFURLToNSURL(urlRef);
    if (urlRef) CFURLRelease(urlRef);
#endif
    NSString *version = (__bridge_transfer NSString *)CFHTTPMessageCopyVersion(message);
    NSDictionary *headers = [self headersFromMessage:message];

    if (![self isSupportedTransferEncoding:headers]) {
        HttpResponse *response = [HttpResponse responseWithStatusCode:HttpStatusNotImplemented];
        response.keepAlive = NO;
        [response setJsonBody:@{@"error": @"UnsupportedTransferEncoding", @"message": @"Transfer-Encoding not supported"}];
        [self queueResponse:response forState:state connection:connection];
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
                                                       body:bodyData ?: [NSData data]
                                               remoteAddress:connection.remoteAddress ?: @""];

    if (!request) {
        HttpResponse *response = [HttpResponse responseWithStatusCode:HttpStatusBadRequest];
        response.keepAlive = NO;
        [response setBodyString:@"Invalid request"];
        [self queueResponse:response forState:state connection:connection];
        return YES;
    }

    WebSocketRequestHandler webSocketHandler = self.webSocketHandlers[path];
    if (webSocketHandler) {
        HttpResponse *upgradeResponse = [HttpResponse response];
        BOOL shouldUpgrade = [self.webSocketUpgradeHandler handleUpgradeRequest:request response:upgradeResponse];
        if (!shouldUpgrade) {
            [state resetForNextRequest];
            [self queueResponse:upgradeResponse forState:state connection:connection];
            return YES;
        }

        state.upgradedToWebSocket = YES;
        [state.pendingRequests removeAllObjects];
        [state.pendingRequestOffsets removeAllObjects];
        [state.outputQueue removeAllObjects];
        state.outputQueueSize = 0;
        [state.buffer setLength:0];

        NSData *responseData = [upgradeResponse serialize];
        [connection sendData:responseData completion:^(NSError * _Nullable error) {
            if (error) {
                [connection cancel];
                return;
            }
            webSocketHandler(request, upgradeResponse, connection);
        }];
        return YES;
    }

    [state resetForNextRequest];

    NSUInteger requestOffset = consumedOffset;
    [state.pendingRequests addObject:request];
    [state.pendingRequestOffsets addObject:@(requestOffset)];

    [self processPipelinedRequestsForState:state connection:connection];

    return YES;
}

- (void)processPipelinedRequestsForState:(HttpConnectionState *)state connection:(id<PDSNetworkConnection>)connection {
    while (state.pendingRequests.count > 0 && state.pendingDispatchCount < state.maxPipelinedRequests) {
        HttpRequest *request = state.pendingRequests[0];
        [state.pendingRequests removeObjectAtIndex:0];
        [state.pendingRequestOffsets removeObjectAtIndex:0];
        state.pendingDispatchCount++;

        [self dispatchRequest:request onConnection:connection];
    }
}

- (void)queueResponse:(HttpResponse *)response forState:(HttpConnectionState *)state connection:(id<PDSNetworkConnection>)connection {
    HttpQueuedResponse *queueItem = [self queueItemForResponse:response];
    [state.outputQueue addObject:queueItem];
    state.outputQueueSize += queueItem.queueByteSize;

    while (state.outputQueueSize > kHttpOutputQueueHighWaterMark) {
        HttpQueuedResponse *oldest = state.outputQueue[0];
        state.outputQueueSize -= oldest.queueByteSize;
        if (oldest.deleteBodyFileAfterSend && oldest.bodyFilePath.length > 0) {
            [[NSFileManager defaultManager] removeItemAtPath:oldest.bodyFilePath error:nil];
        }
        [state.outputQueue removeObjectAtIndex:0];
    }

    [self sendNextQueuedResponseForState:state connection:connection];
}

- (void)dispatchRequest:(HttpRequest *)request onConnection:(id<PDSNetworkConnection>)connection {
    __weak typeof(self) weakSelf = self;
    __weak id<PDSNetworkConnection> weakConnection = connection;
    HttpRequest *requestRef = request;

    dispatch_group_enter(self.taskGroup);
    
    // Wait for semaphore to limit concurrency
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        dispatch_semaphore_wait(weakSelf.concurrencySemaphore, DISPATCH_TIME_FOREVER);
        
        __strong typeof(weakSelf) strongSelf = weakSelf;
        __strong typeof(weakConnection) strongConnection = weakConnection;
        if (!strongSelf) {
            dispatch_semaphore_signal(weakSelf.concurrencySemaphore); // Ensure signal on early exit
            dispatch_group_leave(weakSelf.taskGroup);
            return;
        }

        [[PDSLogger sharedLogger] setCorrelationID:requestRef.correlationID];

        PDS_LOG_HTTP_INFO(@"Starting dispatch for %@ %@", requestRef.methodString, requestRef.path);
        HttpResponse *response = [strongSelf dispatchRequest:requestRef];
        PDS_LOG_HTTP_INFO(@"Finished dispatch for %@ %@, status %ld", requestRef.methodString, requestRef.path, (long)response.statusCode);

        dispatch_async(strongSelf.serverQueue, ^{
            [strongSelf enqueueResponse:response forConnection:strongConnection];
            dispatch_semaphore_signal(strongSelf.concurrencySemaphore); // Signal completion
            dispatch_group_leave(strongSelf.taskGroup);
        });

        [[PDSLogger sharedLogger] clearCorrelationID];
    });
}

- (void)enqueueResponse:(HttpResponse *)response forConnection:(id<PDSNetworkConnection>)connection {
    HttpConnectionState *state = [self connectionStateForConnection:connection];
    HttpQueuedResponse *queueItem = [self queueItemForResponse:response];

    [state.outputQueue addObject:queueItem];
    state.outputQueueSize += queueItem.queueByteSize;

    while (state.outputQueueSize > kHttpOutputQueueHighWaterMark && state.outputQueue.count > 0) {
        HttpQueuedResponse *oldest = state.outputQueue[0];
        state.outputQueueSize -= oldest.queueByteSize;
        if (oldest.deleteBodyFileAfterSend && oldest.bodyFilePath.length > 0) {
            [[NSFileManager defaultManager] removeItemAtPath:oldest.bodyFilePath error:nil];
        }
        [state.outputQueue removeObjectAtIndex:0];
    }

    [self sendNextQueuedResponseForState:state connection:connection];
}

- (void)sendNextQueuedResponseForState:(HttpConnectionState *)state connection:(id<PDSNetworkConnection>)connection {
    if (state.outputQueue.count == 0 || state.sendingActive) {
        return;
    }

    state.sendingActive = YES;
    HttpQueuedResponse *queueItem = state.outputQueue[0];

    __weak typeof(self) weakSelf = self;
    [connection sendData:queueItem.headerData completion:^(NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        if (error) {
            PDS_LOG_HTTP_ERROR(@"Failed to send pipelined response: %@", error);
            if (queueItem.deleteBodyFileAfterSend && queueItem.bodyFilePath.length > 0) {
                [[NSFileManager defaultManager] removeItemAtPath:queueItem.bodyFilePath error:nil];
            }
            [connection cancel];
            return;
        }

        if (queueItem.bodyFilePath.length > 0) {
            [strongSelf streamFileQueueItem:queueItem forState:state connection:connection];
            return;
        }
        [strongSelf finalizeQueuedResponseSend:queueItem forState:state connection:connection];
    }];
}

- (HttpQueuedResponse *)queueItemForResponse:(HttpResponse *)response {
    HttpQueuedResponse *queueItem = [[HttpQueuedResponse alloc] init];
    NSString *bodyFilePath = response.bodyFilePath;
    if (bodyFilePath.length > 0) {
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:bodyFilePath error:nil];
        NSNumber *fileSize = attributes[NSFileSize];
        NSUInteger bodyLength = fileSize ? (NSUInteger)fileSize.unsignedLongLongValue : 0;
        queueItem.headerData = [response serializeHeadersForBodyLength:bodyLength];
        queueItem.bodyFilePath = bodyFilePath;
        queueItem.deleteBodyFileAfterSend = response.deleteBodyFileAfterSend;
        queueItem.queueByteSize = queueItem.headerData.length;
        return queueItem;
    }

    NSData *serialized = [response serialize];
    queueItem.headerData = serialized;
    queueItem.queueByteSize = serialized.length;
    return queueItem;
}

- (void)streamFileQueueItem:(HttpQueuedResponse *)queueItem
                   forState:(HttpConnectionState *)state
                 connection:(id<PDSNetworkConnection>)connection {
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingAtPath:queueItem.bodyFilePath];
    if (!fileHandle) {
        PDS_LOG_HTTP_ERROR(@"Failed to open response body file at path %@", queueItem.bodyFilePath);
        if (queueItem.deleteBodyFileAfterSend && queueItem.bodyFilePath.length > 0) {
            [[NSFileManager defaultManager] removeItemAtPath:queueItem.bodyFilePath error:nil];
        }
        [connection cancel];
        return;
    }

    __weak typeof(self) weakSelf = self;
    __block void (^sendNextChunk)(void) = nil;
    __weak void (^weakSendNextChunk)(void) = nil;
    sendNextChunk = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            @try {
                [fileHandle closeFile];
            } @catch (__unused NSException *exception) {
            }
            return;
        }

        @autoreleasepool {
            NSData *chunk = [fileHandle readDataOfLength:kHttpFileSendChunkSize];
            if (chunk.length == 0) {
                @try {
                    [fileHandle closeFile];
                } @catch (__unused NSException *exception) {
                }
                [strongSelf finalizeQueuedResponseSend:queueItem forState:state connection:connection];
                return;
            }

            [connection sendData:chunk completion:^(NSError *error) {
                if (error) {
                    PDS_LOG_HTTP_ERROR(@"Failed to stream response body file: %@", error);
                    @try {
                        [fileHandle closeFile];
                    } @catch (__unused NSException *exception) {
                    }
                    if (queueItem.deleteBodyFileAfterSend && queueItem.bodyFilePath.length > 0) {
                        [[NSFileManager defaultManager] removeItemAtPath:queueItem.bodyFilePath error:nil];
                    }
                    [connection cancel];
                    return;
                }
                if (weakSendNextChunk) {
                    weakSendNextChunk();
                }
            }];
        }
    };
    weakSendNextChunk = sendNextChunk;

    sendNextChunk();
}

- (void)finalizeQueuedResponseSend:(HttpQueuedResponse *)queueItem
                          forState:(HttpConnectionState *)state
                        connection:(id<PDSNetworkConnection>)connection {
    if (state.outputQueue.count > 0) {
        [state.outputQueue removeObjectAtIndex:0];
    }
    state.outputQueueSize = (state.outputQueueSize > queueItem.queueByteSize)
        ? (state.outputQueueSize - queueItem.queueByteSize)
        : 0;
    if (state.pendingDispatchCount > 0) {
        state.pendingDispatchCount--;
    }
    state.sendingActive = NO;

    if (queueItem.deleteBodyFileAfterSend && queueItem.bodyFilePath.length > 0) {
        [[NSFileManager defaultManager] removeItemAtPath:queueItem.bodyFilePath error:nil];
    }

    if (state.outputQueue.count > 0) {
        [self sendNextQueuedResponseForState:state connection:connection];
    } else {
        [self continueConnection:connection withState:state];
    }
}

- (void)continueConnection:(id<PDSNetworkConnection>)connection withState:(HttpConnectionState *)state {
    if (state.outputQueue.count == 0 && state.pendingDispatchCount == 0 && state.pendingRequests.count == 0) {
        [self readRequestFromConnection:connection];
    }
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
    if ([lowercased isEqualToString:@"identity"]) {
        return YES;
    }
    if ([lowercased isEqualToString:@"chunked"]) {
        return YES;
    }
    return NO;
}

- (RequestHandler _Nullable)handlerForRoute:(NSString *)path method:(NSString *)method parameters:(NSDictionary<NSString *, NSString *> * _Nullable * _Nullable)parameters {
    NSString *normalizedMethod = [(method ?: @"") uppercaseString];
    HttpRouteTrie *trie = self.routeTries[normalizedMethod];
    NSDictionary<NSString *, NSString *> *matchedParams = nil;
    RequestHandler handler = [trie handlerForMethod:normalizedMethod path:path outParameters:&matchedParams];
    if (!handler) {
        HttpRouteTrie *catchAll = self.routeTries[@"*"];
        handler = [catchAll handlerForMethod:@"*" path:path outParameters:&matchedParams];
    }
    if (parameters) {
        *parameters = handler ? matchedParams : nil;
    }
    return handler;
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
    PDS_LOG_HTTP_INFO(@"%@ %@", request.methodString, request.path);
    HttpResponse *response = [HttpResponse response];

    /* Force disabled for now to fix user block
    if ([request.path hasPrefix:@"/oauth/"] && !RateLimiterIsDisabledGlobally() && [RateLimiter sharedLimiter].isEnabled) {
        RateLimitResult *result = [[RateLimiter sharedLimiter] checkRateLimitForIP:request.remoteAddress];
        if (!result.allowed) {
            response.statusCode = 429;
            [response setJsonBody:@{@"error": @"too_many_requests", @"message": @"Rate limit exceeded"}];
            return response;
        }
    }
    */

    if (self.requestHandler) {
        self.requestHandler(request, response);
        return response;
    }

    NSString *methodString = request.methodString;
    NSString *path = request.path;

    NSDictionary<NSString *, NSString *> *pathParameters = nil;

    // First try exact path match
    RequestHandler handler = self.pathHandlers[path];

    // Then try prefix matching for pathHandlers (e.g., /explore matches /explore/css/style.css)
    if (!handler) {
        for (NSString *registeredPath in self.pathHandlers) {
            if ([path hasPrefix:registeredPath] && 
                (path.length == registeredPath.length || 
                 [path characterAtIndex:registeredPath.length] == '/')) {
                handler = self.pathHandlers[registeredPath];
                break;
            }
        }
    }

    // Finally try route trie
    if (!handler) {
        handler = [self handlerForRoute:path method:methodString parameters:&pathParameters];
    }

    request.pathParameters = pathParameters;

    if (handler) {
        handler(request, response);
    } else {
        response.statusCode = HttpStatusNotFound;
        [response setJsonBody:@{@"error": @"Not Found", @"message": [NSString stringWithFormat:@"No handler for %@ %@", methodString, path]}];
    }

    return response;
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
    [self enqueueResponse:response forConnection:connection];
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
    if (!method || !path || !handler) {
        return;
    }
    NSString *normalizedMethod = [method.uppercaseString length] ? method.uppercaseString : @"*";
    HttpRouteTrie *trie = self.routeTries[normalizedMethod];
    if (!trie) {
        trie = [[HttpRouteTrie alloc] init];
        self.routeTries[normalizedMethod] = trie;
    }
    [trie insertRoute:normalizedMethod pattern:path handler:[handler copy] priority:100];
}

- (void)addHandlerForPath:(NSString *)path handler:(RequestHandler)handler {
    self.pathHandlers[path] = [handler copy];
}

- (void)addWebSocketRoute:(NSString *)path handler:(WebSocketRequestHandler)handler {
    if (!path || !handler) {
        return;
    }
    self.webSocketHandlers[path] = [handler copy];
}

@end
