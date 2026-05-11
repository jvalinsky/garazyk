// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Federation/FederationClient.h"

NS_ASSUME_NONNULL_BEGIN

@interface TestDIDResolver : NSObject
@property (nonatomic, copy, nullable) NSDictionary *result;
@end

@implementation TestDIDResolver
- (NSDictionary *)resolveAtprotoDataForDID:(NSString *)did error:(NSError **)error {
    return self.result;
}
@end

@interface FederationClientTests : XCTestCase
@end

#ifndef GNUSTEP
@implementation FederationClientTests

- (void)testForwardXrpcRequestFailsWhenDIDResolutionFails {
    FederationClient *client = [[FederationClient alloc] init];
    TestDIDResolver *resolver = [[TestDIDResolver alloc] init];
    resolver.result = nil;
    client.didResolver = resolver;

    XCTestExpectation *done = [self expectationWithDescription:@"completion"];
    [client forwardXrpcRequest:@"com.atproto.repo.getRecord"
                    parameters:@{@"repo": @"did:plc:missing"}
                           did:@"did:plc:missing"
                    completion:^(NSDictionary * _Nullable response, NSError * _Nullable error) {
        XCTAssertNil(response);
        XCTAssertNotNil(error);
        XCTAssertEqual(error.code, FederationErrorDIDResolutionFailed);
        [done fulfill];
    }];

    [self waitForExpectations:@[done] timeout:1.0];
}

@end
#endif

NS_ASSUME_NONNULL_END
