// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Network/AppViewXRpcRoutePack_Internal.h"
#import "Network/AppViewXRpcRoutePack+Actor.h"
#import "Network/AppViewXRpcRoutePack+Feed.h"
#import "Network/AppViewXRpcRoutePack+Graph.h"
#import "Network/AppViewXRpcRoutePack+Notification.h"
#import "Network/AppViewXRpcRoutePack+Identity.h"
#import "Network/AppViewXRpcRoutePack+AgeAssurance.h"
#import "Network/AppViewXRpcRoutePack+Contact.h"
#import "Network/AppViewXRpcRoutePack+Search.h"
#import "Network/AppViewXRpcRoutePack+DraftsAndBookmarks.h"
#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcAuthHelper.h"
#import "Debug/GZLogger.h"
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

NSInteger parseLimitParam(HttpRequest *request, NSInteger defaultLimit, NSInteger maxLimit) {
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

    // --- app.bsky.labeler ---
    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.labeler.getServices"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 id didsParam = request.queryParams[@"dids"];
                 NSArray *dids = nil;
                 if ([didsParam isKindOfClass:[NSArray class]]) {
                     dids = didsParam;
                 } else if ([didsParam isKindOfClass:[NSString class]] && [(NSString *)didsParam length] > 0) {
                     dids = @[didsParam];
                 }
                 if (dids.count == 0) {
                     response.statusCode = HttpStatusBadRequest;
                     [response setJsonBody:@{
                       @"error": @"InvalidRequest",
                       @"message": @"Missing or empty required parameter: dids"
                     }];
                     return;
                 }
                 response.statusCode = HttpStatusOK;
                 [response setJsonBody:@{@"views" : @[]}];
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

        [server addRoute:@"GET"
                    path:@"/xrpc/app.bsky.graph.getLists"
                 handler:^(HttpRequest *request, HttpResponse *response) {
                     [self handleGetLists:request response:response];
                 }];

        [server addRoute:@"GET"
                    path:@"/xrpc/app.bsky.graph.getList"
                 handler:^(HttpRequest *request, HttpResponse *response) {
                     [self handleGetList:request response:response];
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

    for (NSString *prefix in @[@"did:plc:", @"did:web:"])
    {
        if ([token hasPrefix:prefix])
            return token;
    }

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

@end