// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <XCTest/XCTest.h>

#import "Security/Space/PDSSpaceLtHash.h"

@interface PDSSpaceLtHashTests : XCTestCase
@end

@implementation PDSSpaceLtHashTests

- (void)testEmptyDigestMatchesProposalReference {
  PDSSpaceLtHash *hash = [[PDSSpaceLtHash alloc] init];
  XCTAssertEqual(hash.state.length, 2048UL);

  const unsigned char *bytes = hash.state.bytes;
  for (NSUInteger index = 0; index < hash.state.length; index++) {
    XCTAssertEqual(bytes[index], 0);
  }

  XCTAssertEqualObjects([self hexString:hash.digest],
                        @"e5a00aa9991ac8a5ee3109844d84a55583bd20572ad3ffcd42792f3c36b183ad");
}

- (void)testAddAndRemoveRestoresExactState {
  PDSSpaceLtHash *hash = [[PDSSpaceLtHash alloc] init];
  NSData *empty = hash.state;
  [hash addElement:@"com.example.record/abc/bafy-test"];
  XCTAssertNotEqualObjects(hash.state, empty);
  [hash removeElement:@"com.example.record/abc/bafy-test"];
  XCTAssertEqualObjects(hash.state, empty);
}

- (void)testStateIsOrderIndependent {
  PDSSpaceLtHash *first = [[PDSSpaceLtHash alloc] init];
  PDSSpaceLtHash *second = [[PDSSpaceLtHash alloc] init];
  NSArray<NSString *> *elements = @[@"alpha", @"beta", @"gamma", @"delta"];
  for (NSString *element in elements) {
    [first addElement:element];
  }
  for (NSString *element in elements.reverseObjectEnumerator) {
    [second addElement:element];
  }
  XCTAssertEqualObjects(first.state, second.state);
  XCTAssertEqualObjects(first.digest, second.digest);
}

- (void)testRejectsStateWithWrongLength {
  NSError *error = nil;
  PDSSpaceLtHash *hash = [[PDSSpaceLtHash alloc]
      initWithState:[NSMutableData dataWithLength:32]
              error:&error];
  XCTAssertNil(hash);
  XCTAssertEqual(error.code, PDSSpaceLtHashErrorInvalidState);
}

- (NSString *)hexString:(NSData *)data {
  NSMutableString *result = [NSMutableString stringWithCapacity:data.length * 2];
  const uint8_t *bytes = data.bytes;
  for (NSUInteger index = 0; index < data.length; index++) {
    [result appendFormat:@"%02x", bytes[index]];
  }
  return result;
}

@end
