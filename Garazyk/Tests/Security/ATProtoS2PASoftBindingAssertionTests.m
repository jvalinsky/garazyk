// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Security/S2PA/ATProtoS2PASoftBindingAssertion.h"

@interface ATProtoS2PASoftBindingAssertionTests : XCTestCase
@end

@implementation ATProtoS2PASoftBindingAssertionTests

- (void)testRoundTripWithTimespan {
    ATProtoS2PASoftBindingBlock *b0 =
        [ATProtoS2PASoftBindingBlock blockWithValue:[@"v1" dataUsingEncoding:NSUTF8StringEncoding]
                                           timespan:[ATProtoS2PASoftBindingTimespan timespanWithStart:0
                                                                                                  end:100]];
    ATProtoS2PASoftBindingBlock *b1 =
        [ATProtoS2PASoftBindingBlock blockWithValue:[@"v2" dataUsingEncoding:NSUTF8StringEncoding]
                                           timespan:nil];
    ATProtoS2PASoftBindingAssertion *a =
        [[ATProtoS2PASoftBindingAssertion alloc] initWithAlg:@"phash"
                                                      blocks:@[ b0, b1 ]
                                                        name:ATProtoS2PASoftBindingAssertionLabel
                                                   algParams:[@"p" dataUsingEncoding:NSUTF8StringEncoding]];
    NSError *error = nil;
    NSData *cbor = [a encodeCBOR:&error];
    XCTAssertNotNil(cbor, @"%@", error);
    ATProtoS2PASoftBindingAssertion *round =
        [ATProtoS2PASoftBindingAssertion assertionFromCBOR:cbor error:&error];
    XCTAssertNotNil(round, @"%@", error);
    XCTAssertEqualObjects(round.alg, @"phash");
    XCTAssertEqualObjects(round.name, ATProtoS2PASoftBindingAssertionLabel);
    XCTAssertEqualObjects(round.algParams, [@"p" dataUsingEncoding:NSUTF8StringEncoding]);
    XCTAssertEqual(round.blocks.count, (NSUInteger)2);
    XCTAssertEqualObjects(round.blocks[0].value, [@"v1" dataUsingEncoding:NSUTF8StringEncoding]);
    XCTAssertEqual(round.blocks[0].timespan.start, (NSUInteger)0);
    XCTAssertEqual(round.blocks[0].timespan.end, (NSUInteger)100);
    XCTAssertNil(round.blocks[1].timespan);
    XCTAssertEqualObjects(round.blocks[1].value, [@"v2" dataUsingEncoding:NSUTF8StringEncoding]);
}

- (void)testRejectsEmptyBlocks {
    ATProtoS2PASoftBindingAssertion *a =
        [[ATProtoS2PASoftBindingAssertion alloc] initWithAlg:@"phash"
                                                      blocks:@[]
                                                        name:nil
                                                   algParams:nil];
    NSError *error = nil;
    XCTAssertNil([a encodeCBOR:&error]);
    XCTAssertEqual(error.code, ATProtoS2PASoftBindingAssertionErrorInvalidArgument);
}

@end
