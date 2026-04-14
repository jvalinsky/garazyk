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
    @"app.bsky.ageassurance.begin",
    @"app.bsky.ageassurance.getConfig",
    @"app.bsky.ageassurance.getState",
    @"app.bsky.contact.dismissMatch",
    @"app.bsky.contact.getMatches",
    @"app.bsky.contact.getSyncStatus",
    @"app.bsky.contact.importContacts",
    @"app.bsky.contact.removeData",
    @"app.bsky.contact.sendNotification",
    @"app.bsky.contact.startPhoneVerification",
    @"app.bsky.contact.verifyPhone",
    @"app.bsky.graph.verification.createVerification",
    @"app.bsky.graph.verification.deleteVerification",
    @"app.bsky.unspecced.getAgeAssuranceState",
    @"app.bsky.unspecced.initAgeAssurance"
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

