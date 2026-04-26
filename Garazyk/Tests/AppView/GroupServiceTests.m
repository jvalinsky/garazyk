#import <XCTest/XCTest.h>
#import "AppView/Services/GroupService.h"
#import "Database/PDSDatabase.h"

@interface GroupServiceTests : XCTestCase
@property (nonatomic, strong) NSString *testDirectory;
@property (nonatomic, strong) PDSDatabase *database;
@property (nonatomic, strong) GroupService *service;
@end

@implementation GroupServiceTests

- (void)setUp {
    [super setUp];

    self.testDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.testDirectory withIntermediateDirectories:YES attributes:nil error:nil];

    NSString *dbPath = [self.testDirectory stringByAppendingPathComponent:@"group_service_test.db"];

    [[NSFileManager defaultManager] removeItemAtPath:dbPath error:nil];

    self.database = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:dbPath]];

    NSError *error = nil;
    XCTAssertTrue([self.database openWithError:&error], @"Database setup failed: %@", error);

    [self setupSchema];
    self.service = [[GroupService alloc] initWithDatabase:self.database];
}

- (void)setupSchema {
    NSError *error = nil;

    NSString *createGroups = @"CREATE TABLE IF NOT EXISTS groups ("
        @"uri TEXT PRIMARY KEY, creator_did TEXT, name TEXT, description TEXT, privacy TEXT, joinability TEXT, "
        @"created_at REAL, updated_at REAL)";
    XCTAssertTrue([self.database executeParameterizedUpdate:createGroups params:@[] error:&error], @"Groups table: %@", error);

    NSString *createMembers = @"CREATE TABLE IF NOT EXISTS group_members ("
        @"group_uri TEXT, member_did TEXT, role TEXT, status TEXT, invited_by TEXT, joined_at REAL, "
        @"PRIMARY KEY(group_uri, member_did))";
    XCTAssertTrue([self.database executeParameterizedUpdate:createMembers params:@[] error:&error], @"Members table: %@", error);

    NSString *createInvites = @"CREATE TABLE IF NOT EXISTS group_invite_links ("
        @"id TEXT PRIMARY KEY, group_uri TEXT, created_by TEXT, created_at REAL, expires_at TEXT, "
        @"max_uses INTEGER, uses INTEGER, enabled INTEGER)";
    XCTAssertTrue([self.database executeParameterizedUpdate:createInvites params:@[] error:&error], @"Invites table: %@", error);

    NSString *createRequests = @"CREATE TABLE IF NOT EXISTS group_join_requests ("
        @"id TEXT PRIMARY KEY, group_uri TEXT, requester_did TEXT, status TEXT, requested_at REAL, responded_at REAL, responded_by TEXT)";
    XCTAssertTrue([self.database executeParameterizedUpdate:createRequests params:@[] error:&error], @"Requests table: %@", error);

    NSString *createMessages = @"CREATE TABLE IF NOT EXISTS group_messages ("
        @"id TEXT PRIMARY KEY, group_uri TEXT, sender_did TEXT, text TEXT, embed_json TEXT, deleted_for_json TEXT, created_at REAL)";
    XCTAssertTrue([self.database executeParameterizedUpdate:createMessages params:@[] error:&error], @"Messages table: %@", error);

    NSString *createReactions = @"CREATE TABLE IF NOT EXISTS group_message_reactions ("
        @"message_id TEXT, actor_did TEXT, emoji TEXT, created_at REAL, "
        @"PRIMARY KEY(message_id, actor_did, emoji))";
    XCTAssertTrue([self.database executeParameterizedUpdate:createReactions params:@[] error:&error], @"Reactions table: %@", error);
}

- (void)tearDown {
    [self.database close];
    self.database = nil;
    self.service = nil;
    [[NSFileManager defaultManager] removeItemAtPath:self.testDirectory error:nil];
    [super tearDown];
}

#pragma mark - Group CRUD Tests

- (void)testCreateGroupWithName_Valid_ReturnsGroup {
    NSError *error = nil;

    NSDictionary *group = [self.service createGroupWithName:@"Test Group"
                                       description:@"A test group"
                                          creator:@"did:plc:alice"
                                          privacy:@"public"
                                      joinability:@"invite"
                                            error:&error];

    XCTAssertNotNil(group, @"Group should be created");
    XCTAssertNil(error, @"No error: %@", error);
    XCTAssertTrue([group[@"uri"] hasPrefix:@"at://"], @"URI should be AT URI format");
    XCTAssertEqualObjects(group[@"name"], @"Test Group");
    XCTAssertNotNil(group[@"memberCount"], @"Should have member count");
}

- (void)testCreateGroupWithName_MissingName_Fails {
    NSError *error = nil;

    NSDictionary *group = [self.service createGroupWithName:nil
                                       description:@"desc"
                                          creator:@"did:plc:alice"
                                          privacy:@"public"
                                      joinability:@"invite"
                                            error:&error];

    XCTAssertNil(group, @"Should fail without name");
    XCTAssertNotNil(error, @"Should return error");
    XCTAssertEqual(error.code, 400);
}

- (void)testEditGroup_Valid_Updates {
    NSError *error = nil;

    NSDictionary *group = [self.service createGroupWithName:@"Original"
                                       description:nil
                                          creator:@"did:plc:alice"
                                          privacy:@"public"
                                      joinability:@"invite"
                                            error:&error];
    NSString *uri = group[@"uri"];

    BOOL success = [self.service editGroup:uri newName:@"Updated" newDescription:nil newPrivacy:nil error:&error];

    XCTAssertTrue(success, @"Should update");
    XCTAssertNil(error, @"No error: %@", error);
}

- (void)testGetGroupPublicInfo_Valid_ReturnsGroup {
    NSError *error = nil;

    NSDictionary *created = [self.service createGroupWithName:@"Test"
                                       description:@"Desc"
                                          creator:@"did:plc:alice"
                                          privacy:@"public"
                                      joinability:@"invite"
                                            error:&error];
    NSString *uri = created[@"uri"];

    NSDictionary *fetched = [self.service getGroupPublicInfo:uri error:&error];

    XCTAssertNotNil(fetched, @"Should fetch group");
    XCTAssertEqualObjects(fetched[@"uri"], uri);
    XCTAssertEqualObjects(fetched[@"name"], @"Test");
}

- (void)testGetGroupPublicInfo_NotFound_ReturnsNil {
    NSError *error = nil;

    NSDictionary *group = [self.service getGroupPublicInfo:@"at://did/notexist" error:&error];

    XCTAssertNil(group, @"Should return nil");
    XCTAssertNotNil(error, @"Should error");
    XCTAssertEqual(error.code, 404);
}

- (void)testDeleteGroup_Valid_Deletes {
    NSError *error = nil;

    NSDictionary *group = [self.service createGroupWithName:@"ToDelete"
                                       description:nil
                                          creator:@"did:plc:alice"
                                          privacy:@"public"
                                      joinability:@"invite"
                                            error:&error];
    NSString *uri = group[@"uri"];

    BOOL success = [self.service deleteGroup:uri error:&error];

    XCTAssertTrue(success, @"Should delete");
    XCTAssertNil(error, @"No error: %@", error);
}

- (void)testListAllGroupsWithLimit_ReturnsList {
    NSError *error = nil;

    [self.service createGroupWithName:@"Group1" description:nil creator:@"did:plc:alice" privacy:@"public" joinability:@"invite" error:&error];
    [self.service createGroupWithName:@"Group2" description:nil creator:@"did:plc:bob" privacy:@"public" joinability:@"invite" error:&error];

    NSArray *groups = [self.service listAllGroupsWithLimit:10 cursor:nil query:nil error:&error];

    XCTAssertNotNil(groups);
    XCTAssertGreaterThanOrEqual((NSInteger)groups.count, 2);
}

#pragma mark - Member Management Tests

- (void)testAddMembersToGroup_Valid_Adds {
    NSError *error = nil;

    NSDictionary *group = [self.service createGroupWithName:@"TestGroup"
                                       description:nil
                                          creator:@"did:plc:alice"
                                          privacy:@"public"
                                      joinability:@"invite"
                                            error:&error];
    NSString *uri = group[@"uri"];

    BOOL success = [self.service addMembersToGroup:uri members:@[@"did:plc:bob", @"did:plc:charlie"] invitedBy:@"did:plc:alice" error:&error];

    XCTAssertTrue(success, @"Should add members");
}

- (void)testAddMembersToGroup_EmptyMembers_Fails {
    NSError *error = nil;

    NSDictionary *group = [self.service createGroupWithName:@"TestGroup"
                                       description:nil
                                          creator:@"did:plc:alice"
                                          privacy:@"public"
                                      joinability:@"invite"
                                            error:&error];
    NSString *uri = group[@"uri"];

    BOOL success = [self.service addMembersToGroup:uri members:@[] invitedBy:@"did:plc:alice" error:&error];

    XCTAssertFalse(success, @"Should fail with empty");
    XCTAssertNotNil(error, @"Should return error");
}

- (void)testRemoveMembersFromGroup_Valid_Removes {
    NSError *error = nil;

    NSDictionary *group = [self.service createGroupWithName:@"TestGroup"
                                       description:nil
                                          creator:@"did:plc:alice"
                                          privacy:@"public"
                                      joinability:@"invite"
                                            error:&error];
    NSString *uri = group[@"uri"];

    [self.service addMembersToGroup:uri members:@[@"did:plc:bob"] invitedBy:@"did:plc:alice" error:nil];

    BOOL success = [self.service removeMembersFromGroup:uri members:@[@"did:plc:bob"] error:&error];

    XCTAssertTrue(success, @"Should remove member");
}

- (void)testListGroupMembers_ReturnsList {
    NSError *error = nil;

    NSDictionary *group = [self.service createGroupWithName:@"TestGroup"
                                       description:nil
                                          creator:@"did:plc:alice"
                                          privacy:@"public"
                                      joinability:@"invite"
                                            error:&error];
    NSString *uri = group[@"uri"];

    [self.service addMembersToGroup:uri members:@[@"did:plc:bob"] invitedBy:@"did:plc:alice" error:nil];

    NSArray *members = [self.service listGroupMembers:uri limit:10 cursor:nil error:&error];

    XCTAssertNotNil(members);
    XCTAssertGreaterThanOrEqual((NSInteger)members.count, 1);
}

#pragma mark - Invite Links Tests

- (void)testCreateInviteLinkForGroup_Valid_ReturnsLinkId {
    NSError *error = nil;

    NSDictionary *group = [self.service createGroupWithName:@"TestGroup"
                                       description:nil
                                          creator:@"did:plc:alice"
                                          privacy:@"public"
                                      joinability:@"invite"
                                            error:&error];
    NSString *uri = group[@"uri"];

    NSString *linkId = [self.service createInviteLinkForGroup:uri createdBy:@"did:plc:alice" expiresAt:nil maxUses:@10 error:&error];

    XCTAssertNotNil(linkId, @"Should create link");
}

- (void)testValidateAndUseInviteLink_Valid_JoinsGroup {
    NSError *error = nil;

    NSDictionary *group = [self.service createGroupWithName:@"TestGroup"
                                       description:nil
                                          creator:@"did:plc:alice"
                                          privacy:@"public"
                                      joinability:@"invite"
                                            error:&error];
    NSString *uri = group[@"uri"];

    NSString *linkId = [self.service createInviteLinkForGroup:uri createdBy:@"did:plc:alice" expiresAt:nil maxUses:@10 error:&error];

    NSDictionary *result = [self.service validateAndUseInviteLink:linkId memberDid:@"did:plc:newuser" error:&error];

    XCTAssertNotNil(result, @"Should validate");
    XCTAssertEqualObjects(result[@"status"], @"success");
}

- (void)testValidateAndUseInviteLink_DisabledLink_Fails {
    NSError *error = nil;

    NSDictionary *group = [self.service createGroupWithName:@"TestGroup"
                                       description:nil
                                          creator:@"did:plc:alice"
                                          privacy:@"public"
                                      joinability:@"invite"
                                            error:&error];
    NSString *uri = group[@"uri"];

    NSString *linkId = [self.service createInviteLinkForGroup:uri createdBy:@"did:plc:alice" expiresAt:nil maxUses:@10 error:&error];

    [self.service disableInviteLink:linkId error:nil];

    NSDictionary *result = [self.service validateAndUseInviteLink:linkId memberDid:@"did:plc:newuser" error:&error];

    XCTAssertNil(result, @"Should fail");
    XCTAssertNotNil(error, @"Should return error");
    XCTAssertEqual(error.code, 403);
}

- (void)testValidateAndUseInviteLink_ExpiredLink_Fails {
    NSError *error = nil;

    NSDictionary *group = [self.service createGroupWithName:@"TestGroup"
                                       description:nil
                                          creator:@"did:plc:alice"
                                          privacy:@"public"
                                      joinability:@"invite"
                                            error:&error];
    NSString *uri = group[@"uri"];

    NSString *pastTime = [NSString stringWithFormat:@"%.0f", @([[NSDate date] timeIntervalSince1970] - 100)];
    NSString *linkId = [self.service createInviteLinkForGroup:uri createdBy:@"did:plc:alice" expiresAt:pastTime maxUses:nil error:&error];

    NSDictionary *result = [self.service validateAndUseInviteLink:linkId memberDid:@"did:plc:newuser" error:&error];

    XCTAssertNil(result, @"Should fail");
    XCTAssertNotNil(error, @"Should return error");
    XCTAssertEqual(error.code, 403);
}

- (void)testValidateAndUseInviteLink_MaxUsesReached_Fails {
    NSError *error = nil;

    NSDictionary *group = [self.service createGroupWithName:@"TestGroup"
                                       description:nil
                                          creator:@"did:plc:alice"
                                          privacy:@"public"
                                      joinability:@"invite"
                                            error:&error];
    NSString *uri = group[@"uri"];

    NSString *linkId = [self.service createInviteLinkForGroup:uri createdBy:@"did:plc:alice" expiresAt:nil maxUses:@1 error:&error];
    [self.service validateAndUseInviteLink:linkId memberDid:@"did:plc:user1" error:nil];
    [self.service validateAndUseInviteLink:linkId memberDid:@"did:plc:user2" error:&error];

    NSDictionary *result = [self.service validateAndUseInviteLink:linkId memberDid:@"did:plc:user3" error:&error];

    XCTAssertNil(result, @"Should fail");
    XCTAssertNotNil(error, @"Should return error");
    XCTAssertEqual(error.code, 403);
}

#pragma mark - Join Requests Tests

- (void)testRequestJoinGroup_Valid_ReturnsRequestId {
    NSError *error = nil;

    NSDictionary *group = [self.service createGroupWithName:@"TestGroup"
                                       description:nil
                                          creator:@"did:plc:alice"
                                          privacy:@"public"
                                      joinability:@"request"
                                            error:&error];
    NSString *uri = group[@"uri"];

    NSString *requestId = [self.service requestJoinGroup:uri requesterDid:@"did:plc:bob" error:&error];

    XCTAssertNotNil(requestId, @"Should create request");
}

- (void)testApproveJoinRequest_Valid_Approves {
    NSError *error = nil;

    NSDictionary *group = [self.service createGroupWithName:@"TestGroup"
                                       description:nil
                                          creator:@"did:plc:alice"
                                          privacy:@"public"
                                      joinability:@"request"
                                            error:&error];
    NSString *uri = group[@"uri"];

    NSString *requestId = [self.service requestJoinGroup:uri requesterDid:@"did:plc:bob" error:&error];

    BOOL success = [self.service approveJoinRequest:requestId approvingDid:@"did:plc:alice" error:&error];

    XCTAssertTrue(success, @"Should approve");
}

- (void)testRejectJoinRequest_Valid_Rejects {
    NSError *error = nil;

    NSDictionary *group = [self.service createGroupWithName:@"TestGroup"
                                       description:nil
                                          creator:@"did:plc:alice"
                                          privacy:@"public"
                                      joinability:@"request"
                                            error:&error];
    NSString *uri = group[@"uri"];

    NSString *requestId = [self.service requestJoinGroup:uri requesterDid:@"did:plc:bob" error:&error];

    BOOL success = [self.service rejectJoinRequest:requestId rejectingDid:@"did:plc:alice" error:&error];

    XCTAssertTrue(success, @"Should reject");
}

- (void)testListJoinRequestsForGroup_ReturnsList {
    NSError *error = nil;

    NSDictionary *group = [self.service createGroupWithName:@"TestGroup"
                                       description:nil
                                          creator:@"did:plc:alice"
                                          privacy:@"public"
                                      joinability:@"request"
                                            error:&error];
    NSString *uri = group[@"uri"];

    [self.service requestJoinGroup:uri requesterDid:@"did:plc:bob" error:nil];

    NSArray *requests = [self.service listJoinRequestsForGroup:uri error:&error];

    XCTAssertNotNil(requests);
    XCTAssertGreaterThanOrEqual((NSInteger)requests.count, 1);
}

#pragma mark - Group Messaging Tests

- (void)testSendMessageToGroup_Valid_Sends {
    NSError *error = nil;

    NSDictionary *group = [self.service createGroupWithName:@"TestGroup"
                                       description:nil
                                          creator:@"did:plc:alice"
                                          privacy:@"public"
                                      joinability:@"invite"
                                            error:&error];
    NSString *uri = group[@"uri"];

    NSString *messageId = [self.service sendMessageToGroup:uri senderDid:@"did:plc:alice" text:@"Hello!" embed:nil error:&error];

    XCTAssertNotNil(messageId, @"Should send message");
    XCTAssertTrue([messageId hasPrefix:@"msg/"]);
}

- (void)testSendMessageToGroup_NonMember_Fails {
    NSError *error = nil;

    NSDictionary *group = [self.service createGroupWithName:@"TestGroup"
                                       description:nil
                                          creator:@"did:plc:alice"
                                          privacy:@"public"
                                      joinability:@"invite"
                                            error:&error];
    NSString *uri = group[@"uri"];

    NSString *messageId = [self.service sendMessageToGroup:uri senderDid:@"did:plc:outsider" text:@"Hello!" embed:nil error:&error];

    XCTAssertNil(messageId, @"Should fail");
    XCTAssertNotNil(error, @"Should return error");
    XCTAssertEqual(error.code, 403);
}

- (void)testGetMessagesForGroup_ReturnsList {
    NSError *error = nil;

    NSDictionary *group = [self.service createGroupWithName:@"TestGroup"
                                       description:nil
                                          creator:@"did:plc:alice"
                                          privacy:@"public"
                                      joinability:@"invite"
                                            error:&error];
    NSString *uri = group[@"uri"];

    [self.service sendMessageToGroup:uri senderDid:@"did:plc:alice" text:@"Hello!" embed:nil error:nil];

    NSArray *messages = [self.service getMessagesForGroup:uri limit:10 cursor:nil error:&error];

    XCTAssertNotNil(messages);
    XCTAssertEqual((NSInteger)messages.count, 1);
}

- (void)testAddReactionToGroupMessage_Valid_Adds {
    NSError *error = nil;

    NSDictionary *group = [self.service createGroupWithName:@"TestGroup"
                                       description:nil
                                          creator:@"did:plc:alice"
                                          privacy:@"public"
                                      joinability:@"invite"
                                            error:&error];
    NSString *uri = group[@"uri"];

    NSString *messageId = [self.service sendMessageToGroup:uri senderDid:@"did:plc:alice" text:@"Hello!" embed:nil error:&error];

    BOOL success = [self.service addReactionToGroupMessage:messageId actorDid:@"did:plc:bob" emoji:@"👍" error:&error];

    XCTAssertTrue(success, @"Should add reaction");
}

- (void)testRemoveReactionFromGroupMessage_Valid_Removes {
    NSError *error = nil;

    NSDictionary *group = [self.service createGroupWithName:@"TestGroup"
                                       description:nil
                                          creator:@"did:plc:alice"
                                          privacy:@"public"
                                      joinability:@"invite"
                                            error:&error];
    NSString *uri = group[@"uri"];

    NSString *messageId = [self.service sendMessageToGroup:uri senderDid:@"did:plc:alice" text:@"Hello!" embed:nil error:&error];

    [self.service addReactionToGroupMessage:messageId actorDid:@"did:plc:bob" emoji:@"👍" error:nil];

    BOOL success = [self.service removeReactionFromGroupMessage:messageId actorDid:@"did:plc:bob" emoji:@"👍" error:&error];

    XCTAssertTrue(success, @"Should remove reaction");
}

- (void)testLeaveGroup_Valid_Leaves {
    NSError *error = nil;

    NSDictionary *group = [self.service createGroupWithName:@"TestGroup"
                                       description:nil
                                          creator:@"did:plc:alice"
                                          privacy:@"public"
                                      joinability:@"invite"
                                            error:&error];
    NSString *uri = group[@"uri"];

    [self.service addMembersToGroup:uri members:@[@"did:plc:bob"] invitedBy:@"did:plc:alice" error:nil];

    BOOL success = [self.service leaveGroup:uri memberDid:@"did:plc:bob" error:&error];

    XCTAssertTrue(success, @"Should leave");
}

- (void)testLeaveGroup_CreatorCannotLeave_Fails {
    NSError *error = nil;

    NSDictionary *group = [self.service createGroupWithName:@"TestGroup"
                                       description:nil
                                          creator:@"did:plc:alice"
                                          privacy:@"public"
                                      joinability:@"invite"
                                            error:&error];
    NSString *uri = group[@"uri"];

    BOOL success = [self.service leaveGroup:uri memberDid:@"did:plc:alice" error:&error];

    XCTAssertFalse(success, @"Creator cannot leave");
    XCTAssertNotNil(error, @"Should return error");
    XCTAssertEqual(error.code, 403);
}

@end