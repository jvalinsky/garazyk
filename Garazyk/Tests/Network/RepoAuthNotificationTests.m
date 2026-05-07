#import "RepoAuthXrpcTestBase.h"
#import "Database/Service/ServiceDatabases.h"
#import "Database/PDSDatabase.h"
#import "AppView/Services/ActorService.h"

@interface RepoAuthNotificationTests : RepoAuthXrpcTestBase
@end

@implementation RepoAuthNotificationTests

#pragma mark - registerPush

- (void)testRegisterPushRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.notification.registerPush"
                                                    body:@{
                                                        @"serviceDid": @"did:web:push.example.com",
                                                        @"token": @"apns-token-abc",
                                                        @"platform": @"ios",
                                                        @"appId": @"com.example.app"
                                                    }
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 401, @"Expected 401 without auth, got %ld", (long)response.statusCode);
}

- (void)testRegisterPushValidationErrors {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];

    NSArray *invalidBodies = @[
        @{@"token": @"tok", @"platform": @"ios", @"appId": @"com.example"},
        @{@"serviceDid": @"did:web:push.example.com", @"platform": @"ios", @"appId": @"com.example"},
        @{@"serviceDid": @"did:web:push.example.com", @"token": @"tok", @"appId": @"com.example"},
        @{@"serviceDid": @"did:web:push.example.com", @"token": @"tok", @"platform": @"ios"},
        @{@"serviceDid": @"did:web:push.example.com", @"token": @"tok", @"platform": @"linux", @"appId": @"com.example"}
    ];

    NSArray *expectedMessages = @[
        @"serviceDid",
        @"token",
        @"platform",
        @"appId",
        @"platform"
    ];

    for (NSUInteger i = 0; i < invalidBodies.count; i++) {
        HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.notification.registerPush"
                                                        body:invalidBodies[i]
                                                     headers:@{@"authorization": authHeader}];
        XCTAssertEqual(response.statusCode, 400,
            @"Test %lu: Expected 400 for body %@, got %ld",
            (unsigned long)i, invalidBodies[i], (long)response.statusCode);
        XCTAssertTrue(
            [response.jsonBody[@"message"] rangeOfString:expectedMessages[i] options:NSCaseInsensitiveSearch].location != NSNotFound,
            @"Test %lu: Expected message containing '%@', got '%@'",
            (unsigned long)i, expectedMessages[i], response.jsonBody[@"message"]);
    }

    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.notification.registerPush"
                                                    body:@{@"serviceDid": @"did:web:push.example.com",
                                                           @"token": @"tok",
                                                           @"platform": @"android",
                                                           @"appId": @"com.example"}
                                                 headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200,
        @"Valid android platform should succeed, got %ld: %@",
        (long)response.statusCode, response.jsonBody);

    response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.notification.registerPush"
                                     body:@{@"serviceDid": @"did:web:push.example.com",
                                            @"token": @"tok",
                                            @"platform": @"web",
                                            @"appId": @"com.example"}
                                  headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200,
        @"Valid web platform should succeed, got %ld", (long)response.statusCode);
}

- (void)testRegisterPushSuccess {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.notification.registerPush"
                                                    body:@{
                                                        @"serviceDid": @"did:web:push.example.com",
                                                        @"token": @"apns-token-xyz",
                                                        @"platform": @"ios",
                                                        @"appId": @"com.example.app"
                                                    }
                                                 headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200, @"Expected 200, got %ld: %@",
        (long)response.statusCode, response.jsonBody);
    XCTAssertEqualObjects(response.jsonBody, @{},
        @"registerPush should return empty body on success");
}

#pragma mark - unregisterPush

- (void)testUnregisterPushRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.notification.unregisterPush"
                                                    body:@{
                                                        @"serviceDid": @"did:web:push.example.com",
                                                        @"token": @"apns-token-xyz",
                                                        @"platform": @"ios",
                                                        @"appId": @"com.example.app"
                                                    }
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testUnregisterPushValidationErrors {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];

    NSArray *invalidBodies = @[
        @{@"token": @"tok", @"platform": @"ios", @"appId": @"com.example"},
        @{@"serviceDid": @"did:web:push.example.com", @"platform": @"ios", @"appId": @"com.example"},
        @{@"serviceDid": @"did:web:push.example.com", @"token": @"tok", @"appId": @"com.example"},
        @{@"serviceDid": @"did:web:push.example.com", @"token": @"tok", @"platform": @"ios"}
    ];

    NSArray *expectedMessages = @[@"serviceDid", @"token", @"platform", @"appId"];

    for (NSUInteger i = 0; i < invalidBodies.count; i++) {
        HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.notification.unregisterPush"
                                                        body:invalidBodies[i]
                                                     headers:@{@"authorization": authHeader}];
        XCTAssertEqual(response.statusCode, 400,
            @"Test %lu: Expected 400, got %ld for %@",
            (unsigned long)i, (long)response.statusCode, invalidBodies[i]);
        XCTAssertTrue(
            [response.jsonBody[@"message"] rangeOfString:expectedMessages[i] options:NSCaseInsensitiveSearch].location != NSNotFound,
            @"Expected message containing '%@', got '%@'",
            expectedMessages[i], response.jsonBody[@"message"]);
    }
}

- (void)testUnregisterPushSuccess {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];

    HttpResponse *reg = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.notification.registerPush"
                                                 body:@{
                                                     @"serviceDid": @"did:web:push.example.com",
                                                     @"token": @"tok-to-unreg",
                                                     @"platform": @"ios",
                                                     @"appId": @"com.example.app"
                                                 }
                                              headers:@{@"authorization": authHeader}];
    XCTAssertEqual(reg.statusCode, 200);

    HttpResponse *unreg = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.notification.unregisterPush"
                                                 body:@{
                                                     @"serviceDid": @"did:web:push.example.com",
                                                     @"token": @"tok-to-unreg",
                                                     @"platform": @"ios",
                                                     @"appId": @"com.example.app"
                                                 }
                                              headers:@{@"authorization": authHeader}];
    XCTAssertEqual(unreg.statusCode, 200,
        @"unregisterPush should succeed after registerPush, got %ld: %@",
        (long)unreg.statusCode, unreg.jsonBody);
    XCTAssertEqualObjects(unreg.jsonBody, @{});
}

#pragma mark - putPreferencesV2

- (void)testPutPreferencesV2RequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.notification.putPreferencesV2"
                                                    body:@{@"follow": @{@"include": @"all", @"list": @NO, @"push": @YES}}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testPutPreferencesV2EmptyBody {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.notification.putPreferencesV2"
                                                    body:@{}
                                                 headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 400,
        @"Empty body should return 400, got %ld: %@",
        (long)response.statusCode, response.jsonBody);
    XCTAssertTrue(
        [response.jsonBody[@"message"] rangeOfString:@"preferences" options:NSCaseInsensitiveSearch].location != NSNotFound,
        @"Expected message about preferences, got '%@'", response.jsonBody[@"message"]);
}

- (void)testPutPreferencesV2SuccessPersists {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.notification.putPreferencesV2"
                                                    body:@{
                                                        @"follow": @{@"include": @"all", @"list": @NO, @"push": @YES},
                                                        @"like": @{@"include": @"follows", @"list": @YES, @"push": @NO}
                                                    }
                                                 headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200,
        @"Expected 200, got %ld: %@", (long)response.statusCode, response.jsonBody);
    XCTAssertNotNil(response.jsonBody[@"preferences"],
        @"Response should contain preferences key");
    XCTAssertTrue([response.jsonBody[@"preferences"] isKindOfClass:[NSDictionary class]],
        @"preferences should be a dict in response");

    NSError *dbError = nil;
    PDSDatabase *db = [[self serviceDatabases] serviceDatabaseWithError:&dbError];
    XCTAssertNotNil(db, @"Failed to open service database: %@", dbError);

    ActorService *actorService = [[ActorService alloc] initWithDatabase:db];
    NSError *prefsError = nil;
    NSDictionary *stored = [actorService getPreferencesForActor:self.did1 error:&prefsError];
    XCTAssertNil(prefsError, @"getPreferencesForActor should not error: %@", prefsError);
    XCTAssertTrue([stored[@"preferences"] isKindOfClass:[NSArray class]],
        @"Stored preferences should be an array");
    NSArray *prefsList = stored[@"preferences"];

    BOOL foundFollowPref = NO;
    BOOL foundLikePref = NO;
    for (id entry in prefsList) {
        if ([entry isKindOfClass:[NSDictionary class]]) {
            NSString *type = entry[@"$type"];
            if ([type isEqualToString:@"app.bsky.notification.defs#filterablePreference"]) {
                id include = entry[@"include"];
                if ([include isKindOfClass:[NSString class]] && [include isEqualToString:@"all"]) {
                    foundFollowPref = YES;
                } else if ([include isKindOfClass:[NSString class]] && [include isEqualToString:@"follows"]) {
                    foundLikePref = YES;
                }
            }
        }
    }
    XCTAssertTrue(foundFollowPref, @"Stored preferences should contain follow filterablePreference, got: %@", prefsList);
    XCTAssertTrue(foundLikePref, @"Stored preferences should contain like filterablePreference, got: %@", prefsList);
}

#pragma mark - putActivitySubscription

- (void)testPutActivitySubscriptionRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.notification.putActivitySubscription"
                                                    body:@{
                                                        @"subject": self.did2,
                                                        @"activitySubscription": @{@"post": @YES, @"reply": @NO}
                                                    }
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testPutActivitySubscriptionValidationErrors {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];

    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.notification.putActivitySubscription"
                                                    body:@{
                                                        @"activitySubscription": @{@"post": @YES, @"reply": @NO}
                                                    }
                                                 headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 400,
        @"Missing subject should return 400, got %ld: %@",
        (long)response.statusCode, response.jsonBody);
    XCTAssertTrue(
        [response.jsonBody[@"message"] rangeOfString:@"subject" options:NSCaseInsensitiveSearch].location != NSNotFound,
        @"Expected message about subject, got '%@'", response.jsonBody[@"message"]);

    response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.notification.putActivitySubscription"
                                     body:@{
                                         @"subject": self.did2
                                     }
                                  headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 400,
        @"Missing activitySubscription should return 400, got %ld: %@",
        (long)response.statusCode, response.jsonBody);
}

- (void)testPutActivitySubscriptionUpsert {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];

    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.notification.putActivitySubscription"
                                                    body:@{
                                                        @"subject": self.did2,
                                                        @"activitySubscription": @{@"post": @YES, @"reply": @NO}
                                                    }
                                                 headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200,
        @"First put should succeed, got %ld: %@", (long)response.statusCode, response.jsonBody);
    XCTAssertEqualObjects(response.jsonBody[@"subject"], self.did2);
    XCTAssertTrue([response.jsonBody[@"activitySubscription"] isKindOfClass:[NSDictionary class]]);

    response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.notification.putActivitySubscription"
                                     body:@{
                                         @"subject": self.did2,
                                         @"activitySubscription": @{@"post": @NO, @"reply": @YES}
                                     }
                                  headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200,
        @"Second put (upsert) should succeed, got %ld: %@",
        (long)response.statusCode, response.jsonBody);

    NSError *dbError = nil;
    PDSDatabase *db = [[self serviceDatabases] serviceDatabaseWithError:&dbError];
    XCTAssertNotNil(db);
    NSArray *rows = [db executeParameterizedQuery:
        @"SELECT post_enabled, reply_enabled FROM actor_activity_subscriptions WHERE owner_did = ? AND subject_did = ?"
                      params:@[self.did1, self.did2]
                         error:&dbError];
    XCTAssertEqual(rows.count, 1, @"Should have exactly one subscription row");
    XCTAssertEqual([rows.firstObject[@"post_enabled"] integerValue], 0,
        @"post_enabled should be 0 after update");
    XCTAssertEqual([rows.firstObject[@"reply_enabled"] integerValue], 1,
        @"reply_enabled should be 1 after update");
}

#pragma mark - listActivitySubscriptions

- (void)testListActivitySubscriptionsRequiresAuth {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.notification.listActivitySubscriptions"
                                                headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testListActivitySubscriptionsPagination {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];

    NSArray *subjects = @[self.did2, @"did:plc:sub3", @"did:plc:sub4"];
    for (id subject in subjects) {
        HttpResponse *put = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.notification.putActivitySubscription"
                                                    body:@{
                                                        @"subject": subject,
                                                        @"activitySubscription": @{@"post": @YES, @"reply": @YES}
                                                    }
                                                 headers:@{@"authorization": authHeader}];
        XCTAssertEqual(put.statusCode, 200, @"Setup: put for %@ failed: %@", subject, put.jsonBody);
    }

    HttpResponse *page1 = [self sendGetRequestWithPath:@"/xrpc/app.bsky.notification.listActivitySubscriptions"
                                          queryParams:@{@"limit": @"2"}
                                               headers:@{@"authorization": authHeader}];
    XCTAssertEqual(page1.statusCode, 200,
        @"Expected 200, got %ld: %@", (long)page1.statusCode, page1.jsonBody);
    XCTAssertEqual([page1.jsonBody[@"subscriptions"] count], 2,
        @"First page should have 2 subscriptions");
    XCTAssertNotNil(page1.jsonBody[@"cursor"],
        @"First page should have a cursor");
    XCTAssertTrue([page1.jsonBody[@"subscriptions"] isKindOfClass:[NSArray class]]);
    for (id sub in page1.jsonBody[@"subscriptions"]) {
        XCTAssertTrue([sub isKindOfClass:[NSDictionary class]],
            @"Each subscription should be a dict with did");
        XCTAssertNotNil(sub[@"did"], @"Subscription should be hydrated profile with did");
    }

    NSString *cursor = page1.jsonBody[@"cursor"];
    HttpResponse *page2 = [self sendGetRequestWithPath:@"/xrpc/app.bsky.notification.listActivitySubscriptions"
                                          queryParams:@{@"cursor": cursor}
                                               headers:@{@"authorization": authHeader}];
    XCTAssertEqual(page2.statusCode, 200,
        @"Second page should succeed, got %ld: %@",
        (long)page2.statusCode, page2.jsonBody);
    XCTAssertEqual([page2.jsonBody[@"subscriptions"] count], 1,
        @"Second page should have 1 subscription");
    XCTAssertNil(page2.jsonBody[@"cursor"],
        @"Last page should not have a cursor");
}

#pragma mark - uploadVideo

- (void)testUploadVideoRequiresAuth {
    NSData *mp4Data = [self mp4FixtureDataWithSize:1024 * 1024];
    HttpResponse *response = [self sendRawPostRequestWithPath:@"/xrpc/app.bsky.video.uploadVideo"
                                                   bodyData:mp4Data
                                                    headers:@{
                                                        @"content-type": @"video/mp4",
                                                        @"authorization": @"Bearer invalid-token"
                                                    }];
    XCTAssertEqual(response.statusCode, 401,
        @"Expected 401 without valid auth, got %ld", (long)response.statusCode);
}

- (void)testUploadVideoEmptyBody {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];
    HttpResponse *response = [self sendRawPostRequestWithPath:@"/xrpc/app.bsky.video.uploadVideo"
                                                   bodyData:[NSData data]
                                                    headers:@{
                                                        @"content-type": @"video/mp4",
                                                        @"authorization": authHeader
                                                    }];
    XCTAssertEqual(response.statusCode, 400,
        @"Empty body should return 400, got %ld: %@",
        (long)response.statusCode, response.jsonBody);
    XCTAssertTrue(
        [response.jsonBody[@"message"] rangeOfString:@"body" options:NSCaseInsensitiveSearch].location != NSNotFound,
        @"Expected message about body, got '%@'", response.jsonBody[@"message"]);
}

- (void)testUploadVideoSuccessShape {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];
    NSData *mp4Data = [self mp4FixtureDataWithSize:1024 * 1024];
    HttpResponse *response = [self sendRawPostRequestWithPath:@"/xrpc/app.bsky.video.uploadVideo"
                                                   bodyData:mp4Data
                                                    headers:@{
                                                        @"content-type": @"video/mp4",
                                                        @"authorization": authHeader
                                                    }];
    XCTAssertEqual(response.statusCode, 200,
        @"Expected 200, got %ld: %@", (long)response.statusCode, response.jsonBody);

    NSDictionary *jobStatus = response.jsonBody[@"jobStatus"];
    XCTAssertNotNil(jobStatus, @"Response should contain jobStatus");
    XCTAssertTrue([jobStatus isKindOfClass:[NSDictionary class]],
        @"jobStatus should be a dict");

    XCTAssertTrue([jobStatus[@"jobId"] isKindOfClass:[NSString class]] && ((NSString *)jobStatus[@"jobId"]).length > 0,
        @"jobId should be a non-empty string, got: %@", jobStatus[@"jobId"]);
    XCTAssertEqualObjects(jobStatus[@"did"], self.did1,
        @"jobStatus.did should match requester did");
    XCTAssertEqualObjects(jobStatus[@"state"], @"JOB_STATE_PENDING",
        @"Upload should create a pending video processing job");
    XCTAssertEqualObjects(jobStatus[@"progress"], @0,
        @"progress should start at 0 for a newly queued job");
}

#pragma mark - Helpers

- (NSData *)mp4FixtureDataWithSize:(NSUInteger)size {
    NSMutableData *data = [NSMutableData dataWithLength:size];
    arc4random_buf(data.mutableBytes, size);
    
    // Add valid MP4 header (ftyp box at offset 4)
    if (size >= 12) {
        uint8_t *bytes = (uint8_t *)data.mutableBytes;
        bytes[4] = 'f';
        bytes[5] = 't';
        bytes[6] = 'y';
        bytes[7] = 'p';
    }
    
    return [data copy];
}

@end
