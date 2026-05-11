// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Compat/PDSTypes.h"

@interface PlatformGuardTests : XCTestCase
@end

@implementation PlatformGuardTests

- (void)testExactlyOnePlatformMacroDefined {
    int platformCount = PDS_PLATFORM_APPLE + PDS_PLATFORM_LINUX;
    XCTAssertEqual(platformCount, 1, @"Exactly one platform macro must be defined");
}

- (void)testGCDObjcSupportMatchesPlatform {
#if defined(__APPLE__)
    XCTAssertEqual(PDS_GCD_OBJC_SUPPORT, 1);
#else
    XCTAssertEqual(PDS_GCD_OBJC_SUPPORT, 0);
#endif
}

- (void)testDispatchQueueAttributeDefined {
#if defined(PDS_DISPATCH_QUEUE_STRONG)
    XCTAssertTrue(YES);
#else
    XCTFail(@"PDS_DISPATCH_QUEUE_STRONG is not defined");
#endif
}

@end
