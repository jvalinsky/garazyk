// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminAuthXrpcTestBase.h"
#import "AppView/Services/NotificationService.h"
#import "Database/Service/ServiceDatabases.h"
#import "Database/PDSBlock.h"
#import "Core/CID.h"
#import "Core/ATProtoCBORSerialization.h"
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
    NSDictionary *record = @{
        @"$type" : @"app.bsky.feed.post",
        @"text" : text,
        @"createdAt" : [self iso8601String]
    };
    NSError *error = nil;
    NSDictionary *created = [self.application.legacyController createRecordForDid:self.userDid
                                                                       collection:@"app.bsky.feed.post"
                                                                           record:record
                                                                   validationMode:PDSValidationModeOff
                                                                            error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(created);

    // Seed the record into the service DB so NotificationService can hydrate the record field
    [self seedRecordInServiceDB:created record:record forDid:self.userDid collection:@"app.bsky.feed.post"];

    return created;
}

- (void)seedRecordInServiceDB:(NSDictionary *)createdRecord
                        record:(NSDictionary *)record
                       forDid:(NSString *)did
                   collection:(NSString *)collection {
    NSError *dbError = nil;
    PDSDatabase *database = [self.application.serviceDatabases serviceDatabaseWithError:&dbError];
    XCTAssertNil(dbError);
    XCTAssertNotNil(database);

    NSString *uri = createdRecord[@"uri"];
    NSString *cidStr = createdRecord[@"cid"];
    XCTAssertNotNil(uri);
    XCTAssertNotNil(cidStr);

    // Parse URI to extract rkey: at://did/collection/rkey
    NSArray *components = [uri componentsSeparatedByString:@"/"];
    NSString *rkey = components.count >= 5 ? components[4] : @"";

    // CBOR-encode the record for the blocks table
    NSError *cborError = nil;
    NSData *cborData = [ATProtoCBORSerialization encodeDataWithJSONObject:record error:&cborError];
    XCTAssertNil(cborError);
    XCTAssertNotNil(cborData);

    // Compute CID from CBOR data (same as PDSController does)
    NSData *digest = [CID sha256Digest:cborData];
    CID *cid = [CID cidWithDigest:digest codec:0x71]; // dag-cbor codec

    // Insert into records table
    NSString *valueJSON = [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:record options:0 error:nil] encoding:NSUTF8StringEncoding];
    NSString *insertSQL = @"INSERT OR REPLACE INTO records (uri, did, collection, rkey, cid, value) VALUES (?, ?, ?, ?, ?, ?)";
    BOOL insertOK = [database executeParameterizedUpdate:insertSQL
                                                  params:@[uri, did, collection, rkey, cid.stringValue ?: cidStr, valueJSON ?: @""]
                                                   error:&dbError];
    XCTAssertTrue(insertOK);
    XCTAssertNil(dbError);

    // Insert into blocks table for getRecordBodyFromCID: lookups
    PDSDatabaseBlock *block = [[PDSDatabaseBlock alloc] init];
    block.cid = cid.bytes;
    block.repoDid = did;
    block.blockData = cborData;
    block.contentType = @"application/cbor";
    block.size = (NSInteger)cborData.length;
    block.createdAt = [NSDate date];

    BOOL blockOK = [database saveBlock:block error:&dbError];
    XCTAssertTrue(blockOK);
    XCTAssertNil(dbError);
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

- (void)testGetPreferencesReturnsDefaultPreferences {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.notification.getPreferences"
                                             queryString:@""
                                              queryParams:@{}
                                                  headers:@{@"authorization" : authHeader}];
    XCTAssertEqual(response.statusCode, 200);
    NSDictionary *preferences = response.jsonBody[@"preferences"];
    XCTAssertTrue([preferences isKindOfClass:[NSDictionary class]]);
    NSDictionary *follow = preferences[@"follow"];
    XCTAssertTrue([follow isKindOfClass:[NSDictionary class]]);
    XCTAssertEqualObjects(follow[@"list"], @YES);
    XCTAssertEqualObjects(follow[@"push"], @NO);
}

- (void)testPutPreferencesV2RoundTripThroughGetPreferences {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];

    HttpResponse *updateResponse = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.notification.putPreferencesV2"
                                                           body:@{@"follow" : @{@"include" : @"all", @"list" : @NO, @"push" : @YES}}
                                                        headers:@{@"authorization" : authHeader}];
    XCTAssertEqual(updateResponse.statusCode, 200);

    HttpResponse *getResponse = [self sendGetRequestWithPath:@"/xrpc/app.bsky.notification.getPreferences"
                                                 queryString:@""
                                                  queryParams:@{}
                                                      headers:@{@"authorization" : authHeader}];
    XCTAssertEqual(getResponse.statusCode, 200);
    NSDictionary *preferences = getResponse.jsonBody[@"preferences"];
    NSDictionary *follow = preferences[@"follow"];
    XCTAssertTrue([follow isKindOfClass:[NSDictionary class]]);
    XCTAssertEqualObjects(follow[@"list"], @NO);
    XCTAssertEqualObjects(follow[@"push"], @YES);
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
