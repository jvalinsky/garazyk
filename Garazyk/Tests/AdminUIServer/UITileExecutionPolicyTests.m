// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "AdminUIServer/UITileExecutionPolicy.h"
#import "AdminUIServer/UITileDataProtocol.h"

@interface UITileExecutionPolicyTests : XCTestCase
@end

@implementation UITileExecutionPolicyTests

- (void)testTileCSPMatchesNormativeRestrictedPolicy {
    NSString *csp = GZAdminUITileExecutionContentSecurityPolicy();
    XCTAssertTrue([csp containsString:@"default-src 'self' blob: data:"]);
    XCTAssertTrue([csp containsString:@"script-src 'self' blob: data: 'unsafe-inline' 'wasm-unsafe-eval'"]);
    XCTAssertTrue([csp containsString:@"script-src-attr 'none'"]);
    XCTAssertTrue([csp containsString:@"manifest-src 'none'"]);
    XCTAssertTrue([csp containsString:@"object-src 'none'"]);
    XCTAssertTrue([csp containsString:@"base-uri 'none'"]);
    XCTAssertTrue([csp containsString:@"sandbox allow-downloads allow-forms allow-modals allow-popups allow-popups-to-escape-sandbox allow-same-origin allow-scripts"]);
    XCTAssertFalse([csp containsString:@"connect-src"]);
    XCTAssertFalse([csp containsString:@"https://"]);
}

- (void)testTileSecurityHeadersIncludeIsolationAndNoReferrer {
    NSDictionary *headers = GZAdminUITileExecutionSecurityHeaders();
    XCTAssertEqualObjects(headers[@"cross-origin-opener-policy"], @"same-origin");
    XCTAssertEqualObjects(headers[@"cross-origin-resource-policy"], @"cross-origin");
    XCTAssertEqualObjects(headers[@"origin-agent-cluster"], @"?1");
    XCTAssertEqualObjects(headers[@"referrer-policy"], @"no-referrer");
    XCTAssertEqualObjects(headers[@"x-content-type-options"], @"nosniff");
    XCTAssertEqualObjects(headers[@"x-dns-prefetch-control"], @"off");
}

- (void)testDataProtocolModuleExportsNormativeFunctions {
    NSString *module = GZAdminUITileDataProtocolJavaScript();
    XCTAssertTrue([module containsString:@"export function addDataHandler"]);
    XCTAssertTrue([module containsString:@"export function removeDataHandler"]);
    XCTAssertTrue([module containsString:@"export function listen"]);
    XCTAssertTrue([module containsString:@"export function sendData"]);
    XCTAssertTrue([module containsString:GZAdminUITileDataProtocolReadyAction]);
    XCTAssertTrue([module containsString:GZAdminUITileDataProtocolDownPayloadAction]);
    XCTAssertTrue([module containsString:GZAdminUITileDataProtocolUpPayloadAction]);
    XCTAssertTrue([module containsString:@"event.source !== window.parent"]);
}

- (void)testDataProtocolAcceptsReadyAndPayloadMessages {
    NSError *error = nil;
    XCTAssertTrue(GZAdminUITileDataProtocolIsValidMessage(@{@"action": GZAdminUITileDataProtocolReadyAction}, NO, &error));
    XCTAssertNil(error);
    XCTAssertTrue(GZAdminUITileDataProtocolIsValidMessage(@{@"action": GZAdminUITileDataProtocolUpPayloadAction,
                                                      @"payload": @{@"answer": @YES}}, NO, &error));
    XCTAssertNil(error);
    XCTAssertTrue(GZAdminUITileDataProtocolIsValidMessage(@{@"action": GZAdminUITileDataProtocolDownPayloadAction,
                                                      @"payload": @[@1, @2]}, YES, &error));
    XCTAssertNil(error);
}

- (void)testDataProtocolRejectsWrongDirectionAndMalformedMessages {
    NSError *error = nil;
    XCTAssertFalse(GZAdminUITileDataProtocolIsValidMessage(@{@"action": GZAdminUITileDataProtocolReadyAction}, YES, &error));
    XCTAssertNotNil(error);
    error = nil;
    XCTAssertFalse(GZAdminUITileDataProtocolIsValidMessage(@{@"action": GZAdminUITileDataProtocolUpPayloadAction}, NO, &error));
    XCTAssertNotNil(error);
    error = nil;
    XCTAssertFalse(GZAdminUITileDataProtocolIsValidMessage(@{@"action": GZAdminUITileDataProtocolReadyAction, @"payload": @1}, NO, &error));
    XCTAssertNotNil(error);
    error = nil;
    XCTAssertFalse(GZAdminUITileDataProtocolIsValidMessage(@{@"action": GZAdminUITileDataProtocolDownPayloadAction}, YES, &error));
    XCTAssertNotNil(error);
}

@end
