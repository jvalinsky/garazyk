// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Network/XrpcAppBskyUnspeccedPack.h"

#import "Debug/GZLogger.h"
#import "Network/XrpcRoutePackServices.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/XrpcAuthHelper.h"
#import "Auth/AuthClaimTypeCheck.h"
#import "AppView/Services/AgeAssuranceService.h"
#import "AppView/Services/SearchIndexService.h"
#import "AppView/Services/FeedService.h"
#import "Network/Generated/GZXrpcNSID.h"

// Helper: flatten nested thread tree into V2 flat list format
static void flattenThreadTree(NSDictionary *tree, NSInteger depth, NSMutableArray *outArray) {
    if (!tree) return;

    NSDictionary *post = tree[@"post"];
    if (post) {
        NSMutableDictionary *item = [NSMutableDictionary dictionary];
        item[@"uri"] = post[@"uri"] ?: @"";
        item[@"depth"] = @(depth);
        item[@"value"] = @{@"$type": @"app.bsky.unspecced.defs#threadItemPost",
                           @"uri": post[@"uri"] ?: @"",
                           @"cid": post[@"cid"] ?: @"",
                           @"author": post[@"author"] ?: @{},
                           @"record": post[@"record"] ?: @{},
                           @"replyCount": post[@"replyCount"] ?: @(0),
                           @"repostCount": post[@"repostCount"] ?: @(0),
                           @"likeCount": post[@"likeCount"] ?: @(0)};
        [outArray addObject:[item copy]];
    }

    NSArray *replies = tree[@"replies"];
    if ([replies isKindOfClass:[NSArray class]]) {
        for (NSDictionary *reply in replies) {
            flattenThreadTree(reply, depth + 1, outArray);
        }
    }
}

@implementation ATProtoXrpcAppBskyUnspeccedPack

+ (NSString *)routePackIdentifier {
  return @"app.bsky.unspecced";
}

+ (void)registerWithDispatcher:(ATProtoXrpcDispatcher *)dispatcher
                      services:(id<XrpcRoutePackServices>)services {

    PDSAgeAssuranceService *ageAssuranceService = services.ageAssuranceService;
    PDSSearchIndexService *searchIndexService = services.searchIndexService;
    PDSFeedService *feedService = services.feedService;

#pragma mark - Configuration

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_unspecced_getConfig
                     handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{
                           @"checkEmailConfirmed" : @NO,
                           @"labelerDefinitions": @[],
                           @"generators": @[],
                           @"feeds": @[]
                       }];
                     }];

#pragma mark - Suggestions & Discovery

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_unspecced_getTaggedSuggestions
                     handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"suggestions" : @[]}];
                     }];

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_unspecced_getPopularFeedGenerators
                     handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"feeds" : @[]}];
                     }];

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_unspecced_getSuggestedFeeds
                     handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"feeds" : @[]}];
                     }];

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_unspecced_getSuggestedUsers
                     handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"actors" : @[]}];
                     }];

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_unspecced_getTrendingTopics
                     handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"topics" : @[], @"suggested" : @[]}];
                     }];

#pragma mark - Skeleton Endpoints (Preview/Performance Optimized)

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_unspecced_getSuggestedFeedsSkeleton
                     handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"feeds" : @[]}];
                     }];

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_unspecced_getSuggestedUsersSkeleton
                     handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"actors" : @[]}];
                     }];

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_unspecced_getSuggestionsSkeleton
                     handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"suggestions" : @[]}];
                     }];

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_unspecced_getTrendsSkeleton
                     handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"posts" : @[], @"cursor" : @""}];
                     }];

#pragma mark - Starter Packs

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_unspecced_getOnboardingSuggestedStarterPacks
                     handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"starterPacks" : @[]}];
                     }];

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_unspecced_getOnboardingSuggestedStarterPacksSkeleton
                     handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"starterPacks" : @[]}];
                     }];

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_unspecced_getSuggestedStarterPacks
                     handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"starterPacks" : @[]}];
                     }];

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_unspecced_getSuggestedStarterPacksSkeleton
                     handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"starterPacks" : @[]}];
                     }];

#pragma mark - Search Skeleton Endpoints

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_unspecced_searchActorsSkeleton
                     handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                       NSString *query = [request queryParamForKey:@"q"];

                       if (!query || query.length == 0) {
                           [ATProtoXrpcErrorHelper setValidationError:response message:@"q parameter is required"];
                           return;
                       }

                       if (searchIndexService) {
                           NSString *limitParam = [request queryParamForKey:@"limit"];
                           NSInteger limit = limitParam ? [limitParam integerValue] : 25;
                           NSString *cursor = [request queryParamForKey:@"cursor"];

                           NSDictionary *result = [searchIndexService searchActors:query
                                                                             limit:limit
                                                                            cursor:cursor
                                                                             error:nil];
                           response.statusCode = HttpStatusOK;
                           [response setJsonBody:result ?: @{@"actors": @[], @"hitsTotal": @0}];
                       } else {
                           response.statusCode = 501;
                           [response setJsonBody:@{
                               @"error": @"NotImplemented",
                               @"message": @"app.bsky.unspecced.searchActorsSkeleton is not yet implemented"
                           }];
                       }
                     }];

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_unspecced_searchPostsSkeleton
                     handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                       NSString *query = [request queryParamForKey:@"q"];

                       if (!query || query.length == 0) {
                           [ATProtoXrpcErrorHelper setValidationError:response message:@"q parameter is required"];
                           return;
                       }

                       if (searchIndexService) {
                           NSString *limitParam = [request queryParamForKey:@"limit"];
                           NSInteger limit = limitParam ? [limitParam integerValue] : 25;
                           NSString *cursor = [request queryParamForKey:@"cursor"];

                           NSDictionary *result = [searchIndexService searchPosts:query
                                                                            limit:limit
                                                                           cursor:cursor
                                                                            error:nil];
                           response.statusCode = HttpStatusOK;
                           [response setJsonBody:result ?: @{@"posts": @[], @"hitsTotal": @0}];
                       } else {
                           response.statusCode = 501;
                           [response setJsonBody:@{
                               @"error": @"NotImplemented",
                               @"message": @"app.bsky.unspecced.searchPostsSkeleton is not yet implemented"
                           }];
                       }
                     }];

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_unspecced_searchStarterPacksSkeleton
                     handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                       NSString *query = [request queryParamForKey:@"q"];

                       if (!query || query.length == 0) {
                           [ATProtoXrpcErrorHelper setValidationError:response message:@"q parameter is required"];
                           return;
                       }

                       if (searchIndexService) {
                           NSString *limitParam = [request queryParamForKey:@"limit"];
                           NSInteger limit = limitParam ? [limitParam integerValue] : 25;
                           NSString *cursor = [request queryParamForKey:@"cursor"];

                           NSDictionary *result = [searchIndexService searchStarterPacks:query
                                                                                     limit:limit
                                                                                    cursor:cursor
                                                                                     error:nil];
                           response.statusCode = HttpStatusOK;
                           [response setJsonBody:result ?: @{@"starterPacks": @[], @"hitsTotal": @0}];
                       } else {
                           response.statusCode = 501;
                           [response setJsonBody:@{
                               @"error": @"NotImplemented",
                               @"message": @"app.bsky.unspecced.searchStarterPacksSkeleton is not yet implemented"
                           }];
                       }
                     }];

#pragma mark - Thread Endpoints

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_unspecced_getPostThreadV2
                     handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                       NSString *anchor = [request queryParamForKey:@"anchor"];

                       if (!anchor || anchor.length == 0) {
                           [ATProtoXrpcErrorHelper setValidationError:response message:@"anchor parameter is required"];
                           return;
                       }

                       if (feedService) {
                           NSInteger below = 6;
                           NSString *belowParam = [request queryParamForKey:@"below"];
                           if (belowParam) {
                               NSInteger parsed = [belowParam integerValue];
                               if (parsed >= 0 && parsed <= 20) below = parsed;
                           }

                           NSError *error = nil;
                           NSDictionary *threadTree = [feedService getPostThread:anchor depth:below error:&error];
                           if (error) {
                               [ATProtoXrpcErrorHelper setNotFoundError:response message:error.localizedDescription];
                               return;
                           }

                           // Flatten the nested thread tree into V2 flat list format
                           NSMutableArray *flatThread = [NSMutableArray array];
                           flattenThreadTree(threadTree, 0, flatThread);

                           response.statusCode = HttpStatusOK;
                           [response setJsonBody:@{
                               @"thread": flatThread,
                               @"hasOtherReplies": @NO
                           }];
                       } else {
                           response.statusCode = 501;
                           [response setJsonBody:@{
                               @"error": @"NotImplemented",
                               @"message": @"app.bsky.unspecced.getPostThreadV2 is not yet implemented"
                           }];
                       }
                     }];

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_unspecced_getPostThreadOtherV2
                     handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                       NSString *anchor = [request queryParamForKey:@"anchor"];

                       if (!anchor || anchor.length == 0) {
                           [ATProtoXrpcErrorHelper setValidationError:response message:@"anchor parameter is required"];
                           return;
                       }

                       // getPostThreadOtherV2 returns additional replies hidden by threadgate.
                       // For now, return empty thread (no hidden replies).
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"thread": @[]}];
                     }];

#pragma mark - Age Assurance (Compliance)

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_unspecced_initAgeAssurance
                     handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                       NSDictionary *body = request.jsonBody;
                       BOOL typeMismatch = NO;
                       NSString *assurance = AuthTypedValue(body, @"assurance", [NSString class], &typeMismatch);
                       NSArray *methods = body[@"methods"];
                       if (typeMismatch) {
                           [ATProtoXrpcErrorHelper setValidationError:response message:@"Request field has wrong type"];
                           return;
                       }

                       if (!assurance || assurance.length == 0) {
                           [ATProtoXrpcErrorHelper setValidationError:response message:@"assurance parameter is required"];
                           return;
                       }

                       // Validate assurance value
                       NSArray *validAssurances = @[@"no_verification", @"verified_by_adult", @"verified_by_method"];
                       if (![validAssurances containsObject:assurance]) {
                           [ATProtoXrpcErrorHelper setValidationError:response message:@"assurance must be one of: no_verification, verified_by_adult, verified_by_method"];
                           return;
                       }

                       NSString *now = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]];

                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{
                           @"assurance": assurance,
                           @"verifiedAt": now
                       }];
                     }];

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_unspecced_getAgeAssuranceState
                     handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{
                           @"assurance": @"no_verification",
                           @"verifiedAt": [NSNull null]
                       }];
                     }];

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_unspecced_confirmAgeAssurance
                     handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                       NSDictionary *body = request.jsonBody;
                       BOOL typeMismatch = NO;
                       NSString *token = AuthTypedValue(body, @"token", [NSString class], &typeMismatch);
                       if (typeMismatch) {
                           [ATProtoXrpcErrorHelper setValidationError:response message:@"Request field has wrong type"];
                           return;
                       }

                       if (!token || token.length == 0) {
                           [ATProtoXrpcErrorHelper setValidationError:response message:@"token parameter is required"];
                           return;
                       }

                       if (ageAssuranceService) {
                           NSError *error = nil;
                           if ([ageAssuranceService confirmAgeAssuranceWithToken:token error:&error]) {
                               response.statusCode = HttpStatusOK;
                               [response setJsonBody:@{}];
                           } else {
                               if (error.code == 404) {
                                   [ATProtoXrpcErrorHelper setValidationError:response message:error.localizedDescription];
                               } else {
                                   [ATProtoXrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
                               }
                           }
                       } else {
                           response.statusCode = HttpStatusOK;
                           [response setJsonBody:@{}];
                       }
                     }];

#pragma mark - User Discovery (Onboarding & Discovery Pages)

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_unspecced_getOnboardingSuggestedUsersSkeleton
                     handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"actors" : @[]}];
                     }];

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_unspecced_getSuggestedOnboardingUsers
                     handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"actors" : @[]}];
                     }];

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_unspecced_getSuggestedUsersForDiscover
                     handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"actors" : @[]}];
                     }];

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_unspecced_getSuggestedUsersForDiscoverSkeleton
                     handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"actors" : @[]}];
                     }];

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_unspecced_getSuggestedUsersForExplore
                     handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"actors" : @[]}];
                     }];

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_unspecced_getSuggestedUsersForExploreSkeleton
                     handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"actors" : @[]}];
                     }];

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_unspecced_getSuggestedUsersForSeeMore
                     handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"actors" : @[]}];
                     }];

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_unspecced_getSuggestedUsersForSeeMoreSkeleton
                     handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"actors" : @[]}];
                     }];

  // app.bsky.unspecced.getTrends
  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_unspecced_getTrends
                     handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                       NSString *limitParam = [request queryParamForKey:@"limit"];
                       NSInteger limit = 10;
                       if (limitParam) {
                         limit = [limitParam integerValue];
                         if (limit < 1) limit = 1;
                         if (limit > 25) limit = 25;
                       }

                       // Return empty trends - would need trending topic analysis
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"trends" : @[]}];
                     }];
}

@end
