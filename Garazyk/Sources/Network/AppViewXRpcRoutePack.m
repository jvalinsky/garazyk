#import "Network/AppViewXRpcRoutePack.h"
#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcAuthHelper.h"
#import "Debug/PDSLogger.h"
#import "Auth/JWT.h"
#import "AppView/Services/FeedService.h"
#import "AppView/Services/ActorService.h"
#import "AppView/Services/GraphService.h"
#import "AppView/Services/NotificationService.h"
#import "AppView/Services/AgeAssuranceService.h"
#import "AppView/Services/DraftService.h"
#import "AppView/Services/BookmarkService.h"
#import "AppView/Services/ContactService.h"
#import "AppView/Services/SearchIndexService.h"
#import "Core/ATProtoCBORSerialization.h"
#import "Core/DID.h"

static NSInteger parseLimitParam(HttpRequest *request, NSInteger defaultLimit, NSInteger maxLimit) {
    NSString *limitParam = [request queryParamForKey:@"limit"];
    NSInteger limit = defaultLimit;
    if (limitParam.length > 0) {
        [[NSScanner scannerWithString:limitParam] scanInteger:&limit];
    }
    return MIN(MAX(limit, 1), maxLimit);
}

#import "AppView/Server/WriteProxy/AppViewWriteProxy.h"

@implementation AppViewXRpcRoutePack {
    FeedService *_feedService;
    ActorService *_actorService;
    GraphService *_graphService;
    NotificationService *_notificationService;
    AgeAssuranceService *_ageAssuranceService;
    DraftService *_draftService;
    BookmarkService *_bookmarkService;
    ContactService *_contactService;
    SearchIndexService *_searchIndexService;
    AppViewWriteProxy *_writeProxy;
    id<PDSQueryDatabase> _database;
    JWTMinter *_jwtMinter;
}

- (instancetype)initWithFeedService:(FeedService *)feedService
                       actorService:(ActorService *)actorService
                       graphService:(nullable GraphService *)graphService
                 notificationService:(NotificationService *)notificationService
                ageAssuranceService:(nullable AgeAssuranceService *)ageAssuranceService
                        draftService:(nullable DraftService *)draftService
                     bookmarkService:(nullable BookmarkService *)bookmarkService
                      contactService:(nullable ContactService *)contactService
                  searchIndexService:(nullable SearchIndexService *)searchIndexService
                         writeProxy:(nullable AppViewWriteProxy *)writeProxy
                          database:(nullable id<PDSQueryDatabase>)database
                         jwtMinter:(nullable JWTMinter *)jwtMinter
{
    self = [super init];
    if (self) {
        _feedService = feedService;
        _actorService = actorService;
        _graphService = graphService;
        _notificationService = notificationService;
        _ageAssuranceService = ageAssuranceService;
        _draftService = draftService;
        _bookmarkService = bookmarkService;
        _contactService = contactService;
        _searchIndexService = searchIndexService;
        _writeProxy = writeProxy;
        _database = database;
        _jwtMinter = jwtMinter;
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

    // --- app.bsky.draft ---
    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.draft.getDrafts"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handleGetDrafts:request response:response];
             }];

    // --- app.bsky.bookmark ---
    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.bookmark.getBookmarks"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handleGetBookmarks:request response:response];
             }];

    // --- app.bsky.graph (additional) ---
    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.graph.getStarterPacks"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handleGetStarterPacksBulk:request response:response];
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

    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.feed.getLikes"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handleGetLikes:request response:response];
             }];

    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.feed.getRepostedBy"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handleGetRepostedBy:request response:response];
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
                    path:@"/xrpc/app.bsky.graph.getStarterPack"
                 handler:^(HttpRequest *request, HttpResponse *response) {
                     [self handleGetStarterPack:request response:response];
                 }];

        [server addRoute:@"GET"
                    path:@"/xrpc/app.bsky.graph.getActorStarterPacks"
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

        // --- app.bsky.contact ---
        [server addRoute:@"POST"
                    path:@"/xrpc/app.bsky.contact.startPhoneVerification"
                 handler:^(HttpRequest *request, HttpResponse *response) {
                     [self handleStartPhoneVerification:request response:response];
                 }];

        [server addRoute:@"POST"
                    path:@"/xrpc/app.bsky.contact.verifyPhone"
                 handler:^(HttpRequest *request, HttpResponse *response) {
                     [self handleVerifyPhone:request response:response];
                 }];

        [server addRoute:@"POST"
                    path:@"/xrpc/app.bsky.contact.importContacts"
                 handler:^(HttpRequest *request, HttpResponse *response) {
                     [self handleImportContacts:request response:response];
                 }];

        [server addRoute:@"GET"
                    path:@"/xrpc/app.bsky.contact.getMatches"
                 handler:^(HttpRequest *request, HttpResponse *response) {
                     [self handleGetContactMatches:request response:response];
                 }];

        [server addRoute:@"POST"
                    path:@"/xrpc/app.bsky.contact.dismissMatch"
                 handler:^(HttpRequest *request, HttpResponse *response) {
                     [self handleDismissContactMatch:request response:response];
                 }];

        [server addRoute:@"GET"
                    path:@"/xrpc/app.bsky.contact.getSyncStatus"
                 handler:^(HttpRequest *request, HttpResponse *response) {
                     [self handleGetContactSyncStatus:request response:response];
                 }];

        [server addRoute:@"POST"
                    path:@"/xrpc/app.bsky.contact.removeData"
                 handler:^(HttpRequest *request, HttpResponse *response) {
                     [self handleRemoveContactData:request response:response];
                 }];

    }

    if (_writeProxy) {
        [server addRoute:@"POST"
                    path:@"/xrpc/com.atproto.repo.createRecord"
                 handler:^(HttpRequest *request, HttpResponse *response) {
                     [self handleProxyWrite:request response:response nsid:@"com.atproto.repo.createRecord"];
                 }];
        [server addRoute:@"POST"
                    path:@"/xrpc/com.atproto.repo.putRecord"
                 handler:^(HttpRequest *request, HttpResponse *response) {
                     [self handleProxyWrite:request response:response nsid:@"com.atproto.repo.putRecord"];
                 }];
        [server addRoute:@"POST"
                    path:@"/xrpc/com.atproto.repo.deleteRecord"
                 handler:^(HttpRequest *request, HttpResponse *response) {
                     [self handleProxyWrite:request response:response nsid:@"com.atproto.repo.deleteRecord"];
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

    // --- app.bsky.unspecced search ---
    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.unspecced.searchActorsSkeleton"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handleSearchActorsSkeleton:request response:response];
             }];

    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.unspecced.searchPostsSkeleton"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handleSearchPostsSkeleton:request response:response];
             }];

    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.unspecced.searchStarterPacksSkeleton"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handleSearchStarterPacksSkeleton:request response:response];
             }];

    // --- com.atproto.* (proxied convenience endpoints) ---
    [server addRoute:@"GET"
                path:@"/xrpc/com.atproto.identity.resolveHandle"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handleResolveHandle:request response:response];
             }];

    [server addRoute:@"GET"
                path:@"/xrpc/com.atproto.repo.getRecord"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handleGetRecord:request response:response];
             }];

    [server addRoute:@"GET"
                path:@"/xrpc/com.atproto.label.queryLabels"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handleQueryLabels:request response:response];
             }];

    [server addRoute:@"GET"
                path:@"/xrpc/com.atproto.admin.getAccountInfos"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handleGetAccountInfos:request response:response];
             }];

    [server addRoute:@"GET"
                path:@"/xrpc/com.atproto.admin.getSubjectStatus"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handleGetSubjectStatus:request response:response];
             }];

    // --- app.bsky.ageassurance ---
    [server addRoute:@"POST"
                path:@"/xrpc/app.bsky.ageassurance.begin"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handleAgeAssuranceBegin:request response:response];
             }];

    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.ageassurance.getConfig"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handleAgeAssuranceGetConfig:request response:response];
             }];

    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.ageassurance.getState"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handleAgeAssuranceGetState:request response:response];
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

    // Check if it's a direct DID (for dev/testing)
    for (NSString *prefix in @[@"did:plc:", @"did:web:"])
    {
        if ([token hasPrefix:prefix])
            return token;
    }

    // Attempt to parse as JWT and extract subject (DID)
    NSError *error = nil;
    JWT *jwt = [JWT jwtWithToken:token error:&error];
    if (jwt && jwt.payload.sub) {
        return jwt.payload.sub;
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

    // Attempt to extract DID (supports direct DID for testing or unverified JWT sub)
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

    // Actor can be a DID or handle - query both formats
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
    NSString *term = [request queryParamForKey:@"q"] ?: [request queryParamForKey:@"term"] ?: @"";
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
    NSString *term = [request queryParamForKey:@"q"] ?: [request queryParamForKey:@"term"] ?: @"";
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
    NSString *actorDID = [request queryParamForKey:@"actor"];
    if (!actorDID || ![actorDID isKindOfClass:[NSString class]] || actorDID.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"actor parameter is required" }];
        return;
    }

    id targetObj = [request queryParamForKey:@"others"] ?: [request queryParamForKey:@"subjects"] ?: [request queryParamForKey:@"target"];
    if (!targetObj)
    {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"others parameter is required" }];
        return;
    }

    NSArray *others = [targetObj isKindOfClass:[NSArray class]] ? (NSArray *)targetObj : @[targetObj];
    NSString *primaryTarget = others.firstObject;

    NSError *error = nil;
    NSDictionary *result = [_graphService getRelationship:actorDID withActor:primaryTarget error:&error];
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
    NSString *deviceToken = body[@"token"];
    NSString *platformToken = body[@"platformToken"];
    NSString *serviceEndpoint = body[@"serviceEndpoint"];

    if (!deviceToken || deviceToken.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"token required" }];
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

    if (body[@"priority"] == nil)
    {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"priority field required" }];
        return;
    }
    
    BOOL priority = [body[@"priority"] boolValue];

    NSError *error = nil;
    // We store priority as a preference dictionary
    NSDictionary *prefsObj = @{@"priority": @(priority)};
    BOOL success = [_notificationService putPreferencesForActor:actorDID preferences:(NSArray *)prefsObj error:&error];

    if (!success)
    {
        response.statusCode = 500;
        [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription ?: @"Failed" }];
        return;
    }

    response.statusCode = 200;
    [response setJsonBody:@{}];
}

#pragma mark - com.atproto.* (proxied convenience endpoints)

- (void)handleResolveHandle:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *handle = [request queryParamForKey:@"handle"];
    if (!handle || handle.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"handle parameter is required" }];
        return;
    }

    // Use DIDResolver to resolve the handle
    DIDResolver *resolver = [[DIDResolver alloc] init];
    NSError *error = nil;
    NSString *did = [resolver resolveHandleSync:handle error:&error];

    if (!did)
    {
        response.statusCode = 404;
        [response setJsonBody:@{ @"error": @"HandleNotFound", @"message": [NSString stringWithFormat:@"Handle not found: %@", handle] }];
        return;
    }

    response.statusCode = 200;
    [response setJsonBody:@{ @"did": did }];
}

- (void)handleGetRecord:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *uri = [request queryParamForKey:@"uri"];
    if (!uri || uri.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"uri parameter is required" }];
        return;
    }

    // Parse AT URI: at://<did>/<collection>/<rkey>
    NSArray *components = [uri componentsSeparatedByString:@"/"];
    if (components.count < 5)
    {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"Invalid AT URI format" }];
        return;
    }

    NSString *did = components[2];
    NSString *collection = components[3];
    NSString *rkey = components[4];

    if (!_database)
    {
        response.statusCode = 503;
        [response setJsonBody:@{ @"error": @"ServiceUnavailable", @"message": @"Database not available" }];
        return;
    }

    NSString *query = @"SELECT cid, value FROM records WHERE did = ? AND collection = ? AND rkey = ?";
    NSArray *rows = [_database executeParameterizedQuery:query params:@[did, collection, rkey] error:nil];

    if (!rows || rows.count == 0)
    {
        response.statusCode = 404;
        [response setJsonBody:@{ @"error": @"RecordNotFound", @"message": @"Record not found" }];
        return;
    }

    NSDictionary *row = rows.firstObject;
    NSString *cid = row[@"cid"];
    id valueObj = row[@"value"];

    NSData *data = nil;
    if ([valueObj isKindOfClass:[NSData class]]) {
        data = valueObj;
    } else if ([valueObj isKindOfClass:[NSString class]]) {
        data = [(NSString *)valueObj dataUsingEncoding:NSUTF8StringEncoding];
    }

    NSDictionary *record = nil;
    if (data && data.length > 0)
    {
        record = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    }

    response.statusCode = 200;
    [response setJsonBody:@{
        @"uri": uri,
        @"cid": cid ?: @"",
        @"value": record ?: @{},
        @"did": did,
        @"collection": collection,
        @"rkey": rkey
    }];
}

- (void)handleQueryLabels:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *urisParam = [request queryParamForKey:@"uris"];
    if (!urisParam || urisParam.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"uris parameter is required" }];
        return;
    }

    NSArray<NSString *> *uris = [urisParam componentsSeparatedByString:@","];

    // Query labels from the labels table if it exists
    NSMutableArray *labels = [NSMutableArray array];
    if (_database)
    {
        for (NSString *uri in uris)
        {
            NSString *query = @"SELECT src, uri, cid, val, neg, created_at FROM labels WHERE uri = ?";
            NSArray *rows = [_database executeParameterizedQuery:query params:@[uri] error:nil];
            for (NSDictionary *row in rows)
            {
                [labels addObject:@{
                    @"src": row[@"src"] ?: @"",
                    @"uri": row[@"uri"] ?: uri,
                    @"cid": row[@"cid"] ?: @"",
                    @"val": row[@"val"] ?: @"",
                    @"neg": row[@"neg"] ? @([row[@"neg"] boolValue]) : @(NO),
                    @"cts": row[@"created_at"] ?: @""
                }];
            }
        }
    }

    response.statusCode = 200;
    [response setJsonBody:@{ @"labels": labels }];
}

- (void)handleGetAccountInfos:(HttpRequest *)request response:(HttpResponse *)response
{
    // Admin endpoint - requires auth
    NSString *actorDID = [self requireAuth:request response:response];
    if (!actorDID) return;

    NSString *didsParam = [request queryParamForKey:@"dids"];
    if (!didsParam || didsParam.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"dids parameter is required" }];
        return;
    }

    NSArray<NSString *> *dids = [didsParam componentsSeparatedByString:@","];
    NSMutableArray *accounts = [NSMutableArray array];

    if (_database)
    {
        for (NSString *did in dids)
        {
            NSString *query = @"SELECT did, handle, email, created_at FROM accounts WHERE did = ?";
            NSArray *rows = [_database executeParameterizedQuery:query params:@[did] error:nil];
            if (rows && rows.count > 0)
            {
                NSDictionary *row = rows.firstObject;
                [accounts addObject:@{
                    @"did": row[@"did"] ?: did,
                    @"handle": row[@"handle"] ?: @"",
                    @"email": row[@"email"] ?: @"",
                    @"createdAt": row[@"created_at"] ?: @""
                }];
            }
        }
    }

    response.statusCode = 200;
    [response setJsonBody:@{ @"infos": accounts }];
}

- (void)handleGetSubjectStatus:(HttpRequest *)request response:(HttpResponse *)response
{
    // Admin endpoint - requires auth
    NSString *actorDID = [self requireAuth:request response:response];
    if (!actorDID) return;

    NSString *did = [request queryParamForKey:@"did"];
    NSString *uri = [request queryParamForKey:@"uri"];

    if ((!did || did.length == 0) && (!uri || uri.length == 0))
    {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"did or uri parameter is required" }];
        return;
    }

    // Return basic subject status
    response.statusCode = 200;
    [response setJsonBody:@{
        @"subject": did ? @{ @"did": did } : @{ @"uri": uri },
        @"takedown": @{ @"applied": @(NO) },
        @"review": @{ @"state": @"none" }
    }];
}

#pragma mark - app.bsky.ageassurance

- (void)handleAgeAssuranceBegin:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actorDID = [self requireAuth:request response:response];
    if (!actorDID) return;

    NSDictionary *body = request.jsonBody;
    if (!body || !body[@"email"] || !body[@"language"] || !body[@"countryCode"]) {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"email, language, and countryCode required" }];
        return;
    }

    if (!_ageAssuranceService) {
        response.statusCode = 503;
        [response setJsonBody:@{ @"error": @"ServiceUnavailable", @"message": @"Age assurance service not available" }];
        return;
    }

    NSError *error = nil;
    NSDictionary *result = [_ageAssuranceService beginAgeAssurance:actorDID
                                                             email:body[@"email"]
                                                          language:body[@"language"]
                                                       countryCode:body[@"countryCode"]
                                                        regionCode:body[@"regionCode"]
                                                             error:&error];
    if (error) { response.statusCode = 500; [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription }]; return; }
    response.statusCode = 200;
    [response setJsonBody:result];
}

- (void)handleAgeAssuranceGetConfig:(HttpRequest *)request response:(HttpResponse *)response
{
    if (!_ageAssuranceService) {
        response.statusCode = 503;
        [response setJsonBody:@{ @"error": @"ServiceUnavailable", @"message": @"Age assurance service not available" }];
        return;
    }

    NSError *error = nil;
    NSDictionary *config = [_ageAssuranceService getAgeAssuranceConfig:&error];
    if (error) { response.statusCode = 500; [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription }]; return; }
    response.statusCode = 200;
    [response setJsonBody:config];
}

- (void)handleAgeAssuranceGetState:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actorDID = [self requireAuth:request response:response];
    if (!actorDID) return;

    NSString *countryCode = [request queryParamForKey:@"countryCode"];
    if (!countryCode) {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"countryCode parameter is required" }];
        return;
    }

    if (!_ageAssuranceService) {
        response.statusCode = 503;
        [response setJsonBody:@{ @"error": @"ServiceUnavailable", @"message": @"Age assurance service not available" }];
        return;
    }

    NSError *error = nil;
    NSDictionary *state = [_ageAssuranceService getAgeAssuranceState:actorDID
                                                        countryCode:countryCode
                                                         regionCode:[request queryParamForKey:@"regionCode"]
                                                              error:&error];
    if (error) { response.statusCode = 500; [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription }]; return; }
    
    response.statusCode = 200;
    [response setJsonBody:@{
        @"state": state ?: @{ @"id": @"", @"status": @"none" },
        @"metadata": @{
            @"countryCode": countryCode,
            @"regionCode": [request queryParamForKey:@"regionCode"] ?: @"",
            @"computedAt": [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]]
        }
    }];
}

- (void)handleProxyWrite:(HttpRequest *)request response:(HttpResponse *)response nsid:(NSString *)nsid
{
    NSString *callerDID = [self requireAuth:request response:response];
    if (!callerDID) return;

    [_writeProxy proxyWriteRequest:request response:response nsid:nsid callerDID:callerDID];
}

#pragma mark - Draft Handlers

- (void)handleGetDrafts:(HttpRequest *)request response:(HttpResponse *)response {
    NSString *actorDID = [self requireAuth:request response:response];
    if (!actorDID) return;

    NSError *error = nil;
    NSArray *drafts = [_draftService getDraftsForDID:actorDID error:&error];
    if (error) {
        response.statusCode = 500;
        [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription ?: @"Failed" }];
        return;
    }
    response.statusCode = 200;
    [response setJsonBody:@{ @"drafts": drafts ?: @[] }];
}

#pragma mark - Bookmark Handlers

- (void)handleGetBookmarks:(HttpRequest *)request response:(HttpResponse *)response {
    NSString *actorDID = [self requireAuth:request response:response];
    if (!actorDID) return;

    NSInteger limit = parseLimitParam(request, 50, 100);
    NSString *cursor = [request queryParamForKey:@"cursor"];

    NSError *error = nil;
    NSDictionary *result = [_bookmarkService getBookmarksForActor:actorDID limit:limit cursor:cursor error:&error];
    if (error) {
        response.statusCode = 500;
        [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription ?: @"Failed" }];
        return;
    }
    response.statusCode = 200;
    [response setJsonBody:result ?: @{}];
}

#pragma mark - Graph Handlers (Extended)

- (void)handleGetStarterPacksBulk:(HttpRequest *)request response:(HttpResponse *)response {
    id urisParam = [request queryParamForKey:@"uris"];
    NSArray *uris = [urisParam isKindOfClass:[NSArray class]] ? (NSArray *)urisParam : (urisParam ? @[urisParam] : @[]);

    NSError *error = nil;
    NSArray *packs = [_graphService getStarterPacks:uris error:&error];
    if (error) {
        response.statusCode = 500;
        [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription ?: @"Failed" }];
        return;
    }
    response.statusCode = 200;
    [response setJsonBody:@{ @"starterPacks": packs ?: @[] }];
}

#pragma mark - Contact Handlers

- (void)handleStartPhoneVerification:(HttpRequest *)request response:(HttpResponse *)response {
    NSString *actorDID = [self requireAuth:request response:response];
    if (!actorDID) return;

    NSDictionary *body = request.jsonBody;
    NSString *phone = body[@"phoneNumber"];
    if (!phone) {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"phoneNumber is required" }];
        return;
    }

    NSError *error = nil;
    NSString *vId = [_contactService startPhoneVerification:phone actor:actorDID error:&error];
    if (error) {
        response.statusCode = 500;
        [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription ?: @"Failed" }];
        return;
    }
    response.statusCode = 200;
    [response setJsonBody:@{ @"id": vId ?: @"" }];
}

- (void)handleVerifyPhone:(HttpRequest *)request response:(HttpResponse *)response {
    NSString *actorDID = [self requireAuth:request response:response];
    if (!actorDID) return;

    NSDictionary *body = request.jsonBody;
    NSString *phone = body[@"phoneNumber"];
    NSString *code = body[@"code"];
    if (!phone || !code) {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"phoneNumber and code are required" }];
        return;
    }

    NSError *error = nil;
    NSString *token = [_contactService verifyPhone:phone code:code actor:actorDID error:&error];
    if (error) {
        response.statusCode = 401;
        [response setJsonBody:@{ @"error": @"AuthenticationFailed", @"message": error.localizedDescription ?: @"Failed" }];
        return;
    }
    response.statusCode = 200;
    [response setJsonBody:@{ @"token": token ?: @"" }];
}

- (void)handleImportContacts:(HttpRequest *)request response:(HttpResponse *)response {
    NSString *actorDID = [self requireAuth:request response:response];
    if (!actorDID) return;

    NSDictionary *body = request.jsonBody;
    NSArray *contacts = body[@"contacts"];
    NSString *token = body[@"token"];
    if (!contacts || !token) {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"contacts and token are required" }];
        return;
    }

    NSError *error = nil;
    NSDictionary *result = [_contactService importContacts:contacts token:token actor:actorDID error:&error];
    if (error) {
        response.statusCode = error.code == 401 ? 401 : 500;
        [response setJsonBody:@{ @"error": error.code == 401 ? @"AuthenticationFailed" : @"InternalServerError", @"message": error.localizedDescription ?: @"Failed" }];
        return;
    }
    response.statusCode = 200;
    [response setJsonBody:result ?: @{}];
}

- (void)handleGetContactMatches:(HttpRequest *)request response:(HttpResponse *)response {
    NSString *actorDID = [self requireAuth:request response:response];
    if (!actorDID) return;

    NSError *error = nil;
    NSArray *matches = [_contactService getMatchesForActor:actorDID error:&error];
    if (error) {
        response.statusCode = 500;
        [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription ?: @"Failed" }];
        return;
    }
    response.statusCode = 200;
    [response setJsonBody:@{ @"matches": matches ?: @[] }];
}

- (void)handleDismissContactMatch:(HttpRequest *)request response:(HttpResponse *)response {
    NSString *actorDID = [self requireAuth:request response:response];
    if (!actorDID) return;

    NSDictionary *body = request.jsonBody;
    NSString *matchDID = body[@"did"];
    if (!matchDID) {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"did is required" }];
        return;
    }

    NSError *error = nil;
    BOOL ok = [_contactService dismissMatch:matchDID actor:actorDID error:&error];
    if (!ok) {
        response.statusCode = 500;
        [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription ?: @"Failed" }];
        return;
    }
    response.statusCode = 200;
    [response setJsonBody:@{}];
}

- (void)handleGetContactSyncStatus:(HttpRequest *)request response:(HttpResponse *)response {
    NSString *actorDID = [self requireAuth:request response:response];
    if (!actorDID) return;

    NSError *error = nil;
    NSDictionary *status = [_contactService getSyncStatusForActor:actorDID error:&error];
    if (error) {
        response.statusCode = 500;
        [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription ?: @"Failed" }];
        return;
    }
    response.statusCode = 200;
    [response setJsonBody:status ?: @{}];
}

- (void)handleRemoveContactData:(HttpRequest *)request response:(HttpResponse *)response {
    NSString *actorDID = [self requireAuth:request response:response];
    if (!actorDID) return;

    NSError *error = nil;
    BOOL ok = [_contactService removeDataForActor:actorDID error:&error];
    if (!ok) {
        response.statusCode = 500;
        [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription ?: @"Failed" }];
        return;
    }
    response.statusCode = 200;
    [response setJsonBody:@{}];
}

#pragma mark - Search Skeleton Handlers

- (void)handleSearchActorsSkeleton:(HttpRequest *)request response:(HttpResponse *)response {
    NSString *query = [request queryParamForKey:@"q"];
    if (!query) {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"q parameter is required" }];
        return;
    }
    NSInteger limit = parseLimitParam(request, 50, 100);
    NSString *cursor = [request queryParamForKey:@"cursor"];

    NSError *error = nil;
    NSDictionary *result = [_searchIndexService searchActors:query limit:limit cursor:cursor error:&error];
    if (error) {
        response.statusCode = 500;
        [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription ?: @"Failed" }];
        return;
    }
    response.statusCode = 200;
    [response setJsonBody:result ?: @{}];
}

- (void)handleSearchPostsSkeleton:(HttpRequest *)request response:(HttpResponse *)response {
    NSString *query = [request queryParamForKey:@"q"];
    if (!query) {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"q parameter is required" }];
        return;
    }
    NSInteger limit = parseLimitParam(request, 50, 100);
    NSString *cursor = [request queryParamForKey:@"cursor"];

    NSError *error = nil;
    NSDictionary *result = [_searchIndexService searchPosts:query limit:limit cursor:cursor error:&error];
    if (error) {
        response.statusCode = 500;
        [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription ?: @"Failed" }];
        return;
    }
    response.statusCode = 200;
    [response setJsonBody:result ?: @{}];
}

- (void)handleSearchStarterPacksSkeleton:(HttpRequest *)request response:(HttpResponse *)response {
    NSString *query = [request queryParamForKey:@"q"];
    if (!query) {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"q parameter is required" }];
        return;
    }
    NSInteger limit = parseLimitParam(request, 50, 100);
    NSString *cursor = [request queryParamForKey:@"cursor"];

    NSError *error = nil;
    NSDictionary *result = [_searchIndexService searchStarterPacks:query limit:limit cursor:cursor error:&error];
    if (error) {
        response.statusCode = 500;
        [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription ?: @"Failed" }];
        return;
    }
    response.statusCode = 200;
    [response setJsonBody:result ?: @{}];
}

@end
