// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Chat/Server/Services/ChatService.h"
#import "Database/PDSDatabase.h"
#import "Database/Schema.h"

@interface ChatServiceTests : XCTestCase
@property (nonatomic, strong) NSString *tempDir;
@property (nonatomic, strong) PDSDatabase *db;
@property (nonatomic, strong) ChatService *service;
@end

@implementation ChatServiceTests

- (void)setUp {
    [super setUp];
    self.tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.tempDir withIntermediateDirectories:YES attributes:nil error:nil];
    
    NSURL *dbURL = [NSURL fileURLWithPath:[self.tempDir stringByAppendingPathComponent:@"chat.db"]];
    self.db = [PDSDatabase databaseAtURL:dbURL];
    [self.db openWithError:nil];
    
    // Initialize schema
    [self.db executeUnsafeRawSQL:kPDSConversationsTableCreateSQL error:nil];
    [self.db executeUnsafeRawSQL:kPDSConversationMembersTableCreateSQL error:nil];
    [self.db executeUnsafeRawSQL:kPDSMessagesTableCreateSQL error:nil];
    
    self.service = [[ChatService alloc] initWithDatabase:self.db];
}

- (void)tearDown {
    [self.db close];
    [[NSFileManager defaultManager] removeItemAtPath:self.tempDir error:nil];
    [super tearDown];
}

- (void)testCreateConversation {
    NSArray *members = @[@"did:plc:alice", @"did:plc:bob"];
    NSError *error = nil;
    NSDictionary *convo = [self.service createConversationWithMembers:members error:&error];
    
    XCTAssertNotNil(convo);
    XCTAssertNil(error);
    XCTAssertNotNil(convo[@"id"]);
    XCTAssertEqualObjects(convo[@"memberList"], @"did:plc:alice, did:plc:bob");
}

- (void)testSendMessage {
    NSArray *members = @[@"did:plc:alice", @"did:plc:bob"];
    NSDictionary *convo = [self.service createConversationWithMembers:members error:nil];
    NSString *convoId = convo[@"id"];
    
    NSError *error = nil;
    NSDictionary *msg = [self.service sendMessage:convoId senderDid:@"did:plc:alice" text:@"Hello" embedJson:nil error:&error];
    
    XCTAssertNotNil(msg);
    XCTAssertNil(error);
    XCTAssertEqualObjects(msg[@"text"], @"Hello");
    XCTAssertEqualObjects(msg[@"senderDid"], @"did:plc:alice");
}

- (void)testListConversations {
    [self.service createConversationWithMembers:@[@"did:plc:alice", @"did:plc:bob"] error:nil];
    [self.service createConversationWithMembers:@[@"did:plc:alice", @"did:plc:charlie"] error:nil];
    
    NSError *error = nil;
    NSArray *convos = [self.service listConversationsForActor:@"did:plc:alice" limit:10 cursor:nil error:&error];
    
    XCTAssertEqual(convos.count, 2);
    XCTAssertNil(error);
}

@end
