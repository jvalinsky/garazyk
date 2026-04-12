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
#import "Core/CID.h"
#import "Core/ATProtoCBORSerialization.h"
#import "AppView/RecordLifecycleHandler.h"
#import "App/PDSConfiguration.h"
#import "Core/NSDateFormatter+ATProto.h"
#import "Debug/PDSLogger.h"
#import "Identity/ATProtoHandleValidator.h"

#pragma mark - Helper Functions

static BOOL parseIntegerParam(NSString *value, NSInteger *outValue, NSInteger defaultValue) {
    if (!value || value.length == 0) {
        if (outValue) *outValue = defaultValue;
        return YES;
    }
    NSInteger parsed = 0;
    NSScanner *scanner = [NSScanner scannerWithString:value];
    if (![scanner scanInteger:&parsed] || !scanner.isAtEnd) {
        return NO;
    }
    if (outValue) *outValue = parsed;
    return YES;
}

static BOOL parseAtURI(NSString *uri, NSString **outDid, NSString **outCollection, NSString **outRkey) {
    return XrpcParseAtURI(uri, outDid, outCollection, outRkey);
}

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
    NSError *appViewDbError = nil;
    PDSDatabase *appViewDatabase = [serviceDatabases serviceDatabaseWithError:&appViewDbError];
    if (!appViewDatabase && appViewDbError) {
        PDS_LOG_WARN(@"Failed to open service database for app.bsky handlers: %@",
                     appViewDbError.localizedDescription ?: @"unknown error");
    }
    
    ActorService *actorService = [[ActorService alloc] initWithDatabase:appViewDatabase];

    // ====================================================================
    // Actor methods: always registered (PDS-level)
    // ====================================================================
    [XrpcAppBskyActorPack registerWithDispatcher:dispatcher
                                   appViewDatabase:appViewDatabase
                                        jwtMinter:jwtMinter
                                  adminController:adminController];

    // ====================================================================
    // Put notification preferences (PDS-level)
    // ====================================================================
    [dispatcher registerMethod:@"app.bsky.notification.putNotificationPreferences" handler:^(HttpRequest *request, HttpResponse *response) {
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
        
        // Still register proxy-only methods (age assurance, contact)
        [XrpcAppBskyProxyMethodPack registerProxyOnlyMethodsWithDispatcher:dispatcher];
        
        // Register chat convo endpoints
        [self registerChatConvoWithDispatcher:dispatcher adminController:adminController jwtMinter:jwtMinter];
        return;
    }
    
    // ====================================================================
    // Local AppView Methods
    // ====================================================================
    
    NotificationService *notificationService = [[NotificationService alloc] initWithDatabase:appViewDatabase actorService:actorService];
    GraphService *graphService = [[GraphService alloc] initWithDatabase:appViewDatabase];
    BookmarkService *bookmarkService = [[BookmarkService alloc] initWithDatabase:appViewDatabase];
    
    // Initialize record lifecycle handler for notification generation
    __attribute__((unused)) RecordLifecycleHandler *lifecycleHandler =
        [[RecordLifecycleHandler alloc] initWithNotificationService:notificationService
                                                   bookmarkService:bookmarkService
                                                      graphService:graphService
                                                          database:appViewDatabase];

    // Register namespace packs for AppView endpoints
    [XrpcAppBskyFeedPack registerWithDispatcher:dispatcher
                                appViewDatabase:appViewDatabase
                                     jwtMinter:jwtMinter
                               adminController:adminController];
    
    [XrpcAppBskyGraphPack registerWithDispatcher:dispatcher
                                 serviceDatabases:serviceDatabases
                                   appViewDatabase:appViewDatabase
                                        jwtMinter:jwtMinter
                                  adminController:adminController];
    
    [XrpcAppBskyNotificationPack registerWithDispatcher:dispatcher
                                         appViewDatabase:appViewDatabase
                                              jwtMinter:jwtMinter
                                        adminController:adminController];

    // ====================================================================
    // Bookmarks (AppView-level, private storage)
    // ====================================================================

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

    // ====================================================================
    // Labeler Methods
    // ====================================================================

    // app.bsky.labeler.getServices - Get labeler service views
    [dispatcher registerMethod:@"app.bsky.labeler.getServices" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"views": @[], @"cursor": [NSNull null]}];
    }];

    // ====================================================================
    // Draft Management (stubs - private record storage)
    // ====================================================================

    // app.bsky.draft.createDraft - Create a new draft
    [dispatcher registerMethod:@"app.bsky.draft.createDraft" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        if (!authHeader) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }
        response.statusCode = 501;
        [response setJsonBody:@{@"error": @"NotImplemented", @"message": @"Draft storage not yet implemented"}];
    }];

    // app.bsky.draft.updateDraft - Update an existing draft
    [dispatcher registerMethod:@"app.bsky.draft.updateDraft" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        if (!authHeader) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }
        response.statusCode = 501;
        [response setJsonBody:@{@"error": @"NotImplemented", @"message": @"Draft storage not yet implemented"}];
    }];

    // app.bsky.draft.getDrafts - List actor's drafts with pagination
    [dispatcher registerMethod:@"app.bsky.draft.getDrafts" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        if (!authHeader) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"drafts": @[]}];
    }];

    // app.bsky.draft.deleteDraft - Delete a draft
    [dispatcher registerMethod:@"app.bsky.draft.deleteDraft" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        if (!authHeader) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    // ====================================================================
    // Video Methods (stubs - requires video processing service)
    // ====================================================================

    // app.bsky.video.getJobStatus - Get video processing status
    [dispatcher registerMethod:@"app.bsky.video.getJobStatus" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *jobId = [request queryParamForKey:@"jobId"];
        if (!jobId) {
            [XrpcErrorHelper setValidationError:response message:@"Missing jobId parameter"];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{
            @"jobId": jobId,
            @"state": @"JOB_STATE_COMPLETE",
            @"blobRef": [NSNull null]
        }];
    }];

    // app.bsky.video.uploadVideo - Upload video for processing
    [dispatcher registerMethod:@"app.bsky.video.uploadVideo" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{
            @"jobId": [[NSUUID UUID] UUIDString],
            @"state": @"JOB_STATE_RUNNING"
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

    // ====================================================================
    // Unspecced Methods (stubs)
    // ====================================================================

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
        // Chat is unsupported on single-user PDS for now
        response.statusCode = 501;
        [response setJsonBody:@{@"error": @"NotImplemented", @"message": @"Chat not supported"}];
    }];

    // chat.bsky.convo.listConvos
    [dispatcher registerMethod:@"chat.bsky.convo.listConvos" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        if (!authHeader) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }
        response.statusCode = 501;
        [response setJsonBody:@{@"error": @"NotImplemented", @"message": @"Chat not supported"}];
    }];

    // chat.bsky.convo.sendMessage
    [dispatcher registerMethod:@"chat.bsky.convo.sendMessage" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        if (!authHeader) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }
        response.statusCode = 501;
        [response setJsonBody:@{@"error": @"NotImplemented", @"message": @"Chat not supported"}];
    }];

    // chat.bsky.convo.getMessages
    [dispatcher registerMethod:@"chat.bsky.convo.getMessages" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        if (!authHeader) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }
        response.statusCode = 501;
        [response setJsonBody:@{@"error": @"NotImplemented", @"message": @"Chat not supported"}];
    }];

    // chat.bsky.convo.getLog
    [dispatcher registerMethod:@"chat.bsky.convo.getLog" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        if (!authHeader) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }
        response.statusCode = 501;
        [response setJsonBody:@{@"error": @"NotImplemented", @"message": @"Chat not supported"}];
    }];

    PDS_LOG_INFO(@"Registered chat.bsky.convo.* endpoints (stubs)");
}

@end
