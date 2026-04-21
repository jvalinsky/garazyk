#import "Network/AppViewXRpcRoutePack.h"
#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "AppView/Services/FeedService.h"
#import "AppView/Services/ActorService.h"
#import "AppView/Services/GraphService.h"
#import "AppView/Services/NotificationService.h"
#import "Core/ATProtoCBORSerialization.h"

static NSInteger parseLimitParam(HttpRequest *request, NSInteger defaultLimit, NSInteger maxLimit) {
    NSString *limitParam = [request queryParamForKey:@"limit"];
    NSInteger limit = defaultLimit;
    if (limitParam.length > 0) {
        [[NSScanner scannerWithString:limitParam] scanInteger:&limit];
    }
    return MIN(MAX(limit, 1), maxLimit);
}

@implementation AppViewXRpcRoutePack
{
    FeedService *_feedService;
    ActorService *_actorService;
    GraphService *_graphService;
    NotificationService *_notificationService;
}

- (instancetype)initWithFeedService:(FeedService *)feedService
                      actorService:(ActorService *)actorService
                      graphService:(nullable GraphService *)graphService
                notificationService:(NotificationService *)notificationService
{
    self = [super init];
    if (self)
    {
        _feedService = feedService;
        _actorService = actorService;
        _graphService = graphService;
        _notificationService = notificationService;
    }
    return self;
}

- (void)registerRoutesWithServer:(HttpServer *)server
{
    // --- app.bsky.actor ---
    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.actor.getProfile"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handleGetProfile:request response:response];
             }];

    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.actor.getProfiles"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handleGetProfiles:request response:response];
             }];

    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.actor.searchActors"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handleSearchActors:request response:response];
             }];

    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.actor.searchActorsTypeahead"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handleSearchActorsTypeahead:request response:response];
             }];

    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.actor.getPreferences"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handleGetPreferences:request response:response];
             }];

    [server addRoute:@"POST"
                path:@"/xrpc/app.bsky.actor.putPreferences"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handlePutPreferences:request response:response];
             }];

    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.actor.getSuggestions"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handleGetSuggestions:request response:response];
             }];

    // --- app.bsky.feed ---
    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.feed.getTimeline"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handleGetTimeline:request response:response];
             }];

    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.feed.getAuthorFeed"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handleGetAuthorFeed:request response:response];
             }];

    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.feed.getPostThread"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handleGetPostThread:request response:response];
             }];

    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.feed.getFeed"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handleGetFeed:request response:response];
             }];

    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.feed.getActorLikes"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handleGetActorLikes:request response:response];
             }];

    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.feed.getPosts"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handleGetPosts:request response:response];
             }];

    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.feed.getFeedGenerators"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handleGetFeedGenerators:request response:response];
             }];

    // --- app.bsky.graph ---
    if (_graphService) {
        [server addRoute:@"GET"
                    path:@"/xrpc/app.bsky.graph.getFollows"
                 handler:^(HttpRequest *request, HttpResponse *response) {
                     [self handleGetFollows:request response:response];
                 }];

        [server addRoute:@"GET"
                    path:@"/xrpc/app.bsky.graph.getFollowers"
                 handler:^(HttpRequest *request, HttpResponse *response) {
                     [self handleGetFollowers:request response:response];
                 }];

        [server addRoute:@"GET"
                    path:@"/xrpc/app.bsky.graph.getBlocks"
                 handler:^(HttpRequest *request, HttpResponse *response) {
                     [self handleGetBlocks:request response:response];
                 }];

        [server addRoute:@"GET"
                    path:@"/xrpc/app.bsky.graph.getMutes"
                 handler:^(HttpRequest *request, HttpResponse *response) {
                     [self handleGetMutes:request response:response];
                 }];

        [server addRoute:@"GET"
                    path:@"/xrpc/app.bsky.graph.getRelationships"
                 handler:^(HttpRequest *request, HttpResponse *response) {
                     [self handleGetRelationships:request response:response];
                 }];

        [server addRoute:@"GET"
                    path:@"/xrpc/app.bsky.graph.getLikes"
                 handler:^(HttpRequest *request, HttpResponse *response) {
                     [self handleGetLikes:request response:response];
                 }];

        [server addRoute:@"GET"
                    path:@"/xrpc/app.bsky.graph.getRepostedBy"
                 handler:^(HttpRequest *request, HttpResponse *response) {
                     [self handleGetRepostedBy:request response:response];
                 }];

        [server addRoute:@"GET"
                    path:@"/xrpc/app.bsky.graph.getStarterPack"
                 handler:^(HttpRequest *request, HttpResponse *response) {
                     [self handleGetStarterPack:request response:response];
                 }];

        [server addRoute:@"GET"
                    path:@"/xrpc/app.bsky.graph.getStarterPacks"
                 handler:^(HttpRequest *request, HttpResponse *response) {
                     [self handleGetStarterPacks:request response:response];
                 }];

        [server addRoute:@"POST"
                    path:@"/xrpc/app.bsky.graph.muteActor"
                 handler:^(HttpRequest *request, HttpResponse *response) {
                     [self handleMuteActor:request response:response];
                 }];

        [server addRoute:@"POST"
                    path:@"/xrpc/app.bsky.graph.unmuteActor"
                 handler:^(HttpRequest *request, HttpResponse *response) {
                     [self handleUnmuteActor:request response:response];
                 }];
    }

    // --- app.bsky.notification ---
    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.notification.listNotifications"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handleListNotifications:request response:response];
             }];

    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.notification.getUnreadCount"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handleGetUnreadCount:request response:response];
             }];

    [server addRoute:@"POST"
                path:@"/xrpc/app.bsky.notification.updateSeen"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handleUpdateSeen:request response:response];
             }];

    [server addRoute:@"POST"
                path:@"/xrpc/app.bsky.notification.registerPush"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handleRegisterPush:request response:response];
             }];

    [server addRoute:@"POST"
                path:@"/xrpc/app.bsky.notification.unregisterPush"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handleUnregisterPush:request response:response];
             }];

    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.notification.listActivitySubscriptions"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handleListActivitySubscriptions:request response:response];
             }];

    [server addRoute:@"POST"
                path:@"/xrpc/app.bsky.notification.putActivitySubscription"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handlePutActivitySubscription:request response:response];
             }];

    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.notification.getPreferences"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handleGetNotificationPreferences:request response:response];
             }];

    [server addRoute:@"POST"
                path:@"/xrpc/app.bsky.notification.putPreferences"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handlePutNotificationPreferences:request response:response];
             }];
}

#pragma mark - Auth Helpers

- (NSString *)extractDIDFromAuth:(NSString *)authHeader request:(HttpRequest *)request
{
    if (![authHeader hasPrefix:@"Bearer "])
        return nil;

    NSString *token = [authHeader substringFromIndex:7];
    if (token.length == 0)
        return nil;

    for (NSString *did in @[@"did:plc:", @"did:web:"])
    {
        if ([token hasPrefix:did])
            return token;
    }

    return nil;
}

- (NSString *)requireAuth:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *authHeader = [request headerForKey:@"Authorization"];
    if (!authHeader)
    {
        response.statusCode = 401;
        [response setJsonBody:@{
            @"error": @"AuthenticationRequired",
            @"message": @"Authentication required"
        }];
        return nil;
    }

    NSString *actorDID = [self extractDIDFromAuth:authHeader request:request];
    if (!actorDID)
    {
        response.statusCode = 401;
        [response setJsonBody:@{
            @"error": @"AuthenticationRequired",
            @"message": @"Invalid or expired session"
        }];
        return nil;
    }
    return actorDID;
}

#pragma mark - app.bsky.actor

- (void)handleGetProfile:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actor = [request queryParamForKey:@"actor"];
    if (!actor || actor.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"InvalidRequest",
            @"message": @"actor parameter is required"
        }];
        return;
    }

    NSError *error = nil;
    NSDictionary *profile = [_actorService getProfileForActor:actor error:&error];

    if (error || !profile)
    {
        response.statusCode = 404;
        [response setJsonBody:@{
            @"error": @"ActorNotFound",
            @"message": [NSString stringWithFormat:@"Actor not found: %@", actor]
        }];
        return;
    }

    response.statusCode = 200;
    [response setJsonBody:profile];
}

- (void)handleGetProfiles:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actorsParam = [request queryParamForKey:@"actors"];
    if (!actorsParam || actorsParam.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"InvalidRequest",
            @"message": @"actors parameter is required"
        }];
        return;
    }

    NSArray<NSString *> *actorDIDs = [actorsParam componentsSeparatedByString:@","];
    NSError *error = nil;
    NSArray *profiles = [_actorService getProfilesForActors:actorDIDs error:&error];

    if (error)
    {
        response.statusCode = 500;
        [response setJsonBody:@{
            @"error": @"InternalServerError",
            @"message": error.localizedDescription ?: @"Failed to get profiles"
        }];
        return;
    }

    response.statusCode = 200;
    [response setJsonBody:@{ @"profiles": profiles ?: @[] }];
}

- (void)handleSearchActors:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *term = [request queryParamForKey:@"term"] ?: @"";
    NSInteger limit = parseLimitParam(request, 25, 100);
    NSString *cursor = [request queryParamForKey:@"cursor"];

    NSError *error = nil;
    NSDictionary *result = [_actorService searchActors:term limit:limit cursor:cursor error:&error];

    if (error)
    {
        response.statusCode = 500;
        [response setJsonBody:@{
            @"error": @"InternalServerError",
            @"message": error.localizedDescription ?: @"Search failed"
        }];
        return;
    }

    response.statusCode = 200;
    [response setJsonBody:result ?: @{ @"actors": @[] }];
}

- (void)handleSearchActorsTypeahead:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *term = [request queryParamForKey:@"term"] ?: @"";
    NSInteger limit = parseLimitParam(request, 20, 100);

    NSError *error = nil;
    NSArray *actors = [_actorService searchActorsTypeahead:term limit:limit error:&error];

    if (error)
    {
        response.statusCode = 500;
        [response setJsonBody:@{
            @"error": @"InternalServerError",
            @"message": error.localizedDescription ?: @"Search failed"
        }];
        return;
    }

    response.statusCode = 200;
    [response setJsonBody:@{ @"actors": actors ?: @[] }];
}

- (void)handleGetPreferences:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actorDID = [self requireAuth:request response:response];
    if (!actorDID) return;

    NSError *error = nil;
    NSDictionary *prefs = [_actorService getPreferencesForActor:actorDID error:&error];

    if (error)
    {
        response.statusCode = 500;
        [response setJsonBody:@{
            @"error": @"InternalServerError",
            @"message": error.localizedDescription ?: @"Failed to get preferences"
        }];
        return;
    }

    response.statusCode = 200;
    [response setJsonBody:prefs ?: @{ @"preferences": @[] }];
}

- (void)handlePutPreferences:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actorDID = [self requireAuth:request response:response];
    if (!actorDID) return;

    NSData *bodyData = request.body;
    if (!bodyData || bodyData.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"InvalidRequest",
            @"message": @"Request body required"
        }];
        return;
    }

    NSError *jsonError = nil;
    NSDictionary *body = [NSJSONSerialization JSONObjectWithData:bodyData options:0 error:&jsonError];
    if (!body)
    {
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"InvalidRequest",
            @"message": @"Invalid JSON body"
        }];
        return;
    }

    NSArray *preferences = body[@"preferences"];
    if (!preferences)
    {
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"InvalidRequest",
            @"message": @"preferences field required"
        }];
        return;
    }

    NSError *error = nil;
    BOOL success = [_actorService putPreferencesForActor:actorDID preferences:preferences error:&error];

    if (!success)
    {
        response.statusCode = 500;
        [response setJsonBody:@{
            @"error": @"InternalServerError",
            @"message": error.localizedDescription ?: @"Failed to update preferences"
        }];
        return;
    }

    response.statusCode = 200;
    [response setJsonBody:@{}];
}

- (void)handleGetSuggestions:(HttpRequest *)request response:(HttpResponse *)response
{
    // Suggestions require a recommendation engine; return empty for now
    response.statusCode = 200;
    [response setJsonBody:@{ @"actors": @[] }];
}

#pragma mark - app.bsky.feed

- (void)handleGetTimeline:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actorDID = [self requireAuth:request response:response];
    if (!actorDID) return;

    NSInteger limit = parseLimitParam(request, 50, 100);
    NSString *cursor = [request queryParamForKey:@"cursor"];
    NSString *algorithm = [request queryParamForKey:@"algorithm"];

    NSError *error = nil;
    NSDictionary *result = [_feedService getTimelineForActor:actorDID limit:limit cursor:cursor error:&error];

    if (error)
    {
        response.statusCode = 500;
        [response setJsonBody:@{
            @"error": @"InternalServerError",
            @"message": error.localizedDescription ?: @"Failed to get timeline"
        }];
        return;
    }

    (void)algorithm;
    response.statusCode = 200;
    [response setJsonBody:result ?: @{}];
}

- (void)handleGetAuthorFeed:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actor = [request queryParamForKey:@"actor"];
    if (!actor || actor.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"InvalidRequest",
            @"message": @"actor parameter is required"
        }];
        return;
    }

    NSInteger limit = parseLimitParam(request, 50, 100);
    NSString *cursor = [request queryParamForKey:@"cursor"];
    NSString *filter = [request queryParamForKey:@"filter"];

    NSError *error = nil;
    NSDictionary *result = [_feedService getAuthorFeedForActor:actor limit:limit cursor:cursor filter:filter error:&error];

    if (error)
    {
        response.statusCode = 500;
        [response setJsonBody:@{
            @"error": @"InternalServerError",
            @"message": error.localizedDescription ?: @"Failed to get author feed"
        }];
        return;
    }

    response.statusCode = 200;
    [response setJsonBody:result ?: @{}];
}

- (void)handleGetPostThread:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *uri = [request queryParamForKey:@"uri"];
    if (!uri || uri.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"InvalidRequest",
            @"message": @"uri parameter is required"
        }];
        return;
    }

    NSString *depthParam = [request queryParamForKey:@"depth"];
    NSInteger depth = 10;
    if (depthParam.length > 0)
    {
        [[NSScanner scannerWithString:depthParam] scanInteger:&depth];
    }
    depth = MIN(MAX(depth, 0), 100);

    NSError *error = nil;
    NSDictionary *result = [_feedService getPostThread:uri depth:depth error:&error];

    if (error)
    {
        response.statusCode = 404;
        [response setJsonBody:@{
            @"error": @"NotFound",
            @"message": error.localizedDescription ?: @"Post thread not found"
        }];
        return;
    }

    response.statusCode = 200;
    [response setJsonBody:result ?: @{}];
}

- (void)handleGetFeed:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *feedURI = [request queryParamForKey:@"feed"];
    if (!feedURI || feedURI.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"InvalidRequest",
            @"message": @"feed parameter is required"
        }];
        return;
    }

    NSInteger limit = parseLimitParam(request, 50, 100);
    NSString *cursor = [request queryParamForKey:@"cursor"];

    NSError *error = nil;
    NSDictionary *result = [_feedService getFeed:feedURI limit:limit cursor:cursor error:&error];

    if (error)
    {
        response.statusCode = 500;
        [response setJsonBody:@{
            @"error": @"InternalServerError",
            @"message": error.localizedDescription ?: @"Failed to get feed"
        }];
        return;
    }

    response.statusCode = 200;
    [response setJsonBody:result ?: @{}];
}

- (void)handleGetActorLikes:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actor = [request queryParamForKey:@"actor"];
    if (!actor || actor.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"InvalidRequest",
            @"message": @"actor parameter is required"
        }];
        return;
    }

    NSInteger limit = parseLimitParam(request, 50, 100);
    NSString *cursor = [request queryParamForKey:@"cursor"];

    NSError *error = nil;
    NSDictionary *result = [_feedService getActorLikes:actor limit:limit cursor:cursor error:&error];

    if (error)
    {
        response.statusCode = 500;
        [response setJsonBody:@{
            @"error": @"InternalServerError",
            @"message": error.localizedDescription ?: @"Failed to get actor likes"
        }];
        return;
    }

    response.statusCode = 200;
    [response setJsonBody:result ?: @{}];
}

- (void)handleGetPosts:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *urisParam = [request queryParamForKey:@"uris"];
    if (!urisParam || urisParam.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"InvalidRequest",
            @"message": @"uris parameter is required"
        }];
        return;
    }

    NSArray<NSString *> *uris = [urisParam componentsSeparatedByString:@","];
    NSError *error = nil;
    NSDictionary *result = [_feedService getPosts:uris error:&error];

    if (error)
    {
        response.statusCode = 500;
        [response setJsonBody:@{
            @"error": @"InternalServerError",
            @"message": error.localizedDescription ?: @"Failed to get posts"
        }];
        return;
    }

    response.statusCode = 200;
    [response setJsonBody:result ?: @{ @"posts": @[] }];
}

- (void)handleGetFeedGenerators:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *urisParam = [request queryParamForKey:@"uris"];
    if (!urisParam || urisParam.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"InvalidRequest",
            @"message": @"uris parameter is required"
        }];
        return;
    }

    NSArray<NSString *> *uris = [urisParam componentsSeparatedByString:@","];
    NSError *error = nil;
    NSDictionary *result = [_feedService getFeedGenerators:uris error:&error];

    if (error)
    {
        response.statusCode = 500;
        [response setJsonBody:@{
            @"error": @"InternalServerError",
            @"message": error.localizedDescription ?: @"Failed to get feed generators"
        }];
        return;
    }

    response.statusCode = 200;
    [response setJsonBody:result ?: @{ @"feeds": @[] }];
}

#pragma mark - app.bsky.graph

- (void)handleGetFollows:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actor = [request queryParamForKey:@"actor"];
    if (!actor || actor.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"actor parameter is required" }];
        return;
    }

    NSInteger limit = parseLimitParam(request, 50, 100);
    NSString *cursor = [request queryParamForKey:@"cursor"];
    NSError *error = nil;
    NSDictionary *result = [_graphService getFollowsForActor:actor limit:limit cursor:cursor error:&error];
    if (error) { response.statusCode = 500; [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription ?: @"Failed" }]; return; }
    response.statusCode = 200;
    [response setJsonBody:result ?: @{}];
}

- (void)handleGetFollowers:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actor = [request queryParamForKey:@"actor"];
    if (!actor || actor.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"actor parameter is required" }];
        return;
    }

    NSInteger limit = parseLimitParam(request, 50, 100);
    NSString *cursor = [request queryParamForKey:@"cursor"];
    NSError *error = nil;
    NSDictionary *result = [_graphService getFollowersForActor:actor limit:limit cursor:cursor error:&error];
    if (error) { response.statusCode = 500; [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription ?: @"Failed" }]; return; }
    response.statusCode = 200;
    [response setJsonBody:result ?: @{}];
}

- (void)handleGetBlocks:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actorDID = [self requireAuth:request response:response];
    if (!actorDID) return;

    NSInteger limit = parseLimitParam(request, 50, 100);
    NSString *cursor = [request queryParamForKey:@"cursor"];
    NSError *error = nil;
    NSDictionary *result = [_graphService getBlocksForActor:actorDID limit:limit cursor:cursor error:&error];
    if (error) { response.statusCode = 500; [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription ?: @"Failed" }]; return; }
    response.statusCode = 200;
    [response setJsonBody:result ?: @{}];
}

- (void)handleGetMutes:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actorDID = [self requireAuth:request response:response];
    if (!actorDID) return;

    NSInteger limit = parseLimitParam(request, 50, 100);
    NSString *cursor = [request queryParamForKey:@"cursor"];
    NSError *error = nil;
    NSDictionary *result = [_graphService getMutesForActor:actorDID limit:limit cursor:cursor error:&error];
    if (error) { response.statusCode = 500; [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription ?: @"Failed" }]; return; }
    response.statusCode = 200;
    [response setJsonBody:result ?: @{}];
}

- (void)handleGetRelationships:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actorDID = [self requireAuth:request response:response];
    if (!actorDID) return;

    NSString *target = [request queryParamForKey:@"target"];
    if (!target || target.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"target parameter is required" }];
        return;
    }

    NSError *error = nil;
    NSDictionary *result = [_graphService getRelationship:actorDID withActor:target error:&error];
    if (error) { response.statusCode = 500; [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription ?: @"Failed" }]; return; }
    response.statusCode = 200;
    [response setJsonBody:@{ @"relationships": result ? @[result] : @[] }];
}

- (void)handleGetLikes:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *uri = [request queryParamForKey:@"uri"];
    if (!uri || uri.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"uri parameter is required" }];
        return;
    }

    NSInteger limit = parseLimitParam(request, 50, 100);
    NSString *cursor = [request queryParamForKey:@"cursor"];
    NSError *error = nil;
    NSDictionary *result = [_graphService getLikesForURI:uri limit:limit cursor:cursor error:&error];
    if (error) { response.statusCode = 500; [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription ?: @"Failed" }]; return; }
    response.statusCode = 200;
    [response setJsonBody:result ?: @{}];
}

- (void)handleGetRepostedBy:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *uri = [request queryParamForKey:@"uri"];
    if (!uri || uri.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"uri parameter is required" }];
        return;
    }

    NSInteger limit = parseLimitParam(request, 50, 100);
    NSString *cursor = [request queryParamForKey:@"cursor"];
    NSError *error = nil;
    NSDictionary *result = [_graphService getRepostedByForURI:uri limit:limit cursor:cursor error:&error];
    if (error) { response.statusCode = 500; [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription ?: @"Failed" }]; return; }
    response.statusCode = 200;
    [response setJsonBody:result ?: @{}];
}

- (void)handleGetStarterPack:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *uri = [request queryParamForKey:@"uri"];
    if (!uri || uri.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"uri parameter is required" }];
        return;
    }

    NSError *error = nil;
    NSDictionary *result = [_graphService getStarterPack:uri error:&error];
    if (error || !result) { response.statusCode = 404; [response setJsonBody:@{ @"error": @"NotFound", @"message": @"Starter pack not found" }]; return; }
    response.statusCode = 200;
    [response setJsonBody:@{ @"starterPack": result }];
}

- (void)handleGetStarterPacks:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actor = [request queryParamForKey:@"actor"];
    if (!actor || actor.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"actor parameter is required" }];
        return;
    }

    NSInteger limit = parseLimitParam(request, 50, 100);
    NSString *cursor = [request queryParamForKey:@"cursor"];
    NSError *error = nil;
    NSDictionary *result = [_graphService getStarterPacksForActor:actor limit:limit cursor:cursor error:&error];
    if (error) { response.statusCode = 500; [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription ?: @"Failed" }]; return; }
    response.statusCode = 200;
    [response setJsonBody:result ?: @{ @"starterPacks": @[] }];
}

- (void)handleMuteActor:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actorDID = [self requireAuth:request response:response];
    if (!actorDID) return;

    NSData *bodyData = request.body;
    if (!bodyData || bodyData.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"Request body required" }];
        return;
    }

    NSError *jsonError = nil;
    NSDictionary *body = [NSJSONSerialization JSONObjectWithData:bodyData options:0 error:&jsonError];
    NSString *targetDID = body[@"actor"];
    if (!targetDID || targetDID.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"actor field required in body" }];
        return;
    }

    NSError *error = nil;
    BOOL success = [_graphService muteActor:targetDID forActor:actorDID error:&error];
    if (!success) { response.statusCode = 500; [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription ?: @"Failed" }]; return; }
    response.statusCode = 200;
    [response setJsonBody:@{}];
}

- (void)handleUnmuteActor:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actorDID = [self requireAuth:request response:response];
    if (!actorDID) return;

    NSData *bodyData = request.body;
    if (!bodyData || bodyData.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"Request body required" }];
        return;
    }

    NSError *jsonError = nil;
    NSDictionary *body = [NSJSONSerialization JSONObjectWithData:bodyData options:0 error:&jsonError];
    NSString *targetDID = body[@"actor"];
    if (!targetDID || targetDID.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"actor field required in body" }];
        return;
    }

    NSError *error = nil;
    BOOL success = [_graphService unmuteActor:targetDID forActor:actorDID error:&error];
    if (!success) { response.statusCode = 500; [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription ?: @"Failed" }]; return; }
    response.statusCode = 200;
    [response setJsonBody:@{}];
}

#pragma mark - app.bsky.notification

- (void)handleListNotifications:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actorDID = [self requireAuth:request response:response];
    if (!actorDID) return;

    NSInteger limit = parseLimitParam(request, 50, 100);
    NSString *cursor = [request queryParamForKey:@"cursor"];
    NSError *error = nil;
    NSArray *notifications = [_notificationService getNotificationsForActor:actorDID limit:limit cursor:cursor error:&error];

    if (error)
    {
        response.statusCode = 500;
        [response setJsonBody:@{
            @"error": @"InternalServerError",
            @"message": error.localizedDescription ?: @"Failed to list notifications"
        }];
        return;
    }

    response.statusCode = 200;
    [response setJsonBody:@{
        @"notifications": notifications ?: @[],
        @"cursor": cursor ?: [NSNull null]
    }];
}

- (void)handleGetUnreadCount:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actorDID = [self requireAuth:request response:response];
    if (!actorDID) return;

    NSError *error = nil;
    NSInteger count = [_notificationService getUnreadCountForActor:actorDID error:&error];

    if (error)
    {
        response.statusCode = 500;
        [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription ?: @"Failed" }];
        return;
    }

    response.statusCode = 200;
    [response setJsonBody:@{ @"count": @(count) }];
}

- (void)handleUpdateSeen:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actorDID = [self requireAuth:request response:response];
    if (!actorDID) return;

    NSData *bodyData = request.body;
    NSInteger limit = 0;
    if (bodyData && bodyData.length > 0)
    {
        NSError *jsonError = nil;
        NSDictionary *body = [NSJSONSerialization JSONObjectWithData:bodyData options:0 error:&jsonError];
        if (body[@"limit"])
        {
            [[NSScanner scannerWithString:[body[@"limit"] description]] scanInteger:&limit];
        }
    }

    NSError *error = nil;
    BOOL success = [_notificationService markNotificationsAsReadForActor:actorDID limit:limit error:&error];
    if (!success) { response.statusCode = 500; [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription ?: @"Failed" }]; return; }
    response.statusCode = 200;
    [response setJsonBody:@{}];
}

- (void)handleRegisterPush:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actorDID = [self requireAuth:request response:response];
    if (!actorDID) return;

    NSData *bodyData = request.body;
    if (!bodyData || bodyData.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"Request body required" }];
        return;
    }

    NSError *jsonError = nil;
    NSDictionary *body = [NSJSONSerialization JSONObjectWithData:bodyData options:0 error:&jsonError];
    NSString *deviceToken = body[@"deviceToken"];
    NSString *platformToken = body[@"platformToken"];
    NSString *serviceEndpoint = body[@"serviceEndpoint"];

    if (!deviceToken || deviceToken.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"deviceToken required" }];
        return;
    }

    NSError *error = nil;
    BOOL success = [_notificationService registerPushForActor:actorDID
                                                  deviceToken:deviceToken
                                                platformToken:platformToken
                                              serviceEndpoint:serviceEndpoint ?: @""
                                                        error:&error];
    if (!success) { response.statusCode = 500; [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription ?: @"Failed" }]; return; }
    response.statusCode = 200;
    [response setJsonBody:@{}];
}

- (void)handleUnregisterPush:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actorDID = [self requireAuth:request response:response];
    if (!actorDID) return;

    NSError *error = nil;
    BOOL success = [_notificationService unregisterPushForActor:actorDID error:&error];
    if (!success) { response.statusCode = 500; [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription ?: @"Failed" }]; return; }
    response.statusCode = 200;
    [response setJsonBody:@{}];
}

- (void)handleListActivitySubscriptions:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actorDID = [self requireAuth:request response:response];
    if (!actorDID) return;

    NSInteger limit = parseLimitParam(request, 50, 100);
    NSString *cursor = [request queryParamForKey:@"cursor"];
    NSError *error = nil;
    NSDictionary *result = [_notificationService getActivitySubscriptionsForActor:actorDID limit:limit cursor:cursor error:&error];
    if (error) { response.statusCode = 500; [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription ?: @"Failed" }]; return; }
    response.statusCode = 200;
    [response setJsonBody:result ?: @{ @"subscriptions": @[] }];
}

- (void)handlePutActivitySubscription:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actorDID = [self requireAuth:request response:response];
    if (!actorDID) return;

    NSData *bodyData = request.body;
    if (!bodyData || bodyData.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"Request body required" }];
        return;
    }

    NSError *jsonError = nil;
    NSDictionary *body = [NSJSONSerialization JSONObjectWithData:bodyData options:0 error:&jsonError];
    NSString *subjectDID = body[@"subject"];
    if (!subjectDID || subjectDID.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"subject required" }];
        return;
    }

    BOOL postEnabled = body[@"postEnabled"] ? [body[@"postEnabled"] boolValue] : YES;
    BOOL replyEnabled = body[@"replyEnabled"] ? [body[@"replyEnabled"] boolValue] : YES;

    NSError *error = nil;
    BOOL success = [_notificationService putActivitySubscriptionForActor:actorDID
                                                                subject:subjectDID
                                                             postEnabled:postEnabled
                                                            replyEnabled:replyEnabled
                                                                   error:&error];
    if (!success) { response.statusCode = 500; [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription ?: @"Failed" }]; return; }
    response.statusCode = 200;
    [response setJsonBody:@{}];
}

- (void)handleGetNotificationPreferences:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actorDID = [self requireAuth:request response:response];
    if (!actorDID) return;

    NSError *error = nil;
    NSDictionary *prefs = [_notificationService getPreferencesForActor:actorDID error:&error];

    if (error)
    {
        response.statusCode = 500;
        [response setJsonBody:@{
            @"error": @"InternalServerError",
            @"message": error.localizedDescription ?: @"Failed to get preferences"
        }];
        return;
    }

    response.statusCode = 200;
    [response setJsonBody:prefs ?: @{ @"preferences": @[] }];
}

- (void)handlePutNotificationPreferences:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actorDID = [self requireAuth:request response:response];
    if (!actorDID) return;

    NSData *bodyData = request.body;
    if (!bodyData || bodyData.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"Request body required" }];
        return;
    }

    NSError *jsonError = nil;
    NSDictionary *body = [NSJSONSerialization JSONObjectWithData:bodyData options:0 error:&jsonError];
    if (!body)
    {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"Invalid JSON body" }];
        return;
    }

    NSArray *preferences = body[@"preferences"];
    if (!preferences)
    {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"preferences field required" }];
        return;
    }

    NSError *error = nil;
    BOOL success = [_notificationService putPreferencesForActor:actorDID preferences:preferences error:&error];

    if (!success)
    {
        response.statusCode = 500;
        [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription ?: @"Failed" }];
        return;
    }

    response.statusCode = 200;
    [response setJsonBody:@{}];
}

@end
