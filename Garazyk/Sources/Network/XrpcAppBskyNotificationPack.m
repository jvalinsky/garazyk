// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file XrpcAppBskyNotificationPack.m

 @abstract XRPC route pack for app.bsky.notification endpoints.
 */

#import "Network/XrpcAppBskyNotificationPack.h"

#import "AppView/Services/ActorService.h"
#import "AppView/Services/NotificationService.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcAppBskyGraphHelpers.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcHandlerContext.h"
#import "Network/XrpcRoutePackServices.h"
#import "Network/Generated/GZXrpcNSID.h"

static NSDictionary *XrpcNotificationPreferenceDefaults(void) {
  return @{
    @"chat" : @{@"$type" : @"app.bsky.notification.defs#chatPreference", @"include" : @"all", @"push" : @NO},
    @"follow" :
        @{@"$type" : @"app.bsky.notification.defs#filterablePreference", @"include" : @"all", @"list" : @YES, @"push" : @NO},
    @"like" :
        @{@"$type" : @"app.bsky.notification.defs#filterablePreference", @"include" : @"all", @"list" : @YES, @"push" : @NO},
    @"likeViaRepost" :
        @{@"$type" : @"app.bsky.notification.defs#filterablePreference", @"include" : @"all", @"list" : @YES, @"push" : @NO},
    @"mention" :
        @{@"$type" : @"app.bsky.notification.defs#filterablePreference", @"include" : @"all", @"list" : @YES, @"push" : @NO},
    @"quote" :
        @{@"$type" : @"app.bsky.notification.defs#filterablePreference", @"include" : @"all", @"list" : @YES, @"push" : @NO},
    @"reply" :
        @{@"$type" : @"app.bsky.notification.defs#filterablePreference", @"include" : @"all", @"list" : @YES, @"push" : @NO},
    @"repost" :
        @{@"$type" : @"app.bsky.notification.defs#filterablePreference", @"include" : @"all", @"list" : @YES, @"push" : @NO},
    @"repostViaRepost" :
        @{@"$type" : @"app.bsky.notification.defs#filterablePreference", @"include" : @"all", @"list" : @YES, @"push" : @NO},
    @"starterpackJoined" : @{@"$type" : @"app.bsky.notification.defs#preference", @"list" : @YES, @"push" : @NO},
    @"subscribedPost" : @{@"$type" : @"app.bsky.notification.defs#preference", @"list" : @YES, @"push" : @NO},
    @"unverified" : @{@"$type" : @"app.bsky.notification.defs#preference", @"list" : @YES, @"push" : @NO},
    @"verified" : @{@"$type" : @"app.bsky.notification.defs#preference", @"list" : @YES, @"push" : @NO},
  };
}

@implementation XrpcAppBskyNotificationPack

+ (NSString *)routePackIdentifier {
  return @"app.bsky.notification";
}

+ (nullable ActorService *)actorServiceForServices:(id<XrpcRoutePackServices>)services {
  id<PDSQueryDatabase> database = services.appViewDatabase;
  if (!database) {
    return nil;
  }
  return [[ActorService alloc] initWithDatabase:database];
}

+ (nullable NotificationService *)notificationServiceForServices:(id<XrpcRoutePackServices>)services {
  if (services.notificationService) {
    return services.notificationService;
  }
  ActorService *actorService = [self actorServiceForServices:services];
  if (!actorService) {
    return nil;
  }
  return [[NotificationService alloc] initWithDatabase:services.appViewDatabase actorService:actorService];
}

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                      services:(id<XrpcRoutePackServices>)services {
  [self registerPDSLevelMethodsWithDispatcher:dispatcher services:services];
  [self registerAppViewMethodsWithDispatcher:dispatcher services:services];
}

+ (void)registerPDSLevelMethodsWithDispatcher:(XrpcDispatcher *)dispatcher
                               appViewDatabase:(id<PDSQueryDatabase>)appViewDatabase
                                     jwtMinter:(JWTMinter *)jwtMinter
                               adminController:(id<PDSAdminController>)adminController {
  XrpcRoutePackServiceBag *services =
      [[XrpcRoutePackServiceBag alloc] initWithDispatcher:dispatcher
                                                jwtMinter:jwtMinter
                                          adminController:adminController
                                             configuration:nil
                                               adminSecret:nil
                                         serviceDatabases:nil
                                         userDatabasePool:nil
                                               rateLimiter:nil];
  services.appViewDatabase = appViewDatabase;
  [self registerPDSLevelMethodsWithDispatcher:dispatcher services:services];
}

+ (void)registerAppViewMethodsWithDispatcher:(XrpcDispatcher *)dispatcher
                              appViewDatabase:(id<PDSQueryDatabase>)appViewDatabase
                                    jwtMinter:(JWTMinter *)jwtMinter
                              adminController:(id<PDSAdminController>)adminController {
  XrpcRoutePackServiceBag *services =
      [[XrpcRoutePackServiceBag alloc] initWithDispatcher:dispatcher
                                                jwtMinter:jwtMinter
                                          adminController:adminController
                                             configuration:nil
                                               adminSecret:nil
                                         serviceDatabases:nil
                                         userDatabasePool:nil
                                               rateLimiter:nil];
  services.appViewDatabase = appViewDatabase;
  [self registerAppViewMethodsWithDispatcher:dispatcher services:services];
}

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
               appViewDatabase:(id<PDSQueryDatabase>)appViewDatabase
                     jwtMinter:(JWTMinter *)jwtMinter
               adminController:(id<PDSAdminController>)adminController {
  XrpcRoutePackServiceBag *services =
      [[XrpcRoutePackServiceBag alloc] initWithDispatcher:dispatcher
                                                jwtMinter:jwtMinter
                                          adminController:adminController
                                             configuration:nil
                                               adminSecret:nil
                                         serviceDatabases:nil
                                         userDatabasePool:nil
                                               rateLimiter:nil];
  services.appViewDatabase = appViewDatabase;
  [self registerWithDispatcher:dispatcher services:services];
}

+ (void)registerPDSLevelMethodsWithDispatcher:(XrpcDispatcher *)dispatcher
                                     services:(id<XrpcRoutePackServices>)services {
  ActorService *actorService = [self actorServiceForServices:services];
  if (!actorService) {
    return;
  }

  id<XrpcRoutePackServices> resolvedServices = services;

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_notification_putNotificationPreferences
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       XrpcHandlerContext *context =
                           [[XrpcHandlerContext alloc] initWithRequest:request
                                                             response:response
                                                             services:resolvedServices];
                       NSString *actorDID = nil;
                       if (![context requireAuthenticatedDID:&actorDID]) {
                         return;
                       }

                       NSDictionary *body = request.jsonBody;
                       if (!body || ![body isKindOfClass:[NSDictionary class]]) {
                         [XrpcErrorHelper setValidationError:response message:@"Missing request body"];
                         return;
                       }

                       BOOL priority = [body[@"priority"] boolValue];

                       NSError *error = nil;
                       NSDictionary *currentPrefs = [actorService getPreferencesForActor:actorDID error:&error];

                       NSMutableArray *prefsList = [NSMutableArray array];
                       if (currentPrefs && currentPrefs[@"preferences"] &&
                           [currentPrefs[@"preferences"] isKindOfClass:[NSArray class]]) {
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
                           @"$type" : @"app.bsky.notification.defs#notificationPref",
                           @"priority" : @(priority)
                         }];
                       }

                       BOOL success = [actorService putPreferencesForActor:actorDID preferences:prefsList error:&error];
                       if (!success) {
                         [XrpcErrorHelper setInternalServerError:response
                                                         message:error.localizedDescription ?: @"Failed to save preferences"];
                         return;
                       }

                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{}];
                     }];
}

+ (void)registerAppViewMethodsWithDispatcher:(XrpcDispatcher *)dispatcher
                                    services:(id<XrpcRoutePackServices>)services {
  ActorService *actorService = [self actorServiceForServices:services];
  NotificationService *notificationService = [self notificationServiceForServices:services];
  if (!actorService || !notificationService) {
    return;
  }

  id<XrpcRoutePackServices> resolvedServices = services;

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_notification_getPreferences
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       XrpcHandlerContext *context =
                           [[XrpcHandlerContext alloc] initWithRequest:request
                                                             response:response
                                                             services:resolvedServices];
                       NSString *actorDID = nil;
                       if (![context requireAuthenticatedDID:&actorDID]) {
                         return;
                       }

                       NSError *error = nil;
                       NSDictionary *currentPrefs = [actorService getPreferencesForActor:actorDID error:&error];
                       NSMutableDictionary *prefs = [XrpcNotificationPreferenceDefaults() mutableCopy];

                       if (currentPrefs && currentPrefs[@"preferences"] &&
                           [currentPrefs[@"preferences"] isKindOfClass:[NSArray class]]) {
                         for (NSDictionary *pref in currentPrefs[@"preferences"]) {
                           NSString *type = pref[@"$type"];
                           if ([type isEqualToString:@"app.bsky.notification.defs#chatPreference"]) {
                             prefs[@"chat"] = pref;
                           } else if ([type isEqualToString:@"app.bsky.notification.defs#filterablePreference"]) {
                             NSString *kind = pref[@"kind"];
                             if (kind && prefs[kind]) {
                               prefs[kind] = pref;
                             }
                           } else if ([type isEqualToString:@"app.bsky.notification.defs#preference"]) {
                             NSString *kind = pref[@"kind"];
                             if (kind && prefs[kind]) {
                               prefs[kind] = pref;
                             }
                           }
                         }
                       }

                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"preferences" : prefs}];
                     }];

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_notification_putPreferences
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       XrpcHandlerContext *context =
                           [[XrpcHandlerContext alloc] initWithRequest:request
                                                             response:response
                                                             services:resolvedServices];
                       NSString *actorDID = nil;
                       if (![context requireAuthenticatedDID:&actorDID]) {
                         return;
                       }

                       NSDictionary *body = request.jsonBody;
                       if (!body || ![body isKindOfClass:[NSDictionary class]]) {
                         [XrpcErrorHelper setValidationError:response message:@"Missing request body"];
                         return;
                       }

                       BOOL priority = [body[@"priority"] boolValue];

                       NSError *error = nil;
                       NSDictionary *currentPrefs = [actorService getPreferencesForActor:actorDID error:&error];

                       NSMutableArray *prefsList = [NSMutableArray array];
                       if (currentPrefs && currentPrefs[@"preferences"] &&
                           [currentPrefs[@"preferences"] isKindOfClass:[NSArray class]]) {
                         prefsList = [currentPrefs[@"preferences"] mutableCopy];
                       }

                       NSMutableArray *filtered = [NSMutableArray array];
                       for (NSDictionary *pref in prefsList) {
                         if (![pref[@"$type"] isEqualToString:@"app.bsky.notification.defs#preference"] ||
                             ![pref[@"kind"] isEqualToString:@"priority"]) {
                           [filtered addObject:pref];
                         }
                       }

                       [filtered addObject:@{
                         @"$type" : @"app.bsky.notification.defs#preference",
                         @"kind" : @"priority",
                         @"list" : @(priority),
                         @"push" : @(priority)
                       }];

                       BOOL success = [actorService putPreferencesForActor:actorDID preferences:filtered error:&error];
                       if (!success) {
                         [XrpcErrorHelper setInternalServerError:response
                                                         message:error.localizedDescription ?: @"Failed to save preferences"];
                         return;
                       }

                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{}];
                     }];

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_notification_listNotifications
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       XrpcHandlerContext *context =
                           [[XrpcHandlerContext alloc] initWithRequest:request
                                                             response:response
                                                             services:resolvedServices];
                       NSString *actorDID = nil;
                       if (![context requireAuthenticatedDID:&actorDID]) {
                         return;
                       }

                       NSInteger limit = 50;
                       if (!XrpcParseLimit(request.queryParams[@"limit"], &limit, 1, 100, response)) {
                         return;
                       }
                       NSString *cursor = [request queryParamForKey:@"cursor"];

                       NSError *error = nil;
                       NSArray<NSDictionary *> *notifications =
                           [notificationService getNotificationsForActor:actorDID
                                                                   limit:limit
                                                                  cursor:cursor
                                                                   error:&error];
                       if (error) {
                         [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
                         return;
                       }
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"notifications" : notifications ?: @[]}];
                     }];

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_notification_getUnreadCount
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       XrpcHandlerContext *context =
                           [[XrpcHandlerContext alloc] initWithRequest:request
                                                             response:response
                                                             services:resolvedServices];
                       NSString *actorDID = nil;
                       if (![context requireAuthenticatedDID:&actorDID]) {
                         return;
                       }

                       NSError *error = nil;
                       NSInteger count = [notificationService getUnreadCountForActor:actorDID error:&error];
                       if (error) {
                         [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
                         return;
                       }
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"count" : @(count)}];
                     }];

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_notification_updateSeen
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       XrpcHandlerContext *context =
                           [[XrpcHandlerContext alloc] initWithRequest:request
                                                             response:response
                                                             services:resolvedServices];
                       NSString *actorDID = nil;
                       if (![context requireAuthenticatedDID:&actorDID]) {
                         return;
                       }

                       (void)request.jsonBody;
                       NSError *error = nil;
                       [notificationService markNotificationsAsReadForActor:actorDID limit:0 error:&error];
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{}];
                     }];

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_notification_registerPush handler:^(HttpRequest *request, HttpResponse *response) {
    XrpcHandlerContext *context =
        [[XrpcHandlerContext alloc] initWithRequest:request response:response services:resolvedServices];
    NSString *actorDID = nil;
    if (![context requireAuthenticatedDID:&actorDID]) {
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
      [XrpcErrorHelper setInternalServerError:response
                                      message:error.localizedDescription ?: @"Failed to register push token"];
      return;
    }

    response.statusCode = HttpStatusOK;
    [response setJsonBody:@{}];
  }];

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_notification_unregisterPush handler:^(HttpRequest *request, HttpResponse *response) {
    XrpcHandlerContext *context =
        [[XrpcHandlerContext alloc] initWithRequest:request response:response services:resolvedServices];
    NSString *actorDID = nil;
    if (![context requireAuthenticatedDID:&actorDID]) {
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
    BOOL success = [notificationService unregisterPushToken:token forActor:actorDID error:&error];
    if (!success) {
      [XrpcErrorHelper setInternalServerError:response
                                      message:error.localizedDescription ?: @"Failed to unregister push token"];
      return;
    }

    response.statusCode = HttpStatusOK;
    [response setJsonBody:@{}];
  }];

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_notification_listActivitySubscriptions
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       XrpcHandlerContext *context =
                           [[XrpcHandlerContext alloc] initWithRequest:request
                                                             response:response
                                                             services:resolvedServices];
                       NSString *actorDID = nil;
                       if (![context requireAuthenticatedDID:&actorDID]) {
                         return;
                       }

                       NSInteger limit = 50;
                       if (!XrpcParseLimit(request.queryParams[@"limit"], &limit, 1, 100, response)) {
                         return;
                       }

                       NSString *cursor = [request queryParamForKey:@"cursor"];

                       NSError *error = nil;
                       NSDictionary *result = [notificationService getActivitySubscriptionsForActor:actorDID
                                                                                              limit:limit
                                                                                             cursor:cursor
                                                                                              error:&error];
                       if (error) {
                         [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
                         return;
                       }

                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:result ?: @{@"subscriptions" : @[]}];
                     }];

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_notification_putPreferencesV2
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       XrpcHandlerContext *context =
                           [[XrpcHandlerContext alloc] initWithRequest:request
                                                             response:response
                                                             services:resolvedServices];
                       NSString *actorDID = nil;
                       if (![context requireAuthenticatedDID:&actorDID]) {
                         return;
                       }

                       NSDictionary *body = request.jsonBody;
                       if (![body isKindOfClass:[NSDictionary class]]) {
                         [XrpcErrorHelper setValidationError:response message:@"Missing request body"];
                         return;
                       }

                       NSMutableArray *prefsToStore = [NSMutableArray array];

                       NSDictionary *typeMap = @{
                         @"chat" : @"app.bsky.notification.defs#chatPreference",
                         @"follow" : @"app.bsky.notification.defs#filterablePreference",
                         @"like" : @"app.bsky.notification.defs#filterablePreference",
                         @"likeViaRepost" : @"app.bsky.notification.defs#filterablePreference",
                         @"mention" : @"app.bsky.notification.defs#filterablePreference",
                         @"quote" : @"app.bsky.notification.defs#filterablePreference",
                         @"reply" : @"app.bsky.notification.defs#filterablePreference",
                         @"repost" : @"app.bsky.notification.defs#filterablePreference",
                         @"repostViaRepost" : @"app.bsky.notification.defs#filterablePreference",
                         @"starterpackJoined" : @"app.bsky.notification.defs#preference",
                         @"subscribedPost" : @"app.bsky.notification.defs#preference",
                         @"unverified" : @"app.bsky.notification.defs#preference",
                         @"verified" : @"app.bsky.notification.defs#preference"
                       };

                       for (NSString *key in typeMap) {
                         id value = body[key];
                         if (value && [value isKindOfClass:[NSDictionary class]]) {
                           NSMutableDictionary *pref = [value mutableCopy];
                           pref[@"$type"] = typeMap[key];
                           if (![key isEqualToString:@"chat"]) {
                             pref[@"kind"] = key;
                           }
                           [prefsToStore addObject:[pref copy]];
                         }
                       }

                       if (prefsToStore.count == 0) {
                         [XrpcErrorHelper setValidationError:response message:@"No valid preferences provided"];
                         return;
                       }

                       NSError *error = nil;
                       BOOL success = [actorService putPreferencesForActor:actorDID
                                                               preferences:[prefsToStore copy]
                                                                       error:&error];
                       if (!success) {
                         [XrpcErrorHelper setInternalServerError:response
                                                         message:error.localizedDescription ?: @"Failed to save preferences"];
                         return;
                       }

                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"preferences" : body}];
                     }];

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_notification_putActivitySubscription
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       XrpcHandlerContext *context =
                           [[XrpcHandlerContext alloc] initWithRequest:request
                                                             response:response
                                                             services:resolvedServices];
                       NSString *actorDID = nil;
                       if (![context requireAuthenticatedDID:&actorDID]) {
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
                         [XrpcErrorHelper setInternalServerError:response
                                                         message:error.localizedDescription
                                                                   ?: @"Failed to save activity subscription"];
                         return;
                       }

                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"subject" : subjectDID, @"activitySubscription" : subscription}];
                     }];
}

@end
