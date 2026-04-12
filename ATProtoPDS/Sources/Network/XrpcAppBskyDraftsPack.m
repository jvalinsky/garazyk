#import "Network/XrpcAppBskyDraftsPack.h"

#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/XrpcHandler.h"

@implementation XrpcAppBskyDraftsPack

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher {
  [dispatcher registerMethod:@"app.bsky.draft.createDraft"
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
                         @"message" : @"Draft storage not yet implemented"
                       }];
                     }];

  [dispatcher registerMethod:@"app.bsky.draft.updateDraft"
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
                         @"message" : @"Draft storage not yet implemented"
                       }];
                     }];

  [dispatcher registerMethod:@"app.bsky.draft.getDrafts"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       NSString *authHeader =
                           [request headerForKey:@"Authorization"];
                       if (!authHeader) {
                         [XrpcErrorHelper
                             setAuthenticationError:response
                                            message:@"Authentication required"];
                         return;
                       }
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"drafts" : @[]}];
                     }];

  [dispatcher registerMethod:@"app.bsky.draft.deleteDraft"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       NSString *authHeader =
                           [request headerForKey:@"Authorization"];
                       if (!authHeader) {
                         [XrpcErrorHelper
                             setAuthenticationError:response
                                            message:@"Authentication required"];
                         return;
                       }
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{}];
                     }];
}

@end
