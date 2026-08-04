// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoMUXLBoxTests.m

 @abstract Tests the bounded deterministic MUXL catalog atom primitive.
 */

#import <XCTest/XCTest.h>
#import "MediaCore/ATProtoMUXLBox.h"

@interface ATProtoMUXLBoxTests : XCTestCase
@end

@implementation ATProtoMUXLBoxTests

- (NSDictionary *)videoCatalog {
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
                    @"codedWidth": @1920,
                    @"codedHeight": @1080
                }
            }
        }
    };
}

- (NSData *)boxWithType:(NSString *)type body:(NSData *)body {
    NSMutableData *box = [NSMutableData data];
    uint32_t size = (uint32_t)(8 + body.length);
    uint8_t header[8] = {
        (uint8_t)(size >> 24), (uint8_t)(size >> 16),
        (uint8_t)(size >> 8), (uint8_t)size,
        0, 0, 0, 0
    };
    NSData *typeData = [type dataUsingEncoding:NSASCIIStringEncoding];
    [box appendBytes:header length:4];
    [box appendData:typeData];
    [box appendData:body];
    return box;
}

- (void)testUUIDMuxlBoxRoundTripsDeterministically {
    NSDictionary *catalog = [self videoCatalog];
    NSError *error = nil;
    NSData *box = [ATProtoMUXLBox uuidMuxlBoxWithCatalog:catalog error:&error];
    XCTAssertNotNil(box);
    XCTAssertNil(error);

    NSDictionary *decoded = [ATProtoMUXLBox catalogFromUUIDMuxlBox:box error:&error];
    XCTAssertEqualObjects(decoded, catalog);
    XCTAssertNil(error);

    NSData *second = [ATProtoMUXLBox uuidMuxlBoxWithCatalog:decoded error:&error];
    XCTAssertEqualObjects(second, box);
    XCTAssertNil(error);
}

- (void)testUUIDBoxUsesNormativeTypeAndIdentifier {
    NSData *box = [ATProtoMUXLBox uuidMuxlBoxWithCatalog:[self videoCatalog] error:nil];
    const uint8_t *sizeBytes = box.bytes;
    uint32_t encodedSize = ((uint32_t)sizeBytes[0] << 24) |
                           ((uint32_t)sizeBytes[1] << 16) |
                           ((uint32_t)sizeBytes[2] << 8) |
                           sizeBytes[3];
    XCTAssertGreaterThanOrEqual(box.length, 24U);
    XCTAssertEqual(encodedSize, (uint32_t)box.length);
    const uint8_t *bytes = box.bytes;
    XCTAssertEqual(bytes[4], (uint8_t)'u');
    XCTAssertEqual(bytes[5], (uint8_t)'u');
    XCTAssertEqual(bytes[6], (uint8_t)'i');
    XCTAssertEqual(bytes[7], (uint8_t)'d');
    XCTAssertEqualObjects([NSData dataWithBytes:bytes + 8 length:16], [ATProtoMUXLBox muxlUUID]);
}

- (void)testCatalogRequiresExactlyOneTrackKindAndRendition {
    NSError *error = nil;
    NSDictionary *both = @{
        @"video": @{@"renditions": @{@"main": @{@"codec": @"x", @"container": @{@"kind": @"cmaf", @"timescale": @1, @"trackId": @1}, @"codedWidth": @1, @"codedHeight": @1}}},
        @"audio": @{@"renditions": @{@"main": @{@"codec": @"x", @"container": @{@"kind": @"cmaf", @"timescale": @1, @"trackId": @1}, @"sampleRate": @1, @"numberOfChannels": @1}}}
    };
    XCTAssertNil([ATProtoMUXLBox uuidMuxlBoxWithCatalog:both error:&error]);
    XCTAssertEqual(error.code, ATProtoMUXLErrorInvalidCatalog);

    error = nil;
    NSMutableDictionary *multiple = [[self videoCatalog] mutableCopy];
    multiple[@"video"] = @{@"renditions": @{
        @"a": [self videoCatalog][@"video"][@"renditions"][@"main"],
        @"b": [self videoCatalog][@"video"][@"renditions"][@"main"]
    }};
    XCTAssertNil([ATProtoMUXLBox uuidMuxlBoxWithCatalog:multiple error:&error]);
    XCTAssertEqual(error.code, ATProtoMUXLErrorInvalidCatalog);
}

- (void)testSegmentPreservesOpaqueMoofAndMdatBytes {
    NSData *moof = [self boxWithType:@"moof" body:[NSData dataWithBytes:(const uint8_t[]) {0xde, 0xad} length:2]];
    NSData *mdat = [self boxWithType:@"mdat" body:[NSData dataWithBytes:(const uint8_t[]) {0xca, 0xfe, 0xba, 0xbe} length:4]];
    NSMutableData *fragment = [moof mutableCopy];
    [fragment appendData:mdat];

    NSError *error = nil;
    NSData *segment = [ATProtoMUXLBox segmentWithCatalog:[self videoCatalog]
                                               fragments:@[fragment]
                                                   error:&error];
    XCTAssertNotNil(segment);
    XCTAssertNil(error);
    NSData *box = [ATProtoMUXLBox uuidMuxlBoxWithCatalog:[self videoCatalog] error:&error];
    XCTAssertEqualObjects([segment subdataWithRange:NSMakeRange(box.length, fragment.length)], fragment);
}

- (void)testSegmentRejectsWrongFragmentShape {
    NSData *notMoof = [self boxWithType:@"free" body:[NSData data]];
    NSError *error = nil;
    XCTAssertNil([ATProtoMUXLBox segmentWithCatalog:[self videoCatalog]
                                          fragments:@[notMoof]
                                              error:&error]);
    XCTAssertEqual(error.code, ATProtoMUXLErrorInvalidBox);
}

- (void)testUUIDBoxRejectsWrongSizeTypeAndUUID {
    NSData *valid = [ATProtoMUXLBox uuidMuxlBoxWithCatalog:[self videoCatalog] error:nil];
    NSMutableData *wrongType = [valid mutableCopy];
    uint8_t type[] = {'f', 'r', 'e', 'e'};
    [wrongType replaceBytesInRange:NSMakeRange(4, 4) withBytes:type];
    NSError *error = nil;
    XCTAssertNil([ATProtoMUXLBox catalogFromUUIDMuxlBox:wrongType error:&error]);
    XCTAssertEqual(error.code, ATProtoMUXLErrorInvalidBox);

    error = nil;
    NSMutableData *wrongUUID = [valid mutableCopy];
    uint8_t replacement = 0xff;
    [wrongUUID replaceBytesInRange:NSMakeRange(8, 1) withBytes:&replacement];
    XCTAssertNil([ATProtoMUXLBox catalogFromUUIDMuxlBox:wrongUUID error:&error]);
    XCTAssertEqual(error.code, ATProtoMUXLErrorInvalidBox);

    error = nil;
    NSData *truncated = [valid subdataWithRange:NSMakeRange(0, valid.length - 1)];
    XCTAssertNil([ATProtoMUXLBox catalogFromUUIDMuxlBox:truncated error:&error]);
    XCTAssertEqual(error.code, ATProtoMUXLErrorInvalidBox);
}

@end
