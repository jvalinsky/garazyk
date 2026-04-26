#import "AdminAuthXrpcTestBase.h"
#import "AppView/Services/NotificationService.h"
#import "Database/Service/ServiceDatabases.h"
#import "Network/XrpcAppBskyNotificationPack.h"

#ifndef XCTAssertIsInstance
#define XCTAssertIsInstance(obj, cls) XCTAssertTrue([(obj) isKindOfClass:(cls)])
#endif

@interface XrpcAppBskyNotificationPackTests : AdminAuthXrpcTestBase
@end

@implementation XrpcAppBskyNotificationPackTests

- (id<PDSQueryDatabase>)notificationDatabase {
    NSError *error = nil;
    id<PDSQueryDatabase> database = [self.application.serviceDatabases serviceDatabaseWithError:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(database);
    return database;
}

- (NotificationService *)notificationService {
    return [[NotificationService alloc] initWithDatabase:[self notificationDatabase]];
}

- (NSDictionary *)createdPostWithText:(NSString *)text {
    NSError *error = nil;
    NSDictionary *created = [self.application.legacyController createRecordForDid:self.userDid
                                                                       collection:@"app.bsky.feed.post"
                                                                           record:@{
                                                                               @"$type" : @"app.bsky.feed.post",
                                                                               @"text" : text,
                                                                               @"createdAt" : [self iso8601String]
                                                                           }
                                                                   validationMode:PDSValidationModeOff
                                                                            error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(created);
    return created;
}

- (void)seedNotificationForActor:(NSString *)actorDID
                         subject:(NSDictionary *)subject
                          reason:(NSString *)reason {
    NotificationService *service = [self notificationService];
    NSError *error = nil;
    BOOL success = [service createNotificationForActor:actorDID
                                             authorDID:self.userDid
                                                reason:reason
                                         reasonSubject:subject[@"uri"]
                                            subjectURI:subject[@"uri"]
                                            subjectCID:subject[@"cid"]
                                                 error:&error];
    XCTAssertTrue(success);
    XCTAssertNil(error);
}

- (NSArray *)pushTokenRowsForToken:(NSString *)token actor:(NSString *)actorDID {
    id<PDSQueryDatabase> database = [self notificationDatabase];
    NSError *error = nil;
    NSArray *rows = [database executeParameterizedQuery:@"SELECT did, device_token, platform_token, service_endpoint FROM actor_push_tokens WHERE did = ? AND device_token = ?"
                                                 params:@[actorDID, token]
                                                  error:&error];
    XCTAssertNil(error);
    return rows ?: @[];
}

- (void)testGetPreferencesReturnsDefaultPriorityFalse {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.notification.getPreferences"
                                             queryString:@""
                                              queryParams:@{}
                                                  headers:@{@"authorization" : authHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertEqualObjects(response.jsonBody[@"priority"], @NO);
}

- (void)testPutNotificationPreferencesAndPutPreferencesRoundTrip {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];

    HttpResponse *firstResponse = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.notification.putNotificationPreferences"
                                                          body:@{@"priority" : @YES}
                                                       headers:@{@"authorization" : authHeader}];
    XCTAssertEqual(firstResponse.statusCode, 200);

    HttpResponse *secondResponse = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.notification.putPreferences"
                                                           body:@{@"priority" : @NO}
                                                        headers:@{@"authorization" : authHeader}];
    XCTAssertEqual(secondResponse.statusCode, 200);

    HttpResponse *getResponse = [self sendGetRequestWithPath:@"/xrpc/app.bsky.notification.getPreferences"
                                                 queryString:@""
                                                  queryParams:@{}
                                                      headers:@{@"authorization" : authHeader}];
    XCTAssertEqual(getResponse.statusCode, 200);
    XCTAssertEqualObjects(getResponse.jsonBody[@"priority"], @NO);
}

- (void)testPutPreferencesV2RequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.notification.putPreferencesV2"
                                                      body:@{@"like" : @{@"enabled" : @YES}}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testPutPreferencesV2ValidatesAndStoresPreferences {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];

    HttpResponse *invalidResponse = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.notification.putPreferencesV2"
                                                             body:@{}
                                                          headers:@{@"authorization" : authHeader}];
    XCTAssertEqual(invalidResponse.statusCode, 400);
    XCTAssertEqualObjects(invalidResponse.jsonBody[@"error"], @"InvalidRequest");

    NSDictionary *body = @{
        @"like" : @{@"enabled" : @YES},
        @"reply" : @{@"enabled" : @NO},
        @"verified" : @{@"enabled" : @YES}
    };
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.notification.putPreferencesV2"
                                                      body:body
                                                   headers:@{@"authorization" : authHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertEqualObjects(response.jsonBody[@"preferences"][@"like"][@"enabled"], @YES);
    XCTAssertEqualObjects(response.jsonBody[@"preferences"][@"reply"][@"enabled"], @NO);
}

- (void)testListNotificationsRequiresAuth {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.notification.listNotifications"
                                             queryString:@"limit=10"
                                              queryParams:@{@"limit" : @"10"}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testNotificationsUnreadCountAndUpdateSeenRoundTrip {
    NSDictionary *subject = [self createdPostWithText:@"notification subject"];
    [self seedNotificationForActor:self.userDid subject:subject reason:@"reply"];

    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];

    HttpResponse *listResponse = [self sendGetRequestWithPath:@"/xrpc/app.bsky.notification.listNotifications"
                                                  queryString:@"limit=10"
                                                   queryParams:@{@"limit" : @"10"}
                                                       headers:@{@"authorization" : authHeader}];
    XCTAssertEqual(listResponse.statusCode, 200);

    NSArray *notifications = listResponse.jsonBody[@"notifications"];
    XCTAssertIsInstance(notifications, [NSArray class]);
    XCTAssertEqual(notifications.count, 1U);
    XCTAssertEqualObjects(notifications.firstObject[@"uri"], subject[@"uri"]);
    XCTAssertEqualObjects(notifications.firstObject[@"reason"], @"reply");
    XCTAssertEqualObjects(notifications.firstObject[@"record"][@"text"], @"notification subject");

    HttpResponse *unreadResponse = [self sendGetRequestWithPath:@"/xrpc/app.bsky.notification.getUnreadCount"
                                                     queryString:@""
                                                      queryParams:@{}
                                                          headers:@{@"authorization" : authHeader}];
    XCTAssertEqual(unreadResponse.statusCode, 200);
    XCTAssertEqualObjects(unreadResponse.jsonBody[@"count"], @1);

    HttpResponse *updateResponse = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.notification.updateSeen"
                                                            body:@{@"seenAt" : [self iso8601String]}
                                                         headers:@{@"authorization" : authHeader}];
    XCTAssertEqual(updateResponse.statusCode, 200);

    HttpResponse *afterUpdate = [self sendGetRequestWithPath:@"/xrpc/app.bsky.notification.getUnreadCount"
                                                 queryString:@""
                                                  queryParams:@{}
                                                      headers:@{@"authorization" : authHeader}];
    XCTAssertEqual(afterUpdate.statusCode, 200);
    XCTAssertEqualObjects(afterUpdate.jsonBody[@"count"], @0);
}

- (void)testRegisterPushRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.notification.registerPush"
                                                      body:@{@"serviceDid" : @"did:web:push.example",
                                                             @"token" : @"device-token-auth",
                                                             @"platform" : @"ios",
                                                             @"appId" : @"com.example.app"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testRegisterPushValidatesPlatformAndPersistsToken {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];

    HttpResponse *invalidResponse = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.notification.registerPush"
                                                             body:@{@"serviceDid" : @"did:web:push.example",
                                                                    @"token" : @"device-token-push",
                                                                    @"platform" : @"windows",
                                                                    @"appId" : @"com.example.app"}
                                                          headers:@{@"authorization" : authHeader}];
    XCTAssertEqual(invalidResponse.statusCode, 400);
    XCTAssertEqualObjects(invalidResponse.jsonBody[@"error"], @"InvalidRequest");

    HttpResponse *registerResponse = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.notification.registerPush"
                                                               body:@{@"serviceDid" : @"did:web:push.example",
                                                                      @"token" : @"device-token-push",
                                                                      @"platform" : @"ios",
                                                                      @"appId" : @"com.example.app"}
                                                            headers:@{@"authorization" : authHeader}];
    XCTAssertEqual(registerResponse.statusCode, 200);

    NSArray *rows = [self pushTokenRowsForToken:@"device-token-push" actor:self.userDid];
    XCTAssertEqual(rows.count, 1U);
    XCTAssertEqualObjects(rows.firstObject[@"did"], self.userDid);
    XCTAssertEqualObjects(rows.firstObject[@"device_token"], @"device-token-push");
    XCTAssertEqualObjects(rows.firstObject[@"platform_token"], @"ios");
    XCTAssertEqualObjects(rows.firstObject[@"service_endpoint"], @"did:web:push.example");

    HttpResponse *unregisterResponse = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.notification.unregisterPush"
                                                                body:@{@"serviceDid" : @"did:web:push.example",
                                                                       @"token" : @"device-token-push",
                                                                       @"platform" : @"ios",
                                                                       @"appId" : @"com.example.app"}
                                                             headers:@{@"authorization" : authHeader}];
    XCTAssertEqual(unregisterResponse.statusCode, 200);

    rows = [self pushTokenRowsForToken:@"device-token-push" actor:self.userDid];
    XCTAssertEqual(rows.count, 0U);
}

- (void)testListActivitySubscriptionsRequiresAuth {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.notification.listActivitySubscriptions"
                                             queryString:@"limit=10"
                                              queryParams:@{@"limit" : @"10"}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testPutActivitySubscriptionAndListActivitySubscriptionsRoundTrip {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    NSString *subjectDid = @"did:plc:subscription-subject";

    HttpResponse *putResponse = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.notification.putActivitySubscription"
                                                         body:@{@"subject" : subjectDid,
                                                                @"activitySubscription" : @{@"post" : @YES, @"reply" : @NO}}
                                                      headers:@{@"authorization" : authHeader}];
    XCTAssertEqual(putResponse.statusCode, 200);
    XCTAssertEqualObjects(putResponse.jsonBody[@"subject"], subjectDid);
    XCTAssertEqualObjects(putResponse.jsonBody[@"activitySubscription"][@"post"], @YES);

    HttpResponse *listResponse = [self sendGetRequestWithPath:@"/xrpc/app.bsky.notification.listActivitySubscriptions"
                                                  queryString:@"limit=10"
                                                   queryParams:@{@"limit" : @"10"}
                                                       headers:@{@"authorization" : authHeader}];
    XCTAssertEqual(listResponse.statusCode, 200);

    NSArray *subscriptions = listResponse.jsonBody[@"subscriptions"];
    XCTAssertIsInstance(subscriptions, [NSArray class]);
    XCTAssertEqual(subscriptions.count, 1U);
    XCTAssertEqualObjects(subscriptions.firstObject[@"did"], subjectDid);
}

@end
