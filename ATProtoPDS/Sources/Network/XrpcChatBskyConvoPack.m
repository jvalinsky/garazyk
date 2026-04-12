#import "Network/XrpcChatBskyConvoPack.h"

#import "Debug/PDSLogger.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/XrpcHandler.h"

@implementation XrpcChatBskyConvoPack

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher {
  [dispatcher registerMethod:@"chat.bsky.convo.getConvo"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       NSString *authHeader =
                           [request headerForKey:@"Authorization"];
                       if (!authHeader) {
                         [XrpcErrorHelper
                             setAuthenticationError:response
                                            message:@"Authentication required"];
                         return;
                       }
                       response.statusCode = 501;
                       [response setJsonBody:@{
                         @"error" : @"NotImplemented",
                         @"message" : @"Chat not supported"
                       }];
                     }];

  [dispatcher registerMethod:@"chat.bsky.convo.listConvos"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       NSString *authHeader =
                           [request headerForKey:@"Authorization"];
                       if (!authHeader) {
                         [XrpcErrorHelper
                             setAuthenticationError:response
                                            message:@"Authentication required"];
                         return;
                       }
                       response.statusCode = 501;
                       [response setJsonBody:@{
                         @"error" : @"NotImplemented",
                         @"message" : @"Chat not supported"
                       }];
                     }];

  [dispatcher registerMethod:@"chat.bsky.convo.sendMessage"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       NSString *authHeader =
                           [request headerForKey:@"Authorization"];
                       if (!authHeader) {
                         [XrpcErrorHelper
                             setAuthenticationError:response
                                            message:@"Authentication required"];
                         return;
                       }
                       response.statusCode = 501;
                       [response setJsonBody:@{
                         @"error" : @"NotImplemented",
                         @"message" : @"Chat not supported"
                       }];
                     }];

  [dispatcher registerMethod:@"chat.bsky.convo.getMessages"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       NSString *authHeader =
                           [request headerForKey:@"Authorization"];
                       if (!authHeader) {
                         [XrpcErrorHelper
                             setAuthenticationError:response
                                            message:@"Authentication required"];
                         return;
                       }
                       response.statusCode = 501;
                       [response setJsonBody:@{
                         @"error" : @"NotImplemented",
                         @"message" : @"Chat not supported"
                       }];
                     }];

  [dispatcher registerMethod:@"chat.bsky.convo.getLog"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       NSString *authHeader =
                           [request headerForKey:@"Authorization"];
                       if (!authHeader) {
                         [XrpcErrorHelper
                             setAuthenticationError:response
                                            message:@"Authentication required"];
                         return;
                       }
                       response.statusCode = 501;
                       [response setJsonBody:@{
                         @"error" : @"NotImplemented",
                         @"message" : @"Chat not supported"
                       }];
                     }];

  PDS_LOG_INFO(@"Registered chat.bsky.convo.* endpoints (stubs)");
}

@end
