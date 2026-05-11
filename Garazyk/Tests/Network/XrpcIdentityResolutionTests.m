// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Identity/ATProtoHandleValidator.h"

@interface XrpcIdentityResolutionTests : XCTestCase
@end

@implementation XrpcIdentityResolutionTests

- (void)testHandleNormalization {
    XCTAssertEqualObjects([ATProtoHandleValidator normalizeHandle:@"LUNA.TEST"], @"luna.test");
    XCTAssertEqualObjects([ATProtoHandleValidator normalizeHandle:@"luna.test"], @"luna.test");
}

@end
