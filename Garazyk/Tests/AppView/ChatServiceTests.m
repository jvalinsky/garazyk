#import <XCTest/XCTest.h>
#import "AppView/Services/ChatService.h"
#import "Database/PDSDatabase.h"

@interface ChatServiceTests : XCTestCase
@property (nonatomic, strong) NSString *testDirectory;
@property (nonatomic, strong) PDSDatabase *database;
@property (nonatomic, strong) ChatService *service;
@end

@implementation ChatServiceTests

- (void)setUp {
    [super setUp];

    self.testDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.testDirectory withIntermediateDirectories:YES attributes:nil error:nil];

    NSString *dbPath = [self.testDirectory stringByAppendingPathComponent:@"chat_service_test.db"];

    [[NSFileManager defaultManager] removeItemAtPath:dbPath error:nil];

    self.database = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:dbPath]];

    NSError *error = nil;
    XCTAssertTrue([self.database openWithError:&error], @"Database setup failed: %@", error);

    [self setupSchema];
    self.service = [[ChatService alloc] initWithDatabase:self.database];
}

- (void)setupSchema {
    NSError *error = nil;

    NSString *createConversations = @"CREATE TABLE IF NOT EXISTS conversations ("
        @"id TEXT PRIMARY KEY, created_at REAL, updated_at REAL, locked INTEGER DEFAULT 0)";
    XCTAssertTrue([self.database executeParameterizedUpdate:createConversations params:@[] error:&error], @"Conversations table: %@", error);

    NSString *createMembers = @"CREATE TABLE IF NOT EXISTS conversation_members ("
        @"convo_id TEXT, member_did TEXT, status TEXT, muted INTEGER DEFAULT 0, last_read_id TEXT, joined_at REAL, "
        @"PRIMARY KEY(convo_id, member_did))";
    XCTAssertTrue([self.database executeParameterizedUpdate:createMembers params:@[] error:&error], @"Members table: %@", error);

    NSString *createMessages = @"CREATE TABLE IF NOT EXISTS messages ("
        @"id TEXT PRIMARY KEY, convo_id TEXT, sender_did TEXT, text TEXT, embed_json TEXT, "
        @"deleted_for_json TEXT, created_at REAL)";
    XCTAssertTrue([self.database executeParameterizedUpdate:createMessages params:@[] error:&error], @"Messages table: %@", error);

    NSString *createReactions = @"CREATE TABLE IF NOT EXISTS message_reactions ("
        @"message_id TEXT, actor_did TEXT, emoji TEXT, created_at REAL, "
        @"PRIMARY KEY(message_id, actor_did, emoji))";
    XCTAssertTrue([self.database executeParameterizedUpdate:createReactions params:@[] error:&error], @"Reactions table: %@", error);

    NSString *createEventLog = @"CREATE TABLE IF NOT EXISTS chat_event_log ("
        @"id TEXT PRIMARY KEY, convo_id TEXT, actor_did TEXT, event_type TEXT, event_data TEXT, created_at REAL)";
    XCTAssertTrue([self.database executeParameterizedUpdate:createEventLog params:@[] error:&error], @"Event log table: %@", error);
}

- (void)tearDown {
    [self.database close];
    self.database = nil;
    self.service = nil;
    [[NSFileManager defaultManager] removeItemAtPath:self.testDirectory error:nil];
    [super tearDown];
}

#pragma mark - Conversation CRUD Tests

- (void)testCreateConversationWithMembers_ValidMembers_Succeeds {
    NSError *error = nil;
    NSArray *members = @[@"did:plc:alice", @"did:plc:bob"];

    NSDictionary *convo = [self.service createConversationWithMembers:members error:&error];

    XCTAssertNotNil(convo, @"Conversation should be created");
    XCTAssertNil(error, @"No error should occur: %@", error);
    XCTAssertTrue([convo[@"id"] hasPrefix:@"convo/"], @"Convo ID should have convo/ prefix");
    XCTAssertNotNil(convo[@"createdAt"], @"Should have createdAt");
    XCTAssertNotNil(convo[@"members"], @"Should have members");
}

- (void)testCreateConversationWithMembers_LessThan2_Fails {
    NSError *error = nil;
    NSArray *members = @[@"did:plc:alice"];

    NSDictionary *convo = [self.service createConversationWithMembers:members error:&error];

    XCTAssertNil(convo, @"Should not create with less than 2 members");
    XCTAssertNotNil(error, @"Should return error");
    XCTAssertEqual(error.code, 400, @"Should be 400 error");
}

- (void)testGetConversationForMembers_ExistingConvo_ReturnsExisting {
    NSError *error = nil;
    NSArray *members = @[@"did:plc:alice", @"did:plc:bob"];

    NSDictionary *created = [self.service createConversationWithMembers:members error:&error];
    XCTAssertNotNil(created);

    NSArray *sameMembers = @[@"did:plc:bob", @"did:plc:alice"];
    NSDictionary *found = [self.service getConversationForMembers:sameMembers error:&error];

    XCTAssertNotNil(found, @"Should find existing conversation");
    XCTAssertEqualObjects(found[@"id"], created[@"id"], @"Should return same conversation");
}

- (void)testGetConversationForMembers_NewMembers_CreatesNew {
    NSError *error = nil;

    NSArray *members = @[@"did:plc:charlie", @"did:plc:diana"];
    NSDictionary *convo = [self.service getConversationForMembers:members error:&error];

    XCTAssertNotNil(convo, @"Should create new conversation");
    XCTAssertNil(error, @"No error: %@", error);
    XCTAssertTrue([convo[@"id"] hasPrefix:@"convo/"]);
}

- (void)testGetConversationWithId_Valid_ReturnsWithMembers {
    NSError *error = nil;
    NSArray *members = @[@"did:plc:alice", @"did:plc:bob"];

    NSDictionary *created = [self.service createConversationWithMembers:members error:&error];
    NSString *convoId = created[@"id"];

    NSDictionary *fetched = [self.service getConversationWithId:convoId error:&error];

    XCTAssertNotNil(fetched, @"Should fetch conversation");
    XCTAssertEqualObjects(fetched[@"id"], convoId, @"Should match ID");
    XCTAssertNotNil(fetched[@"members"], @"Should include members");
    XCTAssertEqual([fetched[@"members"] count], 2, @"Should have 2 members");
}

- (void)testGetConversationWithId_NotFound_ReturnsNil {
    NSError *error = nil;

    NSDictionary *convo = [self.service getConversationWithId:@"convo/nonexistent" error:&error];

    XCTAssertNil(convo, @"Should return nil for nonexistent");
    XCTAssertNil(error, @"Should not error for not found");
}

- (void)testListConversationsForActor_Pagination_Works {
    NSError *error = nil;

    [self.service createConversationWithMembers:@[@"did:plc:alice", @"did:plc:bob"] error:&error];
    [self.service createConversationWithMembers:@[@"did:plc:alice", @"did:plc:charlie"] error:&error];

    NSArray *convos = [self.service listConversationsForActor:@"did:plc:alice" limit:1 cursor:nil error:&error];

    XCTAssertNotNil(convos);
    XCTAssertEqual((NSInteger)convos.count, 1, @"Should return 1 due to limit");
}

- (void)testListAllConversations_Admin_ReturnsAll {
    NSError *error = nil;

    [self.service createConversationWithMembers:@[@"did:plc:alice", @"did:plc:bob"] error:&error];
    [self.service createConversationWithMembers:@[@"did:plc:charlie", @"did:plc:diana"] error:&error];

    NSArray *convos = [self.service listAllConversationsWithLimit:10 cursor:nil error:&error];

    XCTAssertNotNil(convos);
    XCTAssertGreaterThanOrEqual((NSInteger)convos.count, 2, @"Should list all for admin");
}

#pragma mark - Member Management Tests

- (void)testAcceptConversation_ValidMember_UpdatesStatus {
    NSError *error = nil;

    NSDictionary *convo = [self.service createConversationWithMembers:@[@"did:plc:alice", @"did:plc:bob"] error:&error];
    NSString *convoId = convo[@"id"];

    BOOL success = [self.service acceptConversation:convoId memberDid:@"did:plc:bob" error:&error];

    XCTAssertTrue(success, @"Should accept member");
    XCTAssertNil(error, @"No error: %@", error);
}

- (void)testLeaveConversation_ValidMember_UpdatesStatus {
    NSError *error = nil;

    NSDictionary *convo = [self.service createConversationWithMembers:@[@"did:plc:alice", @"did:plc:bob"] error:&error];
    NSString *convoId = convo[@"id"];

    BOOL success = [self.service leaveConversation:convoId memberDid:@"did:plc:bob" error:&error];

    XCTAssertTrue(success, @"Should allow member to leave");
    XCTAssertNil(error, @"No error: %@", error);
}

- (void)testListConversationRequests_Pending_ReturnsList {
    NSError *error = nil;

    NSDictionary *convo = [self.service createConversationWithMembers:@[@"did:plc:alice", @"did:plc:bob"] error:&error];

    NSArray *requests = [self.service listConversationRequestsForActor:@"did:plc:alice" error:&error];

    XCTAssertNotNil(requests, @"Should return array");
}

#pragma mark - Message Handling Tests

- (void)testSendMessage_Valid_ReturnsMessage {
    NSError *error = nil;

    NSDictionary *convo = [self.service createConversationWithMembers:@[@"did:plc:alice", @"did:plc:bob"] error:&error];
    NSString *convoId = convo[@"id"];

    NSDictionary *message = [self.service sendMessage:convoId senderDid:@"did:plc:alice" text:@"Hello!" embedJson:nil error:&error];

    XCTAssertNotNil(message, @"Message should be sent");
    XCTAssertNil(error, @"No error: %@", error);
    XCTAssertTrue([message[@"id"] hasPrefix:@"msg/"], @"Message ID should have msg/ prefix");
    XCTAssertEqualObjects(message[@"text"], @"Hello!", @"Text should match");
}

- (void)testGetMessagesForConversation_Pagination_Works {
    NSError *error = nil;

    NSDictionary *convo = [self.service createConversationWithMembers:@[@"did:plc:alice", @"did:plc:bob"] error:&error];
    NSString *convoId = convo[@"id"];

    [self.service sendMessage:convoId senderDid:@"did:plc:alice" text:@"Msg1" embedJson:nil error:&error];
    [self.service sendMessage:convoId senderDid:@"did:plc:bob" text:@"Msg2" embedJson:nil error:&error];

    NSArray *messages = [self.service getMessagesForConversation:convoId limit:1 cursor:nil error:&error];

    XCTAssertNotNil(messages);
    XCTAssertEqual((NSInteger)messages.count, 1, @"Should return 1 due to limit");
}

- (void)testDeleteMessageForSelf_Valid_MarksDeleted {
    NSError *error = nil;

    NSDictionary *convo = [self.service createConversationWithMembers:@[@"did:plc:alice", @"did:plc:bob"] error:&error];
    NSString *convoId = convo[@"id"];

    NSDictionary *message = [self.service sendMessage:convoId senderDid:@"did:plc:alice" text:@"Test" embedJson:nil error:&error];
    NSString *messageId = message[@"id"];

    BOOL success = [self.service deleteMessageForSelf:messageId memberDid:@"did:plc:bob" error:&error];

    XCTAssertTrue(success, @"Should mark message as deleted");
}

- (void)testUpdateLastReadMessage_Valid_Updates {
    NSError *error = nil;

    NSDictionary *convo = [self.service createConversationWithMembers:@[@"did:plc:alice", @"did:plc:bob"] error:&error];
    NSString *convoId = convo[@"id"];

    NSDictionary *message = [self.service sendMessage:convoId senderDid:@"did:plc:alice" text:@"Test" embedJson:nil error:&error];
    NSString *messageId = message[@"id"];

    BOOL success = [self.service updateLastReadMessage:convoId memberDid:@"did:plc:bob" messageId:messageId error:&error];

    XCTAssertTrue(success, @"Should update last read");
}

- (void)testSendMessageBatch_EmptyArray_Fails {
    NSError *error = nil;

    NSDictionary *convo = [self.service createConversationWithMembers:@[@"did:plc:alice", @"did:plc:bob"] error:&error];
    NSString *convoId = convo[@"id"];

    NSArray *result = [self.service sendMessageBatch:convoId senderDid:@"did:plc:alice" messages:@[] error:&error];

    XCTAssertNil(result, @"Should fail with empty array");
    XCTAssertNotNil(error, @"Should return error");
    XCTAssertEqual(error.code, 400, @"Should be 400");
}

#pragma mark - Reactions Tests

- (void)testAddReaction_Valid_AddsReaction {
    NSError *error = nil;

    NSDictionary *convo = [self.service createConversationWithMembers:@[@"did:plc:alice", @"did:plc:bob"] error:&error];
    NSString *convoId = convo[@"id"];

    NSDictionary *message = [self.service sendMessage:convoId senderDid:@"did:plc:alice" text:@"Test" embedJson:nil error:&error];
    NSString *messageId = message[@"id"];

    BOOL success = [self.service addReaction:messageId actorDid:@"did:plc:bob" emoji:@"👍" error:&error];

    XCTAssertTrue(success, @"Should add reaction");
}

- (void)testRemoveReaction_Valid_RemovesReaction {
    NSError *error = nil;

    NSDictionary *convo = [self.service createConversationWithMembers:@[@"did:plc:alice", @"did:plc:bob"] error:&error];
    NSString *convoId = convo[@"id"];

    NSDictionary *message = [self.service sendMessage:convoId senderDid:@"did:plc:alice" text:@"Test" embedJson:nil error:&error];
    NSString *messageId = message[@"id"];

    [self.service addReaction:messageId actorDid:@"did:plc:bob" emoji:@"👍" error:nil];

    BOOL success = [self.service removeReaction:messageId actorDid:@"did:plc:bob" emoji:@"👍" error:&error];

    XCTAssertTrue(success, @"Should remove reaction");
}

#pragma mark - Preferences and Locking Tests

- (void)testMuteConversation_Valid_Mutes {
    NSError *error = nil;

    NSDictionary *convo = [self.service createConversationWithMembers:@[@"did:plc:alice", @"did:plc:bob"] error:&error];
    NSString *convoId = convo[@"id"];

    BOOL success = [self.service muteConversation:convoId memberDid:@"did:plc:bob" error:&error];

    XCTAssertTrue(success, @"Should mute conversation");
}

- (void)testUnmuteConversation_Valid_Unmutes {
    NSError *error = nil;

    NSDictionary *convo = [self.service createConversationWithMembers:@[@"did:plc:alice", @"did:plc:bob"] error:&error];
    NSString *convoId = convo[@"id"];

    [self.service muteConversation:convoId memberDid:@"did:plc:bob" error:nil];

    BOOL success = [self.service unmuteConversation:convoId memberDid:@"did:plc:bob" error:&error];

    XCTAssertTrue(success, @"Should unmute conversation");
}

- (void)testLockConversation_Valid_Locks {
    NSError *error = nil;

    NSDictionary *convo = [self.service createConversationWithMembers:@[@"did:plc:alice", @"did:plc:bob"] error:&error];
    NSString *convoId = convo[@"id"];

    BOOL success = [self.service lockConversation:convoId error:&error];

    XCTAssertTrue(success, @"Should lock conversation");
}

- (void)testUnlockConversation_Valid_Unlocks {
    NSError *error = nil;

    NSDictionary *convo = [self.service createConversationWithMembers:@[@"did:plc:alice", @"did:plc:bob"] error:&error];
    NSString *convoId = convo[@"id"];

    [self.service lockConversation:convoId error:nil];

    BOOL success = [self.service unlockConversation:convoId error:&error];

    XCTAssertTrue(success, @"Should unlock conversation");
}

#pragma mark - Batch and Event Log Tests

- (void)testSendMessageBatch_LockedConvo_Fails {
    NSError *error = nil;

    NSDictionary *convo = [self.service createConversationWithMembers:@[@"did:plc:alice", @"did:plc:bob"] error:&error];
    NSString *convoId = convo[@"id"];

    [self.service lockConversation:convoId error:nil];

    NSArray *result = [self.service sendMessageBatch:convoId senderDid:@"did:plc:alice" messages:@[@{@"text": @"Test"}] error:&error];

    XCTAssertNil(result, @"Should fail when locked");
    XCTAssertNotNil(error, @"Should return error");
    XCTAssertEqual(error.code, 403, @"Should be 403");
}

- (void)testGetChatLog_ReturnsEventLog {
    NSError *error = nil;

    NSDictionary *convo = [self.service createConversationWithMembers:@[@"did:plc:alice", @"did:plc:bob"] error:&error];
    NSString *convoId = convo[@"id"];

    [self.service sendMessage:convoId senderDid:@"did:plc:alice" text:@"Test" embedJson:nil error:nil];

    NSArray *log = [self.service getChatLogWithLimit:10 cursor:nil error:&error];

    XCTAssertNotNil(log, @"Should return event log");
}

@end