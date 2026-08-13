// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "AdminUIServer/GZAdminUIDTOProjection.h"
#import "AdminUIServer/Packs/GZAdminUIPDSPack.h"
#import "AdminUIServer/Packs/GZAdminUIDataExplorerPack.h"

@interface GZAdminUIDTOProjectionTests : XCTestCase
@end

@implementation GZAdminUIDTOProjectionTests

- (void)testProjectDictionaryKeepsOnlyAllowlistedKeys {
    NSDictionary *src = @{
        @"did": @"did:plc:abc",
        @"email": @"a@example.com",
        @"passwordHash": @"SECRET",
        @"refreshJwt": @"SECRET",
    };
    NSDictionary *out = GZAdminUIProjectDictionary(src, @[ @"did", @"email" ]);
    XCTAssertEqualObjects(out[@"did"], @"did:plc:abc");
    XCTAssertEqualObjects(out[@"email"], @"a@example.com");
    XCTAssertNil(out[@"passwordHash"]);
    XCTAssertNil(out[@"refreshJwt"]);
}

- (void)testAccountsPartialStripsSecretFieldsFromHTML {
    NSDictionary *result = @{
        @"accounts": @[
            @{
                @"did": @"did:plc:one",
                @"handle": @"one.test",
                @"email": @"one@example.com",
                @"passwordHash": @"SHOULD-NOT-APPEAR",
                @"accessJwt": @"SHOULD-NOT-APPEAR",
            },
        ],
    };
    NSString *html = [GZAdminUIPDSPack renderAccountsPartial:result];
    XCTAssertTrue([html containsString:@"did:plc:one"]);
    XCTAssertTrue([html containsString:@"one@example.com"]);
    XCTAssertFalse([html containsString:@"SHOULD-NOT-APPEAR"]);
    XCTAssertFalse([html containsString:@"passwordHash"]);
}

- (void)testListRecordsPartialOmitsRecordValuePayload {
    NSDictionary *result = @{
        @"records": @[
            @{
                @"uri": @"at://did:plc:x/app.bsky.feed.post/abc",
                @"cid": @"bafytest",
                @"value": @{ @"text": @"secret body", @"password": @"nope" },
            },
        ],
    };
    NSString *html = [GZAdminUIDataExplorerPack renderListRecordsPartial:result];
    XCTAssertTrue([html containsString:@"bafytest"]);
    XCTAssertTrue([html containsString:@"app.bsky.feed.post"]);
    XCTAssertFalse([html containsString:@"secret body"]);
    XCTAssertFalse([html containsString:@"password"]);
}

- (void)testAuditLogPartialKeepsOnlyAllowlistedColumns {
    NSDictionary *result = @{
        @"events": @[
            @{
                @"createdAt": @"2026-08-12T00:00:00Z",
                @"action": @"com.atproto.admin.updateAccountEmail",
                @"subject": @"did:plc:x",
                @"createdBy": @"did:plc:admin",
                @"details": @{ @"token": @"SECRET" },
                @"ip": @"10.0.0.1",
            },
        ],
    };
    NSString *html = [GZAdminUIPDSPack renderAuditLogPartial:result];
    XCTAssertTrue([html containsString:@"com.atproto.admin.updateAccountEmail"]);
    XCTAssertFalse([html containsString:@"SECRET"]);
    XCTAssertFalse([html containsString:@"10.0.0.1"]);
}

@end
