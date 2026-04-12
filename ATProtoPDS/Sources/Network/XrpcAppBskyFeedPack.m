#import "Network/XrpcAppBskyFeedPack.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcAuthHelper.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "AppView/FeedService.h"
#import "AppView/ActorService.h"
#import "Debug/PDSLogger.h"

static BOOL parseIntegerParam(NSString *value, NSInteger *outValue, NSInteger defaultValue) {
    if (!value || value.length == 0) {
        if (outValue) *outValue = defaultValue;
        return YES;
    }
    NSScanner *scanner = [NSScanner scannerWithString:value];
    NSInteger parsed = 0;
    if (![scanner scanInteger:&parsed] || !scanner.isAtEnd) {
        return NO;
    }
    if (outValue) *outValue = parsed;
    return YES;
}

@implementation XrpcAppBskyFeedPack

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                 appViewDatabase:(PDSDatabase *)appViewDatabase
                      jwtMinter:(JWTMinter *)jwtMinter
                adminController:(id<PDSAdminController>)adminController {

    FeedService *feedService = [[FeedService alloc] initWithDatabase:appViewDatabase];
    ActorService *actorService = [[ActorService alloc] initWithDatabase:appViewDatabase];

    // app.bsky.feed.getAuthorFeed
    [dispatcher registerAppBskyFeedGetAuthorFeed:^(HttpRequest *request, HttpResponse *response) {
        NSString *actor = [request queryParamForKey:@"actor"];
        if (!actor) {
            [XrpcErrorHelper setValidationError:response message:@"Missing actor parameter"];
            return;
        }
        NSInteger limit = 50;
        NSString *limitParam = request.queryParams[@"limit"];
        if (limitParam && limitParam.length > 0) {
            parseIntegerParam(limitParam, &limit, 50);
        }
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSString *filter = [request queryParamForKey:@"filter"];
        NSError *error = nil;
        NSDictionary *result = [feedService getAuthorFeedForActor:actor limit:limit cursor:cursor filter:filter error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    // app.bsky.feed.getTimeline
    [dispatcher registerAppBskyFeedGetTimeline:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        if (!authHeader) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required for timeline"];
            return;
        }
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                            jwtMinter:jwtMinter
                                                      adminController:adminController
                                                              request:request
                                                             response:response];
        if (!actorDID) return;
        NSInteger limit = 50;
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSError *error = nil;
        NSDictionary *result = [feedService getTimelineForActor:actorDID limit:limit cursor:cursor error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    // app.bsky.feed.getActorLikes
    [dispatcher registerAppBskyFeedGetActorLikes:^(HttpRequest *request, HttpResponse *response) {
        NSString *actor = [request queryParamForKey:@"actor"];
        if (!actor) {
            [XrpcErrorHelper setValidationError:response message:@"Missing actor parameter"];
            return;
        }
        NSInteger limit = 50;
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSError *error = nil;
        NSDictionary *result = [feedService getActorLikes:actor limit:limit cursor:cursor error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    // app.bsky.feed.getPostThread
    [dispatcher registerAppBskyFeedGetPostThread:^(HttpRequest *request, HttpResponse *response) {
        NSString *uri = [request queryParamForKey:@"uri"];
        if (!uri) {
            [XrpcErrorHelper setValidationError:response message:@"Missing uri parameter"];
            return;
        }
        NSInteger depth = 6;
        NSString *depthParam = [request queryParamForKey:@"depth"];
        if (depthParam) parseIntegerParam(depthParam, &depth, 6);
        NSError *error = nil;
        NSDictionary *result = [feedService getPostThread:uri depth:depth error:&error];
        if (error) {
            [XrpcErrorHelper setNotFoundError:response message:error.localizedDescription];
            return;
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    // app.bsky.feed.getFeed
    [dispatcher registerAppBskyFeedGetFeed:^(HttpRequest *request, HttpResponse *response) {
        NSString *feed = [request queryParamForKey:@"feed"];
        if (!feed) {
            [XrpcErrorHelper setValidationError:response message:@"Missing feed parameter"];
            return;
        }
        NSInteger limit = 50;
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSError *error = nil;
        NSDictionary *result = [feedService getFeed:feed limit:limit cursor:cursor error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    // app.bsky.feed.getPosts
    [dispatcher registerAppBskyFeedGetPosts:^(HttpRequest *request, HttpResponse *response) {
        id urisParam = request.queryParams[@"uris"];
        NSArray<NSString *> *uris = nil;
        if ([urisParam isKindOfClass:[NSArray class]]) {
            uris = urisParam;
        } else if ([urisParam isKindOfClass:[NSString class]]) {
            uris = @[urisParam];
        } else {
            [XrpcErrorHelper setValidationError:response message:@"Missing uris parameter"];
            return;
        }
        NSError *error = nil;
        NSDictionary *result = [feedService getPosts:uris error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    // app.bsky.feed.getFeedGenerators
    [dispatcher registerAppBskyFeedGetFeedGenerators:^(HttpRequest *request, HttpResponse *response) {
        id feedsParam = request.queryParams[@"feeds"];
        NSArray<NSString *> *feedURIs = nil;
        if ([feedsParam isKindOfClass:[NSArray class]]) {
            feedURIs = (NSArray<NSString *> *)feedsParam;
        } else if ([feedsParam isKindOfClass:[NSString class]]) {
            feedURIs = @[(NSString *)feedsParam];
        } else {
            [XrpcErrorHelper setValidationError:response message:@"Missing feeds parameter"];
            return;
        }
        NSMutableArray<NSDictionary *> *feeds = [NSMutableArray arrayWithCapacity:feedURIs.count];
        for (NSString *feedURI in feedURIs) {
            [feeds addObject:@{@"uri": feedURI, @"did": @"", @"creator": @{@"did": @"", @"handle": @"", @"displayName": @""}}];
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"feeds": feeds}];
    }];

    PDS_LOG_INFO(@"Registered app.bsky.feed.* endpoints");
}

@end
