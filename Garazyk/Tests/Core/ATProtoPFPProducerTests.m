// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoPFPProducerTests.m

 @abstract Tests for the Meta PDQ → DASL PFP producer contract.
 */

#import <XCTest/XCTest.h>
#import "Core/ATProtoPFPProducer.h"
#import "Core/ATProtoPFP.h"

@interface ATProtoPFPProducerTests : XCTestCase
@end

@implementation ATProtoPFPProducerTests

- (void)fillRGB:(uint8_t *)pixels width:(NSUInteger)w height:(NSUInteger)h r:(uint8_t)r g:(uint8_t)g b:(uint8_t)b {
    for (NSUInteger i = 0; i < w * h; i++) {
        pixels[i * 3] = r;
        pixels[i * 3 + 1] = g;
        pixels[i * 3 + 2] = b;
    }
}

- (void)testSolidRGBIsDeterministicPDQ {
    const NSUInteger w = 128;
    const NSUInteger h = 96;
    uint8_t *pixels = calloc(w * h * 3, 1);
    XCTAssertTrue(pixels != NULL);
    [self fillRGB:pixels width:w height:h r:40 g:80 b:120];

    NSError *error = nil;
    ATProtoPFPHashResult *first = [ATProtoPFPProducer hashRGB8Width:w
                                                             height:h
                                                        bytesPerRow:w * 3
                                                             pixels:pixels
                                                              error:&error];
    XCTAssertNotNil(first, @"%@", error);
    XCTAssertEqual(first.pfp.algorithm, ATProtoPFPAlgorithmPDQ);
    XCTAssertEqual(first.pfp.data.length, 32u);
    XCTAssertGreaterThanOrEqual(first.quality, 0);
    XCTAssertLessThanOrEqual(first.quality, 100);

    ATProtoPFPHashResult *second = [ATProtoPFPProducer hashRGB8Width:w
                                                              height:h
                                                         bytesPerRow:w * 3
                                                              pixels:pixels
                                                               error:&error];
    XCTAssertEqualObjects(second.pfp, first.pfp);
    XCTAssertEqual(second.quality, first.quality);
    free(pixels);
}

- (void)testSimilarImagesHaveSmallHammingDistance {
    const NSUInteger w = 64;
    const NSUInteger h = 64;
    uint8_t *a = calloc(w * h * 3, 1);
    uint8_t *b = calloc(w * h * 3, 1);
    XCTAssertTrue(a != NULL);
    XCTAssertTrue(b != NULL);
    for (NSUInteger y = 0; y < h; y++) {
        for (NSUInteger x = 0; x < w; x++) {
            NSUInteger i = (y * w + x) * 3;
            uint8_t v = (uint8_t)((x * 3 + y * 5) & 0xff);
            a[i] = v;
            a[i + 1] = (uint8_t)(v / 2);
            a[i + 2] = (uint8_t)(255 - v);
            b[i] = (uint8_t)MIN(255, (int)v + 2);
            b[i + 1] = a[i + 1];
            b[i + 2] = a[i + 2];
        }
    }

    ATProtoPFPHashResult *left = [ATProtoPFPProducer hashRGB8Width:w height:h bytesPerRow:w * 3 pixels:a error:nil];
    ATProtoPFPHashResult *right = [ATProtoPFPProducer hashRGB8Width:w height:h bytesPerRow:w * 3 pixels:b error:nil];
    XCTAssertNotNil(left);
    XCTAssertNotNil(right);

    NSUInteger distance = 0;
    XCTAssertTrue([ATProtoPFP hammingDistanceBetweenPDQ:left.pfp
                                                 andPDQ:right.pfp
                                               distance:&distance
                                                  error:nil]);
    XCTAssertLessThanOrEqual(distance, [ATProtoPFP recommendedPDQMatchDistance]);
    free(a);
    free(b);
}

- (void)testRejectsEmptyBuffer {
    NSError *error = nil;
    XCTAssertNil([ATProtoPFPProducer hashFloatLumaWidth:0 height:10 samples:(float[]){0} error:&error]);
    XCTAssertEqual(error.code, ATProtoPFPProducerErrorInvalidArgument);
}

@end
