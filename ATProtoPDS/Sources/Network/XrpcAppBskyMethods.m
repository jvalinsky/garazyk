#import "Network/XrpcAppBskyMethods.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcAuthHelper.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Database/Service/ServiceDatabases.h"
#import "Database/PDSDatabase.h"
#import "Admin/PDSAdminController.h"
#import "AppView/ActorService.h"
#import "AppView/FeedService.h"
#import "AppView/NotificationService.h"
#import "AppView/GraphService.h"
#import "Core/CID.h"
#import "Core/ATProtoCBORSerialization.h"
#import "AppView/RecordLifecycleHandler.h"
#import "Debug/PDSLogger.h"

#pragma mark - Helper Functions

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

#pragma mark - XrpcAppBskyMethods Implementation

@implementation XrpcAppBskyMethods

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
              serviceDatabases:(PDSServiceDatabases *)serviceDatabases
                     jwtMinter:(JWTMinter *)jwtMinter
               adminController:(id<PDSAdminController>)adminController {
    
    // Initialize AppView database and services
    NSError *appViewDbError = nil;
    PDSDatabase *appViewDatabase = [serviceDatabases serviceDatabaseWithError:&appViewDbError];
    if (!appViewDatabase && appViewDbError) {
        PDS_LOG_WARN(@"Failed to open service database for app.bsky handlers: %@",
                     appViewDbError.localizedDescription ?: @"unknown error");
    }
    
    ActorService *actorService = [[ActorService alloc] initWithDatabase:appViewDatabase];
    FeedService *feedService = [[FeedService alloc] initWithDatabase:appViewDatabase];
    NotificationService *notificationService = [[NotificationService alloc] initWithDatabase:appViewDatabase actorService:actorService];
    GraphService *graphService = [[GraphService alloc] initWithDatabase:appViewDatabase];
    
    // Initialize record lifecycle handler for notification generation
    __attribute__((unused)) RecordLifecycleHandler *lifecycleHandler =
        [[RecordLifecycleHandler alloc] initWithNotificationService:notificationService
                                                           database:appViewDatabase];
    
    // app.bsky.actor.getProfile - Get actor profile
    [dispatcher registerAppBskyActorGetProfile:^(HttpRequest *request, HttpResponse *response) {
        NSString *actor = [request queryParamForKey:@"actor"];
        if (!actor) {
            [XrpcErrorHelper setValidationError:response message:@"Missing actor parameter"];
            return;
        }
        
        NSError *error = nil;
        NSDictionary *profile = [actorService getProfileForActor:actor error:&error];
        if (error) {
            [XrpcErrorHelper setNotFoundError:response message:error.localizedDescription];
            return;
        }
        
        response.statusCode = HttpStatusOK;
        [response setJsonBody:profile];
    }];
    
    // app.bsky.actor.getProfiles - Get multiple actor profiles
    [dispatcher registerAppBskyActorGetProfiles:^(HttpRequest *request, HttpResponse *response) {
        // actors parameter can be repeated: ?actors=did1&actors=did2
        // HttpRequest should support getting array of values
        id actorsParam = request.queryParams[@"actors"];
        NSArray<NSString *> *actors = nil;
        
        if ([actorsParam isKindOfClass:[NSArray class]]) {
            actors = actorsParam;
        } else if ([actorsParam isKindOfClass:[NSString class]]) {
            actors = @[actorsParam];
        } else {
            [XrpcErrorHelper setValidationError:response message:@"Missing actors parameter"];
            return;
        }
        
        if (actors.count == 0) {
            [XrpcErrorHelper setValidationError:response message:@"Missing actors parameter"];
            return;
        }
        
        NSError *error = nil;
        NSArray<NSDictionary *> *profiles = [actorService getProfilesForActors:actors error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }
        
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"profiles": profiles ?: @[]}];
    }];
    
    // app.bsky.actor.getPreferences - Get actor preferences
    [dispatcher registerAppBskyActorGetPreferences:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        if (!authHeader) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }
        
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                         jwtMinter:jwtMinter
                                                   adminController:adminController
                                                           request:request
                                                          response:response];
        if (!actorDID) {
            return;
        }
        
        NSError *error = nil;
        NSDictionary *preferences = [actorService getPreferencesForActor:actorDID error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }
        
        response.statusCode = HttpStatusOK;
        [response setJsonBody:preferences ?: @{@"preferences": @{}}];
    }];
    
    // app.bsky.actor.putPreferences - Update actor preferences
    [dispatcher registerAppBskyActorPutPreferences:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        if (!authHeader) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }
        
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                         jwtMinter:jwtMinter
                                                   adminController:adminController
                                                           request:request
                                                          response:response];
        if (!actorDID) {
            return;
        }
        
        NSDictionary *body = request.jsonBody;
        if (!body || ![body isKindOfClass:[NSDictionary class]]) {
            [XrpcErrorHelper setValidationError:response message:@"Missing request body"];
            return;
        }
        
        id preferences = body[@"preferences"];
        if (!preferences || (![preferences isKindOfClass:[NSDictionary class]] && ![preferences isKindOfClass:[NSArray class]])) {
            [XrpcErrorHelper setValidationError:response message:@"Missing preferences in body"];
            return;
        }
        
        NSError *error = nil;
        BOOL success = [actorService putPreferencesForActor:actorDID preferences:preferences error:&error];
        if (!success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to save preferences"];
            return;
        }
        
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"preferences": preferences}];
    }];
    
    // app.bsky.actor.searchActors - Search actors with pagination
    [dispatcher registerAppBskyActorSearchActors:^(HttpRequest *request, HttpResponse *response) {
        NSString *term = [request queryParamForKey:@"q"];
        if (!term || term.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"Missing search term (q parameter)"];
            return;
        }
        
        NSInteger limit = 25;
        if (![self parseLimit:request.queryParams[@"limit"] outValue:&limit min:1 max:100 response:response]) {
            return;
        }
        
        NSString *cursor = [request queryParamForKey:@"cursor"];
        
        NSError *error = nil;
        NSDictionary *result = [actorService searchActors:term limit:limit cursor:cursor error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }
        
        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];
    
    // app.bsky.actor.searchActorsTypeahead - Typeahead search for actors
    [dispatcher registerAppBskyActorSearchActorsTypeahead:^(HttpRequest *request, HttpResponse *response) {
        NSString *term = [request queryParamForKey:@"q"];
        if (!term || term.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"Missing search term (q parameter)"];
            return;
        }
        
        NSInteger limit = 10;
        if (![self parseLimit:request.queryParams[@"limit"] outValue:&limit min:1 max:100 response:response]) {
            return;
        }
        
        NSError *error = nil;
        NSArray<NSDictionary *> *actors = [actorService searchActorsTypeahead:term limit:limit error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }
        
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"actors": actors ?: @[]}];
    }];
    
    // app.bsky.feed.getAuthorFeed - Get author's feed with pagination
    [dispatcher registerAppBskyFeedGetAuthorFeed:^(HttpRequest *request, HttpResponse *response) {
        NSString *actor = [request queryParamForKey:@"actor"];
        if (!actor) {
            [XrpcErrorHelper setValidationError:response message:@"Missing actor parameter"];
            return;
        }
        
        NSInteger limit = 50;
        if (![self parseLimit:request.queryParams[@"limit"] outValue:&limit min:1 max:100 response:response]) {
            return;
        }
        
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSString *filter = [request queryParamForKey:@"filter"];
        
        NSError *error = nil;
        NSDictionary *result = [feedService getAuthorFeedForActor:actor
                                                            limit:limit
                                                          cursor:cursor
                                                          filter:filter
                                                            error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }
        
        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];
    
    // app.bsky.feed.getTimeline - Get timeline feed (requires auth)
    [dispatcher registerAppBskyFeedGetTimeline:^(HttpRequest *request, HttpResponse *response) {
        // Optional authentication - if provided, use it for personalized timeline
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = nil;
        
        if (authHeader) {
            actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                     jwtMinter:jwtMinter
                                               adminController:adminController
                                                       request:request
                                                      response:response];
            if (!actorDID && response.statusCode != HttpStatusOK) {
                // Auth was provided but invalid
                return;
            }
        }
        
        if (!actorDID) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required for timeline"];
            return;
        }
        
        NSInteger limit = 50;
        if (![self parseLimit:request.queryParams[@"limit"] outValue:&limit min:1 max:100 response:response]) {
            return;
        }
        
        NSString *cursor = [request queryParamForKey:@"cursor"];
        
        NSError *error = nil;
        NSDictionary *result = [feedService getTimelineForActor:actorDID
                                                          limit:limit
                                                        cursor:cursor
                                                          error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }
        
        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];
    
    // app.bsky.feed.getActorLikes - Get posts liked by actor
    [dispatcher registerAppBskyFeedGetActorLikes:^(HttpRequest *request, HttpResponse *response) {
        NSString *actor = [request queryParamForKey:@"actor"];
        if (!actor) {
            [XrpcErrorHelper setValidationError:response message:@"Missing actor parameter"];
            return;
        }
        
        NSInteger limit = 50;
        if (![self parseLimit:request.queryParams[@"limit"] outValue:&limit min:1 max:100 response:response]) {
            return;
        }
        
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
    
    // app.bsky.feed.getPostThread - Get post thread with replies
    [dispatcher registerAppBskyFeedGetPostThread:^(HttpRequest *request, HttpResponse *response) {
        NSString *uri = [request queryParamForKey:@"uri"];
        if (!uri) {
            [XrpcErrorHelper setValidationError:response message:@"Missing uri parameter"];
            return;
        }
        
        NSInteger depth = 6;
        NSString *depthParam = [request queryParamForKey:@"depth"];
        if (depthParam && !parseIntegerParam(depthParam, &depth, 6)) {
            [XrpcErrorHelper setValidationError:response message:@"Invalid depth parameter"];
            return;
        }
        
        NSError *error = nil;
        NSDictionary *result = [feedService getPostThread:uri depth:depth error:&error];
        if (error) {
            [XrpcErrorHelper setNotFoundError:response message:error.localizedDescription];
            return;
        }
        
        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];
    
    // app.bsky.feed.getFeed - Get custom feed from generator
    [dispatcher registerAppBskyFeedGetFeed:^(HttpRequest *request, HttpResponse *response) {
        NSString *feed = [request queryParamForKey:@"feed"];
        if (!feed) {
            [XrpcErrorHelper setValidationError:response message:@"Missing feed parameter"];
            return;
        }
        
        NSInteger limit = 50;
        if (![self parseLimit:request.queryParams[@"limit"] outValue:&limit min:1 max:100 response:response]) {
            return;
        }
        
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

    // app.bsky.feed.getPosts - Get multiple posts by URI
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

    // app.bsky.feed.getFeedGenerators - Get multiple feed generators by URI
    [dispatcher registerAppBskyFeedGetFeedGenerators:^(HttpRequest *request, HttpResponse *response) {
        // TODO: Query app.bsky.feed.generator records by URI. For now return empty.
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"feeds": @[]}];
    }];

    // app.bsky.feed.getSuggestedFeeds - Get suggested feeds
    [dispatcher registerMethod:@"app.bsky.feed.getSuggestedFeeds" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"feeds": @[]}];
    }];
    
    // app.bsky.graph.getFollowers - Get followers list
    [dispatcher registerMethod:@"app.bsky.graph.getFollowers" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *actor = [request queryParamForKey:@"actor"];
        if (!actor) {
            [XrpcErrorHelper setValidationError:response message:@"Missing actor parameter"];
            return;
        }
        
        NSInteger limit = 50;
        if (![self parseLimit:request.queryParams[@"limit"] outValue:&limit min:1 max:100 response:response]) {
            return;
        }
        
        NSString *cursor = [request queryParamForKey:@"cursor"];
        
        NSError *error = nil;
        NSDictionary *result = [graphService getFollowersForActor:actor limit:limit cursor:cursor error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }
        
        response.statusCode = HttpStatusOK;
        [response setJsonBody:result ?: @{@"subject": @{@"did": actor}, @"followers": @[]}];
    }];
    
    // app.bsky.graph.getFollows - Get follows list
    [dispatcher registerMethod:@"app.bsky.graph.getFollows" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *actor = [request queryParamForKey:@"actor"];
        if (!actor) {
            [XrpcErrorHelper setValidationError:response message:@"Missing actor parameter"];
            return;
        }
        
        NSInteger limit = 50;
        if (![self parseLimit:request.queryParams[@"limit"] outValue:&limit min:1 max:100 response:response]) {
            return;
        }
        
        NSString *cursor = [request queryParamForKey:@"cursor"];
        
        NSError *error = nil;
        NSDictionary *result = [graphService getFollowsForActor:actor limit:limit cursor:cursor error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }
        
        response.statusCode = HttpStatusOK;
        [response setJsonBody:result ?: @{@"subject": @{@"did": actor}, @"follows": @[]}];
    }];

    // app.bsky.graph.getMutes - Get muted actors
    [dispatcher registerAppBskyGraphGetMutes:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                            jwtMinter:jwtMinter
                                                      adminController:adminController
                                                              request:request
                                                             response:response];
        if (!actorDID) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }
        
        NSInteger limit = 50;
        NSString *cursor = [request queryParamForKey:@"cursor"];
        
        NSError *error = nil;
        NSDictionary *result = [graphService getMutesForActor:actorDID limit:limit cursor:cursor error:&error];
        
        response.statusCode = HttpStatusOK;
        [response setJsonBody:result ?: @{@"mutes": @[]}];
    }];

    // app.bsky.graph.getBlocks - Get blocked actors
    [dispatcher registerAppBskyGraphGetBlocks:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                            jwtMinter:jwtMinter
                                                      adminController:adminController
                                                              request:request
                                                             response:response];
        if (!actorDID) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }
        
        NSInteger limit = 50;
        NSString *cursor = [request queryParamForKey:@"cursor"];
        
        NSError *error = nil;
        NSDictionary *result = [graphService getBlocksForActor:actorDID limit:limit cursor:cursor error:&error];
        
        response.statusCode = HttpStatusOK;
        [response setJsonBody:result ?: @{@"blocks": @[]}];
    }];

    // app.bsky.graph.muteActor - Mute an actor
    [dispatcher registerMethod:@"app.bsky.graph.muteActor" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                            jwtMinter:jwtMinter
                                                      adminController:adminController
                                                              request:request
                                                             response:response];
        if (!actorDID) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }
        
        NSDictionary *body = request.jsonBody;
        NSString *targetDID = body[@"actor"];
        if (!targetDID) {
            [XrpcErrorHelper setValidationError:response message:@"Missing actor in body"];
            return;
        }
        
        NSError *error = nil;
        [graphService muteActor:targetDID forActor:actorDID error:&error];
        
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    // app.bsky.graph.unmuteActor - Unmute an actor
    [dispatcher registerMethod:@"app.bsky.graph.unmuteActor" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                            jwtMinter:jwtMinter
                                                      adminController:adminController
                                                              request:request
                                                             response:response];
        if (!actorDID) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }
        
        NSDictionary *body = request.jsonBody;
        NSString *targetDID = body[@"actor"];
        if (!targetDID) {
            [XrpcErrorHelper setValidationError:response message:@"Missing actor in body"];
            return;
        }
        
        NSError *error = nil;
        [graphService unmuteActor:targetDID forActor:actorDID error:&error];
        
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    // app.bsky.feed.getLikes - Get likes for a post
    [dispatcher registerMethod:@"app.bsky.feed.getLikes" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *uri = [request queryParamForKey:@"uri"];
        if (!uri) {
            [XrpcErrorHelper setValidationError:response message:@"Missing uri parameter"];
            return;
        }
        
        NSInteger limit = 50;
        NSString *cursor = [request queryParamForKey:@"cursor"];
        
        NSError *error = nil;
        NSDictionary *result = [graphService getLikesForURI:uri limit:limit cursor:cursor error:&error];
        
        response.statusCode = HttpStatusOK;
        [response setJsonBody:result ?: @{@"uri": uri, @"likes": @[]}];
    }];

    // app.bsky.feed.getRepostedBy - Get actors who reposted
    [dispatcher registerMethod:@"app.bsky.feed.getRepostedBy" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *uri = [request queryParamForKey:@"uri"];
        if (!uri) {
            [XrpcErrorHelper setValidationError:response message:@"Missing uri parameter"];
            return;
        }
        
        NSInteger limit = 50;
        NSString *cursor = [request queryParamForKey:@"cursor"];
        
        NSError *error = nil;
        NSDictionary *result = [graphService getRepostedByForURI:uri limit:limit cursor:cursor error:&error];
        
        response.statusCode = HttpStatusOK;
        [response setJsonBody:result ?: @{@"uri": uri, @"repostedBy": @[]}];
    }];

    // app.bsky.graph.getRelationships - Get relationships between actors
    [dispatcher registerMethod:@"app.bsky.graph.getRelationships" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *actor = [request queryParamForKey:@"actor"];
        if (!actor) {
            [XrpcErrorHelper setValidationError:response message:@"Missing actor parameter"];
            return;
        }
        
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *viewerDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                            jwtMinter:jwtMinter
                                                      adminController:adminController
                                                              request:request
                                                             response:response];
        
        NSArray<NSString *> *others = [request queryParamsForKey:@"others"];
        NSMutableArray *relationships = [NSMutableArray array];
        
        for (NSString *otherDID in others) {
            NSError *error = nil;
            NSDictionary *rel = [graphService getRelationship:viewerDID ?: actor withActor:otherDID error:&error];
            if (rel) {
                [relationships addObject:rel];
            }
        }
        
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"actor": actor, @"relationships": relationships}];
    }];
    
    // app.bsky.notification.listNotifications - List notifications (requires auth)
    [dispatcher registerMethod:@"app.bsky.notification.listNotifications" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        if (!authHeader) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }
        
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
        if (!actorDID) {
            return;
        }
        
        NSInteger limit = 50;
        if (![self parseLimit:request.queryParams[@"limit"] outValue:&limit min:1 max:100 response:response]) {
            return;
        }
        
        NSString *cursor = [request queryParamForKey:@"cursor"];
        
        NSError *error = nil;
        NSArray<NSDictionary *> *notifications = [notificationService getNotificationsForActor:actorDID
                                                                                         limit:limit
                                                                                       cursor:cursor
                                                                                         error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }
        
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"notifications": notifications ?: @[]}];
    }];
    
    // app.bsky.notification.getUnreadCount - Get unread notification count (requires auth)
    [dispatcher registerMethod:@"app.bsky.notification.getUnreadCount" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        if (!authHeader) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }
        
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
        if (!actorDID) {
            return;
        }
        
        // Query real unread count from notifications table
        NSError *error = nil;
        NSInteger count = [notificationService getUnreadCountForActor:actorDID error:&error];
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"count": @(count)}];
    }];
    
    // app.bsky.notification.updateSeen - Mark notifications as seen (requires auth)
    [dispatcher registerMethod:@"app.bsky.notification.updateSeen" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        if (!authHeader) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }
        
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
        if (!actorDID) {
            return;
        }
        
        NSDictionary *body = request.jsonBody;
        if (!body) {
            [XrpcErrorHelper setValidationError:response message:@"Missing request body"];
            return;
        }
        
        // seenAt timestamp from body
        NSString *seenAt = body[@"seenAt"];
        if (!seenAt) {
            [XrpcErrorHelper setValidationError:response message:@"Missing seenAt parameter"];
            return;
        }
        
        // Mark all notifications as read up to this timestamp
        NSError *error = nil;
        [notificationService markNotificationsAsReadForActor:actorDID limit:0 error:&error];
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    // ====================================================================
    // P3: Missing AppView Endpoints
    // ====================================================================

    // app.bsky.feed.getActorFeeds - Get feed generators created by an actor
    [dispatcher registerMethod:@"app.bsky.feed.getActorFeeds" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *actor = [request queryParamForKey:@"actor"];
        if (!actor) {
            [XrpcErrorHelper setValidationError:response message:@"Missing actor parameter"];
            return;
        }

        NSInteger limit = 50;
        NSString *cursor = [request queryParamForKey:@"cursor"];

        // Query app.bsky.feed.generator records from the actor's repo
        NSString *query = @"SELECT rkey, cid FROM records WHERE did = ? AND collection = ?";
        if (cursor) {
            query = [query stringByAppendingString:@" AND rkey < ?"];
        }
        query = [query stringByAppendingString:@" ORDER BY rkey DESC LIMIT ?"];

        NSMutableArray *args = [NSMutableArray arrayWithObjects:actor, @"app.bsky.feed.generator", nil];
        if (cursor) [args addObject:cursor];
        [args addObject:@(limit)];

        NSError *error = nil;
        NSArray *rows = [appViewDatabase executeParameterizedQuery:query params:args error:&error];
        NSMutableArray *feeds = [NSMutableArray array];

        for (NSDictionary *row in rows) {
            NSString *cidStr = row[@"cid"];
            CID *cid = [CID cidFromString:cidStr];
            if (!cid) continue;
            PDSDatabaseBlock *block = [appViewDatabase getBlockWithCid:cid.bytes repoDid:actor error:nil];
            if (!block || !block.blockData) continue;
            NSDictionary *record = [ATProtoCBORSerialization JSONObjectWithData:block.blockData error:nil];
            if (!record) continue;

            NSString *rkey = row[@"rkey"];
            NSString *uri = [NSString stringWithFormat:@"at://%@/app.bsky.feed.generator/%@", actor, rkey];
            NSDictionary *generatorView = @{
                @"uri": uri,
                @"cid": cidStr ?: @"",
                @"did": actor,
                @"creator": [actorService getProfileForActor:actor error:nil] ?: @{@"did": actor},
                @"displayName": record[@"displayName"] ?: @"",
                @"description": record[@"description"] ?: @"",
                @"avatar": record[@"avatar"] ?: [NSNull null],
                @"likeCount": @0,
                @"indexedAt": record[@"createdAt"] ?: @"",
                @"labels": @[],
                @"viewer": @{}
            };
            [feeds addObject:generatorView];
        }

        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        result[@"feeds"] = feeds;
        if (feeds.count >= (NSUInteger)limit && rows.count > 0) {
            result[@"cursor"] = [rows lastObject][@"rkey"];
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    // app.bsky.feed.getFeedGenerator - Get a single feed generator by URI
    [dispatcher registerMethod:@"app.bsky.feed.getFeedGenerator" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *feed = [request queryParamForKey:@"feed"];
        if (!feed) {
            [XrpcErrorHelper setValidationError:response message:@"Missing feed parameter"];
            return;
        }

        // Parse AT URI: at://did/collection/rkey
        NSArray *components = [feed componentsSeparatedByString:@"/"];
        if (components.count < 5) {
            [XrpcErrorHelper setValidationError:response message:@"Invalid feed URI"];
            return;
        }
        NSString *did = components[2];
        NSString *rkey = components[4];

        NSString *query = @"SELECT cid FROM records WHERE did = ? AND collection = ? AND rkey = ? LIMIT 1";
        NSError *error = nil;
        NSArray *rows = [appViewDatabase executeParameterizedQuery:query params:@[did, @"app.bsky.feed.generator", rkey] error:&error];

        if (rows.count == 0) {
            response.statusCode = 404;
            [response setJsonBody:@{@"error": @"NotFound", @"message": @"Feed generator not found"}];
            return;
        }

        NSString *cidStr = rows[0][@"cid"];
        CID *cid = [CID cidFromString:cidStr];
        NSDictionary *record = nil;
        if (cid) {
            PDSDatabaseBlock *block = [appViewDatabase getBlockWithCid:cid.bytes repoDid:did error:nil];
            if (block && block.blockData) {
                record = [ATProtoCBORSerialization JSONObjectWithData:block.blockData error:nil];
            }
        }

        NSDictionary *generatorView = @{
            @"uri": feed,
            @"cid": cidStr ?: @"",
            @"did": did,
            @"creator": [actorService getProfileForActor:did error:nil] ?: @{@"did": did},
            @"displayName": record[@"displayName"] ?: @"",
            @"description": record[@"description"] ?: @"",
            @"likeCount": @0,
            @"indexedAt": record[@"createdAt"] ?: @"",
            @"labels": @[],
            @"viewer": @{}
        };

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"view": generatorView, @"isOnline": @YES, @"isValid": @YES}];
    }];

    // app.bsky.feed.searchPosts - Search posts by text
    [dispatcher registerMethod:@"app.bsky.feed.searchPosts" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *q = [request queryParamForKey:@"q"];
        if (!q || q.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"Missing q parameter"];
            return;
        }

        NSInteger limit = 25;
        NSString *cursor = [request queryParamForKey:@"cursor"];

        // Simple LIKE-based search across post records
        NSString *query = @"SELECT did, rkey, cid FROM records WHERE collection = ? ORDER BY rkey DESC LIMIT ?";
        NSError *error = nil;
        NSArray *rows = [appViewDatabase executeParameterizedQuery:query params:@[@"app.bsky.feed.post", @(limit * 5)] error:&error];

        NSMutableArray *posts = [NSMutableArray array];
        for (NSDictionary *row in rows) {
            if ((NSInteger)posts.count >= limit) break;

            NSString *postDID = row[@"did"];
            NSString *cidStr = row[@"cid"];
            CID *cid = [CID cidFromString:cidStr];
            if (!cid) continue;
            PDSDatabaseBlock *block = [appViewDatabase getBlockWithCid:cid.bytes repoDid:postDID error:nil];
            if (!block || !block.blockData) continue;
            NSDictionary *record = [ATProtoCBORSerialization JSONObjectWithData:block.blockData error:nil];
            if (!record) continue;

            NSString *text = record[@"text"] ?: @"";
            if ([text rangeOfString:q options:NSCaseInsensitiveSearch].location != NSNotFound) {
                NSString *rkey = row[@"rkey"];
                NSString *uri = [NSString stringWithFormat:@"at://%@/app.bsky.feed.post/%@", postDID, rkey];
                NSDictionary *postView = @{
                    @"uri": uri,
                    @"cid": cidStr ?: @"",
                    @"author": [actorService getProfileForActor:postDID error:nil] ?: @{@"did": postDID},
                    @"record": record,
                    @"replyCount": @0,
                    @"repostCount": @0,
                    @"likeCount": @0,
                    @"quoteCount": @0,
                    @"indexedAt": record[@"createdAt"] ?: @"",
                    @"viewer": @{},
                    @"labels": @[]
                };
                [posts addObject:postView];
            }
        }

        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        result[@"posts"] = posts;
        result[@"hitsTotal"] = @(posts.count);

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    // app.bsky.feed.getQuotes - Get posts that quote a given post
    [dispatcher registerMethod:@"app.bsky.feed.getQuotes" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *uri = [request queryParamForKey:@"uri"];
        if (!uri) {
            [XrpcErrorHelper setValidationError:response message:@"Missing uri parameter"];
            return;
        }

        NSInteger limit = 50;
        NSString *cursor = [request queryParamForKey:@"cursor"];

        // Scan post records for embeds that reference this URI
        NSString *query = @"SELECT did, rkey, cid FROM records WHERE collection = ? ORDER BY rkey DESC LIMIT ?";
        NSError *error = nil;
        NSArray *rows = [appViewDatabase executeParameterizedQuery:query params:@[@"app.bsky.feed.post", @(limit * 5)] error:&error];

        NSMutableArray *posts = [NSMutableArray array];
        for (NSDictionary *row in rows) {
            if ((NSInteger)posts.count >= limit) break;

            NSString *postDID = row[@"did"];
            NSString *cidStr = row[@"cid"];
            CID *cid = [CID cidFromString:cidStr];
            if (!cid) continue;
            PDSDatabaseBlock *block = [appViewDatabase getBlockWithCid:cid.bytes repoDid:postDID error:nil];
            if (!block || !block.blockData) continue;
            NSDictionary *record = [ATProtoCBORSerialization JSONObjectWithData:block.blockData error:nil];
            if (!record) continue;

            // Check if this post embeds/quotes the target URI
            NSDictionary *embed = record[@"embed"];
            if (!embed) continue;

            NSString *embedType = embed[@"$type"];
            BOOL isQuote = NO;

            if ([embedType isEqualToString:@"app.bsky.embed.record"]) {
                NSDictionary *embedRecord = embed[@"record"];
                if ([embedRecord[@"uri"] isEqualToString:uri]) {
                    isQuote = YES;
                }
            } else if ([embedType isEqualToString:@"app.bsky.embed.recordWithMedia"]) {
                NSDictionary *embedRecord = embed[@"record"][@"record"];
                if ([embedRecord[@"uri"] isEqualToString:uri]) {
                    isQuote = YES;
                }
            }

            if (isQuote) {
                NSString *rkey = row[@"rkey"];
                NSString *postURI = [NSString stringWithFormat:@"at://%@/app.bsky.feed.post/%@", postDID, rkey];
                NSDictionary *postView = @{
                    @"uri": postURI,
                    @"cid": cidStr ?: @"",
                    @"author": [actorService getProfileForActor:postDID error:nil] ?: @{@"did": postDID},
                    @"record": record,
                    @"replyCount": @0,
                    @"repostCount": @0,
                    @"likeCount": @0,
                    @"quoteCount": @0,
                    @"indexedAt": record[@"createdAt"] ?: @"",
                    @"viewer": @{},
                    @"labels": @[]
                };
                [posts addObject:postView];
            }
        }

        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        result[@"uri"] = uri;
        result[@"posts"] = posts;

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    // app.bsky.feed.describeFeedGenerator - Describe this server's feed generator
    [dispatcher registerMethod:@"app.bsky.feed.describeFeedGenerator" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{
            @"did": @"",
            @"feeds": @[],
            @"links": @{}
        }];
    }];

    // app.bsky.feed.sendInteractions - Log feed interactions
    [dispatcher registerMethod:@"app.bsky.feed.sendInteractions" handler:^(HttpRequest *request, HttpResponse *response) {
        // Accept interaction data but don't persist — single-user PDS doesn't need analytics
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    // app.bsky.feed.getListFeed - Get feed from a list
    [dispatcher registerMethod:@"app.bsky.feed.getListFeed" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *list = [request queryParamForKey:@"list"];
        if (!list) {
            [XrpcErrorHelper setValidationError:response message:@"Missing list parameter"];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"feed": @[]}];
    }];

    // app.bsky.graph.getLists - Get lists created by an actor
    [dispatcher registerMethod:@"app.bsky.graph.getLists" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *actor = [request queryParamForKey:@"actor"];
        if (!actor) {
            [XrpcErrorHelper setValidationError:response message:@"Missing actor parameter"];
            return;
        }

        NSInteger limit = 50;
        NSString *cursor = [request queryParamForKey:@"cursor"];

        // Query app.bsky.graph.list records
        NSString *query = @"SELECT rkey, cid FROM records WHERE did = ? AND collection = ?";
        if (cursor) {
            query = [query stringByAppendingString:@" AND rkey < ?"];
        }
        query = [query stringByAppendingString:@" ORDER BY rkey DESC LIMIT ?"];

        NSMutableArray *args = [NSMutableArray arrayWithObjects:actor, @"app.bsky.graph.list", nil];
        if (cursor) [args addObject:cursor];
        [args addObject:@(limit)];

        NSError *error = nil;
        NSArray *rows = [appViewDatabase executeParameterizedQuery:query params:args error:&error];
        NSMutableArray *lists = [NSMutableArray array];

        for (NSDictionary *row in rows) {
            NSString *cidStr = row[@"cid"];
            CID *cid = [CID cidFromString:cidStr];
            if (!cid) continue;
            PDSDatabaseBlock *block = [appViewDatabase getBlockWithCid:cid.bytes repoDid:actor error:nil];
            if (!block || !block.blockData) continue;
            NSDictionary *record = [ATProtoCBORSerialization JSONObjectWithData:block.blockData error:nil];
            if (!record) continue;

            NSString *rkey = row[@"rkey"];
            NSString *uri = [NSString stringWithFormat:@"at://%@/app.bsky.graph.list/%@", actor, rkey];
            NSDictionary *listView = @{
                @"uri": uri,
                @"cid": cidStr ?: @"",
                @"creator": [actorService getProfileForActor:actor error:nil] ?: @{@"did": actor},
                @"name": record[@"name"] ?: @"",
                @"purpose": record[@"purpose"] ?: @"app.bsky.graph.defs#modlist",
                @"description": record[@"description"] ?: @"",
                @"indexedAt": record[@"createdAt"] ?: @"",
                @"viewer": @{@"muted": @NO},
                @"labels": @[]
            };
            [lists addObject:listView];
        }

        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        result[@"lists"] = lists;
        if (lists.count >= (NSUInteger)limit) {
            result[@"cursor"] = [rows lastObject][@"rkey"];
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    // app.bsky.graph.getList - Get a single list by URI
    [dispatcher registerMethod:@"app.bsky.graph.getList" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *list = [request queryParamForKey:@"list"];
        if (!list) {
            [XrpcErrorHelper setValidationError:response message:@"Missing list parameter"];
            return;
        }

        NSArray *components = [list componentsSeparatedByString:@"/"];
        if (components.count < 5) {
            [XrpcErrorHelper setValidationError:response message:@"Invalid list URI"];
            return;
        }
        NSString *did = components[2];
        NSString *rkey = components[4];

        NSString *query = @"SELECT cid FROM records WHERE did = ? AND collection = ? AND rkey = ? LIMIT 1";
        NSError *error = nil;
        NSArray *rows = [appViewDatabase executeParameterizedQuery:query params:@[did, @"app.bsky.graph.list", rkey] error:&error];

        if (rows.count == 0) {
            response.statusCode = 404;
            [response setJsonBody:@{@"error": @"NotFound", @"message": @"List not found"}];
            return;
        }

        NSString *cidStr = rows[0][@"cid"];
        CID *cid = [CID cidFromString:cidStr];
        NSDictionary *record = nil;
        if (cid) {
            PDSDatabaseBlock *block = [appViewDatabase getBlockWithCid:cid.bytes repoDid:did error:nil];
            if (block && block.blockData) {
                record = [ATProtoCBORSerialization JSONObjectWithData:block.blockData error:nil];
            }
        }

        NSDictionary *listView = @{
            @"uri": list,
            @"cid": cidStr ?: @"",
            @"creator": [actorService getProfileForActor:did error:nil] ?: @{@"did": did},
            @"name": record[@"name"] ?: @"",
            @"purpose": record[@"purpose"] ?: @"app.bsky.graph.defs#modlist",
            @"description": record[@"description"] ?: @"",
            @"indexedAt": record[@"createdAt"] ?: @"",
            @"viewer": @{@"muted": @NO},
            @"labels": @[]
        };

        // Get list items
        NSString *itemQuery = @"SELECT rkey, cid FROM records WHERE did = ? AND collection = ? ORDER BY rkey DESC LIMIT 100";
        NSArray *itemRows = [appViewDatabase executeParameterizedQuery:itemQuery params:@[did, @"app.bsky.graph.listitem"] error:nil];
        NSMutableArray *items = [NSMutableArray array];

        for (NSDictionary *itemRow in itemRows) {
            NSString *itemCidStr = itemRow[@"cid"];
            CID *itemCid = [CID cidFromString:itemCidStr];
            if (!itemCid) continue;
            PDSDatabaseBlock *itemBlock = [appViewDatabase getBlockWithCid:itemCid.bytes repoDid:did error:nil];
            if (!itemBlock || !itemBlock.blockData) continue;
            NSDictionary *itemRecord = [ATProtoCBORSerialization JSONObjectWithData:itemBlock.blockData error:nil];
            if (!itemRecord) continue;

            // Check if item belongs to this list
            NSString *itemList = itemRecord[@"list"];
            if (![itemList isEqualToString:list]) continue;

            NSString *subjectDID = itemRecord[@"subject"];
            if (subjectDID) {
                NSDictionary *subjectProfile = [actorService getProfileForActor:subjectDID error:nil];
                [items addObject:@{
                    @"uri": [NSString stringWithFormat:@"at://%@/app.bsky.graph.listitem/%@", did, itemRow[@"rkey"]],
                    @"subject": subjectProfile ?: @{@"did": subjectDID, @"handle": @"handle.invalid"}
                }];
            }
        }

        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        result[@"list"] = listView;
        result[@"items"] = items;

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    // app.bsky.graph.getListMutes - Get lists the viewer has muted
    [dispatcher registerMethod:@"app.bsky.graph.getListMutes" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"lists": @[]}];
    }];

    // app.bsky.graph.getListBlocks - Get lists the viewer has blocked
    [dispatcher registerMethod:@"app.bsky.graph.getListBlocks" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"lists": @[]}];
    }];

    // app.bsky.graph.getListsWithMembership - Get lists with membership status
    [dispatcher registerMethod:@"app.bsky.graph.getListsWithMembership" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"lists": @[]}];
    }];

    // app.bsky.graph.getKnownFollowers - Get followers known to the viewer
    [dispatcher registerMethod:@"app.bsky.graph.getKnownFollowers" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *actor = [request queryParamForKey:@"actor"];
        if (!actor) {
            [XrpcErrorHelper setValidationError:response message:@"Missing actor parameter"];
            return;
        }

        NSDictionary *subject = [actorService getProfileForActor:actor error:nil] ?: @{@"did": actor};
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"subject": subject, @"followers": @[]}];
    }];

    // app.bsky.graph.getSuggestedFollowsByActor - Suggest follows
    [dispatcher registerMethod:@"app.bsky.graph.getSuggestedFollowsByActor" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"suggestions": @[]}];
    }];

    // app.bsky.graph.muteActorList - Mute a list
    [dispatcher registerMethod:@"app.bsky.graph.muteActorList" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    // app.bsky.graph.unmuteActorList - Unmute a list
    [dispatcher registerMethod:@"app.bsky.graph.unmuteActorList" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    // app.bsky.graph.muteThread - Mute a thread
    [dispatcher registerMethod:@"app.bsky.graph.muteThread" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    // app.bsky.graph.unmuteThread - Unmute a thread
    [dispatcher registerMethod:@"app.bsky.graph.unmuteThread" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    // app.bsky.graph.getActorStarterPacks - Starter packs by actor
    [dispatcher registerMethod:@"app.bsky.graph.getActorStarterPacks" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"starterPacks": @[]}];
    }];

    // app.bsky.graph.getStarterPack - Get starter pack by URI
    [dispatcher registerMethod:@"app.bsky.graph.getStarterPack" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = 404;
        [response setJsonBody:@{@"error": @"NotFound", @"message": @"Starter pack not found"}];
    }];

    // app.bsky.graph.getStarterPacks - Get multiple starter packs
    [dispatcher registerMethod:@"app.bsky.graph.getStarterPacks" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"starterPacks": @[]}];
    }];

    // app.bsky.graph.searchStarterPacks - Search starter packs
    [dispatcher registerMethod:@"app.bsky.graph.searchStarterPacks" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"starterPacks": @[]}];
    }];

    // app.bsky.actor.getSuggestions - Get suggested accounts
    [dispatcher registerMethod:@"app.bsky.actor.getSuggestions" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"actors": @[]}];
    }];

    // app.bsky.labeler.getServices - Get labeler service views
    [dispatcher registerMethod:@"app.bsky.labeler.getServices" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"views": @[]}];
    }];

    // app.bsky.notification.getPreferences - Get notification preferences
    [dispatcher registerMethod:@"app.bsky.notification.getPreferences" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"preferences": @{}}];
    }];

    // app.bsky.notification.putPreferences - Update notification preferences
    [dispatcher registerMethod:@"app.bsky.notification.putPreferences" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    // app.bsky.notification.listActivitySubscriptions - List activity subscriptions
    [dispatcher registerMethod:@"app.bsky.notification.listActivitySubscriptions" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"subscriptions": @[]}];
    }];

    // app.bsky.video.getJobStatus - Get video processing status
    [dispatcher registerMethod:@"app.bsky.video.getJobStatus" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *jobId = [request queryParamForKey:@"jobId"];
        if (!jobId) {
            [XrpcErrorHelper setValidationError:response message:@"Missing jobId parameter"];
            return;
        }
        response.statusCode = 404;
        [response setJsonBody:@{@"error": @"NotFound", @"message": @"Job not found"}];
    }];

    // app.bsky.video.getUploadLimits - Get video upload limits
    [dispatcher registerMethod:@"app.bsky.video.getUploadLimits" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{
            @"canUpload": @YES,
            @"remainingDailyVideos": @25,
            @"remainingDailyBytes": @(50 * 1024 * 1024),
            @"message": @""
        }];
    }];

    // app.bsky.unspecced.getConfig - Get app config
    [dispatcher registerMethod:@"app.bsky.unspecced.getConfig" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"checkEmailConfirmed": @NO}];
    }];

    // app.bsky.unspecced.getTaggedSuggestions - Get tagged suggestions
    [dispatcher registerMethod:@"app.bsky.unspecced.getTaggedSuggestions" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"suggestions": @[]}];
    }];

    // app.bsky.unspecced.getPopularFeedGenerators - Get popular feed generators
    [dispatcher registerMethod:@"app.bsky.unspecced.getPopularFeedGenerators" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"feeds": @[]}];
    }];

    // app.bsky.unspecced.getSuggestedFeeds - Get suggested feeds (unspecced)
    [dispatcher registerMethod:@"app.bsky.unspecced.getSuggestedFeeds" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"feeds": @[]}];
    }];

    // app.bsky.unspecced.getSuggestedUsers - Get suggested users
    [dispatcher registerMethod:@"app.bsky.unspecced.getSuggestedUsers" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"actors": @[]}];
    }];

    // app.bsky.unspecced.getTrendingTopics - Get trending topics
    [dispatcher registerMethod:@"app.bsky.unspecced.getTrendingTopics" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"topics": @[], @"suggested": @[]}];
    }];
}

#pragma mark - Helper Methods

+ (BOOL)parseLimit:(NSString *)limitParam
          outValue:(NSInteger *)outValue
               min:(NSInteger)min
               max:(NSInteger)max
          response:(HttpResponse *)response {
    if (!limitParam || limitParam.length == 0) {
        return YES; // Use default
    }
    
    NSInteger limit = 0;
    if (!parseIntegerParam(limitParam, &limit, 0)) {
        [XrpcErrorHelper setValidationError:response message:@"Invalid limit parameter"];
        return NO;
    }
    
    if (limit < min || limit > max) {
        NSString *message = [NSString stringWithFormat:@"Limit must be between %ld and %ld", (long)min, (long)max];
        [XrpcErrorHelper setValidationError:response message:message];
        return NO;
    }
    
    if (outValue) *outValue = limit;
    return YES;
}

@end
