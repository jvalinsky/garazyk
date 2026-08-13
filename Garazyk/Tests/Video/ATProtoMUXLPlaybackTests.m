// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoMUXLPlaybackTests.m

 @abstract Playback-sanity tests for MUXL fMP4 and Flat presentations.
 */

#import <XCTest/XCTest.h>
#import "Video/ATProtoMUXLPlayback.h"
#import "Video/ATProtoMUXLFMP4.h"
#import "MediaCore/ATProtoMUXLBox.h"
#import "MediaCore/ATProtoMUXLFragment.h"

@interface ATProtoMUXLPlaybackTests : XCTestCase
@end

@implementation ATProtoMUXLPlaybackTests

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

- (NSData *)mintSegmentSeq:(uint32_t)seq dts:(uint64_t)dts sync:(BOOL)sync {
    ATProtoMUXLFragmentSample *sample = [[ATProtoMUXLFragmentSample alloc] init];
    sample.trackID = 1;
    sample.sequenceNumber = seq;
    sample.baseMediaDecodeTime = dts;
    sample.sampleDuration = 40;
    sample.sampleBytes = [NSData dataWithBytes:(const uint8_t[]){0xaa, 0xbb, 0xcc} length:3];
    sample.syncSample = sync;
    NSData *fragment = [ATProtoMUXLFragment fragmentWithSample:sample error:nil];
    return [ATProtoMUXLBox segmentWithCatalog:[self videoCatalog]
                                    fragments:@[fragment]
                                        error:nil];
}

- (void)testFMP4PresentationValidates {
    NSDictionary *catalog = [self videoCatalog];
    NSData *seg1 = [self mintSegmentSeq:1 dts:0 sync:YES];
    NSData *seg2 = [self mintSegmentSeq:2 dts:40 sync:NO];
    NSData *init = [ATProtoMUXLFMP4 initSegmentWithCatalogs:@[catalog] error:nil];
    NSError *error = nil;
    NSData *presentation = [ATProtoMUXLFMP4 presentationWithInit:init
                                                        segments:@[seg1, seg2]
                                                           error:&error];
    XCTAssertNotNil(presentation);
    XCTAssertTrue([ATProtoMUXLPlayback validateFMP4Presentation:presentation error:&error],
                  @"%@", error);
    NSData *recovered = [ATProtoMUXLPlayback canonicalSegmentsFromPresentation:presentation
                                                                         error:&error];
    XCTAssertNotNil(recovered);
    NSMutableData *expected = [NSMutableData data];
    [expected appendData:seg1];
    [expected appendData:seg2];
    XCTAssertEqualObjects(recovered, expected);
}

- (void)testFlatPresentationValidatesAndRoundTrips {
    NSData *seg1 = [self mintSegmentSeq:1 dts:0 sync:YES];
    NSData *seg2 = [self mintSegmentSeq:2 dts:40 sync:NO];
    NSError *error = nil;
    NSData *flat = [ATProtoMUXLFMP4 flatMP4WithSegments:@[seg1, seg2] error:&error];
    XCTAssertNotNil(flat);
    XCTAssertTrue([ATProtoMUXLPlayback validateFlatMP4Presentation:flat error:&error], @"%@", error);
}

- (void)testSplitSegmentsRejectsIncompleteStream {
    NSData *seg = [self mintSegmentSeq:1 dts:0 sync:YES];
    NSData *truncated = [seg subdataWithRange:NSMakeRange(0, seg.length - 1)];
    NSError *error = nil;
    XCTAssertNil([ATProtoMUXLPlayback splitSegments:truncated error:&error]);
    XCTAssertEqual(error.code, ATProtoMUXLPlaybackErrorInvalidSegment);
}

@end
