// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoMUXLTranscoderBridgeTests.m

 @abstract Tests CMAF/HLS → MUXL packaging bridge.
 */

#import <XCTest/XCTest.h>
#import "Video/ATProtoMUXLTranscoderBridge.h"
#import "Video/ATProtoMUXLPlayback.h"
#import "Video/ATProtoMUXLFMP4.h"
#import "MediaCore/ATProtoMUXLBox.h"
#import "MediaCore/ATProtoMUXLFragment.h"

@interface ATProtoMUXLTranscoderBridgeTests : XCTestCase
@end

@implementation ATProtoMUXLTranscoderBridgeTests

- (NSDictionary *)videoCatalog {
    NSData *avcC = [NSData dataWithBytes:(const uint8_t[]){
        0x01, 0x64, 0x00, 0x1f, 0xff, 0xe1, 0x00, 0x04,
        0x67, 0x64, 0x00, 0x1f, 0x01, 0x00, 0x04, 0x68, 0xee, 0x3c, 0xb0
    } length:19];
    return @{
        @"video": @{
            @"renditions": @{
                @"main": @{
                    @"codec": @"avc1.64001f",
                    @"container": @{
                        @"kind": @"cmaf",
                        @"timescale": @1000,
                        @"trackId": @1
                    },
                    @"codedWidth": @640,
                    @"codedHeight": @360,
                    @"description": avcC
                }
            }
        }
    };
}

- (NSData *)mintFragmentSeq:(uint32_t)seq dts:(uint64_t)dts {
    ATProtoMUXLFragmentSample *sample = [[ATProtoMUXLFragmentSample alloc] init];
    sample.trackID = 1;
    sample.sequenceNumber = seq;
    sample.baseMediaDecodeTime = dts;
    sample.sampleDuration = 40;
    sample.sampleBytes = [NSData dataWithBytes:(const uint8_t[]){0x11, 0x22} length:2];
    sample.syncSample = (seq == 1);
    return [ATProtoMUXLFragment fragmentWithSample:sample error:nil];
}

- (void)testCatalogRoundTripFromMUXLInit {
    NSDictionary *catalog = [self videoCatalog];
    NSError *error = nil;
    NSData *init = [ATProtoMUXLFMP4 initSegmentWithCatalogs:@[catalog] error:&error];
    XCTAssertNotNil(init, @"%@", error);

    NSDictionary *recovered = [ATProtoMUXLTranscoderBridge catalogFromCMAFInit:init error:&error];
    XCTAssertNotNil(recovered, @"%@", error);
    NSDictionary *main = recovered[@"video"][@"renditions"][@"main"];
    XCTAssertEqualObjects(main[@"container"][@"trackId"], @1);
    XCTAssertEqualObjects(main[@"container"][@"timescale"], @1000);
    XCTAssertEqualObjects(main[@"codedWidth"], @640);
    XCTAssertEqualObjects(main[@"codedHeight"], @360);
    XCTAssertEqualObjects(main[@"description"], catalog[@"video"][@"renditions"][@"main"][@"description"]);
}

- (void)testPackageHLSVariantDirectoryProducesPlaybackableArtifacts {
    NSDictionary *catalog = [self videoCatalog];
    NSData *init = [ATProtoMUXLFMP4 initSegmentWithCatalogs:@[catalog] error:nil];
    NSData *frag1 = [self mintFragmentSeq:1 dts:0];
    NSData *frag2 = [self mintFragmentSeq:2 dts:40];

    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                     [[NSUUID UUID] UUIDString]];
    XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtPath:dir
                                            withIntermediateDirectories:YES
                                                             attributes:nil
                                                                  error:nil]);
    XCTAssertTrue([init writeToFile:[dir stringByAppendingPathComponent:@"init.mp4"]
                         atomically:YES]);
    XCTAssertTrue([frag1 writeToFile:[dir stringByAppendingPathComponent:@"segment_00000.m4s"]
                          atomically:YES]);
    XCTAssertTrue([frag2 writeToFile:[dir stringByAppendingPathComponent:@"segment_00001.m4s"]
                          atomically:YES]);

    NSError *error = nil;
    NSDictionary *packaged = [ATProtoMUXLTranscoderBridge packageHLSVariantDirectory:dir
                                                                               error:&error];
    XCTAssertNotNil(packaged, @"%@", error);
    XCTAssertNotNil(packaged[@"presentation"]);
    XCTAssertNotNil(packaged[@"flat"]);
    XCTAssertEqual([(NSArray *)packaged[@"segments"] count], 2u);
    XCTAssertTrue([ATProtoMUXLPlayback validateFMP4Presentation:packaged[@"presentation"]
                                                          error:&error],
                  @"%@", error);
    XCTAssertTrue([ATProtoMUXLPlayback validateFlatMP4Presentation:packaged[@"flat"]
                                                             error:&error],
                  @"%@", error);

    NSDictionary *written = [ATProtoMUXLTranscoderBridge writePackage:packaged
                                                          toDirectory:dir
                                                                error:&error];
    XCTAssertNotNil(written, @"%@", error);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:written[@"init"]]);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:written[@"presentation"]]);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:written[@"flat"]]);
    XCTAssertEqual([(NSArray *)written[@"segments"] count], 2u);

    [[NSFileManager defaultManager] removeItemAtPath:dir error:nil];
}

- (void)testRejectsMissingInit {
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                     [[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    NSError *error = nil;
    XCTAssertNil([ATProtoMUXLTranscoderBridge packageHLSVariantDirectory:dir error:&error]);
    XCTAssertEqual(error.code, ATProtoMUXLTranscoderBridgeErrorInvalidArgument);
    [[NSFileManager defaultManager] removeItemAtPath:dir error:nil];
}

@end
