// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Network/ATProtoHttpXrpcRoutePack.h"

#import "App/PDSApplication.h"
#import "App/PDSController.h"
#import "Debug/GZLogger.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"
#import "Network/ATProtoNetworkTransport.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcMethodRegistry.h"
#import "Sync/Firehose/SubscribeReposHandler.h"

@implementation ATProtoHttpXrpcRoutePack

+ (void)registerRoutesWithServer:(ATProtoHttpServer *)server
                      dispatcher:(nullable ATProtoXrpcDispatcher *)dispatcher
                     application:(nullable PDSApplication *)application
                      controller:(nullable PDSController *)controller
           subscribeReposHandler:(nullable ATProtoSubscribeReposHandler *)subscribeReposHandler
                  setCorsHeaders:(ATProtoHttpSetCorsHeadersBlock)setCorsHeaders {
  ATProtoXrpcDispatcher *resolvedDispatcher = dispatcher;
  if (!resolvedDispatcher) {
    resolvedDispatcher = [[ATProtoXrpcDispatcher alloc] init];
  }

  if (application) {
    [ATProtoXrpcMethodRegistry registerMethodsWithDispatcher:resolvedDispatcher
                                          application:application];
  } else if (controller) {
    [ATProtoXrpcMethodRegistry registerMethodsWithDispatcher:resolvedDispatcher
                                           controller:controller];
  } else {
    GZ_LOG_ERROR(@"No application/controller available for XRPC registration");
  }

  __weak ATProtoSubscribeReposHandler *weakSubscribeReposHandler = subscribeReposHandler;
  RequestHandler xrpcDispatchHandler = ^(ATProtoHttpRequest *request,
                                         ATProtoHttpResponse *response) {
    if ([request.methodString isEqualToString:@"OPTIONS"]) {
      setCorsHeaders(response, request);
      response.statusCode = HttpStatusOK;
      return;
    }
    GZ_LOG_HTTP_INFO(@"About to call dispatcher handleRequest for %@",
                      request.path);
    [resolvedDispatcher handleRequest:request response:response];
    GZ_LOG_HTTP_INFO(@"dispatcher handleRequest returned for %@",
                      request.path);
  };

  // OPTIONS preflight for XRPC prefix
  [server addRoute:@"OPTIONS"
              path:@"/xrpc"
           handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
             setCorsHeaders(response, request);
             response.statusCode = HttpStatusOK;
           }];

  // Register GET/HEAD explicitly so API paths are resolved before the
  // default GET wildcard UI route.
  for (NSString *method in @[ @"GET", @"HEAD" ]) {
    [server addRoute:method path:@"/xrpc" handler:xrpcDispatchHandler];
    [server addRoute:method path:@"/xrpc/*" handler:xrpcDispatchHandler];
  }

  // Handler for /xrpc (prefix match for all XRPC methods)
  [server addHandlerForPath:@"/xrpc" handler:xrpcDispatchHandler];

  // OPTIONS preflight for XRPC methods
  [server addRoute:@"OPTIONS"
              path:@"/xrpc/:method"
           handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
             setCorsHeaders(response, request);
             response.statusCode = HttpStatusOK;
           }];

  // Handler for /xrpc/:method
  [server addRoute:@"*"
              path:@"/xrpc/:method"
           handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
             [resolvedDispatcher handleRequest:request response:response];
           }];

  for (NSString *method in @[ @"GET", @"HEAD" ]) {
    [server addRoute:method
                path:@"/xrpc/:method"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
               [resolvedDispatcher handleRequest:request response:response];
             }];
  }

  if (subscribeReposHandler) {
    GZ_LOG_SYNC_INFO(@"ATProtoHttpXrpcRoutePack: Registering WebSocket route for subscribeRepos");
    // OPTIONS preflight for WebSocket upgrade
    [server addRoute:@"OPTIONS"
                path:@"/xrpc/com.atproto.sync.subscribeRepos"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
               setCorsHeaders(response, request);
               response.statusCode = HttpStatusOK;
             }];

    [server addWebSocketRoute:@"/xrpc/com.atproto.sync.subscribeRepos"
                      handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response,
                                id<ATProtoNetworkConnection> connection) {
                        ATProtoSubscribeReposHandler *strongSubscribeReposHandler =
                            weakSubscribeReposHandler;
                        if (!strongSubscribeReposHandler) {
                          [connection cancel];
                          return;
                        }
                        [strongSubscribeReposHandler
                            acceptUpgradedConnection:connection
                                             request:request];
                      }];
  }

  // Install the per-method request-body caps on the HTTP server so the parser
  // can admit large bodies for routes that registered an override (e.g.
  // com.atproto.repo.importRepo with maxImportSize) while every other XRPC
  // endpoint keeps the generic parser limit. 0 means "no override".
  __weak ATProtoXrpcDispatcher *weakDispatcher = resolvedDispatcher;
  server.bodySizeLimitProvider = ^NSUInteger(NSString *path) {
    ATProtoXrpcDispatcher *strongDispatcher = weakDispatcher;
    if (!strongDispatcher || ![path hasPrefix:@"/xrpc/"]) {
      return 0;
    }
    NSString *method = [path substringFromIndex:6];
    if (method.length == 0) {
      return 0;
    }
    return [strongDispatcher maxBodyBytesForMethod:method];
  };

  GZ_LOG_DEBUG(@"ATProtoHttpXrpcRoutePack: XRPC routes registered");
}

@end
