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
