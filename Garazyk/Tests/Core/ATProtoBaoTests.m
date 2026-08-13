// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Core/ATProtoBao.h"

@interface ATProtoBaoTests : XCTestCase
@end

@implementation ATProtoBaoTests

- (NSData *)inputOfLength:(NSUInteger)len {
    NSMutableData *data = [NSMutableData dataWithCapacity:len];
    uint32_t counter = 1;
    while (data.length < len) {
        uint8_t bytes[4];
        bytes[0] = (uint8_t)(counter & 0xff);
        bytes[1] = (uint8_t)((counter >> 8) & 0xff);
        bytes[2] = (uint8_t)((counter >> 16) & 0xff);
        bytes[3] = (uint8_t)((counter >> 24) & 0xff);
        NSUInteger take = MIN((NSUInteger)4, len - data.length);
        [data appendBytes:bytes length:take];
        counter += 1;
    }
    return data;
}

- (NSData *)hexData:(NSString *)hex {
    NSMutableData *data = [NSMutableData dataWithCapacity:hex.length / 2];
    for (NSUInteger i = 0; i + 1 < hex.length; i += 2) {
        NSString *byteStr = [hex substringWithRange:NSMakeRange(i, 2)];
        unsigned int byte = 0;
        [[NSScanner scannerWithString:byteStr] scanHexInt:&byte];
        uint8_t b = (uint8_t)byte;
        [data appendBytes:&b length:1];
    }
    return data;
}

- (void)assertRoundTripLength:(NSUInteger)len
                   expectHash:(NSString *)hashHex
               expectOutboard:(NSString *)outboardHex {
    NSData *input = [self inputOfLength:len];
    NSData *hash = [ATProtoBao hashForData:input];
    XCTAssertEqualObjects(hash, [self hexData:hashHex]);

    NSError *error = nil;
    NSData *outboard = [ATProtoBao outboardForData:input error:&error];
    XCTAssertNotNil(outboard);
    XCTAssertNil(error);
    XCTAssertEqualObjects(outboard, [self hexData:outboardHex]);

    NSUInteger offset = (len > 1024) ? 1000 : 0;
    NSUInteger length = (len == 0) ? 0 : MIN((NSUInteger)500, len - offset);
    NSData *slice = [ATProtoBao sliceFromData:input
                                     outboard:outboard
                                       offset:offset
                                       length:length
                                        error:&error];
    XCTAssertNotNil(slice);
    NSData *verified = [ATProtoBao verifiedContentFromSlice:slice
                                               expectedHash:hash
                                                     offset:offset
                                                     length:length
                                                      error:&error];
    XCTAssertNotNil(verified);
    NSData *expected = [input subdataWithRange:NSMakeRange(offset, length)];
    XCTAssertEqualObjects(verified, expected);
}

- (void)testGoldenOutboardsAndVerifiedRanges {
    [self assertRoundTripLength:0
                     expectHash:@"af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262"
                 expectOutboard:@"0000000000000000"];
    [self assertRoundTripLength:1
                     expectHash:@"48fc721fbbc172e0925fa27af1671de225ba927134802998b10a1568a188652b"
                 expectOutboard:@"0100000000000000"];
    [self assertRoundTripLength:10
                     expectHash:@"6f1ca176d22a5f5d95e37c19be70cd097e4f4a08476c16b1a138ff803653a979"
                 expectOutboard:@"0a00000000000000"];
    [self assertRoundTripLength:1024
                     expectHash:@"f749c19181983b839cd97fe121cebaf076bc951e8c8e6d64accfedad5951ec22"
                 expectOutboard:@"0004000000000000"];
    [self assertRoundTripLength:1025
                     expectHash:@"3613596275c4ea790774dedf20835b2daf86cacc892feef6ce720c121572f1f9"
                 expectOutboard:@"01040000000000009752ec9fb343f7a8747ab5c0d0bcbf317290cf8e13bbd40957952e4a4a47d414643001556307bf5cfc148606fe13db12de819738b541235c75800ecfc991e96a"];
    [self assertRoundTripLength:2048
                     expectHash:@"fed8b40d6095dc7c5061f9cd832fd192337473bd392bf6f6bbaf1261ea78f8fa"
                 expectOutboard:@"00080000000000009752ec9fb343f7a8747ab5c0d0bcbf317290cf8e13bbd40957952e4a4a47d414d1cd6fae144638c4415a2de59dc2bf5c01429027eb1872d96aaa03d188280c45"];
    [self assertRoundTripLength:2049
                     expectHash:@"64770fa15a4bbe7770654c4ac68ed4f0e975ad6c85b5edb4d3db3b4b604e084e"
                 expectOutboard:@"0108000000000000166958cc8f405e4956f4ab8ae28461e2342253c32dd369bb7f01cd189fba431e7aeeb24825097e6c25439faa83c183d485abead271d8a84f247e536fbecfaa959752ec9fb343f7a8747ab5c0d0bcbf317290cf8e13bbd40957952e4a4a47d414d1cd6fae144638c4415a2de59dc2bf5c01429027eb1872d96aaa03d188280c45"];
}

- (void)testTamperedSliceRejected {
    NSData *input = [self inputOfLength:2048];
    NSData *hash = [ATProtoBao hashForData:input];
    NSError *error = nil;
    NSData *outboard = [ATProtoBao outboardForData:input error:&error];
    NSData *slice = [ATProtoBao sliceFromData:input outboard:outboard offset:1000 length:500 error:&error];
    NSMutableData *bad = [slice mutableCopy];
    uint8_t *bytes = bad.mutableBytes;
    bytes[bad.length - 1] ^= 0x01;
    NSData *verified = [ATProtoBao verifiedContentFromSlice:bad
                                               expectedHash:hash
                                                     offset:1000
                                                     length:500
                                                      error:&error];
    XCTAssertNil(verified);
    XCTAssertEqual(error.code, ATProtoBaoErrorHashMismatch);
}

- (void)testWrongOffsetRejected {
    NSData *input = [self inputOfLength:2048];
    NSData *hash = [ATProtoBao hashForData:input];
    NSError *error = nil;
    NSData *outboard = [ATProtoBao outboardForData:input error:&error];
    // Slice only needs the second chunk; claiming offset 0 requires the first.
    NSData *slice = [ATProtoBao sliceFromData:input outboard:outboard offset:1500 length:100 error:&error];
    NSData *verified = [ATProtoBao verifiedContentFromSlice:slice
                                               expectedHash:hash
                                                     offset:0
                                                     length:100
                                                      error:&error];
    XCTAssertNil(verified);
}

- (void)testTruncatedSliceRejected {
    NSData *input = [self inputOfLength:1025];
    NSData *hash = [ATProtoBao hashForData:input];
    NSError *error = nil;
    NSData *outboard = [ATProtoBao outboardForData:input error:&error];
    NSData *slice = [ATProtoBao sliceFromData:input outboard:outboard offset:0 length:100 error:&error];
    NSData *truncated = [slice subdataWithRange:NSMakeRange(0, MIN((NSUInteger)16, slice.length))];
    NSData *verified = [ATProtoBao verifiedContentFromSlice:truncated
                                               expectedHash:hash
                                                     offset:0
                                                     length:100
                                                      error:&error];
    XCTAssertNil(verified);
}

@end
