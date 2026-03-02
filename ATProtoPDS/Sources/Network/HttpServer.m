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
#import "Network/HttpBufferPool.h"
#import "Network/HttpParsing.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpRouteTrie.h"
#import "Network/PDSNetworkTransport.h"
#import "Network/RateLimiter.h"
#import "Network/WebSocketUpgradeHandler.h"
#import "Network/Http1Parser.h"
#import "Network/Http1PipelinePolicy.h"
#import <CoreFoundation/CoreFoundation.h>

@class HttpRouteTrie;

@interface HttpServer ()

@property(nonatomic, readwrite, nullable) NSString *host;
@property(nonatomic, readwrite) NSUInteger port;
@property(nonatomic, readwrite, getter=isRunning) BOOL running;
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
@property(nonatomic, assign) BOOL listenerReady;
@property(nonatomic, assign) BOOL startupFinished;
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

@implementation HttpQueuedResponse
@end

@interface HttpConnectionState : NSObject

@property(nonatomic, strong) Http1Parser *parser;
@property(nonatomic, strong) Http1PipelinePolicy *pipelinePolicy;

@property(nonatomic, assign) NSTimeInterval headerStartTime;
@property(nonatomic, assign) BOOL requestInFlight;
@property(nonatomic, strong) NSMutableArray<HttpQueuedResponse *> *outputQueue;
@property(nonatomic, assign) BOOL readingPaused;
@property(nonatomic, assign) NSUInteger outputQueueSize;
@property(nonatomic, strong) NSMutableArray<HttpRequest *> *pendingRequests;
@property(nonatomic, assign) BOOL sendingActive;
@property(nonatomic, assign) BOOL upgradedToWebSocket;
@property(nonatomic, PDS_DISPATCH_QUEUE_STRONG)
    dispatch_queue_t transportQueue;

@end

@implementation HttpConnectionState

- (instancetype)init {
  self = [super init];
  if (self) {
    _parser = [[Http1Parser alloc] init];
    _pipelinePolicy = [[Http1PipelinePolicy alloc] init];
    _headerStartTime = [NSDate timeIntervalSinceReferenceDate];
    _requestInFlight = NO;
    _outputQueue = [NSMutableArray array];
    _readingPaused = NO;
    _outputQueueSize = 0;
    _pendingRequests = [NSMutableArray array];
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

- (void)resetForNextRequest {
  [_parser reset];
  _headerStartTime = [NSDate timeIntervalSinceReferenceDate];
  _requestInFlight = NO;
  [_outputQueue removeAllObjects];
  _outputQueueSize = 0;
  _readingPaused = NO;
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

  [connection startWithQueue:transportQueue];
}

- (void)readRequestFromConnection:(id<PDSNetworkConnection>)connection {
  HttpConnectionState *state = [self connectionStateForConnection:connection];
  if (state.upgradedToWebSocket) {
    return;
  }

  if (state.pipelinePolicy.pendingDispatchCount > 0 || state.outputQueue.count > 0 ||
      state.pendingRequests.count > 0) {
    return;
  }

  if ([NSDate timeIntervalSinceReferenceDate] - state.headerStartTime >
      kHttpHeaderTimeout) {
    [connection cancel];
    return;
  }

  __weak typeof(self) weakSelf = self;

  // Do NOT use dispatch_group for individual reads — the completion may fire
  // from processReadRequests in contexts where group_enter wasn't called
  // (e.g., when isComplete propagates through a while loop).
  // The taskGroup is only needed for dispatchRequest and server shutdown.
  [connection
      receiveWithMinimumLength:1
                 maximumLength:UINT32_MAX
                    completion:^(NSData *_Nullable content, BOOL isComplete,
                                 NSError *_Nullable error) {
                      __strong typeof(weakSelf) strongSelf = weakSelf;
                      if (!strongSelf) {
                        return;
                      }

                      if (error) {
                        [connection cancel];
                        return;
                      }

                      if (content && content.length > 0) {
                        [strongSelf handleReceivedData:content
                                          onConnection:connection];
                      } else if (isComplete) {
                        [connection cancel];
                      }
                    }];
}

- (void)handleReceivedData:(NSData *)data
              onConnection:(id<PDSNetworkConnection>)connection {
  HttpConnectionState *state = [self connectionStateForConnection:connection];
  
  if (!state.parser.remoteAddress) {
    state.parser.remoteAddress = connection.remoteAddress;
  }
  
  [self tryProcessRequestFromState:state data:data connection:connection];

  if ([state.pipelinePolicy shouldReadMoreData] && state.outputQueue.count == 0) {
    [self readRequestFromConnection:connection];
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

- (void)tryProcessRequestFromState:(HttpConnectionState *)state
                              data:(NSData *)data
                        connection:(id<PDSNetworkConnection>)connection {
  if ([NSDate timeIntervalSinceReferenceDate] - state.headerStartTime >
      kHttpHeaderTimeout) {
    [connection cancel];
    return;
  }
                        
  BOOL completeOrError = [state.parser feedData:data];
  if (!completeOrError) {
    return;
  }

  Http1ParserError *parseError = [state.parser parseError];
  if (parseError) {
    HttpResponse *response =
        [HttpResponse responseWithStatusCode:parseError.statusCode];
    response.keepAlive = NO;
    [response setJsonBody:@{
      @"error" : parseError.errorCode,
      @"message" : parseError.message
    }];
    [self queueResponse:response forState:state connection:connection];
    return;
  }

  HttpRequest *request = [state.parser completedRequest];
  if (!request) {
    return;
  }

  NSString *path = request.path;
  WebSocketRequestHandler webSocketHandler = self.webSocketHandlers[path];
  
  if (webSocketHandler && [request headerForKey:@"upgrade"] != nil) {
    HttpResponse *upgradeResponse = [HttpResponse response];
    BOOL shouldUpgrade =
        [self.webSocketUpgradeHandler handleUpgradeRequest:request
                                                  response:upgradeResponse];
    if (!shouldUpgrade) {
      [state resetForNextRequest];
      [self queueResponse:upgradeResponse forState:state connection:connection];
      return;
    }

    state.upgradedToWebSocket = YES;
    [state.pendingRequests removeAllObjects];
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
    return;
  }

  Http1PipelineAction action = [state.pipelinePolicy requestParsed];
  
  if (action == Http1PipelineActionDispatch || action == Http1PipelineActionQueue) {
    [state.pendingRequests addObject:request];
    NSData *unconsumed = [state.parser unconsumedData];
    [state resetForNextRequest];
    
    [self processPipelinedRequestsForState:state connection:connection];
    
    if (unconsumed.length > 0) {
      [self tryProcessRequestFromState:state data:unconsumed connection:connection];
    }
  }
}

- (void)processPipelinedRequestsForState:(HttpConnectionState *)state
                              connection:(id<PDSNetworkConnection>)connection {
  while (state.pendingRequests.count > 0 &&
         [state.pipelinePolicy shouldReadMoreData]) {
    HttpRequest *request = state.pendingRequests[0];
    [state.pendingRequests removeObjectAtIndex:0];
    [state.pipelinePolicy requestDispatched];

    [self dispatchRequest:request onConnection:connection];
  }
}

- (void)queueResponse:(HttpResponse *)response
             forState:(HttpConnectionState *)state
           connection:(id<PDSNetworkConnection>)connection {
  HttpQueuedResponse *queueItem = [self queueItemForResponse:response];
  [state.outputQueue addObject:queueItem];
  state.outputQueueSize += queueItem.queueByteSize;

  while (state.outputQueueSize > kHttpOutputQueueHighWaterMark &&
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
        HttpResponse *response = [strongSelf dispatchRequest:requestRef];
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

  while (state.outputQueueSize > kHttpOutputQueueHighWaterMark &&
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

- (void)finalizeQueuedResponseSend:(HttpQueuedResponse *)queueItem
                          forState:(HttpConnectionState *)state
                        connection:(id<PDSNetworkConnection>)connection {
  if (state.outputQueue.count > 0) {
    [state.outputQueue removeObjectAtIndex:0];
  }
  state.outputQueueSize =
      (state.outputQueueSize > queueItem.queueByteSize)
          ? (state.outputQueueSize - queueItem.queueByteSize)
          : 0;
  
  [state.pipelinePolicy responseCompleted];
  state.sendingActive = NO;

  if (queueItem.deleteBodyFileAfterSend && queueItem.bodyFilePath.length > 0) {
    [[NSFileManager defaultManager] removeItemAtPath:queueItem.bodyFilePath
                                               error:nil];
  }

  if (state.outputQueue.count > 0) {
    [self sendNextQueuedResponseForState:state connection:connection];
  } else {
    [self continueConnection:connection withState:state];
  }
}

- (void)continueConnection:(id<PDSNetworkConnection>)connection
                 withState:(HttpConnectionState *)state {
  if (state.outputQueue.count == 0 && [state.pipelinePolicy shouldReadMoreData] &&
      state.pendingRequests.count == 0) {
    [self readRequestFromConnection:connection];
  }
}

- (RequestHandler _Nullable)
    handlerForRoute:(NSString *)path
             method:(NSString *)method
         parameters:(NSDictionary<NSString *, NSString *> *_Nullable *_Nullable)
                        parameters {
  NSString *normalizedMethod = [(method ?: @"") uppercaseString];
  HttpRouteTrie *trie = self.routeTries[normalizedMethod];
  NSDictionary<NSString *, NSString *> *matchedParams = nil;
  RequestHandler handler = [trie handlerForMethod:normalizedMethod
                                             path:path
                                    outParameters:&matchedParams];
  if (!handler) {
    HttpRouteTrie *catchAll = self.routeTries[@"*"];
    handler =
        [catchAll handlerForMethod:@"*" path:path outParameters:&matchedParams];
  }
  if (parameters) {
    *parameters = handler ? matchedParams : nil;
  }
  return handler;
}

- (HttpResponse *)dispatchRequest:(HttpRequest *)request {
  NSString *logPath = request.queryString.length > 0
                          ? [NSString stringWithFormat:@"%@?%@", request.path,
                                                       request.queryString]
                          : request.path;
  PDS_LOG_HTTP_INFO(@"[%@] %@ %@", request.remoteAddress, request.methodString,
                    logPath);
  HttpResponse *response = [HttpResponse response];

  if ([request.path hasPrefix:@"/oauth/"] && !RateLimiterIsDisabledGlobally() &&
      [RateLimiter sharedLimiter].isEnabled) {
    RateLimitResult *result =
        [[RateLimiter sharedLimiter] checkRateLimitForIP:request.remoteAddress];
    if (!result.allowed) {
      response.statusCode = 429;
      [response setJsonBody:@{
        @"error" : @"too_many_requests",
        @"message" : @"Rate limit exceeded"
      }];
      return response;
    }
  }

  if (self.requestHandler) {
    self.requestHandler(request, response);
    return response;
  }

  NSString *methodString = request.methodString;
  NSString *path = request.path;

  NSDictionary<NSString *, NSString *> *pathParameters = nil;

  // First try exact path match
  RequestHandler handler = self.pathHandlers[path];
  PDS_LOG_HTTP_INFO(@"Path %@, pathHandlers: %@, exact handler: %@", path,
                    self.pathHandlers.allKeys, handler ? @"found" : @"nil");

  // Then try prefix matching for pathHandlers (e.g., /explore matches
  // /explore/css/style.css)
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
    handler = [self handlerForRoute:path
                             method:methodString
                         parameters:&pathParameters];
  }

  request.pathParameters = pathParameters;

  if (handler) {
    handler(request, response);
  } else {
    response.statusCode = HttpStatusNotFound;
    [response setJsonBody:@{
      @"error" : @"Not Found",
      @"message" : [NSString
          stringWithFormat:@"No handler for %@ %@", methodString, path]
    }];
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

  if ([path hasPrefix:pattern] && [path length] > [pattern length] &&
      [[path substringFromIndex:[pattern length]] hasPrefix:@"/"]) {
    return YES;
  }

  NSArray<NSString *> *pathParts = [path componentsSeparatedByString:@"/"];
  NSArray<NSString *> *patternParts =
      [pattern componentsSeparatedByString:@"/"];

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

- (void)sendResponse:(HttpResponse *)response
        onConnection:(id<PDSNetworkConnection>)connection {
  [self enqueueResponse:response forConnection:connection];
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
  self.pathHandlers[path] = [handler copy];
}

- (void)addWebSocketRoute:(NSString *)path
                  handler:(WebSocketRequestHandler)handler {
  if (!path || !handler) {
    return;
  }
  self.webSocketHandlers[path] = [handler copy];
}

@end
