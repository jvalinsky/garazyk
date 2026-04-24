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
#import "Debug/PDSLogger.h"
#import "Metrics/PDSMetrics.h"
#import "Network/HttpBufferPool.h"
#import "Network/HttpParsing.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpRouteTrie.h"
#import "Network/PDSNetworkTransport.h"
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
@property(nonatomic, strong, nullable) NSData *pendingGeneratedChunk;
@property(nonatomic, assign) NSUInteger pendingGeneratedChunkOffset;
@property(nonatomic, assign) NSUInteger queueByteSize;
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
@property(nonatomic, strong) id<PDSNetworkListener> listener;
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
    NSMutableSet<id<PDSNetworkConnection>> *activeConnections;
@property(nonatomic, PDS_DISPATCH_QUEUE_STRONG)
    dispatch_queue_t connectionQueue;
@property(nonatomic, strong)
    NSMapTable<id<PDSNetworkConnection>, id> *connectionStates;

@property(nonatomic, PDS_DISPATCH_QUEUE_STRONG)
    dispatch_semaphore_t concurrencySemaphore;
@property(nonatomic, strong) WebSocketUpgradeHandler *webSocketUpgradeHandler;
@property(nonatomic, strong)
    NSMutableDictionary<NSString *, WebSocketRequestHandler> *webSocketHandlers;
@property(nonatomic, strong) HttpRequestDispatcher *requestDispatcher;
@property(nonatomic, strong) HttpResponseSender *responseSender;

- (HttpQueuedResponse *)queueItemForResponse:(HttpResponse *)response;
- (void)enqueueResponse:(HttpResponse *)response
           forConnection:(id<PDSNetworkConnection>)connection;
- (void)sendNextQueuedResponseForState:(HttpConnectionState *)state
                             connection:(id<PDSNetworkConnection>)connection;
- (void)finalizeQueuedResponseSend:(HttpQueuedResponse *)queueItem
                          forState:(HttpConnectionState *)state
                        connection:(id<PDSNetworkConnection>)connection;
- (void)streamFileQueueItem:(HttpQueuedResponse *)queueItem
                 forState:(HttpConnectionState *)state
               connection:(id<PDSNetworkConnection>)connection;
- (void)streamGeneratedQueueItem:(HttpQueuedResponse *)queueItem
                       forState:(HttpConnectionState *)state
                     connection:(id<PDSNetworkConnection>)connection;
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
        [PDSNetworkTransportFactory createListenerWithHost:self.host
                                                      port:self.port];
  } else {
    self.listener =
        [PDSNetworkTransportFactory createListenerWithPort:self.port];
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
      ^(PDSNetworkListenerState state, NSError *_Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf)
          return;

        switch (state) {
        case PDSNetworkListenerStateReady:
          strongSelf.listenerReady = YES;
          strongSelf.running = YES;
          strongSelf.port = strongSelf.listener.port;
          strongSelf.startupFinished = YES;
          PDS_LOG_HTTP_INFO(@"HTTPServer listening on port %lu",
                            (unsigned long)strongSelf.port);
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

- (void)handleNewConnection:(id<PDSNetworkConnection>)connection {
  dispatch_async(_connectionQueue, ^{
    [self->_activeConnections addObject:connection];
    [[PDSMetrics sharedMetrics] setActiveConnections:(NSInteger)self->_activeConnections.count];
  });

  HttpConnectionState *connectionState =
      [self connectionStateForConnection:connection];
  dispatch_queue_t transportQueue =
      connectionState.transportQueue ?: self.serverQueue;

  __weak typeof(self) weakSelf = self;
  __weak id<PDSNetworkConnection> weakConnection = connection;

  connection.stateChangedHandler =
      ^(PDSNetworkConnectionState state, NSError *_Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        __strong typeof(weakConnection) strongConnection = weakConnection;
        if (!strongSelf || !strongConnection)
          return;

        switch (state) {
        case PDSNetworkConnectionStateReady: {
          HttpConnectionState *connState = [strongSelf connectionStateForConnection:strongConnection];
          [connState.driver setRemoteAddressForRequests:strongConnection.remoteAddress];
          HttpConnectionIOCoordinator *coordinator = [[HttpConnectionIOCoordinator alloc]
              initWithConnection:strongConnection
                          protocol:connState.driver
                      responseSender:strongSelf.responseSender];
          coordinator.requestReadyHandler = ^(HttpRequest *request) {
            [strongSelf dispatchRequest:request onConnection:strongConnection];
          };
          coordinator.upgradeHandler = ^(HttpRequest *request) {
            [strongSelf handleUpgradeEventForState:connState
                                       connection:strongConnection];
          };
          coordinator.errorHandler = ^(NSError *error) {
            dispatch_async(strongSelf.connectionQueue, ^{
              [strongSelf.activeConnections removeObject:strongConnection];
              [strongSelf.connectionStates removeObjectForKey:strongConnection];
              [[PDSMetrics sharedMetrics] setActiveConnections:(NSInteger)strongSelf.activeConnections.count];
            });
            HttpConnectionState *state = [strongSelf connectionStateForConnection:strongConnection];
            HttpResponse *response = [HttpResponse responseWithStatusCode:error.code ?: 400];
            response.keepAlive = NO;
            [response setJsonBody:@{
              @"error": error.userInfo[@"errorCode"] ?: @"ProtocolError",
              @"message": error.localizedDescription ?: @"Protocol error"
            }];
            [strongSelf enqueueResponse:response forConnection:strongConnection];
          };
          coordinator.outputQueueSizeProvider = ^NSUInteger {
            return connState.outputQueueSize;
          };
          connState.coordinator = coordinator;
          [coordinator start];
          break;
        }
        case PDSNetworkConnectionStateFailed: {
          dispatch_async(strongSelf.connectionQueue, ^{
            [strongSelf.activeConnections removeObject:strongConnection];
            [strongSelf.connectionStates removeObjectForKey:strongConnection];
            [[PDSMetrics sharedMetrics] setActiveConnections:(NSInteger)strongSelf.activeConnections.count];
          });
          [strongConnection cancel];
          break;
        }
        case PDSNetworkConnectionStateCancelled: {
          dispatch_async(strongSelf.connectionQueue, ^{
            [strongSelf.activeConnections removeObject:strongConnection];
            [strongSelf.connectionStates removeObjectForKey:strongConnection];
            [[PDSMetrics sharedMetrics] setActiveConnections:(NSInteger)strongSelf.activeConnections.count];
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
                         connection:(id<PDSNetworkConnection>)connection {
  HttpRequest *request = [state.driver currentUpgradeRequest];
  if (!request) return;

  NSString *path = request.path;
  PDS_LOG_HTTP_DEBUG(@"Attempting WebSocket upgrade for path: %@", path);
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
    [state.outputQueue removeAllObjects];
    state.outputQueueSize = 0;

    NSData *responseData = [upgradeResponse serialize];
    [connection sendData:responseData
              completion:^(NSError *_Nullable error) {
                if (error) {
                  [connection cancel];
                  return;
                }
                webSocketHandler(request, upgradeResponse, connection);
              }];
  }
}


- (HttpConnectionState *)connectionStateForConnection:
    (id<PDSNetworkConnection>)connection {
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
           onConnection:(id<PDSNetworkConnection>)connection {
  __weak typeof(self) weakSelf = self;
  __weak id<PDSNetworkConnection> weakConnection = connection;
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
        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

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

        [[PDSLogger sharedLogger] setCorrelationID:requestRef.correlationID];

        NSString *logPath =
            requestRef.queryString.length > 0
                ? [NSString stringWithFormat:@"%@?%@", requestRef.path,
                                             requestRef.queryString]
                : requestRef.path;
        PDS_LOG_HTTP_INFO(@"Starting dispatch for [%@] %@ %@",
                          requestRef.remoteAddress, requestRef.methodString,
                          logPath);
        NSTimeInterval requestStart = [NSDate timeIntervalSinceReferenceDate];
        HttpResponse *response = [strongSelf dispatchRequest:requestRef];
        NSTimeInterval latency = [NSDate timeIntervalSinceReferenceDate] - requestStart;
        [[PDSMetrics sharedMetrics] incrementHttpRequestsForMethod:requestRef.methodString
                                                          endpoint:requestRef.path
                                                            status:response.statusCode];
        [[PDSMetrics sharedMetrics] observeRequestLatency:latency
                                                   method:requestRef.methodString
                                                 endpoint:requestRef.path
                                                   status:response.statusCode];
        PDS_LOG_HTTP_INFO(@"Finished dispatch for [%@] %@ %@, status %ld",
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

        [[PDSLogger sharedLogger] clearCorrelationID];
      });
}

- (void)enqueueResponse:(HttpResponse *)response
          forConnection:(id<PDSNetworkConnection>)connection {
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
                            connection:(id<PDSNetworkConnection>)connection {
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
          PDS_LOG_HTTP_ERROR(@"Failed to send pipelined response: %@", error);
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
    queueItem.headerData = [response serializeHeadersForBodyLength:bodyLength];
    queueItem.bodyFilePath = bodyFilePath;
    queueItem.deleteBodyFileAfterSend = response.deleteBodyFileAfterSend;
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
    queueItem.queueByteSize =
        queueItem.headerData.length + kHttpGeneratedQueueBudget;
    return queueItem;
  }

  NSData *serialized = [response serialize];
  queueItem.headerData = serialized;
  queueItem.queueByteSize = serialized.length;
  return queueItem;
}

- (void)finalizeQueuedResponseSend:(HttpQueuedResponse *)queueItem
                           forState:(HttpConnectionState *)state
                         connection:(id<PDSNetworkConnection>)connection {
  if (state.outputQueue.count > 0) {
    [state.outputQueue removeObjectAtIndex:0];
  }
  state.outputQueueSize =
      [self.responseSender clampedQueueSizeAfterDequeue:state.outputQueueSize
                                              itemBytes:queueItem.queueByteSize];
  state.sendingActive = NO;
  [self sendNextQueuedResponseForState:state connection:connection];
  
  // Continue connection if idle and not upgraded to WebSocket
  if (state.outputQueue.count == 0 && !state.upgradedToWebSocket) {
    [self continueReadingForConnection:connection state:state];
  }
}

- (void)continueReadingForConnection:(id<PDSNetworkConnection>)connection
                                state:(HttpConnectionState *)state {
  // The coordinator now handles all read scheduling for new connections.
  // This method is kept for backward compatibility but is a no-op.
  if (state.coordinator) {
    return;
  }
}

- (void)streamFileQueueItem:(HttpQueuedResponse *)queueItem
                   forState:(HttpConnectionState *)state
                 connection:(id<PDSNetworkConnection>)connection {
  NSFileHandle *fileHandle =
      [NSFileHandle fileHandleForReadingAtPath:queueItem.bodyFilePath];
  if (!fileHandle) {
    PDS_LOG_HTTP_ERROR(@"Failed to open response body file at path %@",
                       queueItem.bodyFilePath);
    if (queueItem.deleteBodyFileAfterSend &&
        queueItem.bodyFilePath.length > 0) {
      [[NSFileManager defaultManager] removeItemAtPath:queueItem.bodyFilePath
                                                 error:nil];
    }
    [connection cancel];
    return;
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
      NSData *chunk = [fileHandle readDataOfLength:kHttpFileSendChunkSize];
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

      [connection sendData:chunk
                completion:^(NSError *error) {
                  if (error) {
                    PDS_LOG_HTTP_ERROR(
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
                       connection:(id<PDSNetworkConnection>)connection {
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
          PDS_LOG_HTTP_ERROR(@"Failed to produce response body chunk: %@",
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
                    PDS_LOG_HTTP_ERROR(
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
                    PDS_LOG_HTTP_ERROR(
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

- (HttpResponse *)dispatchRequest:(HttpRequest *)request {
  self.requestDispatcher.requestHandler = self.requestHandler;
  return [self.requestDispatcher dispatchRequest:request];
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
  dispatch_group_wait(self.taskGroup, DISPATCH_TIME_FOREVER);

  dispatch_sync(_connectionQueue, ^{
    for (id<PDSNetworkConnection> conn in self->_activeConnections) {
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

- (void)sendResponse:(HttpResponse *)response onConnection:(id<PDSNetworkConnection>)connection {
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
