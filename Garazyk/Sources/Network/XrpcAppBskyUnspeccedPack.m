#import "Network/XrpcAppBskyUnspeccedPack.h"

#import "Debug/PDSLogger.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/XrpcAuthHelper.h"

@implementation XrpcAppBskyUnspeccedPack

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher {

#pragma mark - Labeler

  [dispatcher registerMethod:@"app.bsky.labeler.getServices"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"views" : @[], @"cursor" : [NSNull null]}];
                     }];

#pragma mark - Configuration

  [dispatcher registerMethod:@"app.bsky.unspecced.getConfig"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{
                           @"checkEmailConfirmed" : @NO,
                           @"labelerDefinitions": @[],
                           @"generators": @[],
                           @"feeds": @[]
                       }];
                     }];

#pragma mark - Suggestions & Discovery

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
                       [response setJsonBody:@{@"topics" : @[], @"suggested" : @[]}];
                     }];

#pragma mark - Skeleton Endpoints (Preview/Performance Optimized)

  [dispatcher registerMethod:@"app.bsky.unspecced.getSuggestedFeedsSkeleton"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"feeds" : @[]}];
                     }];

  [dispatcher registerMethod:@"app.bsky.unspecced.getSuggestedUsersSkeleton"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"actors" : @[]}];
                     }];

  [dispatcher registerMethod:@"app.bsky.unspecced.getSuggestionsSkeleton"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"suggestions" : @[]}];
                     }];

  [dispatcher registerMethod:@"app.bsky.unspecced.getTrendsSkeleton"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"posts" : @[], @"cursor" : @""}];
                     }];

#pragma mark - Starter Packs

  [dispatcher registerMethod:@"app.bsky.unspecced.getOnboardingSuggestedStarterPacks"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"starterPacks" : @[]}];
                     }];

  [dispatcher registerMethod:@"app.bsky.unspecced.getOnboardingSuggestedStarterPacksSkeleton"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"starterPacks" : @[]}];
                     }];

  [dispatcher registerMethod:@"app.bsky.unspecced.getSuggestedStarterPacks"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"starterPacks" : @[]}];
                     }];

  [dispatcher registerMethod:@"app.bsky.unspecced.getSuggestedStarterPacksSkeleton"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"starterPacks" : @[]}];
                     }];

#pragma mark - Search Skeleton Endpoints

  [dispatcher registerMethod:@"app.bsky.unspecced.searchActorsSkeleton"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       NSString *query = [request queryParamForKey:@"q"];
                       NSString *limitStr = [request queryParamForKey:@"limit"];

                       if (!query || query.length == 0) {
                           [XrpcErrorHelper setValidationError:response message:@"q parameter is required"];
                           return;
                       }

                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"actors" : @[], @"cursor" : @""}];
                     }];

  [dispatcher registerMethod:@"app.bsky.unspecced.searchPostsSkeleton"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       NSString *query = [request queryParamForKey:@"q"];

                       if (!query || query.length == 0) {
                           [XrpcErrorHelper setValidationError:response message:@"q parameter is required"];
                           return;
                       }

                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"posts" : @[], @"cursor" : @""}];
                     }];

  [dispatcher registerMethod:@"app.bsky.unspecced.searchStarterPacksSkeleton"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       NSString *query = [request queryParamForKey:@"q"];

                       if (!query || query.length == 0) {
                           [XrpcErrorHelper setValidationError:response message:@"q parameter is required"];
                           return;
                       }

                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"starterPacks" : @[], @"cursor" : @""}];
                     }];

#pragma mark - Thread Endpoints

  [dispatcher registerMethod:@"app.bsky.unspecced.getPostThreadV2"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       NSString *uri = [request queryParamForKey:@"uri"];

                       if (!uri || uri.length == 0) {
                           [XrpcErrorHelper setValidationError:response message:@"uri parameter is required"];
                           return;
                       }

                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{
                           @"thread": @{},
                           @"threadgate": [NSNull null]
                       }];
                     }];

  [dispatcher registerMethod:@"app.bsky.unspecced.getPostThreadOtherV2"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       NSString *uri = [request queryParamForKey:@"uri"];

                       if (!uri || uri.length == 0) {
                           [XrpcErrorHelper setValidationError:response message:@"uri parameter is required"];
                           return;
                       }

                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{
                           @"thread": @{},
                           @"threadgate": [NSNull null]
                       }];
                     }];

#pragma mark - Age Assurance (Compliance)

  [dispatcher registerMethod:@"app.bsky.unspecced.initAgeAssurance"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       NSDictionary *body = request.jsonBody;
                       NSString *assurance = body[@"assurance"];
                       NSArray *methods = body[@"methods"];

                       if (!assurance || assurance.length == 0) {
                           [XrpcErrorHelper setValidationError:response message:@"assurance parameter is required"];
                           return;
                       }

                       // Validate assurance value
                       NSArray *validAssurances = @[@"no_verification", @"verified_by_adult", @"verified_by_method"];
                       if (![validAssurances containsObject:assurance]) {
                           [XrpcErrorHelper setValidationError:response message:@"assurance must be one of: no_verification, verified_by_adult, verified_by_method"];
                           return;
                       }

                       NSString *now = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]];

                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{
                           @"assurance": assurance,
                           @"verifiedAt": now
                       }];
                     }];

  [dispatcher registerMethod:@"app.bsky.unspecced.getAgeAssuranceState"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{
                           @"assurance": @"no_verification",
                           @"verifiedAt": [NSNull null]
                       }];
                     }];

#pragma mark - User Discovery (Onboarding & Discovery Pages)

  [dispatcher registerMethod:@"app.bsky.unspecced.getOnboardingSuggestedUsersSkeleton"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"actors" : @[]}];
                     }];

  [dispatcher registerMethod:@"app.bsky.unspecced.getSuggestedOnboardingUsers"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"actors" : @[]}];
                     }];

  [dispatcher registerMethod:@"app.bsky.unspecced.getSuggestedUsersForDiscover"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"actors" : @[]}];
                     }];

  [dispatcher registerMethod:@"app.bsky.unspecced.getSuggestedUsersForDiscoverSkeleton"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"actors" : @[]}];
                     }];

  [dispatcher registerMethod:@"app.bsky.unspecced.getSuggestedUsersForExplore"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"actors" : @[]}];
                     }];

  [dispatcher registerMethod:@"app.bsky.unspecced.getSuggestedUsersForExploreSkeleton"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"actors" : @[]}];
                     }];

  [dispatcher registerMethod:@"app.bsky.unspecced.getSuggestedUsersForSeeMore"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"actors" : @[]}];
                     }];

  [dispatcher registerMethod:@"app.bsky.unspecced.getSuggestedUsersForSeeMoreSkeleton"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"actors" : @[]}];
                     }];
}

@end
