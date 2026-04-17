#import "AdminAuthXrpcTestBase.h"

@interface XrpcChatBskyConvoTests : AdminAuthXrpcTestBase
@property (nonatomic, copy) NSString *secondUserDid;
@property (nonatomic, copy) NSString *secondUserJwt;
@end

@implementation XrpcChatBskyConvoTests

- (void)setUp {
    [super setUp];

    // Create second user for testing conversations
    NSDictionary *createUserResponse = [self createTestUser];
    self.secondUserDid = createUserResponse[@"did"];
    self.secondUserJwt = createUserResponse[@"accessJwt"];
}

// Helper method to create a test user
- (NSDictionary *)createTestUser {
    NSString *uniqueHandle = [NSString stringWithFormat:@"testuser%@", [[NSUUID UUID] UUIDString]];

    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.createAccount"
                                                      body:@{
                                                          @"handle": uniqueHandle,
                                                          @"password": @"password123",
                                                          @"email": [NSString stringWithFormat:@"%@@example.com", uniqueHandle]
                                                      }
                                                   headers:@{}];

    if (response.statusCode == 200 && response.jsonBody[@"did"]) {
        return @{
            @"did": response.jsonBody[@"did"],
            @"accessJwt": response.jsonBody[@"accessJwt"] ?: @""
        };
    }
    return nil;
}

#pragma mark - getConvoForMembers Tests

- (void)testGetConvoForMembersRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.convo.getConvoForMembers"
                                                      body:@{@"members": @[self.userDid, self.secondUserDid]}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"AuthRequired");
}

- (void)testGetConvoForMembersCreatesConversation {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.convo.getConvoForMembers"
                                                      body:@{@"members": @[self.userDid, self.secondUserDid]}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"convo"]);
    XCTAssertNotNil(response.jsonBody[@"convo"][@"id"]);
}

- (void)testGetConvoForMembersRequiresTwoMembers {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.convo.getConvoForMembers"
                                                      body:@{@"members": @[self.userDid]}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 400);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"InvalidRequest");
}

- (void)testGetConvoForMembersReturnsSamConversationOnSecondCall {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];

    // First call
    HttpResponse *response1 = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.convo.getConvoForMembers"
                                                       body:@{@"members": @[self.userDid, self.secondUserDid]}
                                                    headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response1.statusCode, 200);
    NSString *convoId1 = response1.jsonBody[@"convo"][@"id"];

    // Second call with same members
    HttpResponse *response2 = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.convo.getConvoForMembers"
                                                       body:@{@"members": @[self.userDid, self.secondUserDid]}
                                                    headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response2.statusCode, 200);
    NSString *convoId2 = response2.jsonBody[@"convo"][@"id"];

    XCTAssertEqualObjects(convoId1, convoId2);
}

#pragma mark - acceptConvo Tests

- (void)testAcceptConvoRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.convo.acceptConvo"
                                                      body:@{@"convoId": @"convo/test"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testAcceptConvoUpdatesStatus {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];

    // Create conversation
    HttpResponse *createResponse = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.convo.getConvoForMembers"
                                                            body:@{@"members": @[self.userDid, self.secondUserDid]}
                                                         headers:@{@"authorization": authHeader}];
    NSString *convoId = createResponse.jsonBody[@"convo"][@"id"];

    // Accept conversation
    HttpResponse *acceptResponse = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.convo.acceptConvo"
                                                             body:@{@"convoId": convoId}
                                                          headers:@{@"authorization": authHeader}];
    XCTAssertEqual(acceptResponse.statusCode, 200);
    XCTAssertNotNil(acceptResponse.jsonBody[@"convo"]);
}

#pragma mark - leaveConvo Tests

- (void)testLeaveConvoRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.convo.leaveConvo"
                                                      body:@{@"convoId": @"convo/test"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testLeaveConvo {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];

    // Create conversation
    HttpResponse *createResponse = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.convo.getConvoForMembers"
                                                            body:@{@"members": @[self.userDid, self.secondUserDid]}
                                                         headers:@{@"authorization": authHeader}];
    NSString *convoId = createResponse.jsonBody[@"convo"][@"id"];

    // Leave conversation
    HttpResponse *leaveResponse = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.convo.leaveConvo"
                                                           body:@{@"convoId": convoId}
                                                        headers:@{@"authorization": authHeader}];
    XCTAssertEqual(leaveResponse.statusCode, 200);
}

#pragma mark - listConvoRequests Tests

- (void)testListConvoRequestsRequiresAuth {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/chat.bsky.convo.listConvoRequests"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testListConvoRequestsReturnsEmpty {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/chat.bsky.convo.listConvoRequests"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"requests"]);
    XCTAssertEqual([response.jsonBody[@"requests"] count], 0);
}

#pragma mark - getConvoAvailability Tests

- (void)testGetConvoAvailabilityRequiresDid {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/chat.bsky.convo.getConvoAvailability"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testGetConvoAvailabilityForValidActor {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/chat.bsky.convo.getConvoAvailability"
                                             queryString:[NSString stringWithFormat:@"did=%@", self.userDid]
                                             queryParams:@{@"did": self.userDid}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"available"]);
    XCTAssertTrue([response.jsonBody[@"available"] boolValue]);
}

- (void)testGetConvoAvailabilityForInvalidActor {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/chat.bsky.convo.getConvoAvailability"
                                             queryString:@"did=did:plc:invalid"
                                             queryParams:@{@"did": @"did:plc:invalid"}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
}

@end
