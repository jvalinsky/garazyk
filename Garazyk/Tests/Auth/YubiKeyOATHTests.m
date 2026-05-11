// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Auth/YubiKeyOATH.h"

NS_ASSUME_NONNULL_BEGIN

@interface YubiKeyOATHTests : XCTestCase
@end

@implementation YubiKeyOATHTests

- (void)testSoftwareTotpFallbackProducesToken {
    YubiKeyOATHManager *manager = [[YubiKeyOATHManager alloc] init];
    NSData *secret = [@"secret" dataUsingEncoding:NSUTF8StringEncoding];

    NSError *error = nil;
    NSString *token = [manager generateTOTPForSecret:secret counter:0 error:&error];
    XCTAssertNotNil(token);
    XCTAssertNil(error);
    XCTAssertEqual(token.length, 6);
    NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
    XCTAssertEqual([token rangeOfCharacterFromSet:[digits invertedSet]].location, NSNotFound);
}

- (void)testSetOATHSecretNotImplemented {
    YubiKeyOATHManager *manager = [[YubiKeyOATHManager alloc] init];
    NSData *secret = [@"secret" dataUsingEncoding:NSUTF8StringEncoding];

    NSError *error = nil;
    BOOL success = [manager setOATHSecret:secret name:@"test" error:&error];
    XCTAssertFalse(success);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, YubiKeyOATHErrorNotImplemented);
}

- (void)testListCredentialsEmptyInSoftwareMode {
    YubiKeyOATHManager *manager = [[YubiKeyOATHManager alloc] init];
    NSError *error = nil;
    NSArray *credentials = [manager listCredentialsWithError:&error];
    XCTAssertNotNil(credentials);
    XCTAssertEqual(credentials.count, 0);
    XCTAssertNil(error);
}

@end

NS_ASSUME_NONNULL_END
