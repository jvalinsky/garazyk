// SPDX-FileCopyrightText: 2024-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file HttpServer.m

 @abstract HTTP server implementation for the PDS.

 @discussion This file implements the HTTP server that handles incoming
 requests, routes them to handlers, and sends responses. It supports
 route registration, keep-alive connections, and request parsing.

 @copyright Copyright (c) 2024-2026 Jack Valinsky
 */

#import "Network/HttpServer.h"
#import "Compat/PDSTypes.h"
#import "Debug/GZLogger.h"
#import "Metrics/GZMetrics.h"
#import "Network/HttpBufferPool.h"
#import "Network/HttpParsing.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpRouteTrie.h"
#import "Network/ATProtoNetworkTransport.h"
#import "Network/RateLimiter.h"
#import "Network/WebSocketUpgradeHandler.h"
#import "Network/HttpProtocolSession.h"
#import "Network/HttpRequestDispatcher.h"
#import "Network/HttpResponseSender.h"
#import "Network/HttpProtocolDriver.h"
#import "Network/HttpConnectionIOCoordinator.h"
#import <CoreFoundation/CoreFoundation.h>

@class HttpRouteTrie;

@interface HttpQueuedResponse : NSObject
@property(nonatomic, strong) NSData *headerData;
@property(nonatomic, strong, nullable) NSData *bodyData;
@property(nonatomic, copy, nullable) NSString *bodyFilePath;
@property(nonatomic, assign) BOOL deleteBodyFileAfterSend;
@property(nonatomic, copy, nullable)
    HttpResponseBodyChunkProducer bodyChunkProducer;
@property(nonatomic, assign) BOOL chunkedTransferEncoding;
@property(nonatomic, assign) BOOL closeAfterSend;
@property(nonatomic, strong, nullable) NSData *pendingGeneratedChunk;
@property(nonatomic, assign) NSUInteger pendingGeneratedChunkOffset;
@property(nonatomic, assign) NSUInteger queueByteSize;
@property(nonatomic, assign) BOOL isRangeRequest;
@property(nonatomic, assign) NSUInteger rangeStart;
@property(nonatomic, assign) NSUInteger rangeLength;
@end

@interface HttpConnectionState : NSObject

@property(nonatomic, strong) HttpProtocolDriver *driver;
@property(nonatomic, assign) NSTimeInterval headerStartTime;
@property(nonatomic, strong) NSMutableArray<HttpQueuedResponse *> *outputQueue;
@property(nonatomic, assign) NSUInteger outputQueueSize;
@property(nonatomic, assign) BOOL sendingActive;
@property(nonatomic, assign) BOOL upgradedToWebSocket;
@property(nonatomic, PDS_DISPATCH_QUEUE_STRONG)
    dispatch_queue_t transportQueue;
@property(nonatomic, strong, nullable) HttpConnectionIOCoordinator *coordinator;

@end

@interface HttpServer ()

@property(nonatomic, readwrite, nullable) NSString *host;
@property(atomic, readwrite) NSUInteger port;
@property(atomic, readwrite, getter=isRunning) BOOL running;
@property(nonatomic, strong) id<ATProtoNetworkListener> listener;
@property(nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t serverQueue;
@property(nonatomic, strong)
    NSMutableDictionary<NSString *, HttpRouteTrie *> *routeTries;
@property(nonatomic, strong)
    NSMutableDictionary<NSString *, RequestHandler> *pathHandlers;
@property(nonatomic, copy) void (^requestHandler)(HttpRequest *, HttpResponse *)
    ;
@property(nonatomic, PDS_DISPATCH_QUEUE_STRONG)
    dispatch_semaphore_t readySemaphore;
@property(nonatomic, PDS_DISPATCH_QUEUE_STRONG)
    dispatch_semaphore_t stopSemaphore;
@property(nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_group_t taskGroup;
@property(atomic, assign) BOOL listenerReady;
@property(atomic, assign) BOOL startupFinished;
@property(nonatomic, strong, nullable) NSError *startupError;
@property(nonatomic, strong)
    NSMutableSet<id<ATProtoNetworkConnection>> *activeConnections;
@property(nonatomic, PDS_DISPATCH_QUEUE_STRONG)
    dispatch_queue_t connectionQueue;
@property(nonatomic, strong)
    NSMapTable<id<ATProtoNetworkConnection>, id> *connectionStates;

@property(nonatomic, PDS_DISPATCH_QUEUE_STRONG)
    dispatch_semaphore_t concurrencySemaphore;
@property(nonatomic, strong) WebSocketUpgradeHandler *webSocketUpgradeHandler;
@property(nonatomic, strong)
    NSMutableDictionary<NSString *, WebSocketRequestHandler> *webSocketHandlers;
@property(nonatomic, strong) HttpRequestDispatcher *requestDispatcher;
@property(nonatomic, strong) HttpResponseSender *responseSender;

- (HttpQueuedResponse *)queueItemForResponse:(HttpResponse *)response;
- (void)enqueueResponse:(HttpResponse *)response
           forConnection:(id<ATProtoNetworkConnection>)connection;
- (void)sendNextQueuedResponseForState:(HttpConnectionState *)state
                             connection:(id<ATProtoNetworkConnection>)connection;
- (void)finalizeQueuedResponseSend:(HttpQueuedResponse *)queueItem
                          forState:(HttpConnectionState *)state
                        connection:(id<ATProtoNetworkConnection>)connection;
- (void)streamFileQueueItem:(HttpQueuedResponse *)queueItem
                 forState:(HttpConnectionState *)state
               connection:(id<ATProtoNetworkConnection>)connection;
- (void)streamGeneratedQueueItem:(HttpQueuedResponse *)queueItem
                       forState:(HttpConnectionState *)state
                     connection:(id<ATProtoNetworkConnection>)connection;
- (HttpResponse *)dispatchRequest:(HttpRequest *)request;
- (RequestHandler _Nullable)handlerForRoute:(NSString *)path
                                   method:(NSString *)method
                               parameters:(NSDictionary<NSString *, NSString *> *_Nullable *_Nullable)parameters;

@end

static const NSUInteger kHttpMaxHeaderBytes = 16 * 1024;
static const NSUInteger kHttpMaxBodyBytes = 50 * 1024 * 1024;
static const NSUInteger kHttpOutputQueueHighWaterMark =
    10 * 1024 * 1024; // 10MB
static const NSTimeInterval kHttpHeaderTimeout = 5.0;
static const NSUInteger kMaxConcurrentRequests = 64; // Limit concurrent threads
static const NSUInteger kHttpFileSendChunkSize = 64 * 1024;
static const NSUInteger kHttpGeneratedChunkSendSize = 64 * 1024;
static const NSUInteger kHttpGeneratedQueueBudget = 64 * 1024;

@implementation HttpQueuedResponse
@end

@implementation HttpConnectionState

- (instancetype)init {
  self = [super init];
  if (self) {
    _driver = [[HttpProtocolDriver alloc] init];
    _headerStartTime = [NSDate timeIntervalSinceReferenceDate];
    _outputQueue = [NSMutableArray array];
    _outputQueueSize = 0;
    _sendingActive = NO;
    _upgradedToWebSocket = NO;
  }
  return self;
}

- (void)dealloc {
#if !defined(__APPLE__)
  if (_transportQueue) {
    dispatch_release(_transportQueue);
    _transportQueue = NULL;
  }
#endif
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
- (instancetype)initWithHost:(NSString *_Nullable)host port:(NSUInteger)port {
  self = [super init];
  if (self) {
    _host = [host copy];
    _port = port;
    _serverQueue = dispatch_queue_create("com.atproto.pds.httpserver",
                                         DISPATCH_QUEUE_SERIAL);
    _routeTries = [NSMutableDictionary dictionary];
    _pathHandlers = [NSMutableDictionary dictionary];
    _activeConnections = [NSMutableSet set];
    _connectionQueue = dispatch_queue_create(
        "com.atproto.pds.httpserver.connections", DISPATCH_QUEUE_SERIAL);
    _readySemaphore = dispatch_semaphore_create(0);
    _stopSemaphore = dispatch_semaphore_create(0);
    _concurrencySemaphore = dispatch_semaphore_create(kMaxConcurrentRequests);
    _taskGroup = dispatch_group_create();
    _connectionStates = [NSMapTable strongToStrongObjectsMapTable];
    _webSocketUpgradeHandler = [[WebSocketUpgradeHandler alloc] init];
    _webSocketHandlers = [NSMutableDictionary dictionary];
    __weak typeof(self) weakSelf = self;
    _requestDispatcher = [[HttpRequestDispatcher alloc]
        initWithRouteLookupHandler:^HttpServerRequestHandler _Nullable(
            NSString *path, NSString *method,
            NSDictionary<NSString *, NSString *> *__autoreleasing _Nullable *_Nullable parameters) {
          __strong typeof(weakSelf) strongSelf = weakSelf;
          if (!strongSelf) {
            return nil;
          }
          return [strongSelf handlerForRoute:path method:method parameters:parameters];
        }];
    
    _responseSender = [[HttpResponseSender alloc] init];
    _listenerReady = NO;
    _startupFinished = NO;
    _running = NO;
  }
  return self;
}

- (BOOL)startWithError:(NSError *_Nullable *)error {
  if (self.running) {
    return YES;
  }

  if (self.host.length > 0) {
    self.listener =
        [ATProtoNetworkTransportFactory createListenerWithHost:self.host
                                                      port:self.port];
  } else {
    self.listener =
        [ATProtoNetworkTransportFactory createListenerWithPort:self.port];
  }

  if (!self.listener) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"com.atproto.pds.httpserver"
                     code:-1
                 userInfo:@{
                   NSLocalizedDescriptionKey : @"Failed to create listener"
                 }];
    }
    return NO;
  }

  __weak typeof(self) weakSelf = self;
  self.listener.stateChangedHandler =
      ^(ATProtoNetworkListenerState state, NSError *_Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf)
          return;

        switch (state) {
        case ATProtoNetworkListenerStateReady:
          strongSelf.listenerReady = YES;
          strongSelf.running = YES;
          strongSelf.port = strongSelf.listener.port;
          strongSelf.startupFinished = YES;
          GZ_LOG_HTTP_INFO(@"HTTPServer listening on port %lu",
                            (unsigned long)strongSelf.port);
          dispatch_semaphore_signal(strongSelf.readySemaphore);
          break;
        case ATProtoNetworkListenerStateFailed:
          strongSelf.listenerReady = NO;
          strongSelf.running = NO;
          strongSelf.startupFinished = YES;
          strongSelf.startupError = error;
          GZ_LOG_HTTP_ERROR(@"HTTPServer failed to start: %@", error);
          dispatch_semaphore_signal(strongSelf.readySemaphore);
          break;
        case ATProtoNetworkListenerStateCancelled:
          strongSelf.listenerReady = NO;
          strongSelf.running = NO;
          strongSelf.startupFinished = YES;
          GZ_LOG_HTTP_INFO(@"HTTPServer cancelled");
          dispatch_semaphore_signal(strongSelf.readySemaphore);
          dispatch_semaphore_signal(strongSelf.stopSemaphore);
          break;
        default:
          break;
        }
      };

  self.listener.newConnectionHandler = ^(id<ATProtoNetworkConnection> connection) {
    [weakSelf handleNewConnection:connection];
  };

  self.startupFinished = NO;
  self.running =
      YES; // Optimistically set running to YES so the main loop can start

  [self.listener startWithQueue:self.serverQueue];

  // Wait for READY state with 5s timeout
  dispatch_time_t timeout =
      dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC));
  if (dispatch_semaphore_wait(self.readySemaphore, timeout) != 0) {
    if (error) {
      *error = [NSError errorWithDomain:@"com.atproto.pds.httpserver"
                                   code:-2
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"Timed out waiting for server to start"
                               }];
    }
    return NO;
  }

  if (!self.listenerReady) {
    if (error) {
      NSMutableDictionary *userInfo =
          [NSMutableDictionary dictionaryWithObject:@"Server failed to start"
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

- (void)handleNewConnection:(id<ATProtoNetworkConnection>)connection {
  dispatch_async(_connectionQueue, ^{
    [self->_activeConnections addObject:connection];
    [[GZMetrics sharedMetrics] setActiveConnections:(NSInteger)self->_activeConnections.count];
  });

  HttpConnectionState *connectionState =
      [self connectionStateForConnection:connection];
  dispatch_queue_t transportQueue =
      connectionState.transportQueue ?: self.serverQueue;

  __weak typeof(self) weakSelf = self;
  __weak id<ATProtoNetworkConnection> weakConnection = connection;

  connection.stateChangedHandler =
      ^(ATProtoNetworkConnectionState state, NSError *_Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        __strong typeof(weakConnection) strongConnection = weakConnection;
        if (!strongSelf || !strongConnection)
          return;

        switch (state) {
        case ATProtoNetworkConnectionStateReady: {
          HttpConnectionState *connState = [strongSelf connectionStateForConnection:strongConnection];
          [connState.driver setRemoteAddressForRequests:strongConnection.remoteAddress];
          HttpConnectionIOCoordinator *coordinator = [[HttpConnectionIOCoordinator alloc]
              initWithConnection:strongConnection
                          protocol:connState.driver
                      responseSender:strongSelf.responseSender];
          __weak typeof(strongSelf) weakInnerSelf = strongSelf;
          __weak typeof(strongConnection) weakInnerConn = strongConnection;
          __weak HttpConnectionState *weakConnState = connState;
          __weak HttpConnectionIOCoordinator *weakCoord = coordinator;
          coordinator.requestReadyHandler = ^(HttpRequest *request) {
            __strong typeof(weakInnerSelf) s = weakInnerSelf;
            __strong typeof(weakInnerConn) c = weakInnerConn;
            if (!s || !c) return;
            [s dispatchRequest:request onConnection:c];
          };
          coordinator.upgradeHandler = ^(HttpRequest *request) {
            __strong typeof(weakInnerSelf) s = weakInnerSelf;
            __strong typeof(weakInnerConn) c = weakInnerConn;
            HttpConnectionState *cs = weakConnState;
            if (!s || !c || !cs) return;
            [s handleUpgradeEventForState:cs connection:c];
          };
          coordinator.errorHandler = ^(NSError *error) {
            __strong typeof(weakInnerSelf) s = weakInnerSelf;
            __strong typeof(weakInnerConn) c = weakInnerConn;
            HttpConnectionIOCoordinator *coord = weakCoord;
            if (!s || !c) return;
            [coord close];
            dispatch_async(s.connectionQueue, ^{
              [s.activeConnections removeObject:c];
              [s.connectionStates removeObjectForKey:c];
              [[GZMetrics sharedMetrics] setActiveConnections:(NSInteger)s.activeConnections.count];
            });
            HttpResponse *response = [HttpResponse responseWithStatusCode:error.code ?: 400];
            response.keepAlive = NO;
            [response setJsonBody:@{
              @"error": error.userInfo[@"errorCode"] ?: @"ProtocolError",
              @"message": error.localizedDescription ?: @"Protocol error"
            }];
            [s enqueueResponse:response forConnection:c];
          };
          coordinator.outputQueueSizeProvider = ^NSUInteger {
            HttpConnectionState *cs = weakConnState;
            return cs ? cs.outputQueueSize : 0;
          };
          connState.coordinator = coordinator;
          [coordinator start];
          break;
        }
        case ATProtoNetworkConnectionStateFailed: {
          dispatch_async(strongSelf.connectionQueue, ^{
            [strongSelf.activeConnections removeObject:strongConnection];
            [strongSelf.connectionStates removeObjectForKey:strongConnection];
            [[GZMetrics sharedMetrics] setActiveConnections:(NSInteger)strongSelf.activeConnections.count];
          });
          [strongConnection cancel];
          break;
        }
        case ATProtoNetworkConnectionStateCancelled: {
          dispatch_async(strongSelf.connectionQueue, ^{
            [strongSelf.activeConnections removeObject:strongConnection];
            [strongSelf.connectionStates removeObjectForKey:strongConnection];
            [[GZMetrics sharedMetrics] setActiveConnections:(NSInteger)strongSelf.activeConnections.count];
          });
          break;
        }
        default:
          break;
        }
      };

  [connection startWithQueue:transportQueue];
}

- (void)handleUpgradeEventForState:(HttpConnectionState *)state
                         connection:(id<ATProtoNetworkConnection>)connection {
  HttpRequest *request = [state.driver currentUpgradeRequest];
  if (!request) return;

  NSString *path = request.path;
  GZ_LOG_HTTP_DEBUG(@"Attempting WebSocket upgrade for path: %@", path);
  WebSocketRequestHandler webSocketHandler = self.webSocketHandlers[path];
  
  if (webSocketHandler) {

    HttpResponse *upgradeResponse = [HttpResponse response];
    BOOL shouldUpgrade = [self.webSocketUpgradeHandler handleUpgradeRequest:request
                                                                  response:upgradeResponse];
    if (!shouldUpgrade) {
      [self enqueueResponse:upgradeResponse forConnection:connection];
      return;
    }

    state.upgradedToWebSocket = YES;
    state.driver.session.upgradedToWebSocket = YES;
    [state.outputQueue removeAllObjects];
    state.outputQueueSize = 0;

    HttpConnectionIOCoordinator *priorCoordinator = state.coordinator;
    NSData *responseData = [upgradeResponse serialize];
    [connection sendData:responseData
              completion:^(NSError *_Nullable error) {
                if (error) {
                  [priorCoordinator close];
                  [connection cancel];
                  return;
                }
                [priorCoordinator closeForUpgrade];
                webSocketHandler(request, upgradeResponse, connection);
              }];
  }
}


- (HttpConnectionState *)connectionStateForConnection:
    (id<ATProtoNetworkConnection>)connection {
  __block HttpConnectionState *state = nil;
  dispatch_sync(self.connectionQueue, ^{
    state = [self.connectionStates objectForKey:connection];
    if (!state) {
      state = [[HttpConnectionState alloc] init];
      [self.connectionStates setObject:state forKey:connection];
    }
    if (!state.transportQueue) {
      NSString *queueLabel = [NSString
          stringWithFormat:@"com.atproto.pds.httpserver.connection.%p",
                           connection];
      state.transportQueue =
          dispatch_queue_create([queueLabel UTF8String], DISPATCH_QUEUE_SERIAL);
    }
  });
  return state;
}

- (void)dispatchRequest:(HttpRequest *)request
           onConnection:(id<ATProtoNetworkConnection>)connection {
  __weak typeof(self) weakSelf = self;
  __weak id<ATProtoNetworkConnection> weakConnection = connection;
  HttpRequest *requestRef = request;

  // Capture dispatch objects as strong locals so they survive into the block.
  // On Linux, dispatch_queue/semaphore/group properties are 'assign' (not
  // ARC-managed), so we must retain them explicitly to prevent use-after-free.
  dispatch_semaphore_t semaphore = self.concurrencySemaphore;
  dispatch_group_t group = self.taskGroup;
  dispatch_queue_t serverQ = self.serverQueue;
#ifndef __APPLE__
  dispatch_retain(semaphore);
  dispatch_retain(group);
  dispatch_retain(serverQ);
#endif

  dispatch_group_enter(group);

  // Wait for semaphore to limit concurrency
  dispatch_async(
      dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 600 * NSEC_PER_SEC));

        __strong typeof(weakSelf) strongSelf = weakSelf;
        __strong typeof(weakConnection) strongConnection = weakConnection;
        if (!strongSelf || !strongConnection) {
          dispatch_semaphore_signal(semaphore);
          dispatch_group_leave(group);
#ifndef __APPLE__
          dispatch_release(semaphore);
          dispatch_release(group);
          dispatch_release(serverQ);
#endif
          return;
        }

        HttpConnectionState *state = [strongSelf connectionStateForConnection:strongConnection];
        if (state.upgradedToWebSocket) {
          dispatch_semaphore_signal(semaphore);
          dispatch_group_leave(group);
#ifndef __APPLE__
          dispatch_release(semaphore);
          dispatch_release(group);
          dispatch_release(serverQ);
#endif
          return;
        }

        [[GZLogger sharedLogger] setCorrelationID:requestRef.correlationID];

        NSString *logPath =
            requestRef.queryString.length > 0
                ? [NSString stringWithFormat:@"%@?%@", requestRef.path,
                                             requestRef.queryString]
                : requestRef.path;
        GZ_LOG_HTTP_INFO(@"Starting dispatch for [%@] %@ %@",
                          requestRef.remoteAddress, requestRef.methodString,
                          logPath);
        NSTimeInterval requestStart = [NSDate timeIntervalSinceReferenceDate];
        HttpResponse *response = [strongSelf dispatchRequest:requestRef];
        NSString *connectionHeader =
            [[requestRef headerForKey:@"Connection"] lowercaseString];
        if ([connectionHeader isEqualToString:@"close"] ||
            [requestRef.version isEqualToString:@"HTTP/1.0"]) {
          response.keepAlive = NO;
        }
        NSTimeInterval latency = [NSDate timeIntervalSinceReferenceDate] - requestStart;
        [[GZMetrics sharedMetrics] incrementHttpRequestsForMethod:requestRef.methodString
                                                          endpoint:requestRef.path
                                                            status:response.statusCode];
        [[GZMetrics sharedMetrics] observeRequestLatency:latency
                                                   method:requestRef.methodString
                                                 endpoint:requestRef.path
                                                   status:response.statusCode];
        GZ_LOG_HTTP_INFO(@"Finished dispatch for [%@] %@ %@, status %ld",
                          requestRef.remoteAddress, requestRef.methodString,
                          logPath, (long)response.statusCode);

        dispatch_async(serverQ, ^{
          [strongSelf enqueueResponse:response forConnection:strongConnection];
          dispatch_semaphore_signal(semaphore);
          dispatch_group_leave(group);
#ifndef __APPLE__
          dispatch_release(semaphore);
          dispatch_release(group);
          dispatch_release(serverQ);
#endif
        });

        [[GZLogger sharedLogger] clearCorrelationID];
      });
}

- (void)enqueueResponse:(HttpResponse *)response
          forConnection:(id<ATProtoNetworkConnection>)connection {
  HttpConnectionState *state = [self connectionStateForConnection:connection];
  HttpQueuedResponse *queueItem = [self queueItemForResponse:response];

  [state.outputQueue addObject:queueItem];
  state.outputQueueSize += queueItem.queueByteSize;

  while ([self.responseSender shouldTrimQueueWithCurrentSize:state.outputQueueSize
                                               highWaterMark:kHttpOutputQueueHighWaterMark] &&
         state.outputQueue.count > 0) {
    HttpQueuedResponse *oldest = state.outputQueue[0];
    state.outputQueueSize -= oldest.queueByteSize;
    if (oldest.deleteBodyFileAfterSend && oldest.bodyFilePath.length > 0) {
      [[NSFileManager defaultManager] removeItemAtPath:oldest.bodyFilePath
                                                 error:nil];
    }
    [state.outputQueue removeObjectAtIndex:0];
  }

  [self sendNextQueuedResponseForState:state connection:connection];
}

- (void)sendNextQueuedResponseForState:(HttpConnectionState *)state
                            connection:(id<ATProtoNetworkConnection>)connection {
  if (state.outputQueue.count == 0 || state.sendingActive) {
    return;
  }

  state.sendingActive = YES;
  HttpQueuedResponse *queueItem = state.outputQueue[0];

  __weak typeof(self) weakSelf = self;
  [connection
        sendData:queueItem.headerData
      completion:^(NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf)
          return;

        if (error) {
          GZ_LOG_HTTP_ERROR(@"Failed to send pipelined response: %@", error);
          if (queueItem.deleteBodyFileAfterSend &&
              queueItem.bodyFilePath.length > 0) {
            [[NSFileManager defaultManager]
                removeItemAtPath:queueItem.bodyFilePath
                           error:nil];
          }
          [connection cancel];
          return;
        }

        if (queueItem.bodyFilePath.length > 0) {
          [strongSelf streamFileQueueItem:queueItem
                                 forState:state
                               connection:connection];
          return;
        }
        if (queueItem.bodyChunkProducer) {
          [strongSelf streamGeneratedQueueItem:queueItem
                                      forState:state
                                    connection:connection];
          return;
        }
        [strongSelf finalizeQueuedResponseSend:queueItem
                                       forState:state
                                     connection:connection];
      }];
}

- (HttpQueuedResponse *)queueItemForResponse:(HttpResponse *)response {
  HttpQueuedResponse *queueItem = [[HttpQueuedResponse alloc] init];
  NSString *bodyFilePath = response.bodyFilePath;
  if (bodyFilePath.length > 0) {
    NSDictionary *attributes =
        [[NSFileManager defaultManager] attributesOfItemAtPath:bodyFilePath
                                                         error:nil];
    NSNumber *fileSize = attributes[NSFileSize];
    NSUInteger bodyLength =
        fileSize ? (NSUInteger)fileSize.unsignedLongLongValue : 0;
    if (response.isRangeRequest) {
      queueItem.isRangeRequest = YES;
      queueItem.rangeStart = response.rangeStart;
      queueItem.rangeLength = response.rangeLength;
      queueItem.headerData = [response serializeHeadersForBodyLength:response.rangeLength];
    } else {
      queueItem.headerData = [response serializeHeadersForBodyLength:bodyLength];
    }
    queueItem.bodyFilePath = bodyFilePath;
    queueItem.deleteBodyFileAfterSend = response.deleteBodyFileAfterSend;
    queueItem.closeAfterSend = !response.keepAlive;
    queueItem.queueByteSize = queueItem.headerData.length;
    return queueItem;
  }

  if (response.bodyChunkProducer) {
    if (!response.chunkedTransferEncoding) {
      response.chunkedTransferEncoding = YES;
    }
    queueItem.headerData = [response serializeHeadersForBodyLength:0];
    queueItem.bodyChunkProducer = [response.bodyChunkProducer copy];
    queueItem.chunkedTransferEncoding = response.chunkedTransferEncoding;
    queueItem.closeAfterSend = !response.keepAlive;
    queueItem.queueByteSize =
        queueItem.headerData.length + kHttpGeneratedQueueBudget;
    return queueItem;
  }

  NSData *serialized = [response serialize];
  queueItem.headerData = serialized;
  queueItem.closeAfterSend = !response.keepAlive;
  queueItem.queueByteSize = serialized.length;
  return queueItem;
}

- (void)finalizeQueuedResponseSend:(HttpQueuedResponse *)queueItem
                           forState:(HttpConnectionState *)state
                         connection:(id<ATProtoNetworkConnection>)connection {
  if (state.outputQueue.count > 0) {
    [state.outputQueue removeObjectAtIndex:0];
  }
  state.outputQueueSize =
      [self.responseSender clampedQueueSizeAfterDequeue:state.outputQueueSize
                                              itemBytes:queueItem.queueByteSize];
  state.sendingActive = NO;
  [state.driver responseDidFinishSending];
  if (queueItem.closeAfterSend) {
    [connection cancel];
    return;
  }
  [self sendNextQueuedResponseForState:state connection:connection];
  
  // Continue connection if idle and not upgraded to WebSocket
  if (state.outputQueue.count == 0 && !state.upgradedToWebSocket) {
    // The coordinator handles all read scheduling for new connections.
  }
}

- (void)streamFileQueueItem:(HttpQueuedResponse *)queueItem
                   forState:(HttpConnectionState *)state
                 connection:(id<ATProtoNetworkConnection>)connection {
  NSFileHandle *fileHandle =
      [NSFileHandle fileHandleForReadingAtPath:queueItem.bodyFilePath];
  if (!fileHandle) {
    GZ_LOG_HTTP_ERROR(@"Failed to open response body file at path %@",
                       queueItem.bodyFilePath);
    if (queueItem.deleteBodyFileAfterSend &&
        queueItem.bodyFilePath.length > 0) {
      [[NSFileManager defaultManager] removeItemAtPath:queueItem.bodyFilePath
                                                 error:nil];
    }
    [connection cancel];
    return;
  }

  __block NSUInteger remainingBytes = queueItem.isRangeRequest ? queueItem.rangeLength : NSUIntegerMax;
  if (queueItem.isRangeRequest) {
    @try {
      [fileHandle seekToFileOffset:queueItem.rangeStart];
    } @catch (__unused NSException *exception) {
      GZ_LOG_HTTP_ERROR(@"Seek failed on file path %@", queueItem.bodyFilePath);
      @try {
        [fileHandle closeFile];
      } @catch (__unused NSException *e) {
      }
      if (queueItem.deleteBodyFileAfterSend &&
          queueItem.bodyFilePath.length > 0) {
        [[NSFileManager defaultManager] removeItemAtPath:queueItem.bodyFilePath
                                                   error:nil];
      }
      [connection cancel];
      return;
    }
  }

  __weak typeof(self) weakSelf = self;
  __block void (^sendNextChunk)(void) = nil;
  sendNextChunk = ^{
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) {
      @try {
        [fileHandle closeFile];
      } @catch (__unused NSException *exception) {
      }
      sendNextChunk = nil;
      return;
    }

    @autoreleasepool {
      NSUInteger chunkToRead = kHttpFileSendChunkSize;
      if (queueItem.isRangeRequest) {
        if (remainingBytes == 0) {
          @try {
            [fileHandle closeFile];
          } @catch (__unused NSException *exception) {
          }
          [strongSelf finalizeQueuedResponseSend:queueItem
                                         forState:state
                                       connection:connection];
          sendNextChunk = nil;
          return;
        }
        chunkToRead = MIN(kHttpFileSendChunkSize, remainingBytes);
      }

      NSData *chunk = [fileHandle readDataOfLength:chunkToRead];
      if (chunk.length == 0) {
        @try {
          [fileHandle closeFile];
        } @catch (__unused NSException *exception) {
        }
        [strongSelf finalizeQueuedResponseSend:queueItem
                                       forState:state
                                     connection:connection];
        sendNextChunk = nil;
        return;
      }

      if (queueItem.isRangeRequest) {
        remainingBytes -= chunk.length;
      }

      [connection sendData:chunk
                completion:^(NSError *error) {
                  if (error) {
                    GZ_LOG_HTTP_ERROR(
                        @"Failed to stream response body file: %@", error);
                    @try {
                      [fileHandle closeFile];
                    } @catch (__unused NSException *exception) {
                    }
                    if (queueItem.deleteBodyFileAfterSend &&
                        queueItem.bodyFilePath.length > 0) {
                      [[NSFileManager defaultManager]
                          removeItemAtPath:queueItem.bodyFilePath
                                     error:nil];
                    }
                    [connection cancel];
                    sendNextChunk = nil;
                    return;
                  }
                  if (sendNextChunk) {
                    sendNextChunk();
                  }
                }];
    }
  };

  sendNextChunk();
}

- (void)streamGeneratedQueueItem:(HttpQueuedResponse *)queueItem
                         forState:(HttpConnectionState *)state
                       connection:(id<ATProtoNetworkConnection>)connection {
  __weak typeof(self) weakSelf = self;
  __block void (^sendNextChunk)(void) = nil;
  sendNextChunk = ^{
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) {
      sendNextChunk = nil;
      return;
    }

    @autoreleasepool {
      NSData *payloadChunk = nil;
      NSData *pendingChunk = queueItem.pendingGeneratedChunk;
      if (pendingChunk.length > 0 &&
          queueItem.pendingGeneratedChunkOffset < pendingChunk.length) {
        NSUInteger remaining =
            pendingChunk.length - queueItem.pendingGeneratedChunkOffset;
        NSUInteger sendLength = MIN(remaining, kHttpGeneratedChunkSendSize);
        payloadChunk = [pendingChunk
            subdataWithRange:NSMakeRange(queueItem.pendingGeneratedChunkOffset,
                                         sendLength)];
        queueItem.pendingGeneratedChunkOffset += sendLength;
        if (queueItem.pendingGeneratedChunkOffset >= pendingChunk.length) {
          queueItem.pendingGeneratedChunk = nil;
          queueItem.pendingGeneratedChunkOffset = 0;
        }
      } else {
        NSError *produceError = nil;
        NSData *producedChunk = queueItem.bodyChunkProducer
                                    ? queueItem.bodyChunkProducer(&produceError)
                                    : nil;
        if (produceError) {
          GZ_LOG_HTTP_ERROR(@"Failed to produce response body chunk: %@",
                             produceError);
          [connection cancel];
          sendNextChunk = nil;
          return;
        }

        if (producedChunk.length == 0) {
          if (queueItem.chunkedTransferEncoding) {
            NSData *terminator =
                [@"0\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding];
            [connection
                  sendData:terminator
                completion:^(NSError *error) {
                  if (error) {
                    GZ_LOG_HTTP_ERROR(
                        @"Failed to stream chunked terminator: %@", error);
                    [connection cancel];
                    sendNextChunk = nil;
                    return;
                  }
                  [strongSelf finalizeQueuedResponseSend:queueItem
                                                forState:state
                                              connection:connection];
                  sendNextChunk = nil;
                }];
            return;
          }

          [strongSelf finalizeQueuedResponseSend:queueItem
                                        forState:state
                                      connection:connection];
          sendNextChunk = nil;
          return;
        }

        if (producedChunk.length > kHttpGeneratedChunkSendSize) {
          queueItem.pendingGeneratedChunk = producedChunk;
          queueItem.pendingGeneratedChunkOffset = kHttpGeneratedChunkSendSize;
          payloadChunk = [producedChunk
              subdataWithRange:NSMakeRange(0, kHttpGeneratedChunkSendSize)];
        } else {
          payloadChunk = producedChunk;
        }
      }

      NSData *wireChunk = payloadChunk;
      if (queueItem.chunkedTransferEncoding) {
        NSString *sizeLine = [NSString
            stringWithFormat:@"%lx\r\n", (unsigned long)payloadChunk.length];
        NSMutableData *encoded = [NSMutableData
            dataWithCapacity:sizeLine.length + payloadChunk.length + 2];
        [encoded appendData:[sizeLine dataUsingEncoding:NSUTF8StringEncoding]];
        [encoded appendData:payloadChunk];
        [encoded appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
        wireChunk = [encoded copy];
      }

      [connection sendData:wireChunk
                completion:^(NSError *error) {
                  if (error) {
                    GZ_LOG_HTTP_ERROR(
                        @"Failed to stream generated response body: %@", error);
                    [connection cancel];
                    sendNextChunk = nil;
                    return;
                  }
                  if (sendNextChunk) {
                    sendNextChunk();
                  }
                }];
    }
  };

  sendNextChunk();
}

static BOOL ParseHttpRangeHeader(NSString *rangeHeader, NSUInteger fileSize, NSUInteger *outStart, NSUInteger *outLength) {
    if (!rangeHeader || ![rangeHeader hasPrefix:@"bytes="]) {
        return NO;
    }
    
    NSString *bytesSpecifier = [rangeHeader substringFromIndex:6];
    NSArray *ranges = [bytesSpecifier componentsSeparatedByString:@","];
    if (ranges.count != 1) {
        // Multi-range is not supported for simplicity
        return NO;
    }
    
    NSString *rangeStr = [ranges[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSRange dashRange = [rangeStr rangeOfString:@"-"];
    if (dashRange.location == NSNotFound) {
        return NO;
    }
    
    NSString *startStr = [rangeStr substringToIndex:dashRange.location];
    NSString *endStr = [rangeStr substringFromIndex:dashRange.location + 1];
    
    NSInteger start = -1;
    NSInteger end = -1;
    
    if (startStr.length > 0) {
        start = (NSInteger)startStr.longLongValue;
    }
    if (endStr.length > 0) {
        end = (NSInteger)endStr.longLongValue;
    }
    
    if (start < 0 && end < 0) {
        return NO;
    }
    
    NSUInteger finalStart = 0;
    NSUInteger finalEnd = 0;
    
    if (start >= 0) {
        finalStart = (NSUInteger)start;
        if (end >= 0) {
            finalEnd = MIN((NSUInteger)end, fileSize - 1);
        } else {
            finalEnd = fileSize - 1;
        }
    } else {
        // suffix-byte-range-spec: e.g. -500 (last 500 bytes)
        NSUInteger suffix = (NSUInteger)end;
        if (suffix >= fileSize) {
            finalStart = 0;
        } else {
            finalStart = fileSize - suffix;
        }
        finalEnd = fileSize - 1;
    }
    
    if (finalStart >= fileSize) {
        return NO;
    }
    
    if (finalStart > finalEnd) {
        return NO;
    }
    
    *outStart = finalStart;
    *outLength = finalEnd - finalStart + 1;
    return YES;
}

- (HttpResponse *)dispatchRequest:(HttpRequest *)request {
  self.requestDispatcher.requestHandler = self.requestHandler;
  HttpResponse *response = [self.requestDispatcher dispatchRequest:request];
  
  if (response.statusCode == HttpStatusOK && response.bodyFilePath.length > 0) {
      NSString *rangeHeader = [request headerForKey:@"Range"];
      if (rangeHeader) {
          NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:response.bodyFilePath error:nil];
          NSNumber *fileSizeAttr = attributes[NSFileSize];
          if (fileSizeAttr) {
              NSUInteger fileSize = fileSizeAttr.unsignedLongLongValue;
              NSUInteger start = 0;
              NSUInteger length = 0;
              if (ParseHttpRangeHeader(rangeHeader, fileSize, &start, &length)) {
                  response.isRangeRequest = YES;
                  response.rangeStart = start;
                  response.rangeLength = length;
                  response.statusCode = HttpStatusPartialContent;
                  
                  // Set Content-Range header
                  NSString *contentRange = [NSString stringWithFormat:@"bytes %lu-%lu/%lu", 
                                            (unsigned long)start, 
                                            (unsigned long)(start + length - 1), 
                                            (unsigned long)fileSize];
                  [response setHeader:contentRange forKey:@"Content-Range"];
              }
          }
      }
  }
  
  return response;
}

- (void)stop {
  self.running = NO;
  if (self.listener) {
    [self.listener cancel];

    // Wait for CANCELLED state with 2s timeout
    dispatch_time_t timeout =
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC));
    dispatch_semaphore_wait(self.stopSemaphore, timeout);

    self.listener = nil;
  }

  // Wait for all active tasks to complete
  dispatch_group_wait(self.taskGroup, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC));

  dispatch_sync(_connectionQueue, ^{
    for (id<ATProtoNetworkConnection> conn in self->_activeConnections) {
      [conn cancel];
    }
    [self->_activeConnections removeAllObjects];
    [self.connectionStates removeAllObjects];
  });
}

- (void)addRoute:(NSString *)method
            path:(NSString *)path
         handler:(RequestHandler)handler {
  if (!method || !path || !handler) {
    return;
  }
  NSString *normalizedMethod =
      [method.uppercaseString length] ? method.uppercaseString : @"*";
  HttpRouteTrie *trie = self.routeTries[normalizedMethod];
  if (!trie) {
    trie = [[HttpRouteTrie alloc] init];
    self.routeTries[normalizedMethod] = trie;
  }
  [trie insertRoute:normalizedMethod
            pattern:path
            handler:[handler copy]
           priority:100];
}

- (void)addHandlerForPath:(NSString *)path handler:(RequestHandler)handler {
  if (!path || !handler) {
    return;
  }
  // Register for all methods via the trie
  [self addRoute:@"*" path:path handler:handler];

  // Also register as a prefix route to support legacy prefix-matching behavior
  NSString *prefixPath = [path hasSuffix:@"/"] ? [path stringByAppendingString:@"*"]
                                               : [path stringByAppendingString:@"/*"];
  [self addRoute:@"*" path:prefixPath handler:handler];
}

- (RequestHandler _Nullable)handlerForRoute:(NSString *)path
                                     method:(NSString *)method
                                 parameters:(NSDictionary<NSString *, NSString *> *_Nullable *_Nullable)parameters {
  HttpRouteTrie *trie = self.routeTries[method.uppercaseString];
  RequestHandler handler = nil;
  if (trie) {
    handler = [trie handlerForMethod:method path:path outParameters:parameters];
  }
  if (!handler) {
    trie = self.routeTries[@"*"];
    if (trie) {
      handler = [trie handlerForMethod:method path:path outParameters:parameters];
    }
  }
  return handler;
}

- (void)sendResponse:(HttpResponse *)response onConnection:(id<ATProtoNetworkConnection>)connection {
  [self enqueueResponse:response forConnection:connection];
}

- (void)addWebSocketRoute:(NSString *)path
                  handler:(WebSocketRequestHandler)handler {
  if (!path || !handler) {
    return;
  }
  self.webSocketHandlers[path] = [handler copy];
}

@end
