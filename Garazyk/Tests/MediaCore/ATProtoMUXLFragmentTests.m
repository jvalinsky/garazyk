// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoMUXLFragmentTests.m

 @abstract Tests deterministic MUXL fragment minting and nested validation.
 */

#import <XCTest/XCTest.h>
#import "MediaCore/ATProtoMUXLFragment.h"
#import "MediaCore/ATProtoMUXLBox.h"

@interface ATProtoMUXLFragmentTests : XCTestCase
@end

@implementation ATProtoMUXLFragmentTests

- (ATProtoMUXLFragmentSample *)sampleSync:(BOOL)sync cto:(int32_t)cto {
    ATProtoMUXLFragmentSample *sample = [[ATProtoMUXLFragmentSample alloc] init];
    sample.trackID = 1;
    sample.sequenceNumber = 1;
    sample.baseMediaDecodeTime = 1000;
    sample.sampleDuration = 40;
    sample.sampleBytes = [NSData dataWithBytes:(const uint8_t[]){0x00, 0x01, 0x02, 0xaa} length:4];
    sample.syncSample = sync;
    sample.compositionTimeOffset = cto;
    return sample;
}

- (void)testMintedFragmentIsDeterministicAndValid {
    ATProtoMUXLFragmentSample *sample = [self sampleSync:YES cto:0];
    NSError *error = nil;
    NSData *first = [ATProtoMUXLFragment fragmentWithSample:sample error:&error];
    XCTAssertNotNil(first);
    XCTAssertNil(error);
    XCTAssertTrue([ATProtoMUXLFragment validateFragment:first error:&error]);
    XCTAssertNil(error);

    NSData *second = [ATProtoMUXLFragment fragmentWithSample:sample error:&error];
    XCTAssertEqualObjects(first, second);
}

- (void)testMintedFragmentComposesIntoMUXLSegment {
    NSData *fragment = [ATProtoMUXLFragment fragmentWithSample:[self sampleSync:YES cto:0]
                                                         error:nil];
    NSDictionary *catalog = @{
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
                    @"codedHeight": @360
                }
            }
        }
    };
    NSError *error = nil;
    NSData *segment = [ATProtoMUXLBox segmentWithCatalog:catalog
                                               fragments:@[fragment]
                                                   error:&error];
    XCTAssertNotNil(segment);
    XCTAssertNil(error);
}

- (void)testCompositionTimeOffsetUsesVersion1Trun {
    NSData *fragment = [ATProtoMUXLFragment fragmentWithSample:[self sampleSync:NO cto:10]
                                                         error:nil];
    XCTAssertTrue([ATProtoMUXLFragment validateFragment:fragment error:nil]);
    // Locate trun version byte: after moof/mfhd/traf/tfhd/tfdt headers.
    const uint8_t *bytes = fragment.bytes;
    NSUInteger offset = 8; // past moof header
    offset += 16; // mfhd
    offset += 8; // traf header
    offset += 16; // tfhd
    offset += 20; // tfdt
    XCTAssertEqual(bytes[offset + 4], (uint8_t)'t');
    XCTAssertEqual(bytes[offset + 5], (uint8_t)'r');
    XCTAssertEqual(bytes[offset + 6], (uint8_t)'u');
    XCTAssertEqual(bytes[offset + 7], (uint8_t)'n');
    XCTAssertEqual(bytes[offset + 8], 1); // version
}

- (void)testRejectsZeroSequenceAndEmptySample {
    ATProtoMUXLFragmentSample *sample = [self sampleSync:YES cto:0];
    sample.sequenceNumber = 0;
    NSError *error = nil;
    XCTAssertNil([ATProtoMUXLFragment fragmentWithSample:sample error:&error]);
    XCTAssertEqual(error.code, ATProtoMUXLFragmentErrorInvalidArgument);

    sample = [self sampleSync:YES cto:0];
    sample.sampleBytes = [NSData data];
    error = nil;
    XCTAssertNil([ATProtoMUXLFragment fragmentWithSample:sample error:&error]);
    XCTAssertEqual(error.code, ATProtoMUXLFragmentErrorInvalidArgument);
}

- (void)testValidateRejectsOpaqueMoofBody {
    uint8_t body[] = {0xde, 0xad};
    NSMutableData *moof = [NSMutableData data];
    uint32_t size = 10;
    uint8_t header[8] = {
        (uint8_t)(size >> 24), (uint8_t)(size >> 16),
        (uint8_t)(size >> 8), (uint8_t)size,
        'm', 'o', 'o', 'f'
    };
    [moof appendBytes:header length:8];
    [moof appendBytes:body length:2];
    NSMutableData *mdat = [NSMutableData data];
    uint8_t mdatHeader[8] = {0, 0, 0, 12, 'm', 'd', 'a', 't'};
    [mdat appendBytes:mdatHeader length:8];
    [mdat appendBytes:(const uint8_t[]){1, 2, 3, 4} length:4];
    NSMutableData *fragment = [moof mutableCopy];
    [fragment appendData:mdat];
    NSError *error = nil;
    XCTAssertFalse([ATProtoMUXLFragment validateFragment:fragment error:&error]);
    XCTAssertEqual(error.code, ATProtoMUXLFragmentErrorInvalidStructure);
}

@end
