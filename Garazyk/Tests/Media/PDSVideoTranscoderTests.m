// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Video/VideoTranscoder.h"
#import "Video/VideoTranscoderBackend.h"
#import <AVFoundation/AVFoundation.h>

@interface ATProtoVideoTranscoderTests : XCTestCase
@property (nonatomic, strong) ATProtoVideoTranscoder *transcoder;
@end

@implementation ATProtoVideoTranscoderTests

- (void)setUp {
    [super setUp];
    // Use fresh instance instead of shared singleton to avoid state leakage
    self.transcoder = [[ATProtoVideoTranscoder alloc] init];
}

- (void)tearDown {
    self.transcoder = nil;
    [super tearDown];
}

#pragma mark - Error Domain

- (void)testErrorDomain {
    XCTAssertEqualObjects(ATProtoVideoTranscoderErrorDomain, @"com.atproto.video.transcoder");
}

#pragma mark - Singleton

- (void)testSharedTranscoderIsSingleton {
    ATProtoVideoTranscoder *a = [ATProtoVideoTranscoder sharedTranscoder];
    ATProtoVideoTranscoder *b = [ATProtoVideoTranscoder sharedTranscoder];
    XCTAssertEqual(a, b);
}

#pragma mark - Configuration

- (void)testMaxConcurrentExportsDefault {
    XCTAssertEqual(self.transcoder.maxConcurrentExports, 2);
}

#pragma mark - Cancel

- (void)testCancelAllExports {
    // Should not crash when called with no active exports
    [self.transcoder cancelAllExports];

    // Should not crash when called again
    [self.transcoder cancelAllExports];
}

@end
