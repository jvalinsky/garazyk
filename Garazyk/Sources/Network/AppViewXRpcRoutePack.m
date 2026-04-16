#import "Network/AppViewXRpcRoutePack.h"
#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "AppView/Services/FeedService.h"
#import "AppView/Services/ActorService.h"
#import "AppView/Services/NotificationService.h"
#import "Core/ATProtoCBORSerialization.h"

@implementation AppViewXRpcRoutePack
{
    FeedService *_feedService;
    ActorService *_actorService;
    NotificationService *_notificationService;
}

- (instancetype)initWithFeedService:(FeedService *)feedService
                      actorService:(ActorService *)actorService
                notificationService:(NotificationService *)notificationService
{
    self = [super init];
    if (self)
    {
        _feedService = feedService;
        _actorService = actorService;
        _notificationService = notificationService;
    }
    return self;
}

- (void)registerRoutesWithServer:(HttpServer *)server
{
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
                path:@"/xrpc/app.bsky.actor.getProfile"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handleGetProfile:request response:response];
             }];

    [server addRoute:@"GET"
                path:@"/xrpc/app.bsky.notification.listNotifications"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handleListNotifications:request response:response];
             }];
}

#pragma mark - getTimeline

- (void)handleGetTimeline:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *authHeader = [request headerForKey:@"Authorization"];
    if (!authHeader)
    {
        response.statusCode = 401;
        [response setJsonBody:@{
            @"error": @"AuthenticationRequired",
            @"message": @"Authentication required"
        }];
        return;
    }

    NSString *actorDID = [self extractDIDFromAuth:authHeader request:request];
    if (!actorDID)
    {
        response.statusCode = 401;
        [response setJsonBody:@{
            @"error": @"AuthenticationRequired",
            @"message": @"Invalid or expired session"
        }];
        return;
    }

    NSString *limitParam = [request queryParamForKey:@"limit"];
    NSInteger limit = 50;
    if (limitParam.length > 0)
    {
        [[NSScanner scannerWithString:limitParam] scanInteger:&limit];
    }
    limit = MIN(limit, 100);

    NSString *cursor = [request queryParamForKey:@"cursor"];
    NSError *error = nil;
    NSDictionary *result = [_feedService getTimelineForActor:actorDID limit:limit cursor:cursor error:&error];

    if (error)
    {
        response.statusCode = 500;
        [response setJsonBody:@{
            @"error": @"InternalServerError",
            @"message": error.localizedDescription ?: @"Failed to get timeline"
        }];
        return;
    }

    response.statusCode = 200;
    [response setJsonBody:result ?: @{}];
}

#pragma mark - getAuthorFeed

- (void)handleGetAuthorFeed:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actor = [request queryParamForKey:@"actor"];
    if (!actor || actor.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"InvalidRequest",
            @"message": @"actor parameter is required"
        }];
        return;
    }

    NSString *limitParam = [request queryParamForKey:@"limit"];
    NSInteger limit = 50;
    if (limitParam.length > 0)
    {
        [[NSScanner scannerWithString:limitParam] scanInteger:&limit];
    }
    limit = MIN(limit, 100);

    NSString *cursor = [request queryParamForKey:@"cursor"];
    NSString *filter = [request queryParamForKey:@"filter"];
    NSError *error = nil;
    NSDictionary *result = [_feedService getAuthorFeedForActor:actor limit:limit cursor:cursor filter:filter error:&error];

    if (error)
    {
        response.statusCode = 500;
        [response setJsonBody:@{
            @"error": @"InternalServerError",
            @"message": error.localizedDescription ?: @"Failed to get author feed"
        }];
        return;
    }

    response.statusCode = 200;
    [response setJsonBody:result ?: @{}];
}

#pragma mark - getProfile

- (void)handleGetProfile:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actor = [request queryParamForKey:@"actor"];
    if (!actor || actor.length == 0)
    {
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"InvalidRequest",
            @"message": @"actor parameter is required"
        }];
        return;
    }

    NSError *error = nil;
    NSDictionary *profile = [_actorService getProfileForActor:actor error:&error];

    if (error || !profile)
    {
        response.statusCode = 404;
        [response setJsonBody:@{
            @"error": @"ActorNotFound",
            @"message": [NSString stringWithFormat:@"Actor not found: %@", actor]
        }];
        return;
    }

    response.statusCode = 200;
    [response setJsonBody:profile];
}

#pragma mark - listNotifications

- (void)handleListNotifications:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *authHeader = [request headerForKey:@"Authorization"];
    if (!authHeader)
    {
        response.statusCode = 401;
        [response setJsonBody:@{
            @"error": @"AuthenticationRequired",
            @"message": @"Authentication required"
        }];
        return;
    }

    NSString *actorDID = [self extractDIDFromAuth:authHeader request:request];
    if (!actorDID)
    {
        response.statusCode = 401;
        [response setJsonBody:@{
            @"error": @"AuthenticationRequired",
            @"message": @"Invalid or expired session"
        }];
        return;
    }

    NSString *limitParam = [request queryParamForKey:@"limit"];
    NSInteger limit = 50;
    if (limitParam.length > 0)
    {
        [[NSScanner scannerWithString:limitParam] scanInteger:&limit];
    }
    limit = MIN(limit, 100);

    NSString *cursor = [request queryParamForKey:@"cursor"];
    NSError *error = nil;
    NSArray *notifications = [_notificationService getNotificationsForActor:actorDID limit:limit cursor:cursor error:&error];

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

#pragma mark - Auth Helper

- (NSString *)extractDIDFromAuth:(NSString *)authHeader request:(HttpRequest *)request
{
    if (![authHeader hasPrefix:@"Bearer "])
        return nil;

    NSString *token = [authHeader substringFromIndex:7];
    if (token.length == 0)
        return nil;

    for (NSString *did in @[@"did:plc:", @"did:web:"])
    {
        if ([token hasPrefix:did])
            return token;
    }

    return nil;
}

@end
