#import "Network/XrpcAppBskyNotificationPack.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcAuthHelper.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "AppView/NotificationService.h"
#import "AppView/ActorService.h"
#import "Debug/PDSLogger.h"

@implementation XrpcAppBskyNotificationPack

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                 appViewDatabase:(PDSDatabase *)appViewDatabase
                      jwtMinter:(JWTMinter *)jwtMinter
                adminController:(id<PDSAdminController>)adminController {

    ActorService *actorService = [[ActorService alloc] initWithDatabase:appViewDatabase];
    NotificationService *notificationService = [[NotificationService alloc] initWithDatabase:appViewDatabase actorService:actorService];

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
        NSDictionary *result = [notificationService listNotificationsForActor:actorDID limit:limit cursor:cursor error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:result ?: @{@"notifications": @[]}];
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
        NSString *seenAt = body[@"seenAt"];
        NSError *error = nil;
        BOOL success = [notificationService updateSeenForActor:actorDID seenAt:seenAt error:&error];
        if (!success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to update seen"];
            return;
        }
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
        // Stub - push notifications not yet implemented
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
        // Stub - push notifications not yet implemented
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    PDS_LOG_INFO(@"Registered app.bsky.notification.* endpoints");
}

@end
