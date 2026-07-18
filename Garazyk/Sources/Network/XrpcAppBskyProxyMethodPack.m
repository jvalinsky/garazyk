// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Network/XrpcAppBskyProxyMethodPack.h"

#import "Debug/GZLogger.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcProxyHandler.h"
#import "Network/XrpcRoutePackServices.h"
#import "Network/Generated/GZXrpcNSID.h"

@implementation XrpcAppBskyProxyMethodPack

+ (NSString *)routePackIdentifier {
  return @"app.bsky.proxy";
}

+ (void)registerProxyOnlyMethodsWithDispatcher:(XrpcDispatcher *)dispatcher {
  XrpcRoutePackServiceBag *services =
      [[XrpcRoutePackServiceBag alloc] initWithDispatcher:dispatcher
                                                jwtMinter:dispatcher.jwtMinter
                                          adminController:nil
                                             configuration:nil
                                               adminSecret:nil
                                         serviceDatabases:nil
                                         userDatabasePool:nil
                                               rateLimiter:nil];
  [self registerWithDispatcher:dispatcher services:services];
}

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                      services:(id<XrpcRoutePackServices>)services {
  XrpcDispatcher *resolvedDispatcher = services.dispatcher ?: dispatcher;
  if (!resolvedDispatcher) {
    return;
  }
  [self registerProxyOnlyMethodsOnDispatcher:resolvedDispatcher];
}

+ (void)registerProxyOnlyMethodsOnDispatcher:(XrpcDispatcher *)dispatcher {
  NSArray<NSString *> *methodIds = @[
    @"app.bsky.actor.getProfile",
    @"app.bsky.actor.getProfiles",
    @"app.bsky.actor.searchActors",
    @"app.bsky.actor.getSuggestions",
    @"app.bsky.graph.verification.createVerification",
    @"app.bsky.graph.verification.deleteVerification"
  ];

  for (NSString *methodId in methodIds) {
    if ([dispatcher hasRegisteredMethod:methodId]) {
      GZ_LOG_DEBUG(@"Skipping proxy-only registration for local XRPC method '%@'",
                   methodId);
      continue;
    }
    [dispatcher registerMethod:methodId
                       handler:^(HttpRequest *request, HttpResponse *response) {
                         [self proxyOrNotSupported:request
                                          response:response
                                          methodId:methodId
                                        dispatcher:dispatcher];
                       }];
  }
}

+ (void)setUnsupportedError:(HttpResponse *)response methodId:(NSString *)methodId {
  response.statusCode = 501;
  [response setJsonBody:@{
    @"error" : @"NotSupported",
    @"message" : [NSString
        stringWithFormat:@"Method '%@' is not supported by this PDS", methodId]
  }];
}

+ (void)proxyOrNotSupported:(HttpRequest *)request
                   response:(HttpResponse *)response
                   methodId:(NSString *)methodId
                 dispatcher:(XrpcDispatcher *)dispatcher {
  if (dispatcher.proxyURL) {
    GZ_LOG_INFO(@"Proxying XRPC method '%@' to %@", methodId, dispatcher.proxyURL);
    XrpcProxyHandler *proxy = [[XrpcProxyHandler alloc]
        initWithProxyURL:dispatcher.proxyURL
             upstreamDID:dispatcher.upstreamDID
                  minter:dispatcher.jwtMinter];
    [proxy handleRequest:request response:response];
  } else {
    GZ_LOG_INFO(
        @"Method '%@' not supported locally and no upstream AppView configured",
        methodId);
    [self setUnsupportedError:response methodId:methodId];
  }
}

@end
