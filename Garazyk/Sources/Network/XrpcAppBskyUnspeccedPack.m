#import "Network/XrpcAppBskyUnspeccedPack.h"

#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcHandler.h"

@implementation XrpcAppBskyUnspeccedPack

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher {
  [dispatcher registerMethod:@"app.bsky.labeler.getServices"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       response.statusCode = HttpStatusOK;
                       [response
                           setJsonBody:@{@"views" : @[], @"cursor" : [NSNull null]}];
                     }];

  [dispatcher registerMethod:@"app.bsky.unspecced.getConfig"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"checkEmailConfirmed" : @NO}];
                     }];

  [dispatcher registerMethod:@"app.bsky.unspecced.getTaggedSuggestions"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"suggestions" : @[]}];
                     }];

  [dispatcher registerMethod:@"app.bsky.unspecced.getPopularFeedGenerators"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"feeds" : @[]}];
                     }];

  [dispatcher registerMethod:@"app.bsky.unspecced.getSuggestedFeeds"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"feeds" : @[]}];
                     }];

  [dispatcher registerMethod:@"app.bsky.unspecced.getSuggestedUsers"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"actors" : @[]}];
                     }];

  [dispatcher registerMethod:@"app.bsky.unspecced.getTrendingTopics"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       response.statusCode = HttpStatusOK;
                       [response
                           setJsonBody:@{@"topics" : @[], @"suggested" : @[]}];
                     }];
}

@end
