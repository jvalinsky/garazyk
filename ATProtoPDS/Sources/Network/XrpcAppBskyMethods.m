#import "Network/XrpcAppBskyMethods.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcAuthHelper.h"
#import "Network/XrpcAppBskyProxyMethodPack.h"
#import "Network/XrpcAppBskyActorPack.h"
#import "Network/XrpcAppBskyFeedPack.h"
#import "Network/XrpcAppBskyGraphPack.h"
#import "Network/XrpcAppBskyNotificationPack.h"
#import "Network/XrpcAppBskyGraphHelpers.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Database/Service/ServiceDatabases.h"
#import "Database/PDSDatabase.h"
#import "Database/Pool/DatabasePool.h"
#import "Admin/PDSAdminController.h"
#import "AppView/ActorService.h"
#import "AppView/FeedService.h"
#import "AppView/NotificationService.h"
#import "AppView/GraphService.h"
#import "AppView/BookmarkService.h"
#import "App/Services/PDSRecordService.h"
#import "Core/CID.h"
#import "Core/ATProtoCBORSerialization.h"
#import "AppView/RecordLifecycleHandler.h"
#import "App/PDSConfiguration.h"
#import "Core/NSDateFormatter+ATProto.h"
#import "Debug/PDSLogger.h"
#import "Identity/ATProtoHandleValidator.h"

#pragma mark - Helper Functions

static BOOL parseIntegerParam(NSString *value, NSInteger *outValue, NSInteger defaultValue) {
    return XrpcParseLimit(value, outValue, 0, INT_MAX, nil) || (outValue && (*outValue = defaultValue, YES));
}

static BOOL parseAtURI(NSString *uri, NSString **outDid, NSString **outCollection, NSString **outRkey) {
    return XrpcParseAtURI(uri, outDid, outCollection, outRkey);
}

static NSString *const kGraphMuteStatePreferenceType = kXrpcGraphMuteStatePreferenceType;

static NSMutableArray<NSDictionary *> *mutablePreferenceEntries(NSDictionary *preferencesEnvelope) {
    return XrpcMutablePreferenceEntries(preferencesEnvelope);
}

static NSMutableArray<NSString *> *normalizedUniqueStringArray(id rawValue) {
    return XrpcNormalizedUniqueStringArray(rawValue);
}

static NSMutableDictionary *graphMuteStateFromPreferences(NSArray<NSDictionary *> *preferences,
                                                          NSUInteger *outIndex) {
    return XrpcGraphMuteStateFromPreferences(preferences, outIndex);
}

static BOOL persistGraphMuteState(ActorService *actorService,
                                  NSString *actorDID,
                                  NSMutableArray<NSDictionary *> *preferences,
                                  NSMutableDictionary *state,
                                  NSUInteger existingIndex,
                                  NSError **error) {
    return XrpcPersistGraphMuteState(actorService, actorDID, preferences, state, existingIndex, error);
}

static NSString *normalizeListPurpose(NSString *purpose) {
    return XrpcNormalizeListPurpose(purpose);
}

static NSString *resolveActorIdentifierToDid(PDSServiceDatabases *serviceDatabases, NSString *actorIdentifier) {
    return XrpcResolveActorIdentifierToDid(serviceDatabases, actorIdentifier);
}

static NSDictionary *loadListItemViewForListAndSubject(PDSDatabase *appViewDatabase,
                                                        ActorService *actorService,
                                                        NSString *creatorDid,
                                                        NSString *listURI,
                                                        NSString *subjectDid) {
    return XrpcLoadListItemViewForListAndSubject(appViewDatabase, actorService, creatorDid, listURI, subjectDid);
}

static NSDictionary *loadListViewForURI(PDSDatabase *appViewDatabase, ActorService *actorService, NSString *listURI) {
    return XrpcLoadListViewForURI(appViewDatabase, actorService, listURI);
}

#pragma mark - XrpcAppBskyMethods Implementation

@interface XrpcAppBskyMethods ()
@end

@implementation XrpcAppBskyMethods

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
              serviceDatabases:(PDSServiceDatabases *)serviceDatabases
                      jwtMinter:(JWTMinter *)jwtMinter
                adminController:(id<PDSAdminController>)adminController {
    
    // Initialize AppView database and services for all bsky methods
    // Even if local app view is disabled, the PDS still must serve get/putPreferences
    NSError *appViewDbError = nil;
    PDSDatabase *appViewDatabase = [serviceDatabases serviceDatabaseWithError:&appViewDbError];
    if (!appViewDatabase && appViewDbError) {
        PDS_LOG_WARN(@"Failed to open service database for app.bsky handlers: %@",
                     appViewDbError.localizedDescription ?: @"unknown error");
    }
    
    ActorService *actorService = [[ActorService alloc] initWithDatabase:appViewDatabase];
    
    // Always register getPreferences and putPreferences, as they belong to the PDS
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

    // app.bsky.notification.getPreferences - Get notification preferences
    [dispatcher registerMethod:@"app.bsky.notification.getPreferences" handler:^(HttpRequest *request, HttpResponse *response) {
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
        
        // Extract notification preferences if they exist, otherwise return defaults
        BOOL priority = NO;
        if (preferences && preferences[@"preferences"] && [preferences[@"preferences"] isKindOfClass:[NSArray class]]) {
            NSArray *prefsList = preferences[@"preferences"];
            for (NSDictionary *pref in prefsList) {
                if ([pref[@"$type"] isEqualToString:@"app.bsky.actor.defs#bskyAppStatePref"]) {
                    // Extract app state preferences if needed
                }
                // Check for notification preferences if stored in actor preferences
                if ([pref[@"$type"] isEqualToString:@"app.bsky.notification.defs#notificationPref"]) {
                    if (pref[@"priority"]) {
                        priority = [pref[@"priority"] boolValue];
                    }
                }
            }
        }
        
        [response setJsonBody:@{@"priority": @(priority)}];
    }];

    // app.bsky.notification.putPreferences - Update notification preferences
    [dispatcher registerMethod:@"app.bsky.notification.putPreferences" handler:^(HttpRequest *request, HttpResponse *response) {
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
        
        BOOL priority = [body[@"priority"] boolValue];
        
        // Update notification preferences inside actor preferences
        NSError *error = nil;
        NSDictionary *currentPrefs = [actorService getPreferencesForActor:actorDID error:&error];
        
        NSMutableArray *prefsList = [NSMutableArray array];
        if (currentPrefs && currentPrefs[@"preferences"] && [currentPrefs[@"preferences"] isKindOfClass:[NSArray class]]) {
            prefsList = [currentPrefs[@"preferences"] mutableCopy];
        }
        
        // Find and update or add notification preference
        BOOL found = NO;
        for (NSUInteger i = 0; i < prefsList.count; i++) {
            NSMutableDictionary *pref = [prefsList[i] mutableCopy];
            if ([pref[@"$type"] isEqualToString:@"app.bsky.notification.defs#notificationPref"]) {
                pref[@"priority"] = @(priority);
                prefsList[i] = pref;
                found = YES;
                break;
            }
        }
        
        if (!found) {
            [prefsList addObject:@{
                @"$type": @"app.bsky.notification.defs#notificationPref",
                @"priority": @(priority)
            }];
        }
        
        
        BOOL success = [actorService putPreferencesForActor:actorDID preferences:prefsList error:&error];
        if (!success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to save preferences"];
            return;
        }
        
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    // Check if local AppView is enabled. If not, we skip registration of the rest of the endpoints
    if (![PDSConfiguration sharedConfiguration].localAppViewEnabled) {
        PDS_LOG_INFO(@"Local AppView disabled; skipping registration of app.bsky.* feed/graph/notification handlers.");
        return;
    }
    
    FeedService *feedService = [[FeedService alloc] initWithDatabase:appViewDatabase];
    NotificationService *notificationService = [[NotificationService alloc] initWithDatabase:appViewDatabase actorService:actorService];
    GraphService *graphService = [[GraphService alloc] initWithDatabase:appViewDatabase];
    BookmarkService *bookmarkService = [[BookmarkService alloc] initWithDatabase:appViewDatabase];
    
    // Initialize record lifecycle handler for notification generation
    __attribute__((unused)) RecordLifecycleHandler *lifecycleHandler =
        [[RecordLifecycleHandler alloc] initWithNotificationService:notificationService
                                                            bookmarkService:bookmarkService
                                                               graphService:graphService
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
    
    
    // app.bsky.actor.searchActors - Search actors with pagination
    [dispatcher registerAppBskyActorSearchActors:^(HttpRequest *request, HttpResponse *response) {
        NSString *term = [request queryParamForKey:@"q"];
        if (!term || term.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"Missing search term (q parameter)"];
            return;
        }
        
        NSInteger limit = 25;
        if (!XrpcParseLimit(request.queryParams[@"limit"], &limit, 1, 100, response)) {
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
        if (!XrpcParseLimit(request.queryParams[@"limit"], &limit, 1, 100, response)) {
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
        if (!XrpcParseLimit(request.queryParams[@"limit"], &limit, 1, 100, response)) {
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
        if (!XrpcParseLimit(request.queryParams[@"limit"], &limit, 1, 100, response)) {
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
        if (!XrpcParseLimit(request.queryParams[@"limit"], &limit, 1, 100, response)) {
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
        if (!XrpcParseLimit(request.queryParams[@"limit"], &limit, 1, 100, response)) {
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
        id feedsParam = request.queryParams[@"feeds"];
        NSArray<NSString *> *feedURIs = nil;
        if ([feedsParam isKindOfClass:[NSArray class]]) {
            feedURIs = (NSArray<NSString *> *)feedsParam;
        } else if ([feedsParam isKindOfClass:[NSString class]]) {
            feedURIs = @[ (NSString *)feedsParam ];
        } else {
            [XrpcErrorHelper setValidationError:response message:@"Missing feeds parameter"];
            return;
        }

        if (feedURIs.count > 100) {
            [XrpcErrorHelper setValidationError:response message:@"feeds must contain at most 100 URIs"];
            return;
        }

        NSMutableArray<NSDictionary *> *feeds = [NSMutableArray arrayWithCapacity:feedURIs.count];
        for (NSString *feedURI in feedURIs) {
            NSString *did = nil;
            NSString *collection = nil;
            NSString *rkey = nil;
            if (!parseAtURI(feedURI, &did, &collection, &rkey) ||
                ![collection isEqualToString:@"app.bsky.feed.generator"]) {
                [XrpcErrorHelper setValidationError:response message:@"feeds must contain valid app.bsky.feed.generator URIs"];
                return;
            }

            NSArray *rows = [appViewDatabase executeParameterizedQuery:@"SELECT cid FROM records WHERE did = ? AND collection = ? AND rkey = ? LIMIT 1"
                                                                params:@[did, collection, rkey]
                                                                 error:nil];
            if (rows.count == 0) {
                continue;
            }

            NSString *cidStr = rows.firstObject[@"cid"];
            CID *cid = [CID cidFromString:cidStr];
            NSDictionary *record = nil;
            if (cid) {
                PDSDatabaseBlock *block = [appViewDatabase getBlockWithCid:cid.bytes repoDid:did error:nil];
                if (block.blockData) {
                    record = [ATProtoCBORSerialization JSONObjectWithData:block.blockData error:nil];
                }
            }

            [feeds addObject:@{
                @"uri": feedURI,
                @"cid": cidStr ?: @"",
                @"did": did,
                @"creator": [actorService getProfileForActor:did error:nil] ?: @{@"did": did},
                @"displayName": record[@"displayName"] ?: @"",
                @"description": record[@"description"] ?: @"",
                @"avatar": record[@"avatar"] ?: [NSNull null],
                @"indexedAt": record[@"createdAt"] ?: @""
            }];
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"feeds": feeds}];
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
        if (!XrpcParseLimit(request.queryParams[@"limit"], &limit, 1, 100, response)) {
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
        if (!XrpcParseLimit(request.queryParams[@"limit"], &limit, 1, 100, response)) {
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
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to load mutes"];
            return;
        }
        
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
        if (!XrpcParseLimit(request.queryParams[@"limit"], &limit, 1, 100, response)) {
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

    // app.bsky.bookmark.getBookmarks - Get bookmarks for an actor
    [dispatcher registerAppBskyBookmarkGetBookmarks:^(HttpRequest *request, HttpResponse *response) {
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
        if (!actorDID) return;

        NSInteger limit = 50;
        if (!XrpcParseLimit(request.queryParams[@"limit"], &limit, 1, 100, response)) {
            return;
        }

        NSString *cursor = [request queryParamForKey:@"cursor"];

        NSError *error = nil;
        NSDictionary *result = [bookmarkService getBookmarksForActor:actorDID
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

    // app.bsky.bookmark.createBookmark - Create a private bookmark
    [dispatcher registerAppBskyBookmarkCreateBookmark:^(HttpRequest *request, HttpResponse *response) {
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
        if (!actorDID) return;

        NSDictionary *body = [request jsonBody];
        NSString *subjectURI = body[@"uri"];
        NSString *subjectCID = body[@"cid"];

        if (!subjectURI) {
            [XrpcErrorHelper setValidationError:response message:@"Missing uri"];
            return;
        }

        NSString *now = [NSDateFormatter atproto_stringFromDate:[NSDate date]];
        NSError *error = nil;
        BOOL success = [bookmarkService indexBookmarkWithDid:actorDID
                                                  subjectURI:subjectURI
                                                  subjectCID:subjectCID
                                                   createdAt:now
                                                       error:&error];
        if (!success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    // app.bsky.bookmark.deleteBookmark - Delete a private bookmark
    [dispatcher registerAppBskyBookmarkDeleteBookmark:^(HttpRequest *request, HttpResponse *response) {
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
        if (!actorDID) return;

        NSDictionary *body = [request jsonBody];
        NSString *subjectURI = body[@"uri"];

        if (!subjectURI) {
            [XrpcErrorHelper setValidationError:response message:@"Missing uri"];
            return;
        }

        NSError *error = nil;
        BOOL success = [bookmarkService unindexBookmarkWithSubjectURI:subjectURI
                                                              did:actorDID
                                                            error:&error];
        if (!success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    // app.bsky.graph.getStarterPack - Get details for a specific starter pack
    [dispatcher registerAppBskyGraphGetStarterPack:^(HttpRequest *request, HttpResponse *response) {
        NSString *starterPackURI = [request queryParamForKey:@"starterPack"];
        if (!starterPackURI) {
            [XrpcErrorHelper setValidationError:response message:@"Missing starterPack parameter"];
            return;
        }

        NSError *error = nil;
        NSDictionary *result = [graphService getStarterPack:starterPackURI error:&error];
        if (error) {
            [XrpcErrorHelper setNotFoundError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    // app.bsky.graph.getActorStarterPacks - Get starter packs created by an actor
    [dispatcher registerAppBskyGraphGetActorStarterPacks:^(HttpRequest *request, HttpResponse *response) {
        NSString *actor = [request queryParamForKey:@"actor"];
        if (!actor) {
            [XrpcErrorHelper setValidationError:response message:@"Missing actor parameter"];
            return;
        }

        NSInteger limit = 50;
        if (!XrpcParseLimit(request.queryParams[@"limit"], &limit, 1, 100, response)) {
            return;
        }

        NSString *cursor = [request queryParamForKey:@"cursor"];

        NSError *error = nil;
        NSDictionary *result = [graphService getStarterPacksForActor:actor
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

    // app.bsky.graph.getStarterPacks - Get multiple starter packs by URIs
    [dispatcher registerAppBskyGraphGetStarterPacks:^(HttpRequest *request, HttpResponse *response) {
        NSArray *uris = request.queryParams[@"uris"];
        if (!uris || uris.count == 0) {
            [XrpcErrorHelper setValidationError:response message:@"Missing uris parameter"];
            return;
        }

        NSMutableArray *starterPacks = [NSMutableArray array];
        for (NSString *uri in uris) {
            NSError *error = nil;
            NSDictionary *result = [graphService getStarterPack:uri error:&error];
            if (result && result[@"starterPack"]) {
                [starterPacks addObject:result[@"starterPack"]];
            }
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"starterPacks": starterPacks}];
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

    // app.bsky.feed.getFeedSkeleton - Get skeleton of a feed from a feed generator
    [dispatcher registerMethod:@"app.bsky.feed.getFeedSkeleton" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *feed = [request queryParamForKey:@"feed"];
        if (!feed || feed.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"Missing feed parameter"];
            return;
        }

        NSInteger limit = 50;
        if (!XrpcParseLimit(request.queryParams[@"limit"], &limit, 1, 100, response)) {
            return;
        }

        NSString *cursor = [request queryParamForKey:@"cursor"];

        NSArray *feedComponents = [feed componentsSeparatedByString:@"/"];
        if (feedComponents.count < 5) {
            response.statusCode = 400;
            [response setJsonBody:@{@"error": @"UnknownFeed", @"message": @"Unknown feed"}];
            return;
        }
        NSString *feedDid = feedComponents[2];
        NSString *feedCollection = feedComponents[3];
        NSString *feedRkey = feedComponents[4];

        if (![feedCollection isEqualToString:@"app.bsky.feed.generator"]) {
            response.statusCode = 400;
            [response setJsonBody:@{@"error": @"UnknownFeed", @"message": @"Unknown feed"}];
            return;
        }

        NSString *query = @"SELECT rkey, cid FROM records WHERE did = ? AND collection = ?";
        NSMutableArray *args = [NSMutableArray arrayWithObjects:feedDid, @"app.bsky.feed.post", nil];
        if (cursor.length > 0) {
            query = [query stringByAppendingString:@" AND rkey < ?"];
            [args addObject:cursor];
        }
        query = [query stringByAppendingString:@" ORDER BY rkey DESC LIMIT ?"];
        [args addObject:@(limit)];

        NSError *queryError = nil;
        NSArray *rows = [appViewDatabase executeParameterizedQuery:query params:args error:&queryError];
        if (!rows) {
            [XrpcErrorHelper setInternalServerError:response message:queryError.localizedDescription ?: @"Failed to query feed"];
            return;
        }

        NSMutableArray *skeletonFeed = [NSMutableArray array];
        for (NSDictionary *row in rows) {
            NSString *postRkey = row[@"rkey"];
            NSString *postURI = [NSString stringWithFormat:@"at://%@/app.bsky.feed.post/%@", feedDid, postRkey ?: @""];
            [skeletonFeed addObject:@{@"post": postURI}];
        }

        NSMutableDictionary *result = [NSMutableDictionary dictionaryWithObject:skeletonFeed forKey:@"feed"];
        if (rows.count >= (NSUInteger)limit && rows.lastObject[@"rkey"]) {
            result[@"cursor"] = rows.lastObject[@"rkey"];
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
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
        if (!XrpcParseLimit(request.queryParams[@"limit"], &limit, 1, 100, response)) {
            return;
        }

        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSInteger offset = 0;
        if (cursor.length > 0 && !parseIntegerParam(cursor, &offset, 0)) {
            [XrpcErrorHelper setValidationError:response message:@"Invalid cursor"];
            return;
        }
        if (offset < 0) {
            offset = 0;
        }

        NSError *prefsError = nil;
        NSDictionary *currentPrefs = [actorService getPreferencesForActor:actorDID error:&prefsError];
        if (prefsError) {
            [XrpcErrorHelper setInternalServerError:response message:prefsError.localizedDescription ?: @"Failed to load preferences"];
            return;
        }

        NSMutableArray<NSDictionary *> *prefsList = mutablePreferenceEntries(currentPrefs);
        NSMutableDictionary *muteState = graphMuteStateFromPreferences(prefsList, NULL);
        NSArray<NSString *> *mutedListURIs = normalizedUniqueStringArray(muteState[@"mutedLists"]);

        NSUInteger startIndex = (NSUInteger)MIN((NSInteger)mutedListURIs.count, offset);
        NSUInteger endIndex = MIN(startIndex + (NSUInteger)limit, mutedListURIs.count);

        NSMutableArray<NSDictionary *> *lists = [NSMutableArray array];
        for (NSUInteger index = startIndex; index < endIndex; index++) {
            NSString *listURI = mutedListURIs[index];
            NSDictionary *listView = loadListViewForURI(appViewDatabase, actorService, listURI);
            if (listView) {
                [lists addObject:listView];
            }
        }

        NSMutableDictionary *result = [@{@"lists": lists} mutableCopy];
        if (endIndex < mutedListURIs.count) {
            result[@"cursor"] = [NSString stringWithFormat:@"%lu", (unsigned long)endIndex];
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    // app.bsky.graph.getListBlocks - Get lists the viewer has blocked
    [dispatcher registerMethod:@"app.bsky.graph.getListBlocks" handler:^(HttpRequest *request, HttpResponse *response) {
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
        if (!XrpcParseLimit(request.queryParams[@"limit"], &limit, 1, 100, response)) {
            return;
        }

        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSString *query = @"SELECT rkey, cid FROM records WHERE did = ? AND collection = ?";
        NSMutableArray *params = [NSMutableArray arrayWithObjects:actorDID, @"app.bsky.graph.listblock", nil];
        if (cursor.length > 0) {
            query = [query stringByAppendingString:@" AND rkey < ?"];
            [params addObject:cursor];
        }
        query = [query stringByAppendingString:@" ORDER BY rkey DESC LIMIT ?"];
        [params addObject:@(limit)];

        NSError *queryError = nil;
        NSArray<NSDictionary *> *rows = [appViewDatabase executeParameterizedQuery:query
                                                                             params:params
                                                                              error:&queryError];
        if (!rows) {
            [XrpcErrorHelper setInternalServerError:response message:queryError.localizedDescription ?: @"Failed to query list blocks"];
            return;
        }

        NSMutableArray<NSDictionary *> *lists = [NSMutableArray array];
        for (NSDictionary *row in rows) {
            NSString *cidStr = row[@"cid"];
            CID *cid = [CID cidFromString:cidStr];
            if (!cid) continue;
            PDSDatabaseBlock *block = [appViewDatabase getBlockWithCid:cid.bytes repoDid:actorDID error:nil];
            if (!block.blockData) continue;

            NSDictionary *record = [ATProtoCBORSerialization JSONObjectWithData:block.blockData error:nil];
            NSString *listURI = [record[@"list"] isKindOfClass:[NSString class]] ? record[@"list"] : nil;
            NSDictionary *listView = loadListViewForURI(appViewDatabase, actorService, listURI);
            if (listView) {
                [lists addObject:listView];
            }
        }

        NSMutableDictionary *result = [@{@"lists": lists} mutableCopy];
        if (rows.count == (NSUInteger)limit && rows.lastObject[@"rkey"]) {
            result[@"cursor"] = rows.lastObject[@"rkey"];
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    // app.bsky.graph.getListsWithMembership - Get lists with membership status
    [dispatcher registerMethod:@"app.bsky.graph.getListsWithMembership" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        if (!authHeader) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }

        NSString *viewerDid = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                              jwtMinter:jwtMinter
                                                        adminController:adminController
                                                                request:request
                                                               response:response];
        if (!viewerDid) {
            return;
        }

        NSString *actor = [request queryParamForKey:@"actor"];
        if (actor.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"Missing actor parameter"];
            return;
        }

        NSString *subjectDid = resolveActorIdentifierToDid(serviceDatabases, actor);
        if (!subjectDid) {
            [XrpcErrorHelper setNotFoundError:response message:@"Actor not found"];
            return;
        }

        NSInteger limit = 50;
        if (!XrpcParseLimit(request.queryParams[@"limit"], &limit, 1, 100, response)) {
            return;
        }
        NSString *cursor = [request queryParamForKey:@"cursor"];

        NSMutableSet<NSString *> *allowedPurposes = [NSMutableSet set];
        id rawPurposes = request.queryParams[@"purposes"];
        if ([rawPurposes isKindOfClass:[NSString class]]) {
            NSString *normalizedPurpose = normalizeListPurpose((NSString *)rawPurposes);
            if (!normalizedPurpose) {
                [XrpcErrorHelper setValidationError:response message:@"Invalid purposes value"];
                return;
            }
            [allowedPurposes addObject:normalizedPurpose];
        } else if ([rawPurposes isKindOfClass:[NSArray class]]) {
            for (id purpose in (NSArray *)rawPurposes) {
                NSString *normalizedPurpose = normalizeListPurpose(purpose);
                if (!normalizedPurpose) {
                    [XrpcErrorHelper setValidationError:response message:@"Invalid purposes value"];
                    return;
                }
                [allowedPurposes addObject:normalizedPurpose];
            }
        } else if (rawPurposes != nil) {
            [XrpcErrorHelper setValidationError:response message:@"Invalid purposes parameter"];
            return;
        }

        NSMutableString *query = [NSMutableString stringWithString:
                                  @"SELECT rkey, cid FROM records WHERE did = ? AND collection = ?"];
        NSMutableArray *params = [NSMutableArray arrayWithObjects:viewerDid, @"app.bsky.graph.list", nil];
        if (cursor.length > 0) {
            [query appendString:@" AND rkey < ?"];
            [params addObject:cursor];
        }
        [query appendString:@" ORDER BY rkey DESC LIMIT ?"];
        NSInteger scanLimit = MAX(limit * 4, limit);
        [params addObject:@(scanLimit)];

        NSError *queryError = nil;
        NSArray<NSDictionary *> *rows = [appViewDatabase executeParameterizedQuery:query params:params error:&queryError];
        if (!rows) {
            [XrpcErrorHelper setInternalServerError:response message:queryError.localizedDescription ?: @"Failed to query lists"];
            return;
        }

        NSMutableArray<NSDictionary *> *listsWithMembership = [NSMutableArray array];
        NSString *nextCursor = nil;
        for (NSDictionary *row in rows) {
            if ((NSInteger)listsWithMembership.count >= limit) {
                nextCursor = row[@"rkey"];
                break;
            }

            NSString *cidStr = row[@"cid"];
            CID *cid = [CID cidFromString:cidStr];
            if (!cid) continue;
            PDSDatabaseBlock *block = [appViewDatabase getBlockWithCid:cid.bytes repoDid:viewerDid error:nil];
            if (!block.blockData) continue;

            NSDictionary *record = [ATProtoCBORSerialization JSONObjectWithData:block.blockData error:nil];
            if (![record isKindOfClass:[NSDictionary class]]) continue;

            NSString *purpose = normalizeListPurpose(record[@"purpose"]) ?: @"app.bsky.graph.defs#modlist";
            if (allowedPurposes.count > 0 && ![allowedPurposes containsObject:purpose]) {
                continue;
            }

            NSString *rkey = row[@"rkey"];
            NSString *listURI = [NSString stringWithFormat:@"at://%@/app.bsky.graph.list/%@", viewerDid, rkey ?: @""];
            NSDictionary *listView = @{
                @"uri": listURI,
                @"cid": cidStr ?: @"",
                @"creator": [actorService getProfileForActor:viewerDid error:nil] ?: @{@"did": viewerDid},
                @"name": record[@"name"] ?: @"",
                @"purpose": purpose,
                @"description": record[@"description"] ?: @"",
                @"indexedAt": record[@"createdAt"] ?: @"",
                @"viewer": @{@"muted": @NO},
                @"labels": @[]
            };

            NSMutableDictionary *entry = [NSMutableDictionary dictionaryWithObject:listView forKey:@"list"];
            NSDictionary *listItemView = loadListItemViewForListAndSubject(appViewDatabase,
                                                                            actorService,
                                                                            viewerDid,
                                                                            listURI,
                                                                            subjectDid);
            if (listItemView) {
                entry[@"listItem"] = listItemView;
            }
            [listsWithMembership addObject:entry];
        }

        NSMutableDictionary *result = [NSMutableDictionary dictionaryWithObject:listsWithMembership
                                                                          forKey:@"listsWithMembership"];
        if (nextCursor.length > 0) {
            result[@"cursor"] = nextCursor;
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
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
        NSString *listURI = [body[@"list"] isKindOfClass:[NSString class]] ? body[@"list"] : nil;
        NSString *did = nil;
        NSString *collection = nil;
        NSString *rkey = nil;
        if (listURI.length == 0 ||
            !parseAtURI(listURI, &did, &collection, &rkey) ||
            ![collection isEqualToString:@"app.bsky.graph.list"]) {
            [XrpcErrorHelper setValidationError:response message:@"Invalid list URI"];
            return;
        }

        NSError *prefsError = nil;
        NSDictionary *currentPrefs = [actorService getPreferencesForActor:actorDID error:&prefsError];
        if (prefsError) {
            [XrpcErrorHelper setInternalServerError:response message:prefsError.localizedDescription ?: @"Failed to load preferences"];
            return;
        }

        NSMutableArray<NSDictionary *> *prefsList = mutablePreferenceEntries(currentPrefs);
        NSUInteger existingIndex = NSNotFound;
        NSMutableDictionary *muteState = graphMuteStateFromPreferences(prefsList, &existingIndex);
        NSMutableArray<NSString *> *mutedLists = normalizedUniqueStringArray(muteState[@"mutedLists"]);
        if (![mutedLists containsObject:listURI]) {
            [mutedLists addObject:listURI];
        }
        muteState[@"mutedLists"] = mutedLists;

        NSError *saveError = nil;
        if (!persistGraphMuteState(actorService, actorDID, prefsList, muteState, existingIndex, &saveError)) {
            [XrpcErrorHelper setInternalServerError:response message:saveError.localizedDescription ?: @"Failed to persist list mute"];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    // app.bsky.graph.unmuteActorList - Unmute a list
    [dispatcher registerMethod:@"app.bsky.graph.unmuteActorList" handler:^(HttpRequest *request, HttpResponse *response) {
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
        NSString *listURI = [body[@"list"] isKindOfClass:[NSString class]] ? body[@"list"] : nil;
        NSString *did = nil;
        NSString *collection = nil;
        NSString *rkey = nil;
        if (listURI.length == 0 ||
            !parseAtURI(listURI, &did, &collection, &rkey) ||
            ![collection isEqualToString:@"app.bsky.graph.list"]) {
            [XrpcErrorHelper setValidationError:response message:@"Invalid list URI"];
            return;
        }

        NSError *prefsError = nil;
        NSDictionary *currentPrefs = [actorService getPreferencesForActor:actorDID error:&prefsError];
        if (prefsError) {
            [XrpcErrorHelper setInternalServerError:response message:prefsError.localizedDescription ?: @"Failed to load preferences"];
            return;
        }

        NSMutableArray<NSDictionary *> *prefsList = mutablePreferenceEntries(currentPrefs);
        NSUInteger existingIndex = NSNotFound;
        NSMutableDictionary *muteState = graphMuteStateFromPreferences(prefsList, &existingIndex);
        NSMutableArray<NSString *> *mutedLists = normalizedUniqueStringArray(muteState[@"mutedLists"]);
        [mutedLists removeObject:listURI];
        muteState[@"mutedLists"] = mutedLists;

        NSError *saveError = nil;
        if (!persistGraphMuteState(actorService, actorDID, prefsList, muteState, existingIndex, &saveError)) {
            [XrpcErrorHelper setInternalServerError:response message:saveError.localizedDescription ?: @"Failed to persist list mute"];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    // app.bsky.graph.muteThread - Mute a thread
    [dispatcher registerMethod:@"app.bsky.graph.muteThread" handler:^(HttpRequest *request, HttpResponse *response) {
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
        NSString *rootURI = [body[@"root"] isKindOfClass:[NSString class]] ? body[@"root"] : nil;
        NSString *did = nil;
        NSString *collection = nil;
        NSString *rkey = nil;
        if (rootURI.length == 0 || !parseAtURI(rootURI, &did, &collection, &rkey)) {
            [XrpcErrorHelper setValidationError:response message:@"Invalid root URI"];
            return;
        }

        NSError *prefsError = nil;
        NSDictionary *currentPrefs = [actorService getPreferencesForActor:actorDID error:&prefsError];
        if (prefsError) {
            [XrpcErrorHelper setInternalServerError:response message:prefsError.localizedDescription ?: @"Failed to load preferences"];
            return;
        }

        NSMutableArray<NSDictionary *> *prefsList = mutablePreferenceEntries(currentPrefs);
        NSUInteger existingIndex = NSNotFound;
        NSMutableDictionary *muteState = graphMuteStateFromPreferences(prefsList, &existingIndex);
        NSMutableArray<NSString *> *mutedThreads = normalizedUniqueStringArray(muteState[@"mutedThreads"]);
        if (![mutedThreads containsObject:rootURI]) {
            [mutedThreads addObject:rootURI];
        }
        muteState[@"mutedThreads"] = mutedThreads;

        NSError *saveError = nil;
        if (!persistGraphMuteState(actorService, actorDID, prefsList, muteState, existingIndex, &saveError)) {
            [XrpcErrorHelper setInternalServerError:response message:saveError.localizedDescription ?: @"Failed to persist thread mute"];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    // app.bsky.graph.unmuteThread - Unmute a thread
    [dispatcher registerMethod:@"app.bsky.graph.unmuteThread" handler:^(HttpRequest *request, HttpResponse *response) {
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
        NSString *rootURI = [body[@"root"] isKindOfClass:[NSString class]] ? body[@"root"] : nil;
        NSString *did = nil;
        NSString *collection = nil;
        NSString *rkey = nil;
        if (rootURI.length == 0 || !parseAtURI(rootURI, &did, &collection, &rkey)) {
            [XrpcErrorHelper setValidationError:response message:@"Invalid root URI"];
            return;
        }

        NSError *prefsError = nil;
        NSDictionary *currentPrefs = [actorService getPreferencesForActor:actorDID error:&prefsError];
        if (prefsError) {
            [XrpcErrorHelper setInternalServerError:response message:prefsError.localizedDescription ?: @"Failed to load preferences"];
            return;
        }

        NSMutableArray<NSDictionary *> *prefsList = mutablePreferenceEntries(currentPrefs);
        NSUInteger existingIndex = NSNotFound;
        NSMutableDictionary *muteState = graphMuteStateFromPreferences(prefsList, &existingIndex);
        NSMutableArray<NSString *> *mutedThreads = normalizedUniqueStringArray(muteState[@"mutedThreads"]);
        [mutedThreads removeObject:rootURI];
        muteState[@"mutedThreads"] = mutedThreads;

        NSError *saveError = nil;
        if (!persistGraphMuteState(actorService, actorDID, prefsList, muteState, existingIndex, &saveError)) {
            [XrpcErrorHelper setInternalServerError:response message:saveError.localizedDescription ?: @"Failed to persist thread mute"];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    // app.bsky.graph.searchStarterPacks - Search starter packs
    [dispatcher registerMethod:@"app.bsky.graph.searchStarterPacks" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"starterPacks": @[]}];
    }];

    // app.bsky.graph.getStarterPacksWithMembership - Get owned starter packs with membership info
    [dispatcher registerMethod:@"app.bsky.graph.getStarterPacksWithMembership" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        if (!authHeader) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }

        NSString *ownerDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
        if (!ownerDID) {
            return;
        }

        NSString *actor = [request queryParamForKey:@"actor"];
        if (!actor || actor.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"Missing actor parameter"];
            return;
        }

        NSString *memberDid = resolveActorIdentifierToDid(serviceDatabases, actor);
        if (!memberDid) {
            [XrpcErrorHelper setNotFoundError:response message:@"Actor not found"];
            return;
        }

        NSInteger limit = 50;
        if (!XrpcParseLimit(request.queryParams[@"limit"], &limit, 1, 100, response)) {
            return;
        }

        NSString *cursor = [request queryParamForKey:@"cursor"];

        NSMutableString *query = [NSMutableString stringWithString:@"SELECT rkey, cid FROM records WHERE did = ? AND collection = ?"];
        NSMutableArray *args = [NSMutableArray arrayWithObjects:ownerDID, @"app.bsky.graph.starterpack", nil];
        if (cursor.length > 0) {
            [query appendString:@" AND rkey < ?"];
            [args addObject:cursor];
        }
        [query appendString:@" ORDER BY rkey DESC LIMIT ?"];
        [args addObject:@(limit)];

        NSError *queryError = nil;
        NSArray *packRows = [appViewDatabase executeParameterizedQuery:query params:args error:&queryError];
        if (!packRows) {
            [XrpcErrorHelper setInternalServerError:response message:queryError.localizedDescription ?: @"Failed to query starter packs"];
            return;
        }

        NSMutableArray *starterPacksWithMembership = [NSMutableArray array];

        for (NSDictionary *packRow in packRows) {
            NSString *packRkey = packRow[@"rkey"];
            NSString *packCidStr = packRow[@"cid"];
            NSString *packURI = [NSString stringWithFormat:@"at://%@/app.bsky.graph.starterpack/%@", ownerDID, packRkey ?: @""];

            CID *packCid = [CID cidFromString:packCidStr];
            NSDictionary *packRecord = nil;
            if (packCid) {
                PDSDatabaseBlock *packBlock = [appViewDatabase getBlockWithCid:packCid.bytes repoDid:ownerDID error:nil];
                if (packBlock && packBlock.blockData) {
                    packRecord = [ATProtoCBORSerialization JSONObjectWithData:packBlock.blockData error:nil];
                }
            }

            NSDictionary *creator = [actorService getProfileForActor:ownerDID error:nil] ?: @{@"did": ownerDID};

            NSString *listRef = packRecord[@"list"];
            NSDictionary *listItem = nil;
            if ([listRef isKindOfClass:[NSString class]] && listRef.length > 0) {
                listItem = loadListItemViewForListAndSubject(appViewDatabase, actorService, ownerDID, listRef, memberDid);
            }

            NSDictionary *starterPackView = @{
                @"uri": packURI,
                @"cid": packCidStr ?: @"",
                @"record": packRecord ?: @{},
                @"creator": creator,
                @"listItem": listItem ?: [NSNull null]
            };

            [starterPacksWithMembership addObject:@{
                @"starterPack": starterPackView
            }];
        }

        NSMutableDictionary *result = [NSMutableDictionary dictionaryWithObject:starterPacksWithMembership forKey:@"starterPacksWithMembership"];
        if (packRows.count >= (NSUInteger)limit && packRows.lastObject[@"rkey"]) {
            result[@"cursor"] = packRows.lastObject[@"rkey"];
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
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

    // app.bsky.notification.listActivitySubscriptions - List activity subscriptions
    [dispatcher registerMethod:@"app.bsky.notification.listActivitySubscriptions" handler:^(HttpRequest *request, HttpResponse *response) {
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
        if (!XrpcParseLimit(request.queryParams[@"limit"], &limit, 1, 100, response)) {
            return;
        }

        NSString *cursor = [request queryParamForKey:@"cursor"];

        NSError *error = nil;
        NSDictionary *result = [notificationService getActivitySubscriptionsForActor:actorDID limit:limit cursor:cursor error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result ?: @{@"subscriptions": @[]}];
    }];

    // app.bsky.notification.registerPush - Register push notification
    [dispatcher registerAppBskyNotificationRegisterPush:^(HttpRequest *request, HttpResponse *response) {
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
        if (![body isKindOfClass:[NSDictionary class]]) {
            [XrpcErrorHelper setValidationError:response message:@"Missing request body"];
            return;
        }

        NSString *serviceDid = body[@"serviceDid"];
        NSString *token = body[@"token"];
        NSString *platform = body[@"platform"];
        NSString *appId = body[@"appId"];

        if (![serviceDid isKindOfClass:[NSString class]] || serviceDid.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"Missing or invalid serviceDid"];
            return;
        }
        if (![token isKindOfClass:[NSString class]] || token.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"Missing or invalid token"];
            return;
        }
        if (![platform isKindOfClass:[NSString class]] || platform.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"Missing or invalid platform"];
            return;
        }
        if (![appId isKindOfClass:[NSString class]] || appId.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"Missing or invalid appId"];
            return;
        }

        NSArray *validPlatforms = @[@"ios", @"android", @"web"];
        if (![validPlatforms containsObject:platform]) {
            [XrpcErrorHelper setValidationError:response message:@"Invalid platform, must be one of: ios, android, web"];
            return;
        }

        NSError *error = nil;
        BOOL success = [notificationService registerPushForActor:actorDID
                                                  deviceToken:token
                                                platformToken:platform
                                                serviceEndpoint:serviceDid
                                                          error:&error];
        if (!success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to register push token"];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    // app.bsky.notification.unregisterPush - Unregister push notification
    [dispatcher registerMethod:@"app.bsky.notification.unregisterPush" handler:^(HttpRequest *request, HttpResponse *response) {
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
        if (![body isKindOfClass:[NSDictionary class]]) {
            [XrpcErrorHelper setValidationError:response message:@"Missing request body"];
            return;
        }

        NSString *serviceDid = body[@"serviceDid"];
        NSString *token = body[@"token"];
        NSString *platform = body[@"platform"];
        NSString *appId = body[@"appId"];

        if (![serviceDid isKindOfClass:[NSString class]] || serviceDid.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"Missing or invalid serviceDid"];
            return;
        }
        if (![token isKindOfClass:[NSString class]] || token.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"Missing or invalid token"];
            return;
        }
        if (![platform isKindOfClass:[NSString class]] || platform.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"Missing or invalid platform"];
            return;
        }
        if (![appId isKindOfClass:[NSString class]] || appId.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"Missing or invalid appId"];
            return;
        }

        NSError *error = nil;
        BOOL success = [notificationService unregisterPushToken:token forActor:actorDID error:&error];
        if (!success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to unregister push token"];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    // app.bsky.notification.putPreferencesV2 - Set notification preferences
    [dispatcher registerMethod:@"app.bsky.notification.putPreferencesV2" handler:^(HttpRequest *request, HttpResponse *response) {
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
        if (![body isKindOfClass:[NSDictionary class]]) {
            [XrpcErrorHelper setValidationError:response message:@"Missing request body"];
            return;
        }

        NSMutableArray *prefsToStore = [NSMutableArray array];

        NSDictionary *typeMap = @{
            @"chat": @"app.bsky.notification.defs#chatPreference",
            @"follow": @"app.bsky.notification.defs#filterablePreference",
            @"like": @"app.bsky.notification.defs#filterablePreference",
            @"likeViaRepost": @"app.bsky.notification.defs#filterablePreference",
            @"mention": @"app.bsky.notification.defs#filterablePreference",
            @"quote": @"app.bsky.notification.defs#filterablePreference",
            @"reply": @"app.bsky.notification.defs#filterablePreference",
            @"repost": @"app.bsky.notification.defs#filterablePreference",
            @"repostViaRepost": @"app.bsky.notification.defs#filterablePreference",
            @"starterpackJoined": @"app.bsky.notification.defs#preference",
            @"subscribedPost": @"app.bsky.notification.defs#preference",
            @"unverified": @"app.bsky.notification.defs#preference",
            @"verified": @"app.bsky.notification.defs#preference"
        };

        for (NSString *key in typeMap) {
            id value = body[key];
            if (value && [value isKindOfClass:[NSDictionary class]]) {
                NSMutableDictionary *pref = [value mutableCopy];
                pref[@"$type"] = typeMap[key];
                [prefsToStore addObject:[pref copy]];
            }
        }

        if (prefsToStore.count == 0) {
            [XrpcErrorHelper setValidationError:response message:@"No valid preferences provided"];
            return;
        }

        NSError *error = nil;
        BOOL success = [actorService putPreferencesForActor:actorDID preferences:[prefsToStore copy] error:&error];
        if (!success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to save preferences"];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"preferences": body}];
    }];

    // app.bsky.notification.putActivitySubscription - Put activity subscription
    [dispatcher registerMethod:@"app.bsky.notification.putActivitySubscription" handler:^(HttpRequest *request, HttpResponse *response) {
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
        if (![body isKindOfClass:[NSDictionary class]]) {
            [XrpcErrorHelper setValidationError:response message:@"Missing request body"];
            return;
        }

        NSString *subjectDID = body[@"subject"];
        NSDictionary *subscription = body[@"activitySubscription"];

        if (![subjectDID isKindOfClass:[NSString class]] || subjectDID.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"Missing or invalid subject"];
            return;
        }
        if (![subscription isKindOfClass:[NSDictionary class]]) {
            [XrpcErrorHelper setValidationError:response message:@"Missing or invalid activitySubscription"];
            return;
        }

        BOOL postEnabled = [subscription[@"post"] boolValue];
        BOOL replyEnabled = [subscription[@"reply"] boolValue];

        NSError *error = nil;
        BOOL success = [notificationService putActivitySubscriptionForActor:actorDID
                                                                   subject:subjectDID
                                                              postEnabled:postEnabled
                                                              replyEnabled:replyEnabled
                                                                    error:&error];
        if (!success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to save activity subscription"];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"subject": subjectDID, @"activitySubscription": subscription}];
    }];

    // MARK: - app.bsky.draft.* (Draft management - stored as private records)

    // Use service pool for draft storage (simpler than per-user)
    PDSDatabasePool *userDatabasePool = serviceDatabases.servicePool;
    PDSRecordService *recordService = [[PDSRecordService alloc] initWithDatabasePool:userDatabasePool];

    // app.bsky.draft.createDraft - Create a new draft
    // Request: {draft: {posts: [{text, ...}], ...}}
    // Response: {id: string (tid)}
    [dispatcher registerMethod:@"app.bsky.draft.createDraft" handler:^(HttpRequest *request, HttpResponse *response) {
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
        if (![body isKindOfClass:[NSDictionary class]]) {
            [XrpcErrorHelper setValidationError:response message:@"Missing request body"];
            return;
        }

        NSDictionary *draft = body[@"draft"];
        if (![draft isKindOfClass:[NSDictionary class]]) {
            [XrpcErrorHelper setValidationError:response message:@"Missing or invalid draft"];
            return;
        }

        id posts = draft[@"posts"];
        if (![posts isKindOfClass:[NSArray class]] || [(NSArray *)posts count] == 0) {
            [XrpcErrorHelper setValidationError:response message:@"Draft must contain at least one post"];
            return;
        }

        // Generate TID-formatted draft ID
        NSString *draftId = [[NSUUID UUID] UUIDString];
        NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSSZ";
    NSString *now = [fmt stringFromDate:[NSDate date]];

        // Store draft object as-is with metadata
        NSMutableDictionary *draftRecord = [draft mutableCopy];
        draftRecord[@"$type"] = @"app.bsky.draft.defs#draft";
        draftRecord[@"createdAt"] = now;
        draftRecord[@"updatedAt"] = now;

        NSError *error = nil;
        BOOL success = [recordService putRecord:@"app.bsky.draft.defs#draft"
                                          rkey:draftId
                                         value:[draftRecord copy]
                                       forDid:actorDID
                                        error:&error];
        if (!success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to create draft"];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"id": draftId}];
    }];

    // app.bsky.draft.updateDraft - Update an existing draft
    // Request: {draft: {id: string, posts: [{text, ...}], ...}}
    // Response: {} (empty on success)
    [dispatcher registerMethod:@"app.bsky.draft.updateDraft" handler:^(HttpRequest *request, HttpResponse *response) {
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
        if (![body isKindOfClass:[NSDictionary class]]) {
            [XrpcErrorHelper setValidationError:response message:@"Missing request body"];
            return;
        }

        NSDictionary *draft = body[@"draft"];
        if (![draft isKindOfClass:[NSDictionary class]]) {
            [XrpcErrorHelper setValidationError:response message:@"Missing or invalid draft"];
            return;
        }

        NSString *draftId = draft[@"id"];
        if (![draftId isKindOfClass:[NSString class]] || draftId.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"Missing or invalid draft id"];
            return;
        }

        id posts = draft[@"posts"];
        if (![posts isKindOfClass:[NSArray class]] || [(NSArray *)posts count] == 0) {
            [XrpcErrorHelper setValidationError:response message:@"Draft must contain at least one post"];
            return;
        }

        // Get existing draft to preserve createdAt
        NSError *getError = nil;
        NSDictionary *existingDraft = [recordService getRecord:[NSString stringWithFormat:@"at://%@/app.bsky.draft.defs#draft/%@", actorDID, draftId]
                                                       forDid:actorDID
                                                       error:&getError];
        if (!existingDraft) {
            response.statusCode = HttpStatusNotFound;
            [XrpcErrorHelper setNotFoundError:response message:@"Draft not found"];
            return;
        }

        NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSSZ";
    NSString *now = [fmt stringFromDate:[NSDate date]];
        NSString *createdAt = existingDraft[@"createdAt"] ?: now;

        NSMutableDictionary *updatedRecord = [draft mutableCopy];
        updatedRecord[@"$type"] = @"app.bsky.draft.defs#draft";
        updatedRecord[@"createdAt"] = createdAt;
        updatedRecord[@"updatedAt"] = now;

        NSError *error = nil;
        BOOL success = [recordService putRecord:@"app.bsky.draft.defs#draft"
                                          rkey:draftId
                                         value:[updatedRecord copy]
                                       forDid:actorDID
                                        error:&error];
        if (!success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to update draft"];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    // app.bsky.draft.getDrafts - List actor's drafts with pagination
    // Query params: limit (1-100, default 50), cursor
    // Response: {drafts: [...], cursor?: string}
    [dispatcher registerMethod:@"app.bsky.draft.getDrafts" handler:^(HttpRequest *request, HttpResponse *response) {
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

        NSUInteger limit = 50;
        NSString *limitParam = [request queryParamForKey:@"limit"];
        if (limitParam) {
            [PDSDatabase parseLimit:limitParam outLimit:&limit];
        }
        if (limit > 100) limit = 100;
        if (limit < 1) limit = 1;

        NSString *cursor = [request queryParamForKey:@"cursor"];

        NSError *error = nil;
        NSArray *draftRecords = [recordService listRecords:@"app.bsky.draft.defs#draft"
                                                 forDid:actorDID
                                                  limit:limit + 1  // Fetch one extra to determine if there are more
                                                 cursor:cursor
                                                 error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to list drafts"];
            return;
        }

        if (!draftRecords) {
            draftRecords = @[];
        }

        NSMutableArray *drafts = [NSMutableArray array];
        NSString *nextCursor = nil;

        for (NSUInteger i = 0; i < draftRecords.count && i < limit; i++) {
            NSDictionary *recordInfo = draftRecords[i];
            NSString *rkey = recordInfo[@"rkey"];
            if (!rkey) continue;

            // Return draft view with id and posts
            NSMutableDictionary *draftView = [@{@"id": rkey} mutableCopy];
            if (recordInfo[@"posts"]) {
                draftView[@"posts"] = recordInfo[@"posts"];
            }
            if (recordInfo[@"createdAt"]) {
                draftView[@"createdAt"] = recordInfo[@"createdAt"];
            }
            [drafts addObject:[draftView copy]];
        }

        // Check if there are more results
        if (draftRecords.count > limit) {
            NSDictionary *lastRecord = draftRecords[limit];
            nextCursor = lastRecord[@"rkey"];
        }

        response.statusCode = HttpStatusOK;
        NSMutableDictionary *result = [@{@"drafts": [drafts copy]} mutableCopy];
        if (nextCursor) {
            result[@"cursor"] = nextCursor;
        }
        [response setJsonBody:[result copy]];
    }];

    // app.bsky.draft.deleteDraft - Delete a draft
    // Request: {id: string (tid)}
    // Response: {} (empty on success)
    [dispatcher registerMethod:@"app.bsky.draft.deleteDraft" handler:^(HttpRequest *request, HttpResponse *response) {
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
        if (![body isKindOfClass:[NSDictionary class]]) {
            [XrpcErrorHelper setValidationError:response message:@"Missing request body"];
            return;
        }

        NSString *draftId = body[@"id"];
        if (![draftId isKindOfClass:[NSString class]] || draftId.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"Missing or invalid id"];
            return;
        }

        NSError *error = nil;
        BOOL success = [recordService deleteRecord:@"app.bsky.draft.defs#draft"
                                              rkey:draftId
                                            forDid:actorDID
                                             error:&error];
        if (!success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to delete draft"];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    // app.bsky.video.getJobStatus - Get video processing status
    [dispatcher registerMethod:@"app.bsky.video.getJobStatus" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *jobId = [request queryParamForKey:@"jobId"];
        if (!jobId) {
            [XrpcErrorHelper setValidationError:response message:@"Missing jobId parameter"];
            return;
        }

        // Query job from database
        NSError *dbError = nil;
        NSDictionary *job = [[PDSDatabase sharedDatabase] getVideoJobById:jobId error:&dbError];
        if (!job) {
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{@"error": @"NotFound", @"message": @"Job not found"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{
            @"jobStatus": @{
                @"jobId": job[@"job_id"] ?: jobId,
                @"did": job[@"did"] ?: @"",
                @"state": job[@"state"] ?: @"UNKNOWN",
                @"progress": job[@"progress"] ?: @0,
                @"message": job[@"message"] ?: @""
            }
        }];
    }];

    // app.bsky.video.uploadVideo - Upload video for processing
    [dispatcher registerMethod:@"app.bsky.video.uploadVideo" handler:^(HttpRequest *request, HttpResponse *response) {
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
            [XrpcErrorHelper setAuthenticationError:response message:@"Invalid or expired token"];
            return;
        }

        NSData *bodyData = request.body;
        if (!bodyData || bodyData.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"Missing request body"];
            return;
        }

        // Generate job ID and store job in database
        NSString *jobId = [[NSUUID UUID] UUIDString];
        NSString *blobCid = @"unknown"; // Would be computed from blob storage

        NSError *dbError = nil;
        BOOL stored = [[PDSDatabase sharedDatabase] createVideoJobWithId:jobId
                                                                   did:actorDID
                                                                blobCid:blobCid
                                                              mimeType:request.headers[@"Content-Type"]
                                                              fileSize:@(bodyData.length)
                                                                 error:&dbError];
        if (!stored) {
            PDS_LOG_SERVICE_ERROR(@"Failed to create video job: %@", dbError.localizedDescription ?: @"unknown");
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"InternalError", @"message": @"Failed to create video job"}];
            return;
        }

        // Queue async processing (would be handled by background worker)
        // For now, immediately mark as processing
        [[PDSDatabase sharedDatabase] updateVideoJobState:jobId state:@"PROCESSING" progress:@0 message:@"Starting video processing" error:nil];

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{
            @"jobStatus": @{
                @"jobId": jobId,
                @"did": actorDID,
                @"state": @"PROCESSING",
                @"progress": @0,
                @"message": @"Video uploaded, processing started"
            }
        }];
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

    // ====================================================================
    // Age Assurance & Contact: proxy-or-501 policy
    // Registered unconditionally — age assurance and contact are PDS-level
    // capabilities that may be fulfilled by an upstream AppView when
    // localAppViewEnabled is false.
    // ====================================================================

    [XrpcAppBskyProxyMethodPack registerProxyOnlyMethodsWithDispatcher:dispatcher];

    // Register chat.bsky.convo (DM) endpoints
    [self registerChatConvoWithDispatcher:dispatcher adminController:adminController jwtMinter:jwtMinter];
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

#pragma mark - Chat Convo (DM) Endpoints

+ (void)registerChatConvoWithDispatcher:(XrpcDispatcher *)dispatcher
                       adminController:(id<PDSAdminController>)adminController
                              jwtMinter:(JWTMinter *)jwtMinter {
    // chat.bsky.convo.getConvo
    [dispatcher registerMethod:@"chat.bsky.convo.getConvo" handler:^(HttpRequest *request, HttpResponse *response) {
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
        if (!actorDID) return;

        // Stub - Direct messages not yet implemented
        response.statusCode = HttpStatusNotImplemented;
        [response setJsonBody:@{@"error": @"NotImplemented", @"message": @"Direct messages are not yet supported by this PDS."}];
    }];

    // chat.bsky.convo.getMessages
    [dispatcher registerMethod:@"chat.bsky.convo.getMessages" handler:^(HttpRequest *request, HttpResponse *response) {
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
        if (!actorDID) return;

        // Stub - Direct messages not yet implemented
        response.statusCode = HttpStatusNotImplemented;
        [response setJsonBody:@{@"error": @"NotImplemented", @"message": @"Direct messages are not yet supported by this PDS."}];
    }];

    // chat.bsky.convo.sendMessage
    [dispatcher registerMethod:@"chat.bsky.convo.sendMessage" handler:^(HttpRequest *request, HttpResponse *response) {
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
        if (!actorDID) return;

        // Stub - Direct messages not yet implemented
        response.statusCode = HttpStatusNotImplemented;
        [response setJsonBody:@{@"error": @"NotImplemented", @"message": @"Direct messages are not yet supported by this PDS."}];
    }];

    // chat.bsky.convo.listConvos
    [dispatcher registerMethod:@"chat.bsky.convo.listConvos" handler:^(HttpRequest *request, HttpResponse *response) {
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
        if (!actorDID) return;

        // Stub - Direct messages not yet implemented
        response.statusCode = HttpStatusNotImplemented;
        [response setJsonBody:@{@"error": @"NotImplemented", @"message": @"Direct messages are not yet supported by this PDS."}];
    }];

    // chat.bsky.convo.leaveConvo
    [dispatcher registerMethod:@"chat.bsky.convo.leaveConvo" handler:^(HttpRequest *request, HttpResponse *response) {
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
        if (!actorDID) return;

        // Stub - Direct messages not yet implemented
        response.statusCode = HttpStatusNotImplemented;
        [response setJsonBody:@{@"error": @"NotImplemented", @"message": @"Direct messages are not yet supported by this PDS."}];
    }];

    // chat.bsky.convo.updateRead
    [dispatcher registerMethod:@"chat.bsky.convo.updateRead" handler:^(HttpRequest *request, HttpResponse *response) {
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
        if (!actorDID) return;

        // Stub - Direct messages not yet implemented
        response.statusCode = HttpStatusNotImplemented;
        [response setJsonBody:@{@"error": @"NotImplemented", @"message": @"Direct messages are not yet supported by this PDS."}];
    }];
}

@end
