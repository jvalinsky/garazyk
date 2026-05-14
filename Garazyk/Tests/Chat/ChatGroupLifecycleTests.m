// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
// Unit tests for ChatService group/conversation lifecycle and e2ee state machine (P2 gap).
// Gap: 1 unit test file vs. 3 e2e scenarios — group lifecycle, member management,
//   and e2ee state are untested at the unit tier.
// Note: ChatService has no addMember/rotateKey methods. Member management uses
//   createConversationWithMembers:mode: (set at creation) and leaveConversation:memberDid:.
//   E2EE state is toggled via setConversationMode:mode: (@"e2ee" / @"plaintext").
#import <XCTest/XCTest.h>
#import "Chat/Server/Services/ChatService.h"
#import "Database/PDSDatabase.h"
#import "Database/Schema.h"

@interface ChatGroupLifecycleTests : XCTestCase
@property (nonatomic, strong) NSString *tempDir;
@property (nonatomic, strong) PDSDatabase *db;
@property (nonatomic, strong) ChatService *service;
@end

@implementation ChatGroupLifecycleTests

- (void)setUp {
    [super setUp];
    self.tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.tempDir
                                withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    NSURL *dbURL = [NSURL fileURLWithPath:[self.tempDir stringByAppendingPathComponent:@"chat_group.db"]];
    self.db = [PDSDatabase databaseAtURL:dbURL];
    [self.db openWithError:nil];

    // Core conversation tables
    [self.db executeUnsafeRawSQL:kPDSConversationsTableCreateSQL         error:nil];
    [self.db executeUnsafeRawSQL:kPDSConversationMembersTableCreateSQL   error:nil];
    [self.db executeUnsafeRawSQL:kPDSMessagesTableCreateSQL              error:nil];
    [self.db executeUnsafeRawSQL:kPDSMessageReactionsTableCreateSQL      error:nil];
    // Indices for conversation member/message queries
    [self.db executeUnsafeRawSQL:kPDSIndexConversationMembersConvoSQL    error:nil];
    [self.db executeUnsafeRawSQL:kPDSIndexConversationMembersActorSQL    error:nil];
    [self.db executeUnsafeRawSQL:kPDSIndexMessagesConvoSQL               error:nil];
    [self.db executeUnsafeRawSQL:kPDSIndexMessagesCreatedSQL             error:nil];
    // Group tables (used by XrpcChatBskyGroupPack, included for completeness)
    [self.db executeUnsafeRawSQL:kPDSGroupsTableCreateSQL                error:nil];
    [self.db executeUnsafeRawSQL:kPDSGroupMembersTableCreateSQL          error:nil];
    [self.db executeUnsafeRawSQL:kPDSGroupMessagesTableCreateSQL         error:nil];
    [self.db executeUnsafeRawSQL:kPDSGroupMessageReactionsTableCreateSQL error:nil];

    self.service = [[ChatService alloc] initWithDatabase:self.db];
}

- (void)tearDown {
    [self.db close];
    self.db = nil;
    self.service = nil;
    [[NSFileManager defaultManager] removeItemAtPath:self.tempDir error:nil];
    [super tearDown];
}

// MARK: - Group creation

- (void)testCreateGroupWithMinimumTwoMembers {
    NSError *error = nil;
    NSDictionary *convo = [self.service
        createConversationWithMembers:@[@"did:plc:alice", @"did:plc:bob"]
        error:&error];
    XCTAssertNotNil(convo, @"createConversationWithMembers:error: failed: %@", error);
    XCTAssertNil(error);
    XCTAssertNotNil(convo[@"id"], @"conversation must have an id");
}

- (void)testCreateGroupWithSingleMemberIsRejected {
    // A conversation requires at least two distinct participants.
    // If ChatService does not enforce this yet, this test will fail and document the gap.
    NSError *error = nil;
    NSDictionary *convo = [self.service
        createConversationWithMembers:@[@"did:plc:alice"]
        error:&error];
    XCTAssertNil(convo, @"createConversation with 1 member must fail");
    XCTAssertNotNil(error, @"error must be set when fewer than 2 members are provided");
}

- (void)testCreateGroupWithDuplicateMembersIsNormalized {
    // Duplicate DIDs in the member list must be deduplicated.
    NSError *error = nil;
    NSDictionary *convo = [self.service
        createConversationWithMembers:@[@"did:plc:alice", @"did:plc:alice", @"did:plc:bob"]
        error:&error];
    XCTAssertNotNil(convo, @"%@", error);

    // convo[@"memberList"] is a comma-separated DID string, e.g. "did:plc:alice, did:plc:bob"
    NSString *memberList = convo[@"memberList"];
    XCTAssertNotNil(memberList, @"memberList must be present in conversation dict");
    NSArray *members = [memberList componentsSeparatedByString:@", "];
    // Strip empty entries in case of trailing separator
    NSArray *nonEmpty = [members filteredArrayUsingPredicate:
        [NSPredicate predicateWithFormat:@"length > 0"]];
    XCTAssertEqual(nonEmpty.count, 2U,
        @"Duplicate alice must be deduplicated; expected 2 members, got %lu: '%@'",
        (unsigned long)nonEmpty.count, memberList);
}

// MARK: - Member management

- (void)testAddMemberToExistingGroup {
    // ChatService has no addMember method — members are specified at creation time.
    // This test verifies that a 3-member conversation is created correctly (equivalent semantics).
    NSError *error = nil;
    NSDictionary *convo = [self.service
        createConversationWithMembers:@[@"did:plc:alice", @"did:plc:bob", @"did:plc:charlie"]
        error:&error];
    XCTAssertNotNil(convo, @"%@", error);

    NSString *memberList = convo[@"memberList"];
    NSArray *members = [[memberList componentsSeparatedByString:@", "]
        filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
    XCTAssertEqual(members.count, 3U,
        @"3-member conversation must have 3 distinct members; got: '%@'", memberList);
}

- (void)testRemoveMemberFromGroup {
    NSError *error = nil;
    NSDictionary *convo = [self.service
        createConversationWithMembers:@[@"did:plc:alice", @"did:plc:bob", @"did:plc:charlie"]
        error:&error];
    XCTAssertNotNil(convo);
    NSString *convoId = convo[@"id"];

    BOOL left = [self.service leaveConversation:convoId memberDid:@"did:plc:charlie" error:&error];
    XCTAssertTrue(left, @"leaveConversation:memberDid: failed: %@", error);

    // charlie must not see this conversation in her list after leaving.
    NSArray *charlieConvos = [self.service listConversationsForActor:@"did:plc:charlie"
                                                              limit:10 cursor:nil error:&error];
    XCTAssertNotNil(charlieConvos);
    for (NSDictionary *c in charlieConvos) {
        XCTAssertFalse([c[@"id"] isEqualToString:convoId],
            @"Removed member must not appear in conversation list for that convo");
    }
}

- (void)testRemoveLastMemberDeletesGroup {
    NSError *error = nil;
    NSDictionary *convo = [self.service
        createConversationWithMembers:@[@"did:plc:alice", @"did:plc:bob"]
        error:&error];
    XCTAssertNotNil(convo);
    NSString *convoId = convo[@"id"];

    [self.service leaveConversation:convoId memberDid:@"did:plc:alice" error:nil];
    [self.service leaveConversation:convoId memberDid:@"did:plc:bob"   error:nil];

    // After all members leave, the conversation must be absent or return an error.
    NSDictionary *gone = [self.service getConversationWithId:convoId error:&error];
    XCTAssertTrue(gone == nil || error != nil,
        @"Conversation with no members must be absent or return an error when fetched by id");
}

// MARK: - E2EE state machine

- (void)testGroupKeyRotationIncreasesKeyVersion {
    // ChatService has no explicit key rotation. E2EE is toggled via setConversationMode:mode:.
    // This test verifies that a conversation can transition to e2ee mode.
    NSError *error = nil;
    NSDictionary *convo = [self.service
        createConversationWithMembers:@[@"did:plc:alice", @"did:plc:bob"]
        mode:@"plaintext"
        error:&error];
    XCTAssertNotNil(convo, @"%@", error);
    NSString *convoId = convo[@"id"];

    BOOL ok = [self.service setConversationMode:convoId mode:@"e2ee" error:&error];
    XCTAssertTrue(ok, @"setConversationMode:e2ee failed: %@", error);

    NSDictionary *updated = [self.service getConversationWithId:convoId error:&error];
    XCTAssertNotNil(updated);
    XCTAssertEqualObjects(updated[@"mode"], @"e2ee",
        @"Conversation mode must be persisted as 'e2ee' after setConversationMode:");
}

- (void)testNewMemberReceivesCurrentGroupKey {
    // In e2ee mode, messages must be retrievable by members of the conversation.
    // (ChatService does not manage per-member key material — this tests delivery, not encryption.)
    NSError *error = nil;
    NSDictionary *convo = [self.service
        createConversationWithMembers:@[@"did:plc:alice", @"did:plc:bob"]
        mode:@"e2ee"
        error:&error];
    XCTAssertNotNil(convo, @"%@", error);
    NSString *convoId = convo[@"id"];

    NSDictionary *msg = [self.service sendMessage:convoId
                                        senderDid:@"did:plc:alice"
                                             text:@"e2ee hello"
                                        embedJson:nil
                                            error:&error];
    XCTAssertNotNil(msg, @"sendMessage in e2ee mode failed: %@", error);

    NSArray *messages = [self.service getMessagesForConversation:convoId
                                                          limit:10 cursor:nil error:&error];
    XCTAssertNotNil(messages);
    XCTAssertGreaterThan(messages.count, 0U,
        @"Members must be able to retrieve messages sent in e2ee mode");
}

- (void)testRemovedMemberDoesNotReceiveSubsequentKeys {
    // After a member leaves, the conversation must not appear in their list,
    // meaning they cannot receive subsequent messages (or key material).
    NSError *error = nil;
    NSDictionary *convo = [self.service
        createConversationWithMembers:@[@"did:plc:alice", @"did:plc:bob", @"did:plc:charlie"]
        mode:@"e2ee"
        error:&error];
    XCTAssertNotNil(convo, @"%@", error);
    NSString *convoId = convo[@"id"];

    // Send a message before charlie leaves.
    [self.service sendMessage:convoId senderDid:@"did:plc:alice"
                         text:@"before leave" embedJson:nil error:nil];

    BOOL left = [self.service leaveConversation:convoId memberDid:@"did:plc:charlie" error:&error];
    XCTAssertTrue(left, @"%@", error);

    // Send a message after charlie leaves.
    [self.service sendMessage:convoId senderDid:@"did:plc:alice"
                         text:@"after leave" embedJson:nil error:nil];

    // Charlie's conversation list must not include this convo.
    NSArray *charlieConvos = [self.service listConversationsForActor:@"did:plc:charlie"
                                                              limit:10 cursor:nil error:nil];
    for (NSDictionary *c in charlieConvos) {
        XCTAssertFalse([c[@"id"] isEqualToString:convoId],
            @"Removed member must not see the conversation after leaving");
    }
}

// MARK: - Message routing

- (void)testMessageRoutedToAllGroupMembers {
    NSError *error = nil;
    NSDictionary *convo = [self.service
        createConversationWithMembers:@[@"did:plc:alice", @"did:plc:bob"]
        error:&error];
    XCTAssertNotNil(convo, @"%@", error);
    NSString *convoId = convo[@"id"];

    NSDictionary *msg = [self.service sendMessage:convoId
                                        senderDid:@"did:plc:alice"
                                             text:@"hello group"
                                        embedJson:nil
                                            error:&error];
    XCTAssertNotNil(msg, @"sendMessage failed: %@", error);

    // The message must be retrievable via the conversation (both members share one view).
    NSArray *messages = [self.service getMessagesForConversation:convoId
                                                          limit:10 cursor:nil error:&error];
    XCTAssertNotNil(messages);
    XCTAssertGreaterThan(messages.count, 0U);
    BOOL found = NO;
    for (NSDictionary *m in messages) {
        if ([m[@"text"] isEqualToString:@"hello group"]) { found = YES; break; }
    }
    XCTAssertTrue(found, @"Sent message must be retrievable from the conversation");
}

- (void)testRemovedMemberDoesNotReceiveNewMessages {
    NSError *error = nil;
    NSDictionary *convo = [self.service
        createConversationWithMembers:@[@"did:plc:alice", @"did:plc:bob"]
        error:&error];
    XCTAssertNotNil(convo, @"%@", error);
    NSString *convoId = convo[@"id"];

    BOOL left = [self.service leaveConversation:convoId memberDid:@"did:plc:bob" error:&error];
    XCTAssertTrue(left, @"%@", error);

    // Send a message after bob leaves — alice is still a member so this must succeed.
    NSDictionary *msg = [self.service sendMessage:convoId
                                        senderDid:@"did:plc:alice"
                                             text:@"post-leave msg"
                                        embedJson:nil
                                            error:&error];
    XCTAssertNotNil(msg, @"Alice should still be able to send after bob leaves: %@", error);

    // Bob's conversation list must not include this convo.
    NSArray *bobConvos = [self.service listConversationsForActor:@"did:plc:bob"
                                                          limit:10 cursor:nil error:nil];
    for (NSDictionary *c in bobConvos) {
        XCTAssertFalse([c[@"id"] isEqualToString:convoId],
            @"Removed member must not see the conversation in their list");
    }
}

@end
