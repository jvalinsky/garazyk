// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoMUXLFMP4Tests.m

 @abstract Tests deterministic MUXL fMP4 init-header synthesis.
 */

#import <XCTest/XCTest.h>
#import "Video/ATProtoMUXLFMP4.h"
#import "MediaCore/ATProtoMUXLBox.h"
#import "MediaCore/ATProtoMUXLFragment.h"

@interface ATProtoMUXLFMP4Tests : XCTestCase
@end

@implementation ATProtoMUXLFMP4Tests

- (NSDictionary *)videoCatalogTrackID:(uint32_t)trackID
                                width:(uint32_t)width
                               height:(uint32_t)height {
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
                        @"trackId": @(trackID)
                    },
                    @"codedWidth": @(width),
                    @"codedHeight": @(height),
                    @"description": avcC
                }
            }
        }
    };
}

- (NSDictionary *)audioCatalogTrackID:(uint32_t)trackID {
    NSData *esds = [NSData dataWithBytes:(const uint8_t[]){
        0x00, 0x00, 0x00, 0x00, 0x03, 0x19, 0x00, 0x01, 0x00
    } length:9];
    return @{
        @"audio": @{
            @"renditions": @{
                @"main": @{
                    @"codec": @"mp4a.40.2",
                    @"container": @{
                        @"kind": @"cmaf",
                        @"timescale": @48000,
                        @"trackId": @(trackID)
                    },
                    @"sampleRate": @48000,
                    @"numberOfChannels": @2,
                    @"description": esds
                }
            }
        }
    };
}

- (void)testInitIsDeterministicAndValid {
    NSDictionary *catalog = [self videoCatalogTrackID:1 width:640 height:360];
    NSError *error = nil;
    NSData *first = [ATProtoMUXLFMP4 initSegmentWithCatalogs:@[catalog] error:&error];
    XCTAssertNotNil(first);
    XCTAssertNil(error);
    XCTAssertTrue([ATProtoMUXLFMP4 validateInitSegment:first error:&error]);
    XCTAssertNil(error);

    NSData *second = [ATProtoMUXLFMP4 initSegmentWithCatalogs:@[catalog] error:&error];
    XCTAssertEqualObjects(first, second);
}

- (void)testInitSortsTracksByTrackID {
    NSError *error = nil;
    NSData *init = [ATProtoMUXLFMP4 initSegmentWithCatalogs:@[
        [self audioCatalogTrackID:2],
        [self videoCatalogTrackID:1 width:320 height:180]
    ] error:&error];
    XCTAssertNotNil(init);
    XCTAssertNil(error);
    XCTAssertTrue([ATProtoMUXLFMP4 validateInitSegment:init error:&error]);

    // After ftyp, moov/mvhd, first trak should be track_id 1.
    const uint8_t *bytes = init.bytes;
    NSUInteger ftypSize = ((NSUInteger)bytes[0] << 24) | ((NSUInteger)bytes[1] << 16) |
                          ((NSUInteger)bytes[2] << 8) | bytes[3];
    NSUInteger offset = ftypSize + 8; // past moov header
    // mvhd
    NSUInteger mvhdSize = ((NSUInteger)bytes[offset] << 24) | ((NSUInteger)bytes[offset + 1] << 16) |
                          ((NSUInteger)bytes[offset + 2] << 8) | bytes[offset + 3];
    offset += mvhdSize;
    XCTAssertEqual(bytes[offset + 4], (uint8_t)'t');
    XCTAssertEqual(bytes[offset + 5], (uint8_t)'r');
    XCTAssertEqual(bytes[offset + 6], (uint8_t)'a');
    XCTAssertEqual(bytes[offset + 7], (uint8_t)'k');
    // tkhd track_id at fullbox header + creation/mod + track_id
    // trak(8) + tkhd size(4) + 'tkhd'(4) + vf(4) + creation(4) + mod(4) = 28 into trak body...
    NSUInteger tkhdTrackIDOffset = offset + 8 + 12 + 8;
    uint32_t trackID = ((uint32_t)bytes[tkhdTrackIDOffset] << 24) |
                       ((uint32_t)bytes[tkhdTrackIDOffset + 1] << 16) |
                       ((uint32_t)bytes[tkhdTrackIDOffset + 2] << 8) |
                       bytes[tkhdTrackIDOffset + 3];
    XCTAssertEqual(trackID, (uint32_t)1);
}

- (void)testPresentationPrependsWithoutAlteringSegments {
    NSDictionary *catalog = [self videoCatalogTrackID:1 width:640 height:360];
    ATProtoMUXLFragmentSample *sample = [[ATProtoMUXLFragmentSample alloc] init];
    sample.trackID = 1;
    sample.sequenceNumber = 1;
    sample.baseMediaDecodeTime = 0;
    sample.sampleDuration = 40;
    sample.sampleBytes = [NSData dataWithBytes:(const uint8_t[]){0x00, 0x01} length:2];
    sample.syncSample = YES;

    NSData *fragment = [ATProtoMUXLFragment fragmentWithSample:sample error:nil];
    NSData *segment = [ATProtoMUXLBox segmentWithCatalog:catalog fragments:@[fragment] error:nil];
    NSData *init = [ATProtoMUXLFMP4 initSegmentWithCatalogs:@[catalog] error:nil];

    NSError *error = nil;
    NSData *presentation = [ATProtoMUXLFMP4 presentationWithInit:init
                                                         segments:@[segment]
                                                            error:&error];
    XCTAssertNotNil(presentation);
    XCTAssertNil(error);
    XCTAssertEqualObjects([presentation subdataWithRange:NSMakeRange(0, init.length)], init);
    XCTAssertEqualObjects([presentation subdataWithRange:NSMakeRange(init.length, segment.length)],
                          segment);
}

- (void)testRejectsDuplicateTrackIDsAndUnsupportedCodec {
    NSError *error = nil;
    NSArray *dupes = @[
        [self videoCatalogTrackID:1 width:640 height:360],
        [self videoCatalogTrackID:1 width:320 height:180]
    ];
    NSData *dupeInit = [ATProtoMUXLFMP4 initSegmentWithCatalogs:dupes error:&error];
    XCTAssertNil(dupeInit);
    XCTAssertEqual(error.code, ATProtoMUXLFMP4ErrorDuplicateTrackID);

    NSDictionary *bad = @{
        @"video": @{
            @"renditions": @{
                @"main": @{
                    @"codec": @"vp09.00.10.08",
                    @"container": @{
                        @"kind": @"cmaf",
                        @"timescale": @1000,
                        @"trackId": @3
                    },
                    @"codedWidth": @64,
                    @"codedHeight": @64
                }
            }
        }
    };

    error = nil;
    NSData *badInit = [ATProtoMUXLFMP4 initSegmentWithCatalogs:@[bad] error:&error];
    XCTAssertNil(badInit);
    XCTAssertEqual(error.code, ATProtoMUXLFMP4ErrorUnsupportedCodec);
}

- (void)testRejectsEmptyCatalogList {
    NSError *error = nil;
    NSData *empty = [ATProtoMUXLFMP4 initSegmentWithCatalogs:@[] error:&error];
    XCTAssertNil(empty);
    XCTAssertEqual(error.code, ATProtoMUXLFMP4ErrorInvalidArgument);
}

- (NSData *)mintSegmentTrackID:(uint32_t)trackID
                      sync:(BOOL)sync
                       cto:(int32_t)cto
                     seq:(uint32_t)seq
                      dts:(uint64_t)dts {
    ATProtoMUXLFragmentSample *sample = [[ATProtoMUXLFragmentSample alloc] init];
    sample.trackID = trackID;
    sample.sequenceNumber = seq;
    sample.baseMediaDecodeTime = dts;
    sample.sampleDuration = 40;
    sample.sampleBytes = [NSData dataWithBytes:(const uint8_t[]){0x11, 0x22, 0x33} length:3];
    sample.syncSample = sync;
    sample.compositionTimeOffset = cto;
    NSData *fragment = [ATProtoMUXLFragment fragmentWithSample:sample error:nil];
    return [ATProtoMUXLBox segmentWithCatalog:[self videoCatalogTrackID:trackID width:640 height:360]
                                    fragments:@[fragment]
                                        error:nil];
}

- (void)testFlatMP4IsDeterministicAndPreservesSegmentBytes {
    NSData *seg1 = [self mintSegmentTrackID:1 sync:YES cto:0 seq:1 dts:0];
    NSData *seg2 = [self mintSegmentTrackID:1 sync:NO cto:10 seq:2 dts:40];
    NSError *error = nil;
    NSArray *segments = @[seg1, seg2];
    NSData *first = [ATProtoMUXLFMP4 flatMP4WithSegments:segments error:&error];
    XCTAssertNotNil(first);
    XCTAssertNil(error);

    NSData *second = [ATProtoMUXLFMP4 flatMP4WithSegments:segments error:&error];
    XCTAssertEqualObjects(first, second);

    // Trailing mdat payload must be the verbatim concatenation of segments.
    const uint8_t *bytes = first.bytes;
    NSUInteger offset = 0;
    uint32_t ftypSize = ((uint32_t)bytes[0] << 24) | ((uint32_t)bytes[1] << 16) |
                        ((uint32_t)bytes[2] << 8) | bytes[3];
    offset += ftypSize;
    uint32_t moovSize = ((uint32_t)bytes[offset] << 24) | ((uint32_t)bytes[offset + 1] << 16) |
                        ((uint32_t)bytes[offset + 2] << 8) | bytes[offset + 3];
    offset += moovSize;
    XCTAssertEqual(bytes[offset + 4], (uint8_t)'m');
    XCTAssertEqual(bytes[offset + 5], (uint8_t)'d');
    XCTAssertEqual(bytes[offset + 6], (uint8_t)'a');
    XCTAssertEqual(bytes[offset + 7], (uint8_t)'t');
    XCTAssertEqual(((uint32_t)bytes[offset] << 24) | ((uint32_t)bytes[offset + 1] << 16) |
                   ((uint32_t)bytes[offset + 2] << 8) | bytes[offset + 3], (uint32_t)1);
    NSMutableData *expected = [NSMutableData data];
    [expected appendData:seg1];
    [expected appendData:seg2];
    NSData *payload = [first subdataWithRange:NSMakeRange(offset + 16, expected.length)];
    XCTAssertEqualObjects(payload, expected);

    // Flat moov must not contain mvex.
    NSData *moov = [first subdataWithRange:NSMakeRange(ftypSize, moovSize)];
    NSData *mvex = [@"mvex" dataUsingEncoding:NSASCIIStringEncoding];
    NSRange found = [moov rangeOfData:mvex options:0 range:NSMakeRange(0, moov.length)];
    XCTAssertEqual(found.location, (NSUInteger)NSNotFound);

    // Non-sync samples require stss.
    NSData *stss = [@"stss" dataUsingEncoding:NSASCIIStringEncoding];
    found = [moov rangeOfData:stss options:0 range:NSMakeRange(0, moov.length)];
    XCTAssertNotEqual(found.location, (NSUInteger)NSNotFound);

    // Non-zero CTO requires ctts.
    NSData *ctts = [@"ctts" dataUsingEncoding:NSASCIIStringEncoding];
    found = [moov rangeOfData:ctts options:0 range:NSMakeRange(0, moov.length)];
    XCTAssertNotEqual(found.location, (NSUInteger)NSNotFound);

    // dts==0 → no edts/elst (presentation offset rides on first tfdt only when non-zero).
    NSData *edts = [@"edts" dataUsingEncoding:NSASCIIStringEncoding];
    found = [moov rangeOfData:edts options:0 range:NSMakeRange(0, moov.length)];
    XCTAssertEqual(found.location, (NSUInteger)NSNotFound);
}

- (void)testFlatMP4EmitsElstForNonZeroFirstTfdt {
    NSData *seg = [self mintSegmentTrackID:1 sync:YES cto:0 seq:1 dts:1000];
    NSError *error = nil;
    NSData *flat = [ATProtoMUXLFMP4 flatMP4WithSegments:@[seg] error:&error];
    XCTAssertNotNil(flat);
    XCTAssertNil(error);
    const uint8_t *bytes = flat.bytes;
    uint32_t ftypSize = ((uint32_t)bytes[0] << 24) | ((uint32_t)bytes[1] << 16) |
                        ((uint32_t)bytes[2] << 8) | bytes[3];
    uint32_t moovSize = ((uint32_t)bytes[ftypSize] << 24) | ((uint32_t)bytes[ftypSize + 1] << 16) |
                        ((uint32_t)bytes[ftypSize + 2] << 8) | bytes[ftypSize + 3];
    NSData *moov = [flat subdataWithRange:NSMakeRange(ftypSize, moovSize)];
    NSRange edts = [moov rangeOfData:[@"edts" dataUsingEncoding:NSASCIIStringEncoding]
                             options:0
                               range:NSMakeRange(0, moov.length)];
    XCTAssertNotEqual(edts.location, (NSUInteger)NSNotFound);
    NSRange elst = [moov rangeOfData:[@"elst" dataUsingEncoding:NSASCIIStringEncoding]
                             options:0
                               range:NSMakeRange(0, moov.length)];
    XCTAssertNotEqual(elst.location, (NSUInteger)NSNotFound);
    XCTAssertGreaterThanOrEqual(elst.location, (NSUInteger)4);
    // rangeOfData matches the type field; box starts 4 bytes earlier (size).
    const uint8_t *elstBytes = (const uint8_t *)moov.bytes + (elst.location - 4);
    uint32_t entryCount = ((uint32_t)elstBytes[12] << 24) | ((uint32_t)elstBytes[13] << 16) |
                          ((uint32_t)elstBytes[14] << 8) | elstBytes[15];
    XCTAssertEqual(entryCount, (uint32_t)2);
    uint32_t emptyDur = ((uint32_t)elstBytes[16] << 24) | ((uint32_t)elstBytes[17] << 16) |
                        ((uint32_t)elstBytes[18] << 8) | elstBytes[19];
    XCTAssertEqual(emptyDur, (uint32_t)1000); // dts 1000 @ timescale 1000 → movie ts 1000
    int32_t mediaTime0 = (int32_t)(((uint32_t)elstBytes[20] << 24) | ((uint32_t)elstBytes[21] << 16) |
                                   ((uint32_t)elstBytes[22] << 8) | elstBytes[23]);
    XCTAssertEqual(mediaTime0, (int32_t)-1);
}

- (void)testFlatMP4OmitsElstWhenOnlyCTONonZero {
    NSData *seg = [self mintSegmentTrackID:1 sync:YES cto:10 seq:1 dts:0];
    NSError *error = nil;
    NSData *flat = [ATProtoMUXLFMP4 flatMP4WithSegments:@[seg] error:&error];
    XCTAssertNotNil(flat);
    const uint8_t *bytes = flat.bytes;
    uint32_t ftypSize = ((uint32_t)bytes[0] << 24) | ((uint32_t)bytes[1] << 16) |
                        ((uint32_t)bytes[2] << 8) | bytes[3];
    uint32_t moovSize = ((uint32_t)bytes[ftypSize] << 24) | ((uint32_t)bytes[ftypSize + 1] << 16) |
                        ((uint32_t)bytes[ftypSize + 2] << 8) | bytes[ftypSize + 3];
    NSData *moov = [flat subdataWithRange:NSMakeRange(ftypSize, moovSize)];
    NSRange edts = [moov rangeOfData:[@"edts" dataUsingEncoding:NSASCIIStringEncoding]
                             options:0
                               range:NSMakeRange(0, moov.length)];
    XCTAssertEqual(edts.location, (NSUInteger)NSNotFound);
    NSRange ctts = [moov rangeOfData:[@"ctts" dataUsingEncoding:NSASCIIStringEncoding]
                             options:0
                               range:NSMakeRange(0, moov.length)];
    XCTAssertNotEqual(ctts.location, (NSUInteger)NSNotFound);
}

- (void)testFlatMP4RejectsEmptyInput {
    NSError *error = nil;
    NSData *empty = [ATProtoMUXLFMP4 flatMP4WithSegments:@[] error:&error];
    XCTAssertNil(empty);
    XCTAssertEqual(error.code, ATProtoMUXLFMP4ErrorInvalidArgument);
}

@end
