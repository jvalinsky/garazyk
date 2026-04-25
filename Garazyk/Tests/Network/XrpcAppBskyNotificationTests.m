#import "AdminAuthXrpcTestBase.h"

#ifndef XCTAssertIsInstance
#define XCTAssertIsInstance(expr, classExpr) \
    XCTAssertTrue([(expr) isKindOfClass:(classExpr)], @"Expected %@ to be instance of %@", (expr), (classExpr))
#endif

@interface XrpcAppBskyNotificationTests : AdminAuthXrpcTestBase
@end

@implementation XrpcAppBskyNotificationTests

#pragma mark - getPreferences Tests

- (void)testGetPreferencesRequiresAuth {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.notification.getPreferences"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testGetPreferencesSuccess {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.notification.getPreferences"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"priority"]);
}

#pragma mark - putPreferences Tests

- (void)testPutPreferencesRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.notification.putPreferences"
                                                      body:@{@"priority": @YES}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testPutPreferencesSuccess {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.notification.putPreferences"
                                                      body:@{@"priority": @YES}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
}

#pragma mark - listNotifications Tests

- (void)testListNotificationsRequiresAuth {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.notification.listNotifications"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testListNotificationsSuccess {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.notification.listNotifications"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"notifications"]);
    XCTAssertIsInstance(response.jsonBody[@"notifications"], [NSArray class]);
}

#pragma mark - getUnreadCount Tests

- (void)testGetUnreadCountRequiresAuth {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.notification.getUnreadCount"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testGetUnreadCountSuccess {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.notification.getUnreadCount"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"count"]);
}

#pragma mark - updateSeen Tests

- (void)testUpdateSeenRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.notification.updateSeen"
                                                      body:@{@"seenAt": @"2026-01-01T00:00:00Z"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testUpdateSeenSuccess {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.notification.updateSeen"
                                                      body:@{@"seenAt": @"2026-01-01T00:00:00Z"}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
}

#pragma mark - registerPush Tests

- (void)testRegisterPushRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.notification.registerPush"
                                                      body:@{
                                                          @"serviceDid": @"did:web:push.example.com",
                                                          @"token": @"device-token-abc",
                                                          @"platform": @"ios",
                                                          @"appId": @"com.example.app"
                                                      }
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testRegisterPushRequiresServiceDid {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.notification.registerPush"
                                                      body:@{
                                                          @"token": @"device-token-abc",
                                                          @"platform": @"ios",
                                                          @"appId": @"com.example.app"
                                                      }
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testRegisterPushRequiresToken {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.notification.registerPush"
                                                      body:@{
                                                          @"serviceDid": @"did:web:push.example.com",
                                                          @"platform": @"ios",
                                                          @"appId": @"com.example.app"
                                                      }
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testRegisterPushRequiresPlatform {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.notification.registerPush"
                                                      body:@{
                                                          @"serviceDid": @"did:web:push.example.com",
                                                          @"token": @"device-token-abc",
                                                          @"appId": @"com.example.app"
                                                      }
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testRegisterPushRequiresAppId {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.notification.registerPush"
                                                      body:@{
                                                          @"serviceDid": @"did:web:push.example.com",
                                                          @"token": @"device-token-abc",
                                                          @"platform": @"ios"
                                                      }
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testRegisterPushInvalidPlatform {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.notification.registerPush"
                                                      body:@{
                                                          @"serviceDid": @"did:web:push.example.com",
                                                          @"token": @"device-token-abc",
                                                          @"platform": @"windows",
                                                          @"appId": @"com.example.app"
                                                      }
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testRegisterPushSuccess {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.notification.registerPush"
                                                      body:@{
                                                          @"serviceDid": @"did:web:push.example.com",
                                                          @"token": @"device-token-abc",
                                                          @"platform": @"ios",
                                                          @"appId": @"com.example.app"
                                                      }
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
}

#pragma mark - unregisterPush Tests

- (void)testUnregisterPushRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.notification.unregisterPush"
                                                      body:@{
                                                          @"serviceDid": @"did:web:push.example.com",
                                                          @"token": @"device-token-abc",
                                                          @"platform": @"ios",
                                                          @"appId": @"com.example.app"
                                                      }
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testUnregisterPushSuccess {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.notification.unregisterPush"
                                                      body:@{
                                                          @"serviceDid": @"did:web:push.example.com",
                                                          @"token": @"device-token-abc",
                                                          @"platform": @"ios",
                                                          @"appId": @"com.example.app"
                                                      }
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
}

#pragma mark - listActivitySubscriptions Tests

- (void)testListActivitySubscriptionsRequiresAuth {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.notification.listActivitySubscriptions"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testListActivitySubscriptionsSuccess {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.notification.listActivitySubscriptions"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
}

#pragma mark - putPreferencesV2 Tests

- (void)testPutPreferencesV2RequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.notification.putPreferencesV2"
                                                      body:@{@"like": @{@"enabled": @YES}, @"reply": @{@"enabled": @YES}}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testPutPreferencesV2Success {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.notification.putPreferencesV2"
                                                      body:@{@"like": @{@"enabled": @YES}, @"reply": @{@"enabled": @YES}}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"preferences"]);
}

#pragma mark - putActivitySubscription Tests

- (void)testPutActivitySubscriptionRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.notification.putActivitySubscription"
                                                      body:@{
                                                          @"subject": @"did:plc:test",
                                                          @"activitySubscription": @{@"post": @YES, @"reply": @NO}
                                                      }
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testPutActivitySubscriptionRequiresSubject {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.notification.putActivitySubscription"
                                                      body:@{@"activitySubscription": @{@"post": @YES, @"reply": @NO}}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testPutActivitySubscriptionSuccess {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.notification.putActivitySubscription"
                                                      body:@{
                                                          @"subject": @"did:plc:test",
                                                          @"activitySubscription": @{@"post": @YES, @"reply": @NO}
                                                      }
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"subject"]);
    XCTAssertNotNil(response.jsonBody[@"activitySubscription"]);
}

@end
