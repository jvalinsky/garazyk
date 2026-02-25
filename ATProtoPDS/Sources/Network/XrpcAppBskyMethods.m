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
    NotificationService *notificationService = [[NotificationService alloc] initWithDatabase:appViewDatabase];
    
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
    
    // app.bsky.feed.getPosts - Get multiple posts by URI
    [dispatcher registerAppBskyFeedGetFeed:^(HttpRequest *request, HttpResponse *response) {
        // This is actually getFeed, not getPosts - getPosts would need different implementation
        // For now, implement as custom feed generator
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
        
        // For now, return empty list - full implementation would query social graph
        NSDictionary *result = @{
            @"subject": @{@"did": actor, @"handle": actor},
            @"followers": @[],
            @"cursor": cursor ?: [NSNull null]
        };
        
        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
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
        
        // For now, return empty list - full implementation would query social graph
        NSDictionary *result = @{
            @"subject": @{@"did": actor, @"handle": actor},
            @"follows": @[],
            @"cursor": cursor ?: [NSNull null]
        };
        
        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
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
        
        // For now, return 0 - full implementation would query notification database
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"count": @0}];
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
        
        // For now, just return success - full implementation would update database
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
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
