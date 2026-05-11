// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Network/XrpcAppBskyProxyMethodPack.h"

#import "Debug/PDSLogger.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcProxyHandler.h"

@implementation XrpcAppBskyProxyMethodPack

+ (void)setUnsupportedError:(HttpResponse *)response methodId:(NSString *)methodId {
  response.statusCode = 501;
  [response setJsonBody:@{
    @"error" : @"NotSupported",
    @"message" : [NSString
        stringWithFormat:@"Method '%@' is not supported by this PDS",
                         methodId]
  }];
}

+ (void)proxyOrNotSupported:(HttpRequest *)request
                   response:(HttpResponse *)response
                   methodId:(NSString *)methodId
                 dispatcher:(XrpcDispatcher *)dispatcher {
  if (dispatcher.proxyURL) {
    PDS_LOG_INFO(@"Proxying XRPC method '%@' to %@", methodId,
                 dispatcher.proxyURL);
    XrpcProxyHandler *proxy = [[XrpcProxyHandler alloc]
        initWithProxyURL:dispatcher.proxyURL
             upstreamDID:dispatcher.upstreamDID
                  minter:dispatcher.jwtMinter];
    [proxy handleRequest:request response:response];
  } else {
    PDS_LOG_INFO(
        @"Method '%@' not supported locally and no upstream AppView configured",
        methodId);
    [self setUnsupportedError:response methodId:methodId];
  }
}

+ (void)registerProxyOnlyMethodsWithDispatcher:(XrpcDispatcher *)dispatcher {
  NSArray<NSString *> *methodIds = @[
    @"app.bsky.actor.getProfile",
    @"app.bsky.actor.getProfiles",
    @"app.bsky.actor.searchActors",
    @"app.bsky.actor.getSuggestions",
    @"app.bsky.graph.verification.createVerification",
    @"app.bsky.graph.verification.deleteVerification"
  ];

  for (NSString *methodId in methodIds) {
    [dispatcher registerMethod:methodId
                       handler:^(HttpRequest *request, HttpResponse *response) {
                         [self proxyOrNotSupported:request
                                          response:response
                                          methodId:methodId
                                        dispatcher:dispatcher];
                       }];
  }
}

@end

