#import "RepoAuthXrpcTestBase.h"
#import "Database/Service/ServiceDatabases.h"

@interface RepoAuthTempTests : RepoAuthXrpcTestBase
@end

@implementation RepoAuthTempTests

- (void)testTempRevokeAccountCredentialsRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.temp.revokeAccountCredentials"
                                                      body:@{@"account": self.did1}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testTempRevokeAccountCredentialsRejectsOtherAccount {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.temp.revokeAccountCredentials"
                                                      body:@{@"account": self.did2}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 403);
}

- (void)testTempRevokeAccountCredentialsRevokesRefreshAndAppPasswords {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];

    HttpResponse *createdResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.createAppPassword"
                                                             body:@{@"name": @"temp-revoke-test"}
                                                          headers:@{@"authorization": authHeader}];
    XCTAssertEqual(createdResponse.statusCode, 200);
    NSString *appPassword = createdResponse.jsonBody[@"password"];
    XCTAssertNotNil(appPassword);

    HttpResponse *revokeResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.temp.revokeAccountCredentials"
                                                            body:@{@"account": @"repoauth1.test"}
                                                         headers:@{@"authorization": authHeader}];
    XCTAssertEqual(revokeResponse.statusCode, 200);
    XCTAssertTrue([revokeResponse.jsonBody isKindOfClass:[NSDictionary class]]);
    XCTAssertEqual(((NSDictionary *)revokeResponse.jsonBody).count, 0U);

    NSError *refreshError = nil;
    NSDictionary *refreshed = [self.controller refreshAccessToken:self.refreshJwt1 error:&refreshError];
    XCTAssertNil(refreshed);
    XCTAssertNotNil(refreshError);

    HttpResponse *sessionAfterRevoke = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.createSession"
                                                                body:@{@"identifier": @"repoauth1.test",
                                                                       @"password": appPassword}
                                                             headers:@{}];
    XCTAssertEqual(sessionAfterRevoke.statusCode, 401);
}

- (void)testTempAddReservedHandleRequiresAdmin {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.temp.addReservedHandle"
                                                      body:@{@"handle": @"reserved-temp.test"}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 403);
}

- (void)testTempAddReservedHandleAdminMakesHandleUnavailable {
    NSString *adminAuthHeader = [NSString stringWithFormat:@"Bearer %@", self.adminAccessJwt];
    HttpResponse *reserveResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.temp.addReservedHandle"
                                                             body:@{@"handle": @"reserved-temp.test"}
                                                          headers:@{@"authorization": adminAuthHeader}];
    XCTAssertEqual(reserveResponse.statusCode, 200);

    HttpResponse *checkResponse = [self sendGetRequestWithPath:@"/xrpc/com.atproto.temp.checkHandleAvailability"
                                                   queryParams:@{@"handle": @"reserved-temp.test"}
                                                       headers:@{}];
    XCTAssertEqual(checkResponse.statusCode, 200);
    XCTAssertEqualObjects(checkResponse.jsonBody[@"handle"], @"reserved-temp.test");
    NSDictionary *result = checkResponse.jsonBody[@"result"];
    XCTAssertTrue([result isKindOfClass:[NSDictionary class]]);
    NSArray *suggestions = result[@"suggestions"];
    XCTAssertTrue([suggestions isKindOfClass:[NSArray class]]);
}

- (void)testTempAddReservedHandlePersistsInServiceDatabase {
    NSString *adminAuthHeader = [NSString stringWithFormat:@"Bearer %@", self.adminAccessJwt];
    HttpResponse *reserveResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.temp.addReservedHandle"
                                                             body:@{@"handle": @"reserved-persisted.test"}
                                                          headers:@{@"authorization": adminAuthHeader}];
    XCTAssertEqual(reserveResponse.statusCode, 200);

    NSError *error = nil;
    BOOL reserved = [self.controller.serviceDatabases isHandleReserved:@"reserved-persisted.test" error:&error];
    XCTAssertNil(error);
    XCTAssertTrue(reserved);
}

- (void)testTempCheckHandleAvailabilityAvailable {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.temp.checkHandleAvailability"
                                              queryParams:@{@"handle": @"fresh-temp.test"}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertEqualObjects(response.jsonBody[@"handle"], @"fresh-temp.test");
    NSDictionary *result = response.jsonBody[@"result"];
    XCTAssertTrue([result isKindOfClass:[NSDictionary class]]);
    XCTAssertEqual(result.count, 0U);
}

- (void)testTempCheckHandleAvailabilityUnavailableForExistingAccount {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.temp.checkHandleAvailability"
                                              queryParams:@{@"handle": @"repoauth2.test"}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    NSDictionary *result = response.jsonBody[@"result"];
    XCTAssertTrue([result isKindOfClass:[NSDictionary class]]);
    NSArray *suggestions = result[@"suggestions"];
    XCTAssertTrue([suggestions isKindOfClass:[NSArray class]]);
    XCTAssertTrue(suggestions.count > 0U);
}

- (void)testTempCheckHandleAvailabilityRejectsInvalidEmail {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.temp.checkHandleAvailability"
                                              queryParams:@{@"handle": @"fresh-email.test",
                                                            @"email": @"not-an-email"}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"InvalidEmail");
}

- (void)testTempCheckSignupQueueReturnsActivated {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.temp.checkSignupQueue"
                                              queryParams:@{}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertEqualObjects(response.jsonBody[@"activated"], @YES);
}

- (void)testTempDereferenceScopeRejectsInvalidReference {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.temp.dereferenceScope"
                                              queryParams:@{@"scope": @"com.atproto.transition:generic"}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"InvalidScopeReference");
}

- (void)testTempDereferenceScopeReturnsResolvedScope {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.temp.dereferenceScope"
                                              queryParams:@{@"scope": @"ref:com.atproto.transition:generic"}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertEqualObjects(response.jsonBody[@"scope"], @"atproto transition:generic");
}

- (void)testTempDereferenceScopeRejectsUnknownReference {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.temp.dereferenceScope"
                                              queryParams:@{@"scope": @"ref:com.atproto.transition:does-not-exist"}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"InvalidScopeReference");
}

- (void)testTempDereferenceScopeResolvesKnownCompositeReference {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.temp.dereferenceScope"
                                              queryParams:@{@"scope": @"ref:com.atproto.transition:chat.bsky"}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertEqualObjects(response.jsonBody[@"scope"], @"atproto transition:generic transition:chat.bsky");
}

- (void)testTempFetchLabelsReturnsArray {
    NSError *error = nil;
    NSDictionary *label = [self.controller createLabel:@{
        @"src": self.did1,
        @"uri": [NSString stringWithFormat:@"at://%@/app.bsky.feed.post/test", self.did1],
        @"val": @"test-label",
        @"cts": [self iso8601String]
    } error:&error];
    XCTAssertNotNil(label);
    XCTAssertNil(error);

    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.temp.fetchLabels"
                                              queryParams:@{@"limit": @"10"}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertEqualObjects(response.headers[@"Deprecation"], @"true");
    XCTAssertNotNil(response.headers[@"Sunset"]);
    XCTAssertTrue([response.headers[@"Warning"] containsString:@"deprecated"]);
    XCTAssertTrue([response.headers[@"Link"] containsString:@"com.atproto.label.queryLabels"]);
    NSArray *labels = response.jsonBody[@"labels"];
    XCTAssertTrue([labels isKindOfClass:[NSArray class]]);
    XCTAssertTrue(labels.count > 0U);
}

- (void)testTempRequestPhoneVerificationValidation {
    HttpResponse *invalidResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.temp.requestPhoneVerification"
                                                             body:@{@"phoneNumber": @"bad-phone"}
                                                          headers:@{}];
    XCTAssertEqual(invalidResponse.statusCode, 400);
}

- (void)testTempRequestPhoneVerificationReturnsNotConfiguredByDefault {
    const char *existingProvider = getenv("PDS_PHONE_VERIFICATION_PROVIDER");
    NSString *previousValue = existingProvider ? [NSString stringWithUTF8String:existingProvider] : nil;
    unsetenv("PDS_PHONE_VERIFICATION_PROVIDER");

    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.temp.requestPhoneVerification"
                                                      body:@{@"phoneNumber": @"+12025550123"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 501);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"PhoneVerificationNotConfigured");

    if (previousValue) {
        setenv("PDS_PHONE_VERIFICATION_PROVIDER", previousValue.UTF8String, 1);
    } else {
        unsetenv("PDS_PHONE_VERIFICATION_PROVIDER");
    }
}

- (void)testTempRequestPhoneVerificationMockProviderSuccess {
    const char *existingProvider = getenv("PDS_PHONE_VERIFICATION_PROVIDER");
    NSString *previousValue = existingProvider ? [NSString stringWithUTF8String:existingProvider] : nil;
    setenv("PDS_PHONE_VERIFICATION_PROVIDER", "mock", 1);

    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.temp.requestPhoneVerification"
                                                      body:@{@"phoneNumber": @"+12025550123"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertTrue([response.jsonBody isKindOfClass:[NSDictionary class]]);
    XCTAssertEqual(((NSDictionary *)response.jsonBody).count, 0U);

    if (previousValue) {
        setenv("PDS_PHONE_VERIFICATION_PROVIDER", previousValue.UTF8String, 1);
    } else {
        unsetenv("PDS_PHONE_VERIFICATION_PROVIDER");
    }
}

- (void)testTempRequestPhoneVerificationRejectsUnsupportedProvider {
    const char *existingProvider = getenv("PDS_PHONE_VERIFICATION_PROVIDER");
    NSString *previousValue = existingProvider ? [NSString stringWithUTF8String:existingProvider] : nil;
    setenv("PDS_PHONE_VERIFICATION_PROVIDER", "example-provider", 1);

    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.temp.requestPhoneVerification"
                                                      body:@{@"phoneNumber": @"+12025550123"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 501);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"UnsupportedPhoneVerificationProvider");

    if (previousValue) {
        setenv("PDS_PHONE_VERIFICATION_PROVIDER", previousValue.UTF8String, 1);
    } else {
        unsetenv("PDS_PHONE_VERIFICATION_PROVIDER");
    }
}

@end
