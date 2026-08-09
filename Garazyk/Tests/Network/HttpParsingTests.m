// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Network/HttpParsing.h"

@interface HttpParsingTests : XCTestCase
@end

@implementation HttpParsingTests

#pragma mark - parseQueryString

- (void)testParseQueryString_EmptyMatchesResultObject {
  NSDictionary *result = [ATProtoHttpParsing parseQueryString:@""];
  XCTAssertEqualObjects(result, @{});
}

- (void)testParseQueryString_SingleParamReturnsExpectedDictionary {
  NSDictionary *result = [ATProtoHttpParsing parseQueryString:@"key=value"];
  XCTAssertEqualObjects(result[@"key"], @"value");
}

- (void)testParseQueryString_MultipleParams {
  NSDictionary *result = [ATProtoHttpParsing parseQueryString:@"a=1&b=2&c=3"];
  XCTAssertEqualObjects(result[@"a"], @"1");
  XCTAssertEqualObjects(result[@"b"], @"2");
  XCTAssertEqualObjects(result[@"c"], @"3");
}

- (void)testParseQueryString_DuplicateKeys {
  NSDictionary *result = [ATProtoHttpParsing parseQueryString:@"key=a&key=b"];
  XCTAssertTrue([result[@"key"] isKindOfClass:[NSArray class]]);
  NSArray *values = result[@"key"];
  XCTAssertEqual(values.count, 2u);
  XCTAssertEqualObjects(values[0], @"a");
  XCTAssertEqualObjects(values[1], @"b");
}

- (void)testParseQueryString_KeyWithoutValueReturnsExpectedDictionary {
  NSDictionary *result = [ATProtoHttpParsing parseQueryString:@"flag"];
  XCTAssertEqualObjects(result[@"flag"], @"");
}

- (void)testParseQueryString_PercentEncodedReturnsExpectedDictionary {
  NSDictionary *result = [ATProtoHttpParsing parseQueryString:@"key=hello%20world"];
  XCTAssertEqualObjects(result[@"key"], @"hello world");
}

- (void)testParseQueryString_PlusAsSpaceReturnsExpectedDictionary {
  NSDictionary *result = [ATProtoHttpParsing parseQueryString:@"key=hello+world"];
  XCTAssertEqualObjects(result[@"key"], @"hello world");
}

- (void)testParseQueryString_EmptyValueReturnsExpectedDictionary {
  NSDictionary *result = [ATProtoHttpParsing parseQueryString:@"key="];
  XCTAssertEqualObjects(result[@"key"], @"");
}

- (void)testParseQueryString_EqualsInValue {
  NSDictionary *result = [ATProtoHttpParsing parseQueryString:@"key=a=b"];
  XCTAssertEqualObjects(result[@"key"], @"a=b");
}

#pragma mark - urlDecode

- (void)testUrlDecode_PlainReturnsUnchanged {
  XCTAssertEqualObjects([ATProtoHttpParsing urlDecode:@"hello"], @"hello");
}

- (void)testUrlDecode_PercentEncodedMatchesObject {
  XCTAssertEqualObjects([ATProtoHttpParsing urlDecode:@"hello%20world"],
                        @"hello world");
}

- (void)testUrlDecode_PlusToSpaceMatchesObject {
  XCTAssertEqualObjects([ATProtoHttpParsing urlDecode:@"hello+world"],
                        @"hello world");
}

- (void)testUrlDecode_SpecialChars {
  XCTAssertEqualObjects([ATProtoHttpParsing urlDecode:@"%26%3D"], @"&=");
}

#pragma mark - methodFromString

- (void)testMethodFromString_GET {
  XCTAssertEqual([ATProtoHttpParsing methodFromString:@"GET"], HttpMethodGET);
}

- (void)testMethodFromString_POST {
  XCTAssertEqual([ATProtoHttpParsing methodFromString:@"POST"], HttpMethodPOST);
}

- (void)testMethodFromString_PUT {
  XCTAssertEqual([ATProtoHttpParsing methodFromString:@"PUT"], HttpMethodPUT);
}

- (void)testMethodFromString_DELETE {
  XCTAssertEqual([ATProtoHttpParsing methodFromString:@"DELETE"], HttpMethodDELETE);
}

- (void)testMethodFromString_PATCH {
  XCTAssertEqual([ATProtoHttpParsing methodFromString:@"PATCH"], HttpMethodPATCH);
}

- (void)testMethodFromString_OPTIONS {
  XCTAssertEqual([ATProtoHttpParsing methodFromString:@"OPTIONS"], HttpMethodOPTIONS);
}

- (void)testMethodFromString_HEAD {
  XCTAssertEqual([ATProtoHttpParsing methodFromString:@"HEAD"], HttpMethodHEAD);
}

- (void)testMethodFromString_UnknownReturnsUnknown {
  XCTAssertEqual([ATProtoHttpParsing methodFromString:@"TRACE"], HttpMethodUnknown);
}

- (void)testMethodFromString_Empty {
  XCTAssertEqual([ATProtoHttpParsing methodFromString:@""], HttpMethodUnknown);
}

@end
