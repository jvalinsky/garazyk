// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "App/ATProtoServiceConfiguration.h"
#import "Identity/ATProtoHandleValidator.h"
#import "Network/XrpcIdentityHelper.h"

@interface XrpcIdentityResolutionTests : XCTestCase
@end

@implementation XrpcIdentityResolutionTests

- (void)testHandleNormalization {
    XCTAssertEqualObjects([ATProtoHandleValidator normalizeHandle:@"LUNA.TEST"], @"luna.test");
    XCTAssertEqualObjects([ATProtoHandleValidator normalizeHandle:@"luna.test"], @"luna.test");
}

- (void)testExperimentalSpaceHostIsPublishedWithConfiguredPeerEndpoint {
    ATProtoServiceConfiguration *configuration =
        [self configurationWithSpaceHostEndpoint:@"http://spaces.internal:2583"];
    NSDictionary *services = [XrpcIdentityHelper defaultPdsServiceForConfig:configuration];

    XCTAssertEqualObjects(services[@"atproto_pds"][@"endpoint"], @"https://pds.public.example");
    XCTAssertEqualObjects(services[@"atproto_space_host"][@"endpoint"],
                          @"http://spaces.internal:2583");
}

- (void)testExperimentalSpaceHostRejectsUnsafeConfiguredEndpoint {
    ATProtoServiceConfiguration *configuration =
        [self configurationWithSpaceHostEndpoint:@"https://user@spaces.internal:2583/?token=secret"];
    NSDictionary *services = [XrpcIdentityHelper defaultPdsServiceForConfig:configuration];

    XCTAssertEqualObjects(services[@"atproto_space_host"][@"endpoint"],
                          @"https://pds.public.example");
}

- (ATProtoServiceConfiguration *)configurationWithSpaceHostEndpoint:(NSString *)spaceHostEndpoint {
    NSDictionary *contents = @{
        @"permissionedSpacesEnabled" : @YES,
        @"permissionedSpacesHostEndpoint" : spaceHostEndpoint,
        @"server" : @{ @"issuer" : @"https://pds.public.example" }
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:contents options:0 error:nil];
    NSString *path = [NSTemporaryDirectory()
        stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    XCTAssertTrue([data writeToFile:path atomically:YES]);

    NSError *error = nil;
    ATProtoServiceConfiguration *configuration =
        [ATProtoServiceConfiguration configurationWithPath:path error:&error];
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    XCTAssertNil(error);
    XCTAssertNotNil(configuration);
    return configuration;
}

@end
