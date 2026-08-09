// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminAuthXrpcTestBase.h"
#import "Database/Service/ServiceDatabases.h"

@interface XrpcChatBskyConvoTests : AdminAuthXrpcTestBase
@property (nonatomic, copy) NSString *secondUserDid;
@property (nonatomic, copy) NSString *secondUserJwt;
@property (nonatomic, copy) NSString *thirdUserDid;
@property (nonatomic, copy) NSString *thirdUserJwt;
@end

@implementation XrpcChatBskyConvoTests

- (void)setUp {
    [super setUp];

    // Create second user for testing conversations
    NSDictionary *createUserResponse = [self createTestUser];
    self.secondUserDid = createUserResponse[@"did"];
    self.secondUserJwt = createUserResponse[@"accessJwt"];

    // Create third user for non-member gate tests
    NSDictionary *thirdUserResponse = [self createTestUser];
    self.thirdUserDid = thirdUserResponse[@"did"];
    self.thirdUserJwt = thirdUserResponse[@"accessJwt"];
}

// Helper method to create a test user
- (NSDictionary *)createTestUser {
    NSString *uniqueHandle = [NSString stringWithFormat:@"testuser%@.test", [[NSUUID UUID] UUIDString]];

    // Create invite code first
    NSString *inviteCode = @"test-invite-code";
    PDSServiceDatabases *sdb = self.application.serviceDatabases;
    [sdb createInviteCode:inviteCode forAccount:self.userDid maxUses:1 error:nil];

    ATProtoHttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.createAccount"
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
    ATProtoHttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/chat.bsky.convo.getConvoForMembers"
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
    ATProtoHttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/chat.bsky.convo.getConvoForMembers"
                                             queryString:queryString
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"AuthRequired");
}

- (void)testGetConvoForMembersCreatesConversation {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    NSString *queryString = [NSString stringWithFormat:@"members=%@&members=%@", self.userDid, self.secondUserDid];
    ATProtoHttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/chat.bsky.convo.getConvoForMembers"
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
    ATProtoHttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/chat.bsky.convo.getConvoForMembers"
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
    ATProtoHttpResponse *response1 = [self sendGetRequestWithPath:@"/xrpc/chat.bsky.convo.getConvoForMembers"
                                              queryString:queryString
                                              queryParams:@{}
                                                  headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response1.statusCode, 200);
    NSString *convoId1 = response1.jsonBody[@"convo"][@"id"];

    // Second call with same members
    ATProtoHttpResponse *response2 = [self sendGetRequestWithPath:@"/xrpc/chat.bsky.convo.getConvoForMembers"
                                              queryString:queryString
                                              queryParams:@{}
                                                  headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response2.statusCode, 200);
    NSString *convoId2 = response2.jsonBody[@"convo"][@"id"];

    XCTAssertEqualObjects(convoId1, convoId2);
}

#pragma mark - acceptConvo Tests

- (void)testAcceptConvoRequiresAuth {
    ATProtoHttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.convo.acceptConvo"
                                                      body:@{@"convoId": @"convo/test"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

/// Tests that acceptConvo returns 409 Conflict when the actor is already a member
/// (S15 slice 4: handler now rejects duplicate membership instead of succeeding silently).
- (void)testAcceptConvoByExistingMemberReturns409 {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];

    // Create conversation (user1 is automatically a member via getConvoForMembers).
    NSString *convoId = [self createConvoWithAuth:authHeader];
    XCTAssertNotNil(convoId, @"Failed to create conversation");

    // Accept conversation as user1 — already a member so should be 409 Conflict.
    ATProtoHttpResponse *acceptResponse = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.convo.acceptConvo"
                                                             body:@{@"convoId": convoId}
                                                          headers:@{@"authorization": authHeader}];
    XCTAssertEqual(acceptResponse.statusCode, 409);
    XCTAssertEqualObjects(acceptResponse.jsonBody[@"error"], @"Conflict");
}

/// Tests that acceptConvo adds a non-member to the conversation (200).
- (void)testAcceptConvoAddsNonMember {
    // Create a conversation between user1 and user3 (user2 is excluded).
    NSString *convoId = [self createConvoBetween:self.userDid and:self.thirdUserDid];
    XCTAssertNotNil(convoId, @"Failed to create user1+user3 conversation");

    // user2 accepts the conversation (user2 is NOT a member — should get 200).
    NSString *user2Auth = [NSString stringWithFormat:@"Bearer %@", self.secondUserJwt];
    ATProtoHttpResponse *acceptResponse = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.convo.acceptConvo"
                                                             body:@{@"convoId": convoId}
                                                          headers:@{@"authorization": user2Auth}];
    XCTAssertEqual(acceptResponse.statusCode, 200, @"Non-member should be able to accept: %@", acceptResponse.jsonBody[@"error"]);
    XCTAssertNotNil(acceptResponse.jsonBody[@"convo"]);
}

#pragma mark - leaveConvo Tests

- (void)testLeaveConvoRequiresAuth {
    ATProtoHttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.convo.leaveConvo"
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
    ATProtoHttpResponse *leaveResponse = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.convo.leaveConvo"
                                                           body:@{@"convoId": convoId}
                                                        headers:@{@"authorization": authHeader}];
    XCTAssertEqual(leaveResponse.statusCode, 200);
}

#pragma mark - listConvoRequests Tests

- (void)testListConvoRequestsRequiresAuth {
    ATProtoHttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/chat.bsky.convo.listConvoRequests"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testListConvoRequestsReturnsEmpty {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    ATProtoHttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/chat.bsky.convo.listConvoRequests"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"requests"]);
    XCTAssertEqual([response.jsonBody[@"requests"] count], 0);
}

#pragma mark - getConvoAvailability Tests

- (void)testGetConvoAvailabilityRequiresDid {
    ATProtoHttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/chat.bsky.convo.getConvoAvailability"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testGetConvoAvailabilityForValidActor {
    ATProtoHttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/chat.bsky.convo.getConvoAvailability"
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
    ATProtoHttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/chat.bsky.convo.getConvoAvailability"
                                             queryString:@"did=did:plc:invalid"
                                             queryParams:@{@"did": @"did:plc:invalid"}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertTrue([response.jsonBody[@"available"] boolValue]);
}

#pragma mark - Reaction Tests

- (void)testAddReactionRequiresAuth {
    ATProtoHttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.convo.addReaction"
                                                      body:@{@"messageId": @"msg/test", @"emoji": @"❤️"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testAddReactionToMessage {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];

    // Create conversation and send a real message (S15 slice 5 requires message exists).
    NSString *convoId = [self createConvoWithAuth:authHeader];
    XCTAssertNotNil(convoId, @"Failed to create conversation");

    ATProtoHttpResponse *sendResponse = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.convo.sendMessage"
                                                           body:@{
                                                               @"convoId": convoId,
                                                               @"message": @{@"text": @"test message for reaction"}
                                                           }
                                                        headers:@{@"authorization": authHeader}];
    XCTAssertEqual(sendResponse.statusCode, 200);
    NSString *messageId = sendResponse.jsonBody[@"id"];
    XCTAssertNotNil(messageId);

    // Add reaction to the real message.
    ATProtoHttpResponse *reactionResponse = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.convo.addReaction"
                                                               body:@{@"messageId": messageId, @"emoji": @"❤️"}
                                                            headers:@{@"authorization": authHeader}];
    XCTAssertEqual(reactionResponse.statusCode, 200);
    XCTAssertEqualObjects(reactionResponse.jsonBody[@"emoji"], @"❤️");
}

- (void)testRemoveReactionFromMessage {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];

    // Create conversation and send a real message.
    NSString *convoId = [self createConvoWithAuth:authHeader];
    XCTAssertNotNil(convoId, @"Failed to create conversation");

    ATProtoHttpResponse *sendResponse = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.convo.sendMessage"
                                                           body:@{
                                                               @"convoId": convoId,
                                                               @"message": @{@"text": @"test message for un-reaction"}
                                                           }
                                                        headers:@{@"authorization": authHeader}];
    XCTAssertEqual(sendResponse.statusCode, 200);
    NSString *messageId = sendResponse.jsonBody[@"id"];
    XCTAssertNotNil(messageId);

    // Remove reaction from the real message.
    ATProtoHttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.convo.removeReaction"
                                                      body:@{@"messageId": messageId, @"emoji": @"❤️"}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
}

#pragma mark - Read Status Tests

- (void)testUpdateReadRequiresAuth {
    ATProtoHttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.convo.updateRead"
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
    ATProtoHttpResponse *readResponse = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.convo.updateRead"
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
    ATProtoHttpResponse *allReadResponse = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.convo.updateAllRead"
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
    ATProtoHttpResponse *muteResponse = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.convo.muteConvo"
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
    ATProtoHttpResponse *unmuteResponse = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.convo.unmuteConvo"
                                                             body:@{@"convoId": convoId}
                                                          headers:@{@"authorization": authHeader}];
    XCTAssertEqual(unmuteResponse.statusCode, 200);
}

#pragma mark - Batch Operations Tests

- (void)testSendMessage {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];

    NSString *convoId = [self createConvoWithAuth:authHeader];
    XCTAssertNotNil(convoId, @"Failed to create conversation");

    ATProtoHttpResponse *sendResponse = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.convo.sendMessage"
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
    ATProtoHttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.convo.sendMessageBatch"
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
    ATProtoHttpResponse *batchResponse = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.convo.sendMessageBatch"
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
    ATProtoHttpResponse *lockResponse = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.convo.lockConvo"
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
    ATProtoHttpResponse *unlockResponse = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.convo.unlockConvo"
                                                             body:@{@"convoId": convoId}
                                                          headers:@{@"authorization": authHeader}];
    XCTAssertEqual(unlockResponse.statusCode, 200);
}

- (void)testDeleteMessageForSelfRequiresAuth {
    ATProtoHttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.convo.deleteMessageForSelf"
                                                      body:@{@"messageId": @"msg/test"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testGetLogSuccess {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];

    // Create some activity
    [self createConvoWithAuth:authHeader];

    ATProtoHttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/chat.bsky.convo.getLog"
                                              queryString:@""
                                              queryParams:@{}
                                                  headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"logs"]);
}

#pragma mark - S15 Gate Tests: Non-string input returns 400

- (void)testNonStringConvoIdReturns400 {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];

    // Send muteConvo with a numeric convoId (not a string).
    ATProtoHttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.convo.muteConvo"
                                                      body:@{@"convoId": @12345}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testNonStringMessageIdReturns400 {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];

    // Send addReaction with an array messageId (not a string).
    ATProtoHttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.convo.addReaction"
                                                      body:@{@"messageId": @[@"not-a-string"], @"emoji": @"❤️"}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testNonStringEmojiReturns400 {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];

    // Send addReaction with a dict emoji (not a string).
    ATProtoHttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.convo.addReaction"
                                                      body:@{@"messageId": @"msg/test", @"emoji": @{@":)": @"smile"}}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 400);
}

#pragma mark - S15 Gate Tests: Non-member cannot operate on conversation (403)

// Helper: create a conversation between two specific DIDs using user1's auth.
- (NSString *)createConvoBetween:(NSString *)didA and:(NSString *)didB {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    NSString *queryString = [NSString stringWithFormat:@"members=%@&members=%@", didA, didB];
    ATProtoHttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/chat.bsky.convo.getConvoForMembers"
                                             queryString:queryString
                                             queryParams:@{}
                                                 headers:@{@"authorization": authHeader}];
    if (response.statusCode == 200 && response.jsonBody[@"convo"]) {
        return response.jsonBody[@"convo"][@"id"];
    }
    return nil;
}

- (void)testNonMemberMuteConvoReturns403 {
    // Create a conversation between user1 and user3 (user2 is excluded).
    NSString *convoId = [self createConvoBetween:self.userDid and:self.thirdUserDid];
    XCTAssertNotNil(convoId, @"Failed to create user1+user3 conversation");

    // user2 (not a member) tries to mute the conversation.
    NSString *user2Auth = [NSString stringWithFormat:@"Bearer %@", self.secondUserJwt];
    ATProtoHttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.convo.muteConvo"
                                                      body:@{@"convoId": convoId}
                                                   headers:@{@"authorization": user2Auth}];
    XCTAssertEqual(response.statusCode, 403);
}

- (void)testNonMemberLeaveConvoReturns403 {
    // Create a conversation between user1 and user3 (user2 is excluded).
    NSString *convoId = [self createConvoBetween:self.userDid and:self.thirdUserDid];
    XCTAssertNotNil(convoId, @"Failed to create user1+user3 conversation");

    // user2 (not a member) tries to leave the conversation.
    NSString *user2Auth = [NSString stringWithFormat:@"Bearer %@", self.secondUserJwt];
    ATProtoHttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.convo.leaveConvo"
                                                      body:@{@"convoId": convoId}
                                                   headers:@{@"authorization": user2Auth}];
    XCTAssertEqual(response.statusCode, 403);
}

- (void)testNonMemberLockConvoReturns403 {
    // Create a conversation between user1 and user3 (user2 is excluded).
    NSString *convoId = [self createConvoBetween:self.userDid and:self.thirdUserDid];
    XCTAssertNotNil(convoId, @"Failed to create user1+user3 conversation");

    // user2 (not a member) tries to lock the conversation.
    NSString *user2Auth = [NSString stringWithFormat:@"Bearer %@", self.secondUserJwt];
    ATProtoHttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.convo.lockConvo"
                                                      body:@{@"convoId": convoId}
                                                   headers:@{@"authorization": user2Auth}];
    XCTAssertEqual(response.statusCode, 403);
}

- (void)testNonMemberUnlockConvoReturns403 {
    // Create a conversation between user1 and user3 (user2 is excluded).
    NSString *convoId = [self createConvoBetween:self.userDid and:self.thirdUserDid];
    XCTAssertNotNil(convoId, @"Failed to create user1+user3 conversation");

    // user2 (not a member) tries to unlock the conversation.
    NSString *user2Auth = [NSString stringWithFormat:@"Bearer %@", self.secondUserJwt];
    ATProtoHttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.convo.unlockConvo"
                                                      body:@{@"convoId": convoId}
                                                   headers:@{@"authorization": user2Auth}];
    XCTAssertEqual(response.statusCode, 403);
}

- (void)testNonMemberUnmuteConvoReturns403 {
    // Create a conversation between user1 and user3 (user2 is excluded).
    NSString *convoId = [self createConvoBetween:self.userDid and:self.thirdUserDid];
    XCTAssertNotNil(convoId, @"Failed to create user1+user3 conversation");

    // user2 (not a member) tries to unmute the conversation.
    NSString *user2Auth = [NSString stringWithFormat:@"Bearer %@", self.secondUserJwt];
    ATProtoHttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/chat.bsky.convo.unmuteConvo"
                                                      body:@{@"convoId": convoId}
                                                   headers:@{@"authorization": user2Auth}];
    XCTAssertEqual(response.statusCode, 403);
}

#pragma mark - S15 Gate Tests: getConvoAvailability respects allowIncoming

- (void)testGetConvoAvailabilityRespectsAllowIncomingNone {
    NSString *user3Auth = [NSString stringWithFormat:@"Bearer %@", self.thirdUserJwt];

    // Put chat.bsky.actor.declaration with allowIncoming: "none" for user3
    // (uses user3 to avoid test isolation conflict with testGetConvoAvailabilityForValidActor
    //  which queries user1).
    NSString *collection = @"chat.bsky.actor.declaration";
    NSString *rkey = @"self";
    NSDictionary *declaration = @{
        @"$type": @"chat.bsky.actor.declaration",
        @"allowIncoming": @"none"
    };
    ATProtoHttpResponse *putResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.repo.putRecord"
                                                          body:@{
                                                              @"repo": self.thirdUserDid,
                                                              @"collection": collection,
                                                              @"rkey": rkey,
                                                              @"record": declaration
                                                          }
                                                       headers:@{@"authorization": user3Auth}];
    XCTAssertEqual(putResponse.statusCode, 200, @"putRecord should succeed: %@", putResponse.jsonBody[@"error"]);

    // Now query getConvoAvailability for user3 — should return available: NO.
    ATProtoHttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/chat.bsky.convo.getConvoAvailability"
                                             queryString:[NSString stringWithFormat:@"did=%@", self.thirdUserDid]
                                             queryParams:@{@"did": self.thirdUserDid}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertFalse([response.jsonBody[@"available"] boolValue],
                   @"getConvoAvailability should return available:NO when allowIncoming is 'none'");
}

@end
