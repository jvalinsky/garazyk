#import "Network/XrpcAppBskyNotificationPack.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcAuthHelper.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/XrpcAppBskyGraphHelpers.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "AppView/Services/NotificationService.h"
#import "AppView/Services/ActorService.h"
#import "Debug/PDSLogger.h"

@implementation XrpcAppBskyNotificationPack

+ (void)registerPDSLevelMethodsWithDispatcher:(XrpcDispatcher *)dispatcher
                              appViewDatabase:(id<PDSQueryDatabase>)appViewDatabase
                                    jwtMinter:(JWTMinter *)jwtMinter
                              adminController:(id<PDSAdminController>)adminController {
    ActorService *actorService = [[ActorService alloc] initWithDatabase:appViewDatabase];

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

        NSError *error = nil;
        NSDictionary *currentPrefs = [actorService getPreferencesForActor:actorDID error:&error];

        NSMutableArray *prefsList = [NSMutableArray array];
        if (currentPrefs && currentPrefs[@"preferences"] && [currentPrefs[@"preferences"] isKindOfClass:[NSArray class]]) {
            prefsList = [currentPrefs[@"preferences"] mutableCopy];
        }

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
}

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                 appViewDatabase:(id<PDSQueryDatabase>)appViewDatabase
                      jwtMinter:(JWTMinter *)jwtMinter
                adminController:(id<PDSAdminController>)adminController {

    ActorService *actorService = [[ActorService alloc] initWithDatabase:appViewDatabase];
    NotificationService *notificationService = [[NotificationService alloc] initWithDatabase:appViewDatabase actorService:actorService];

    // app.bsky.notification.getPreferences (legacy alias used by tests/clients)
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
        if (!actorDID) return;

        NSError *error = nil;
        NSDictionary *currentPrefs = [actorService getPreferencesForActor:actorDID error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to load preferences"];
            return;
        }

        BOOL priority = NO;
        NSArray *prefsList = [currentPrefs[@"preferences"] isKindOfClass:[NSArray class]] ? currentPrefs[@"preferences"] : @[];
        for (id entry in prefsList) {
            if (![entry isKindOfClass:[NSDictionary class]]) {
                continue;
            }
            NSDictionary *pref = (NSDictionary *)entry;
            if ([pref[@"$type"] isEqualToString:@"app.bsky.notification.defs#notificationPref"]) {
                priority = [pref[@"priority"] boolValue];
                break;
            }
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"priority": @(priority)}];
    }];

    // app.bsky.notification.putPreferences (legacy alias used by tests/clients)
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
        if (!actorDID) return;

        NSDictionary *body = request.jsonBody;
        if (![body isKindOfClass:[NSDictionary class]]) {
            [XrpcErrorHelper setValidationError:response message:@"Missing request body"];
            return;
        }

        BOOL priority = [body[@"priority"] boolValue];
        NSError *error = nil;
        NSDictionary *currentPrefs = [actorService getPreferencesForActor:actorDID error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to load preferences"];
            return;
        }

        NSMutableArray *prefsList = [NSMutableArray array];
        if ([currentPrefs[@"preferences"] isKindOfClass:[NSArray class]]) {
            [prefsList addObjectsFromArray:currentPrefs[@"preferences"]];
        }

        BOOL replaced = NO;
        for (NSUInteger index = 0; index < prefsList.count; index++) {
            id entry = prefsList[index];
            if (![entry isKindOfClass:[NSDictionary class]]) {
                continue;
            }
            NSDictionary *pref = (NSDictionary *)entry;
            if ([pref[@"$type"] isEqualToString:@"app.bsky.notification.defs#notificationPref"]) {
                prefsList[index] = @{
                    @"$type": @"app.bsky.notification.defs#notificationPref",
                    @"priority": @(priority)
                };
                replaced = YES;
                break;
            }
        }

        if (!replaced) {
            [prefsList addObject:@{
                @"$type": @"app.bsky.notification.defs#notificationPref",
                @"priority": @(priority)
            }];
        }

        BOOL saved = [actorService putPreferencesForActor:actorDID preferences:prefsList error:&error];
        if (!saved) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to save preferences"];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    // app.bsky.notification.listNotifications
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
        if (!actorDID) return;
        NSInteger limit = 50;
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

    // app.bsky.notification.getUnreadCount
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
        if (!actorDID) return;
        NSError *error = nil;
        NSInteger count = [notificationService getUnreadCountForActor:actorDID error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"count": @(count)}];
    }];

    // app.bsky.notification.updateSeen
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
        if (!actorDID) return;
        NSDictionary *body = request.jsonBody;
        (void)body; // seenAt is acknowledged but marking all as read
        NSError *error = nil;
        [notificationService markNotificationsAsReadForActor:actorDID limit:0 error:&error];
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    // app.bsky.notification.registerPush
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
        if (!actorDID) return;

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

    // app.bsky.notification.unregisterPush
    [dispatcher registerAppBskyNotificationUnregisterPush:^(HttpRequest *request, HttpResponse *response) {
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
        BOOL success = [notificationService unregisterPushToken:token forActor:actorDID error:&error];
        if (!success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to unregister push token"];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    // app.bsky.notification.listActivitySubscriptions
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
        if (!actorDID) return;

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

    // app.bsky.notification.putPreferencesV2
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
        if (!actorDID) return;

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

    // app.bsky.notification.putActivitySubscription
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
        if (!actorDID) return;

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

    PDS_LOG_INFO(@"Registered app.bsky.notification.* endpoints");
}

@end
