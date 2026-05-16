// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminAuthXrpcTestBase.h"
#import "Database/Service/ServiceDatabases.h"

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
    NSString *uniqueHandle = [NSString stringWithFormat:@"testuser%@.test", [[NSUUID UUID] UUIDString]];

    // Create invite code first
    NSString *inviteCode = @"test-invite-code";
    PDSServiceDatabases *sdb = self.application.serviceDatabases;
    [sdb createInviteCode:inviteCode forAccount:self.userDid maxUses:1 error:nil];

    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.createAccount"
                                                      body:@{
                                                          @"handle": uniqueHandle,
                                                          @"password": @"password123",
                                                          @"email": [NSString stringWithFormat:@"%@@example.com", uniqueHandle],
                                                          @"inviteCode": inviteCode
                                                      }
                                                   headers:@{}];

    if (response.statusCode == 200 && response.jsonBody[@"did"]) {
        return @{
            @"did": response.jsonBody[@"did"],
            @"accessJwt": response.jsonBody[@"accessJwt"] ?: @""
        };
    }
    NSLog(@"createTestUser failed: status=%ld, error=%@, message=%@", response.statusCode, response.jsonBody[@"error"], response.jsonBody[@"message"]);
    return nil;
}

// Helper: create a conversation via GET query (getConvoForMembers is a query endpoint)
- (NSString *)createConvoWithAuth:(NSString *)authHeader {
    NSString *queryString = [NSString stringWithFormat:@"members=%@&members=%@", self.userDid, self.secondUserDid];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/chat.bsky.convo.getConvoForMembers"
                                             queryString:queryString
                                             queryParams:@{}
                                                 headers:@{@"authorization": authHeader}];
    if (response.statusCode == 200 && response.jsonBody[@"convo"]) {
        return response.jsonBody[@"convo"][@"id"];
    }
    return nil;
}

#pragma mark - getConvoForMembers Tests

- (void)testGetConvoForMembersRequiresAuth {
    NSString *queryString = [NSString stringWithFormat:@"members=%@&members=%@", self.userDid, self.secondUserDid];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/chat.bsky.convo.getConvoForMembers"
                                             queryString:queryString
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"AuthRequired");
}

- (void)testGetConvoForMembersCreatesConversation {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    NSString *queryString = [NSString stringWithFormat:@"members=%@&members=%@", self.userDid, self.secondUserDid];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/chat.bsky.convo.getConvoForMembers"
                                             queryString:queryString
                                             queryParams:@{}
                                                 headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"convo"]);
    XCTAssertNotNil(response.jsonBody[@"convo"][@"id"]);
}

- (void)testGetConvoForMembersRequiresTwoMembers {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    NSString *queryString = [NSString stringWithFormat:@"members=%@", self.userDid];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/chat.bsky.convo.getConvoForMembers"
                                             queryString:queryString
                                             queryParams:@{}
                                                 headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 400);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"InvalidRequest");
}

- (void)testGetConvoForMembersReturnsSamConversationOnSecondCall {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    NSString *queryString = [NSString stringWithFormat:@"members=%@&members=%@", self.userDid, self.secondUserDid];

    // First call
    HttpResponse *response1 = [self sendGetRequestWithPath:@"/xrpc/chat.bsky.convo.getConvoForMembers"
                                              queryString:queryString
                                              queryParams:@{}
                                                  headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response1.statusCode, 200);
    NSString *convoId1 = response1.jsonBody[@"convo"][@"id"];

    // Second call with same members
    HttpResponse *response2 = [self sendGetRequestWithPath:@"/xrpc/chat.bsky.convo.getConvoForMembers"
                                              queryString:queryString
                                              queryParams:@{}
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
    NSString *convoId = [self createConvoWithAuth:authHeader];
    XCTAssertNotNil(convoId, @"Failed to create conversation");

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
    NSString *convoId = [self createConvoWithAuth:authHeader];
    XCTAssertNotNil(convoId, @"Failed to create conversation");

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
    // Current handler returns available=YES for any DID string
    // (does not validate DID existence). TODO: align with lexicon
    // which uses 'members' array, not 'did' param.
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/chat.bsky.convo.getConvoAvailability"
                                             queryString:@"did=did:plc:invalid"
                                             queryParams:@{@"did": @"did:plc:invalid"}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertTrue([response.jsonBody[@"available"] boolValue]);
}

#pragma mark - Reaction Tests

- (void)testAddReactionRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.convo.addReaction"
                                                      body:@{@"messageId": @"msg/test", @"emoji": @"❤️"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testAddReactionToMessage {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];

    // Create conversation
    NSString *convoId = [self createConvoWithAuth:authHeader];
    XCTAssertNotNil(convoId, @"Failed to create conversation");

    // Add reaction
    HttpResponse *reactionResponse = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.convo.addReaction"
                                                               body:@{@"messageId": @"msg/test123", @"emoji": @"❤️"}
                                                            headers:@{@"authorization": authHeader}];
    XCTAssertEqual(reactionResponse.statusCode, 200);
    XCTAssertEqualObjects(reactionResponse.jsonBody[@"emoji"], @"❤️");
}

- (void)testRemoveReactionFromMessage {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];

    // Remove reaction
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.convo.removeReaction"
                                                      body:@{@"messageId": @"msg/test123", @"emoji": @"❤️"}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
}

#pragma mark - Read Status Tests

- (void)testUpdateReadRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.convo.updateRead"
                                                      body:@{@"convoId": @"convo/test", @"messageId": @"msg/test"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testUpdateReadState {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];

    // Create conversation
    NSString *convoId = [self createConvoWithAuth:authHeader];
    XCTAssertNotNil(convoId, @"Failed to create conversation");

    // Update read
    HttpResponse *readResponse = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.convo.updateRead"
                                                          body:@{@"convoId": convoId, @"messageId": @"msg/test123"}
                                                       headers:@{@"authorization": authHeader}];
    XCTAssertEqual(readResponse.statusCode, 200);
}

- (void)testUpdateAllRead {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];

    // Create conversation
    NSString *convoId = [self createConvoWithAuth:authHeader];
    XCTAssertNotNil(convoId, @"Failed to create conversation");

    // Mark all as read
    HttpResponse *allReadResponse = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.convo.updateAllRead"
                                                              body:@{@"convoId": convoId}
                                                           headers:@{@"authorization": authHeader}];
    XCTAssertEqual(allReadResponse.statusCode, 200);
}

#pragma mark - Muting Tests

- (void)testMuteConvo {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];

    // Create conversation
    NSString *convoId = [self createConvoWithAuth:authHeader];
    XCTAssertNotNil(convoId, @"Failed to create conversation");

    // Mute conversation
    HttpResponse *muteResponse = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.convo.muteConvo"
                                                          body:@{@"convoId": convoId}
                                                       headers:@{@"authorization": authHeader}];
    XCTAssertEqual(muteResponse.statusCode, 200);
}

- (void)testUnmuteConvo {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];

    // Create conversation
    NSString *convoId = [self createConvoWithAuth:authHeader];
    XCTAssertNotNil(convoId, @"Failed to create conversation");

    // Unmute conversation
    HttpResponse *unmuteResponse = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.convo.unmuteConvo"
                                                             body:@{@"convoId": convoId}
                                                          headers:@{@"authorization": authHeader}];
    XCTAssertEqual(unmuteResponse.statusCode, 200);
}

#pragma mark - Batch Operations Tests

- (void)testSendMessage {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];

    NSString *convoId = [self createConvoWithAuth:authHeader];
    XCTAssertNotNil(convoId, @"Failed to create conversation");

    HttpResponse *sendResponse = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.convo.sendMessage"
                                                           body:@{
                                                               @"convoId": convoId,
                                                               @"message": @{@"text": @"hello"}
                                                           }
                                                        headers:@{@"authorization": authHeader}];
    XCTAssertEqual(sendResponse.statusCode, 200);
    XCTAssertNotNil(sendResponse.jsonBody[@"id"]);
    XCTAssertEqualObjects(sendResponse.jsonBody[@"text"], @"hello");
}

- (void)testSendMessageBatchRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.convo.sendMessageBatch"
                                                      body:@{@"convoId": @"convo/test", @"messages": @[@{@"text": @"hello"}]}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testSendMessageBatch {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];

    // Create conversation
    NSString *convoId = [self createConvoWithAuth:authHeader];
    XCTAssertNotNil(convoId, @"Failed to create conversation");

    // Send batch
    HttpResponse *batchResponse = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.convo.sendMessageBatch"
                                                           body:@{
                                                               @"convoId": convoId,
                                                               @"messages": @[
                                                                   @{@"text": @"hello"},
                                                                   @{@"text": @"world"}
                                                               ]
                                                           }
                                                        headers:@{@"authorization": authHeader}];
    XCTAssertEqual(batchResponse.statusCode, 200);
    XCTAssertNotNil(batchResponse.jsonBody[@"messages"]);
    XCTAssertEqual([batchResponse.jsonBody[@"messages"] count], 2);
}

#pragma mark - Locking Tests

- (void)testLockConvo {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];

    // Create conversation
    NSString *convoId = [self createConvoWithAuth:authHeader];
    XCTAssertNotNil(convoId, @"Failed to create conversation");

    // Lock conversation
    HttpResponse *lockResponse = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.convo.lockConvo"
                                                          body:@{@"convoId": convoId}
                                                       headers:@{@"authorization": authHeader}];
    XCTAssertEqual(lockResponse.statusCode, 200);
}

- (void)testUnlockConvo {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];

    // Create conversation
    NSString *convoId = [self createConvoWithAuth:authHeader];
    XCTAssertNotNil(convoId, @"Failed to create conversation");

    // Unlock conversation
    HttpResponse *unlockResponse = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.convo.unlockConvo"
                                                             body:@{@"convoId": convoId}
                                                          headers:@{@"authorization": authHeader}];
    XCTAssertEqual(unlockResponse.statusCode, 200);
}

- (void)testDeleteMessageForSelfRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.convo.deleteMessageForSelf"
                                                      body:@{@"messageId": @"msg/test"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testGetLogSuccess {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];

    // Create some activity
    [self createConvoWithAuth:authHeader];

    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/chat.bsky.convo.getLog"
                                              queryString:@""
                                              queryParams:@{}
                                                  headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"logs"]);
}

@end
