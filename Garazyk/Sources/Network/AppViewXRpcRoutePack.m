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
#import "Auth/Crypto/JWT.h"
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

NSInteger parseLimitParam(ATProtoHttpRequest *request, NSInteger defaultLimit, NSInteger maxLimit) {
    NSString *limitParam = [request queryParamForKey:@"limit"];
    NSInteger limit = defaultLimit;
    if (limitParam.length > 0) {
        [[NSScanner scannerWithString:limitParam] scanInteger:&limit];
    }
    return MIN(MAX(limit, 1), maxLimit);
}

#import "AppView/Server/WriteProxy/AppViewWriteProxy.h"

@implementation ATProtoAppViewXRpcRoutePack {
    PDSFeedService *_feedService;
    PDSActorService *_actorService;
    PDSGraphService *_graphService;
    PDSNotificationService *_notificationService;
    PDSAgeAssuranceService *_ageAssuranceService;
    PDSDraftService *_draftService;
    PDSBookmarkService *_bookmarkService;
    PDSContactService *_contactService;
    PDSSearchIndexService *_searchIndexService;
    AppViewWriteProxy *_writeProxy;
    id<PDSQueryDatabase> _database;
    ATProtoJWTMinter *_jwtMinter;
}

- (instancetype)initWithFeedService:(PDSFeedService *)feedService
                       actorService:(PDSActorService *)actorService
                       graphService:(nullable PDSGraphService *)graphService
                 notificationService:(PDSNotificationService *)notificationService
                ageAssuranceService:(nullable PDSAgeAssuranceService *)ageAssuranceService
                        draftService:(nullable PDSDraftService *)draftService
                     bookmarkService:(nullable PDSBookmarkService *)bookmarkService
                      contactService:(nullable PDSContactService *)contactService
                  searchIndexService:(nullable PDSSearchIndexService *)searchIndexService
                         writeProxy:(nullable AppViewWriteProxy *)writeProxy
                          database:(nullable id<PDSQueryDatabase>)database
                         jwtMinter:(nullable ATProtoJWTMinter *)jwtMinter
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

- (void)registerRoutesWithServer:(ATProtoHttpServer *)server
{
    // --- app.bsky.actor ---
    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.actor.getProfile"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 [self handleGetProfile:request response:response];
             }];

    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.actor.getProfiles"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 [self handleGetProfiles:request response:response];
             }];

    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.actor.searchActors"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 [self handleSearchActors:request response:response];
             }];

    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.actor.searchActorsTypeahead"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 [self handleSearchActorsTypeahead:request response:response];
             }];

    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.actor.getPreferences"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 [self handleGetPreferences:request response:response];
             }];

    [server addRoute:@"POST"
                path:@"/xrpc/app.bsky.actor.putPreferences"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 [self handlePutPreferences:request response:response];
             }];

    // --- app.bsky.draft ---
    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.draft.getDrafts"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 [self handleGetDrafts:request response:response];
             }];

    // --- app.bsky.bookmark ---
    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.bookmark.getBookmarks"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 [self handleGetBookmarks:request response:response];
             }];

    // --- app.bsky.graph (additional) ---
    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.graph.getStarterPacks"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 [self handleGetStarterPacksBulk:request response:response];
             }];

    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.actor.getSuggestions"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 [self handleGetSuggestions:request response:response];
             }];

    // --- app.bsky.feed ---
    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.feed.getTimeline"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 [self handleGetTimeline:request response:response];
             }];

    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.feed.getAuthorFeed"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 [self handleGetAuthorFeed:request response:response];
             }];

    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.feed.getPostThread"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 [self handleGetPostThread:request response:response];
             }];

    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.feed.getFeed"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 [self handleGetFeed:request response:response];
             }];

    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.feed.getActorLikes"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 [self handleGetActorLikes:request response:response];
             }];

    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.feed.getPosts"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 [self handleGetPosts:request response:response];
             }];

    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.feed.getFeedGenerators"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 [self handleGetFeedGenerators:request response:response];
             }];

    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.feed.getLikes"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 [self handleGetLikes:request response:response];
             }];

    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.feed.getRepostedBy"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 [self handleGetRepostedBy:request response:response];
             }];

    // --- app.bsky.labeler ---
    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.labeler.getServices"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
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
                 handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                     [self handleGetFollows:request response:response];
                 }];

        [server addRoute:@"GET"
                    path:@"/xrpc/app.bsky.graph.getFollowers"
                 handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                     [self handleGetFollowers:request response:response];
                 }];

        [server addRoute:@"GET"
                    path:@"/xrpc/app.bsky.graph.getBlocks"
                 handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                     [self handleGetBlocks:request response:response];
                 }];

        [server addRoute:@"GET"
                    path:@"/xrpc/app.bsky.graph.getMutes"
                 handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                     [self handleGetMutes:request response:response];
                 }];

        [server addRoute:@"GET"
                    path:@"/xrpc/app.bsky.graph.getRelationships"
                 handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                     [self handleGetRelationships:request response:response];
                 }];

        [server addRoute:@"GET"
                    path:@"/xrpc/app.bsky.graph.getStarterPack"
                 handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                     [self handleGetStarterPack:request response:response];
                 }];

        [server addRoute:@"GET"
                    path:@"/xrpc/app.bsky.graph.getActorStarterPacks"
                 handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                     [self handleGetStarterPacks:request response:response];
                 }];

        [server addRoute:@"GET"
                    path:@"/xrpc/app.bsky.graph.getLists"
                 handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                     [self handleGetLists:request response:response];
                 }];

        [server addRoute:@"GET"
                    path:@"/xrpc/app.bsky.graph.getList"
                 handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                     [self handleGetList:request response:response];
                 }];

        [server addRoute:@"POST"
                    path:@"/xrpc/app.bsky.graph.muteActor"
                 handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                     [self handleMuteActor:request response:response];
                 }];

        [server addRoute:@"POST"
                    path:@"/xrpc/app.bsky.graph.unmuteActor"
                 handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                     [self handleUnmuteActor:request response:response];
                 }];

        // --- app.bsky.contact ---
        [server addRoute:@"POST"
                    path:@"/xrpc/app.bsky.contact.startPhoneVerification"
                 handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                     [self handleStartPhoneVerification:request response:response];
                 }];

        [server addRoute:@"POST"
                    path:@"/xrpc/app.bsky.contact.verifyPhone"
                 handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                     [self handleVerifyPhone:request response:response];
                 }];

        [server addRoute:@"POST"
                    path:@"/xrpc/app.bsky.contact.importContacts"
                 handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                     [self handleImportContacts:request response:response];
                 }];

        [server addRoute:@"GET"
                    path:@"/xrpc/app.bsky.contact.getMatches"
                 handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                     [self handleGetContactMatches:request response:response];
                 }];

        [server addRoute:@"POST"
                    path:@"/xrpc/app.bsky.contact.dismissMatch"
                 handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                     [self handleDismissContactMatch:request response:response];
                 }];

        [server addRoute:@"GET"
                    path:@"/xrpc/app.bsky.contact.getSyncStatus"
                 handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                     [self handleGetContactSyncStatus:request response:response];
                 }];

        [server addRoute:@"POST"
                    path:@"/xrpc/app.bsky.contact.removeData"
                 handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                     [self handleRemoveContactData:request response:response];
                 }];

    }

    if (_writeProxy) {
        [server addRoute:@"POST"
                    path:@"/xrpc/com.atproto.repo.createRecord"
                 handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                     [self handleProxyWrite:request response:response nsid:@"com.atproto.repo.createRecord"];
                 }];
        [server addRoute:@"POST"
                    path:@"/xrpc/com.atproto.repo.putRecord"
                 handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                     [self handleProxyWrite:request response:response nsid:@"com.atproto.repo.putRecord"];
                 }];
        [server addRoute:@"POST"
                    path:@"/xrpc/com.atproto.repo.deleteRecord"
                 handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                     [self handleProxyWrite:request response:response nsid:@"com.atproto.repo.deleteRecord"];
                 }];
    }

    // --- app.bsky.notification ---
    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.notification.listNotifications"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 [self handleListNotifications:request response:response];
             }];

    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.notification.getUnreadCount"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 [self handleGetUnreadCount:request response:response];
             }];

    [server addRoute:@"POST"
                path:@"/xrpc/app.bsky.notification.updateSeen"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 [self handleUpdateSeen:request response:response];
             }];

    [server addRoute:@"POST"
                path:@"/xrpc/app.bsky.notification.registerPush"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 [self handleRegisterPush:request response:response];
             }];

    [server addRoute:@"POST"
                path:@"/xrpc/app.bsky.notification.unregisterPush"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 [self handleUnregisterPush:request response:response];
             }];

    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.notification.listActivitySubscriptions"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 [self handleListActivitySubscriptions:request response:response];
             }];

    [server addRoute:@"POST"
                path:@"/xrpc/app.bsky.notification.putActivitySubscription"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 [self handlePutActivitySubscription:request response:response];
             }];

    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.notification.getPreferences"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 [self handleGetNotificationPreferences:request response:response];
             }];

    [server addRoute:@"POST"
                path:@"/xrpc/app.bsky.notification.putPreferences"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 [self handlePutNotificationPreferences:request response:response];
             }];

    // --- app.bsky.unspecced search ---
    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.unspecced.searchActorsSkeleton"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 [self handleSearchActorsSkeleton:request response:response];
             }];

    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.unspecced.searchPostsSkeleton"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 [self handleSearchPostsSkeleton:request response:response];
             }];

    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.unspecced.searchStarterPacksSkeleton"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 [self handleSearchStarterPacksSkeleton:request response:response];
             }];

    // --- com.atproto.* (proxied convenience endpoints) ---
    [server addRoute:@"GET"
                path:@"/xrpc/com.atproto.identity.resolveHandle"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 [self handleResolveHandle:request response:response];
             }];

    [server addRoute:@"GET"
                path:@"/xrpc/com.atproto.repo.getRecord"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 [self handleGetRecord:request response:response];
             }];

    [server addRoute:@"GET"
                path:@"/xrpc/com.atproto.label.queryLabels"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 [self handleQueryLabels:request response:response];
             }];

    [server addRoute:@"GET"
                path:@"/xrpc/com.atproto.admin.getAccountInfos"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 [self handleGetAccountInfos:request response:response];
             }];

    [server addRoute:@"GET"
                path:@"/xrpc/com.atproto.admin.getSubjectStatus"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 [self handleGetSubjectStatus:request response:response];
             }];

    // --- app.bsky.ageassurance ---
    [server addRoute:@"POST"
                path:@"/xrpc/app.bsky.ageassurance.begin"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 [self handleAgeAssuranceBegin:request response:response];
             }];

    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.ageassurance.getConfig"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 [self handleAgeAssuranceGetConfig:request response:response];
             }];

    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.ageassurance.getState"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 [self handleAgeAssuranceGetState:request response:response];
             }];

}

#pragma mark - Auth Helpers

- (NSString *)extractDIDFromAuth:(NSString *)authHeader request:(ATProtoHttpRequest *)request
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
    ATProtoJWT *jwt = [ATProtoJWT jwtWithToken:token error:&error];
    if (jwt && jwt.payload.sub) {
        return jwt.payload.sub;
    }

    return nil;
}

- (NSString *)requireAuth:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response
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