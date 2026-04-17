#import "AdminAuthXrpcTestBase.h"

@interface XrpcChatBskyGroupTests : AdminAuthXrpcTestBase
@property (nonatomic, copy) NSString *secondUserDid;
@property (nonatomic, copy) NSString *secondUserJwt;
@property (nonatomic, copy) NSString *thirdUserDid;
@property (nonatomic, copy) NSString *thirdUserJwt;
@property (nonatomic, copy) NSString *testGroupUri;
@end

@implementation XrpcChatBskyGroupTests

- (void)setUp {
    [super setUp];

    // Create additional test users
    NSDictionary *secondUser = [self createTestUser];
    self.secondUserDid = secondUser[@"did"];
    self.secondUserJwt = secondUser[@"accessJwt"];

    NSDictionary *thirdUser = [self createTestUser];
    self.thirdUserDid = thirdUser[@"did"];
    self.thirdUserJwt = thirdUser[@"accessJwt"];

    // Create a test group
    self.testGroupUri = [self createTestGroupReturningUri];
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

// Helper method to create a test group
- (NSString *)createTestGroupReturningUri {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.group.createGroup"
                                                      body:@{
                                                          @"name": @"Test Group",
                                                          @"description": @"A test group",
                                                          @"privacy": @"private",
                                                          @"joinability": @"invite_only"
                                                      }
                                                   headers:@{@"authorization": authHeader}];

    if (response.statusCode == 200 && response.jsonBody[@"group"][@"uri"]) {
        return response.jsonBody[@"group"][@"uri"];
    }
    return nil;
}

#pragma mark - createGroup Tests

- (void)testCreateGroupRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.group.createGroup"
                                                      body:@{
                                                          @"name": @"Test Group",
                                                          @"privacy": @"private",
                                                          @"joinability": @"invite_only"
                                                      }
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"AuthRequired");
}

- (void)testCreateGroupSuccessfully {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.group.createGroup"
                                                      body:@{
                                                          @"name": @"New Test Group",
                                                          @"description": @"A new test group",
                                                          @"privacy": @"private",
                                                          @"joinability": @"invite_only"
                                                      }
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"group"]);
    XCTAssertNotNil(response.jsonBody[@"group"][@"uri"]);
    XCTAssertEqualObjects(response.jsonBody[@"group"][@"name"], @"New Test Group");
    XCTAssertEqualObjects(response.jsonBody[@"group"][@"creator"], self.userDid);
}

- (void)testCreateGroupRequiresName {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.group.createGroup"
                                                      body:@{
                                                          @"privacy": @"private",
                                                          @"joinability": @"invite_only"
                                                      }
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 400);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"InvalidRequest");
}

#pragma mark - editGroup Tests

- (void)testEditGroupRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.group.editGroup"
                                                      body:@{
                                                          @"groupUri": self.testGroupUri,
                                                          @"name": @"Updated Group"
                                                      }
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testEditGroupSuccessfully {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.group.editGroup"
                                                      body:@{
                                                          @"groupUri": self.testGroupUri,
                                                          @"name": @"Updated Group Name",
                                                          @"description": @"Updated description"
                                                      }
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"group"]);
    XCTAssertEqualObjects(response.jsonBody[@"group"][@"name"], @"Updated Group Name");
}

- (void)testEditGroupOnlyForAdmin {
    NSString *secondUserAuthHeader = [NSString stringWithFormat:@"Bearer %@", self.secondUserJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.group.editGroup"
                                                      body:@{
                                                          @"groupUri": self.testGroupUri,
                                                          @"name": @"Hacked Name"
                                                      }
                                                   headers:@{@"authorization": secondUserAuthHeader}];
    XCTAssertEqual(response.statusCode, 401);
}

#pragma mark - getGroupPublicInfo Tests

- (void)testGetGroupPublicInfoNoAuthRequired {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/chat.bsky.group.getGroupPublicInfo"
                                             queryString:[NSString stringWithFormat:@"groupUri=%@", self.testGroupUri]
                                             queryParams:@{@"groupUri": self.testGroupUri}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"group"]);
    XCTAssertEqualObjects(response.jsonBody[@"group"][@"uri"], self.testGroupUri);
}

- (void)testGetGroupPublicInfoIncludesMemberCount {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/chat.bsky.group.getGroupPublicInfo"
                                             queryString:[NSString stringWithFormat:@"groupUri=%@", self.testGroupUri]
                                             queryParams:@{@"groupUri": self.testGroupUri}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"group"][@"memberCount"]);
    // Should at least have the creator
    XCTAssertGreaterThanOrEqual([response.jsonBody[@"group"][@"memberCount"] integerValue], 1);
}

- (void)testGetGroupPublicInfoNotFound {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/chat.bsky.group.getGroupPublicInfo"
                                             queryString:@"groupUri=at://invalid/uri"
                                             queryParams:@{@"groupUri": @"at://invalid/uri"}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
}

#pragma mark - addMembers Tests

- (void)testAddMembersRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.group.addMembers"
                                                      body:@{
                                                          @"groupUri": self.testGroupUri,
                                                          @"members": @[self.secondUserDid]
                                                      }
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testAddMembersSuccessfully {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.group.addMembers"
                                                      body:@{
                                                          @"groupUri": self.testGroupUri,
                                                          @"members": @[self.secondUserDid]
                                                      }
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertTrue([response.jsonBody[@"success"] boolValue]);
}

- (void)testAddMultipleMembers {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.group.addMembers"
                                                      body:@{
                                                          @"groupUri": self.testGroupUri,
                                                          @"members": @[self.secondUserDid, self.thirdUserDid]
                                                      }
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertTrue([response.jsonBody[@"success"] boolValue]);
}

- (void)testAddMembersOnlyForAdmin {
    NSString *secondUserAuthHeader = [NSString stringWithFormat:@"Bearer %@", self.secondUserJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.group.addMembers"
                                                      body:@{
                                                          @"groupUri": self.testGroupUri,
                                                          @"members": @[self.thirdUserDid]
                                                      }
                                                   headers:@{@"authorization": secondUserAuthHeader}];
    XCTAssertEqual(response.statusCode, 401);
}

#pragma mark - removeMembers Tests

- (void)testRemoveMembersRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.group.removeMembers"
                                                      body:@{
                                                          @"groupUri": self.testGroupUri,
                                                          @"members": @[self.secondUserDid]
                                                      }
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testRemoveMembersSuccessfully {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];

    // First add a member
    [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.group.addMembers"
                             body:@{
                                 @"groupUri": self.testGroupUri,
                                 @"members": @[self.secondUserDid]
                             }
                          headers:@{@"authorization": authHeader}];

    // Now remove them
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.group.removeMembers"
                                                      body:@{
                                                          @"groupUri": self.testGroupUri,
                                                          @"members": @[self.secondUserDid]
                                                      }
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertTrue([response.jsonBody[@"success"] boolValue]);
}

#pragma mark - listMembers Tests

- (void)testListMembersNoAuthRequired {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/chat.bsky.group.listMembers"
                                             queryString:[NSString stringWithFormat:@"groupUri=%@", self.testGroupUri]
                                             queryParams:@{@"groupUri": self.testGroupUri}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"members"]);
    XCTAssertIsInstance(response.jsonBody[@"members"], [NSArray class]);
}

- (void)testListMembersIncludesCreator {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/chat.bsky.group.listMembers"
                                             queryString:[NSString stringWithFormat:@"groupUri=%@", self.testGroupUri]
                                             queryParams:@{@"groupUri": self.testGroupUri}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    NSArray *members = response.jsonBody[@"members"];
    XCTAssertGreaterThanOrEqual(members.count, 1);
    // Check that creator is in the list
    BOOL creatorFound = NO;
    for (NSDictionary *member in members) {
        if ([member[@"did"] isEqualToString:self.userDid]) {
            creatorFound = YES;
            XCTAssertEqualObjects(member[@"role"], @"admin");
            break;
        }
    }
    XCTAssertTrue(creatorFound);
}

- (void)testListMembersWithLimit {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];

    // Add some members
    for (int i = 0; i < 3; i++) {
        NSDictionary *testUser = [self createTestUser];
        [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.group.addMembers"
                                 body:@{@"groupUri": self.testGroupUri, @"members": @[testUser[@"did"]]}
                              headers:@{@"authorization": authHeader}];
    }

    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/chat.bsky.group.listMembers"
                                             queryString:[NSString stringWithFormat:@"groupUri=%@&limit=2", self.testGroupUri]
                                             queryParams:@{@"groupUri": self.testGroupUri, @"limit": @"2"}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertLessThanOrEqual([response.jsonBody[@"members"] count], 2);
}

#pragma mark - createJoinLink Tests

- (void)testCreateJoinLinkRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.group.createJoinLink"
                                                      body:@{@"groupUri": self.testGroupUri}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testCreateJoinLinkSuccessfully {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.group.createJoinLink"
                                                      body:@{@"groupUri": self.testGroupUri}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"linkId"]);
}

- (void)testCreateJoinLinkWithExpiry {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    NSNumber *futureTimestamp = @([[NSDate dateWithTimeIntervalSinceNow:3600] timeIntervalSince1970]);
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.group.createJoinLink"
                                                      body:@{
                                                          @"groupUri": self.testGroupUri,
                                                          @"expiresAt": futureTimestamp
                                                      }
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"linkId"]);
}

- (void)testCreateJoinLinkOnlyForAdmin {
    NSString *secondUserAuthHeader = [NSString stringWithFormat:@"Bearer %@", self.secondUserJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.group.createJoinLink"
                                                      body:@{@"groupUri": self.testGroupUri}
                                                   headers:@{@"authorization": secondUserAuthHeader}];
    XCTAssertEqual(response.statusCode, 401);
}

#pragma mark - editJoinLink Tests

- (void)testEditJoinLinkRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.group.editJoinLink"
                                                      body:@{
                                                          @"linkId": @"test-link",
                                                          @"enabled": @YES
                                                      }
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

#pragma mark - requestJoin Tests

- (void)testRequestJoinRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.group.requestJoin"
                                                      body:@{@"groupUri": self.testGroupUri}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testRequestJoinSuccessfully {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.secondUserJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.group.requestJoin"
                                                      body:@{@"groupUri": self.testGroupUri}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"requestId"]);
}

#pragma mark - approveJoinRequest Tests

- (void)testApproveJoinRequestRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.group.approveJoinRequest"
                                                      body:@{@"requestId": @"test-request"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testApproveJoinRequestSuccessfully {
    // Second user requests to join
    NSString *secondUserAuthHeader = [NSString stringWithFormat:@"Bearer %@", self.secondUserJwt];
    HttpResponse *requestResponse = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.group.requestJoin"
                                                              body:@{@"groupUri": self.testGroupUri}
                                                           headers:@{@"authorization": secondUserAuthHeader}];
    NSString *requestId = requestResponse.jsonBody[@"requestId"];

    // Admin approves
    NSString *adminAuthHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *approveResponse = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.group.approveJoinRequest"
                                                              body:@{@"requestId": requestId}
                                                           headers:@{@"authorization": adminAuthHeader}];
    XCTAssertEqual(approveResponse.statusCode, 200);
    XCTAssertTrue([approveResponse.jsonBody[@"success"] boolValue]);
}

@end
