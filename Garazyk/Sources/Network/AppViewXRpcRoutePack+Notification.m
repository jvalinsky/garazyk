// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Network/AppViewXRpcRoutePack_Internal.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "AppView/Services/NotificationService.h"

@implementation AppViewXRpcRoutePack (Notification)

- (void)handleListNotifications:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actorDID = [self requireAuth:request response:response];
    if (!actorDID) return;

    NSInteger limit = parseLimitParam(request, 50, 100);
    NSString *cursor = [request queryParamForKey:@"cursor"];
    NSError *error = nil;
    NSArray *notifications = [self.notificationService getNotificationsForActor:actorDID limit:limit cursor:cursor error:&error];

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
    NSInteger count = [self.notificationService getUnreadCountForActor:actorDID error:&error];

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
    BOOL success = [self.notificationService markNotificationsAsReadForActor:actorDID limit:limit error:&error];
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
    BOOL success = [self.notificationService registerPushForActor:actorDID
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
    BOOL success = [self.notificationService unregisterPushForActor:actorDID error:&error];
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
    NSDictionary *result = [self.notificationService getActivitySubscriptionsForActor:actorDID limit:limit cursor:cursor error:&error];
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
    BOOL success = [self.notificationService putActivitySubscriptionForActor:actorDID
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
    NSDictionary *prefs = [self.notificationService getPreferencesForActor:actorDID error:&error];

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
    NSDictionary *prefsObj = @{@"priority": @(priority)};
    BOOL success = [self.notificationService putPreferencesForActor:actorDID preferences:(NSArray *)prefsObj error:&error];

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