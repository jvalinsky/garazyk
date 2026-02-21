#import "RepoAuthXrpcTestBase.h"

@interface RepoAuthIdentityTests : RepoAuthXrpcTestBase
@end

@implementation RepoAuthIdentityTests

- (void)testIdentityUpdateHandleRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.identity.updateHandle"
                                                      body:@{@"handle": @"repoauth1-renamed.test"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testIdentityUpdateHandleUpdatesAccountHandle {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.identity.updateHandle"
                                                      body:@{@"handle": @"repoauth1-renamed.test"}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);

    NSError *error = nil;
    NSDictionary *account = [self.controller getAccountForDid:self.did1 error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(account[@"handle"], @"repoauth1-renamed.test");

    NSDictionary *session = [self.controller loginWithHandle:@"repoauth1-renamed.test" password:@"password" error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(session[@"accessJwt"]);
}

- (void)testRefreshIdentityReturnsIdentityInfo {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.identity.refreshIdentity"
                                                      body:@{@"identifier": @"repoauth1.test"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertEqualObjects(response.jsonBody[@"did"], self.did1);
    XCTAssertNotNil(response.jsonBody[@"didDoc"]);
    XCTAssertNotNil(response.jsonBody[@"handle"]);
}

- (void)testIdentitySignAndSubmitPlcOperation {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];

    HttpResponse *requestSignature = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.identity.requestPlcOperationSignature"
                                                              body:@{}
                                                           headers:@{@"authorization": authHeader}];
    XCTAssertEqual(requestSignature.statusCode, 200);
    NSString *token = requestSignature.jsonBody[@"token"];
    XCTAssertNotNil(token);

    HttpResponse *signResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.identity.signPlcOperation"
                                                          body:@{@"token": token}
                                                       headers:@{@"authorization": authHeader}];
    XCTAssertEqual(signResponse.statusCode, 200);
    NSDictionary *operation = signResponse.jsonBody[@"operation"];
    XCTAssertNotNil(operation);
    XCTAssertEqualObjects(operation[@"did"], self.did1);
    NSString *sig = operation[@"sig"];
    XCTAssertNotNil(sig);
    XCTAssertFalse([sig containsString:@"="]);
    XCTAssertFalse([sig containsString:@"+"]);
    XCTAssertFalse([sig containsString:@"/"]);

    HttpResponse *submitResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.identity.submitPlcOperation"
                                                            body:@{@"operation": operation}
                                                         headers:@{@"authorization": authHeader}];
    XCTAssertEqual(submitResponse.statusCode, 200);
}

@end
