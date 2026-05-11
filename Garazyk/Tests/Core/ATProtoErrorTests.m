// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Core/ATProtoError.h"

@interface ATProtoErrorTests : XCTestCase
@end

@implementation ATProtoErrorTests

- (void)testErrorWithCodeAndMessage {
    NSString *message = @"Test error message";
    NSError *error = [ATProtoError errorWithCode:ATProtoErrorCodeInvalidInput message:message];
    
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, ATProtoErrorDomain);
    XCTAssertEqual(error.code, ATProtoErrorCodeInvalidInput);
    XCTAssertEqualObjects(error.localizedDescription, message);
}

- (void)testErrorWithUnderlyingError {
    NSError *underlying = [NSError errorWithDomain:@"TestDomain" code:123 userInfo:nil];
    NSError *error = [ATProtoError errorWithCode:ATProtoErrorCodeDatabaseError message:@"DB Fail" underlyingError:underlying];
    
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.userInfo[NSUnderlyingErrorKey], underlying);
    XCTAssertEqualObjects(error.userInfo[ATProtoErrorUnderlyingCauseKey], underlying);
}

- (void)testInvalidInputHelper {
    NSError *error = [ATProtoError invalidInputWithMessage:@"Bad input"];
    XCTAssertEqual(error.code, ATProtoErrorCodeInvalidInput);
}

@end
