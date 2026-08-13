// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>

#import "Chat/AdminUI/ChatAdminUIPack.h"

NS_ASSUME_NONNULL_BEGIN

@interface ChatAdminUIPackTests : XCTestCase
@end

@implementation ChatAdminUIPackTests

- (void)testPackIdentityAndSidebar {
    XCTAssertEqualObjects([GZChatAdminUIPack packIdentifier], @"chat");
    XCTAssertEqualObjects([GZChatAdminUIPack displayName], @"Chat");
    NSArray *sections = [GZChatAdminUIPack sidebarSections];
    XCTAssertEqual(sections.count, 1u);
    XCTAssertEqualObjects(sections.firstObject[@"tabIdentifier"], @"chat");
}

- (void)testStatsHTMLShowsHeadlineCountersWithoutBodies {
    NSString *html = [GZChatAdminUIPack statsHTML:@{
        @"health": @"ok",
        @"uptimeSeconds": @90,
        @"conversationsTotal": @12,
        @"conversationsLocked": @2,
        @"conversationsE2EE": @5,
        @"conversationsPlaintext": @7,
        @"membersActive": @20,
        @"messagesTotal": @100,
        @"database": @{@"storageBytes": @(1024 * 1024)},
        @"text": @"SHOULD_NOT_RENDER",
        @"ciphertext": @"SHOULD_NOT_RENDER",
    }];
    XCTAssertTrue([html containsString:@"Conversations"]);
    XCTAssertTrue([html containsString:@"Locked"]);
    XCTAssertTrue([html containsString:@"Messages"]);
    XCTAssertTrue([html containsString:@"12"]);
    XCTAssertFalse([html containsString:@"SHOULD_NOT_RENDER"]);
}

- (void)testConvosHTMLOmitsBodiesAndShowsAllowlistedFields {
    NSDictionary *payload = @{
        @"convos": @[
            @{
                @"id": @"convo1",
                @"mode": @"plaintext",
                @"locked": @YES,
                @"memberCount": @2,
                @"text": @"SHOULD_NOT_RENDER",
                @"ciphertext": @"SHOULD_NOT_RENDER",
                @"lastMessage": @{
                    @"id": @"m1",
                    @"senderDid": @"did:plc:alice",
                    @"createdAt": @"2026-08-12T00:00:00Z",
                    @"text": @"secret body",
                },
            },
        ],
        @"cursor": @"",
    };
    NSString *html = [GZChatAdminUIPack convosHTML:payload];
    XCTAssertTrue([html containsString:@"convo1"]);
    XCTAssertTrue([html containsString:@"plaintext"]);
    XCTAssertTrue([html containsString:@"locked"]);
    XCTAssertTrue([html containsString:@"Unlock"]);
    XCTAssertTrue([html containsString:@"/admin/actions/chat-unlock"]);
    XCTAssertTrue([html containsString:@"2026-08-12T00:00:00Z"]);
    XCTAssertFalse([html containsString:@"SHOULD_NOT_RENDER"]);
    XCTAssertFalse([html containsString:@"secret body"]);
}

- (void)testMessagesHTMLUsesSenderDidCreatedAtAndOmitsText {
    NSDictionary *payload = @{
        @"messages": @[
            @{
                @"id": @"msg1",
                @"senderDid": @"did:plc:bob",
                @"createdAt": @"2026-08-12T01:00:00Z",
                @"mode": @"e2ee",
                @"text": @"leak",
                @"embedJson": @"{}",
            },
        ],
    };
    NSString *html = [GZChatAdminUIPack messagesHTML:payload convoID:@"convo1"];
    XCTAssertTrue([html containsString:@"msg1"]);
    XCTAssertTrue([html containsString:@"did:plc:bob"]);
    XCTAssertTrue([html containsString:@"2026-08-12T01:00:00Z"]);
    XCTAssertFalse([html containsString:@"leak"]);
    XCTAssertFalse([html containsString:@"embedJson"]);
}

- (void)testMainWiresBackendConfigureAndAdminSecret {
    NSString *testsDirectory = [@__FILE__ stringByDeletingLastPathComponent];
    NSString *garazykDirectory = [[testsDirectory stringByDeletingLastPathComponent]
        stringByDeletingLastPathComponent];
    NSString *mainPath =
        [garazykDirectory stringByAppendingPathComponent:@"Binaries/syrena-chat/main.m"];
    NSString *source = [NSString stringWithContentsOfFile:mainPath
                                                 encoding:NSUTF8StringEncoding
                                                    error:nil];
    XCTAssertNotNil(source);
    XCTAssertTrue([source containsString:@"configureHost:adminUIHost"]);
    XCTAssertTrue([source containsString:@"adminSecret = adminPassword"]);
    XCTAssertTrue([source containsString:@"serviceBaseURL:serviceURL"]);
}

@end

NS_ASSUME_NONNULL_END
