// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <XCTest/XCTest.h>

#import "Network/HttpRequest.h"
#import "Network/XrpcSpaceRecoveryTestPack.h"

@interface XrpcSpaceRecoveryTestPackTests : XCTestCase
@end

@implementation XrpcSpaceRecoveryTestPackTests

- (NSDictionary<NSString *, NSString *> *)enabledEnvironment {
  return @{
      @"PDS_RUNNING_TESTS" : @"true",
      @"PDS_SPACE_RECOVERY_TEST_CONTROL" : @"1",
      @"PDS_SPACE_RECOVERY_TEST_CONTROL_TOKEN" : @"c81593b6-4af0-40eb-a3b8-461591da0843",
  };
}

- (HttpRequest *)requestWithAuthorization:(nullable NSString *)authorization
                             remoteAddress:(NSString *)remoteAddress {
  NSMutableDictionary *headers = [NSMutableDictionary dictionary];
  if (authorization) headers[@"Authorization"] = authorization;
  return [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                methodString:@"POST"
                                       path:@"/xrpc/tools.garazyk.test.spaceRecovery"
                                queryString:@""
                                queryParams:@{}
                                    version:@"1.1"
                                    headers:headers
                                       body:[NSData data]
                              remoteAddress:remoteAddress];
}

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
  NSDictionary *enabled = [self enabledEnvironment];
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

- (void)testIssuerRequiredEnvironmentAlwaysVetoesControlRegistration {
  NSMutableDictionary *issuerRequired = [[self enabledEnvironment] mutableCopy];
  issuerRequired[@"PDS_REQUIRE_ISSUER"] = @"true";
  XCTAssertFalse([XrpcSpaceRecoveryTestPack isEnabledForEnvironment:issuerRequired]);
}

- (void)testControlRequiresLoopbackBearerToken {
  NSDictionary *environment = [self enabledEnvironment];
  NSString *token = environment[@"PDS_SPACE_RECOVERY_TEST_CONTROL_TOKEN"];
  XCTAssertTrue([XrpcSpaceRecoveryTestPack
      isAuthorizedRequest:[self requestWithAuthorization:[@"Bearer " stringByAppendingString:token]
                                            remoteAddress:@"127.0.0.1"]
      environment:environment]);
  XCTAssertFalse([XrpcSpaceRecoveryTestPack
      isAuthorizedRequest:[self requestWithAuthorization:nil remoteAddress:@"127.0.0.1"]
      environment:environment]);
  XCTAssertFalse([XrpcSpaceRecoveryTestPack
      isAuthorizedRequest:[self requestWithAuthorization:@"Bearer wrong" remoteAddress:@"127.0.0.1"]
      environment:environment]);
  XCTAssertFalse([XrpcSpaceRecoveryTestPack
      isAuthorizedRequest:[self requestWithAuthorization:[@"Bearer " stringByAppendingString:token]
                                            remoteAddress:@"203.0.113.7"]
      environment:environment]);
}

- (void)testControlAcceptsOnlyRecoveryFixtureSpaces {
  XCTAssertTrue([XrpcSpaceRecoveryTestPack
      isFixtureSpaceURI:@"at://did:plc:authority/space/com.garazyk.permissioned/recovery-lightweight"]);
  XCTAssertFalse([XrpcSpaceRecoveryTestPack
      isFixtureSpaceURI:@"at://did:plc:authority/space/com.garazyk.permissioned/ordinary-space"]);
}

@end
