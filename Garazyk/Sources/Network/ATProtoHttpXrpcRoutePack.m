// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Network/PDSHttpXrpcRoutePack.h"

#import "App/PDSApplication.h"
#import "App/PDSController.h"
#import "Debug/GZLogger.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"
#import "Network/PDSNetworkTransport.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcMethodRegistry.h"
#import "Sync/Firehose/SubscribeReposHandler.h"

@implementation PDSHttpXrpcRoutePack

+ (void)registerRoutesWithServer:(HttpServer *)server
                      dispatcher:(nullable XrpcDispatcher *)dispatcher
                     application:(nullable PDSApplication *)application
                      controller:(nullable PDSController *)controller
           subscribeReposHandler:(nullable SubscribeReposHandler *)subscribeReposHandler
                  setCorsHeaders:(PDSHttpSetCorsHeadersBlock)setCorsHeaders {
  XrpcDispatcher *resolvedDispatcher = dispatcher;
  if (!resolvedDispatcher) {
    resolvedDispatcher = [[XrpcDispatcher alloc] init];
  }

  if (application) {
    [XrpcMethodRegistry registerMethodsWithDispatcher:resolvedDispatcher
                                          application:application];
  } else if (controller) {
    [XrpcMethodRegistry registerMethodsWithDispatcher:resolvedDispatcher
                                           controller:controller];
  } else {
    GZ_LOG_ERROR(@"No application/controller available for XRPC registration");
  }

  __weak SubscribeReposHandler *weakSubscribeReposHandler = subscribeReposHandler;
  RequestHandler xrpcDispatchHandler = ^(HttpRequest *request,
                                         HttpResponse *response) {
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
           handler:^(HttpRequest *request, HttpResponse *response) {
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
           handler:^(HttpRequest *request, HttpResponse *response) {
             setCorsHeaders(response, request);
             response.statusCode = HttpStatusOK;
           }];

  // Handler for /xrpc/:method
  [server addRoute:@"*"
              path:@"/xrpc/:method"
           handler:^(HttpRequest *request, HttpResponse *response) {
             [resolvedDispatcher handleRequest:request response:response];
           }];

  for (NSString *method in @[ @"GET", @"HEAD" ]) {
    [server addRoute:method
                path:@"/xrpc/:method"
             handler:^(HttpRequest *request, HttpResponse *response) {
               [resolvedDispatcher handleRequest:request response:response];
             }];
  }

  if (subscribeReposHandler) {
    GZ_LOG_SYNC_INFO(@"PDSHttpXrpcRoutePack: Registering WebSocket route for subscribeRepos");
    // OPTIONS preflight for WebSocket upgrade
    [server addRoute:@"OPTIONS"
                path:@"/xrpc/com.atproto.sync.subscribeRepos"
             handler:^(HttpRequest *request, HttpResponse *response) {
               setCorsHeaders(response, request);
               response.statusCode = HttpStatusOK;
             }];

    [server addWebSocketRoute:@"/xrpc/com.atproto.sync.subscribeRepos"
                      handler:^(HttpRequest *request, HttpResponse *response,
                                id<PDSNetworkConnection> connection) {
                        SubscribeReposHandler *strongSubscribeReposHandler =
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

  GZ_LOG_DEBUG(@"PDSHttpXrpcRoutePack: XRPC routes registered");
}

@end
