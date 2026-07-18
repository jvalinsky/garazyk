// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <XCTest/XCTest.h>

#import "Network/XrpcSpaceRecoveryTestPack.h"

@interface XrpcSpaceRecoveryTestPackTests : XCTestCase
@end

@implementation XrpcSpaceRecoveryTestPackTests

- (void)testControlRequiresBothExplicitTestGates {
  XCTAssertFalse([XrpcSpaceRecoveryTestPack isEnabledForEnvironment:@{}]);
  NSDictionary *testsOnly = @{
      @"PDS_RUNNING_TESTS" : @"true",
  };
  XCTAssertFalse([XrpcSpaceRecoveryTestPack isEnabledForEnvironment:testsOnly]);
  NSDictionary *controlOnly = @{
      @"PDS_SPACE_RECOVERY_TEST_CONTROL" : @"true",
  };
  XCTAssertFalse([XrpcSpaceRecoveryTestPack isEnabledForEnvironment:controlOnly]);
  NSDictionary *enabled = @{
      @"PDS_RUNNING_TESTS" : @"true",
      @"PDS_SPACE_RECOVERY_TEST_CONTROL" : @"1",
  };
  XCTAssertTrue([XrpcSpaceRecoveryTestPack isEnabledForEnvironment:enabled]);
}

- (void)testProductionEnvironmentAlwaysVetoesControlRegistration {
  NSDictionary *production = @{
      @"PDS_RUNNING_TESTS" : @"true",
      @"PDS_SPACE_RECOVERY_TEST_CONTROL" : @"true",
      @"PDS_ENV" : @"production",
  };
  XCTAssertFalse([XrpcSpaceRecoveryTestPack isEnabledForEnvironment:production]);
}

@end
