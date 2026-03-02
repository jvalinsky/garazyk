#import <XCTest/XCTest.h>
#import "Network/HttpParsing.h"

@interface HttpParsingTests : XCTestCase
@end

@implementation HttpParsingTests

#pragma mark - parseQueryString

- (void)testParseQueryString_Empty {
  NSDictionary *result = [HttpParsing parseQueryString:@""];
  XCTAssertEqualObjects(result, @{});
}

- (void)testParseQueryString_SingleParam {
  NSDictionary *result = [HttpParsing parseQueryString:@"key=value"];
  XCTAssertEqualObjects(result[@"key"], @"value");
}

- (void)testParseQueryString_MultipleParams {
  NSDictionary *result = [HttpParsing parseQueryString:@"a=1&b=2&c=3"];
  XCTAssertEqualObjects(result[@"a"], @"1");
  XCTAssertEqualObjects(result[@"b"], @"2");
  XCTAssertEqualObjects(result[@"c"], @"3");
}

- (void)testParseQueryString_DuplicateKeys {
  NSDictionary *result = [HttpParsing parseQueryString:@"key=a&key=b"];
  XCTAssertTrue([result[@"key"] isKindOfClass:[NSArray class]]);
  NSArray *values = result[@"key"];
  XCTAssertEqual(values.count, 2u);
  XCTAssertEqualObjects(values[0], @"a");
  XCTAssertEqualObjects(values[1], @"b");
}

- (void)testParseQueryString_KeyWithoutValue {
  NSDictionary *result = [HttpParsing parseQueryString:@"flag"];
  XCTAssertEqualObjects(result[@"flag"], @"");
}

- (void)testParseQueryString_PercentEncoded {
  NSDictionary *result = [HttpParsing parseQueryString:@"key=hello%20world"];
  XCTAssertEqualObjects(result[@"key"], @"hello world");
}

- (void)testParseQueryString_PlusAsSpace {
  NSDictionary *result = [HttpParsing parseQueryString:@"key=hello+world"];
  XCTAssertEqualObjects(result[@"key"], @"hello world");
}

- (void)testParseQueryString_EmptyValue {
  NSDictionary *result = [HttpParsing parseQueryString:@"key="];
  XCTAssertEqualObjects(result[@"key"], @"");
}

- (void)testParseQueryString_EqualsInValue {
  NSDictionary *result = [HttpParsing parseQueryString:@"key=a=b"];
  XCTAssertEqualObjects(result[@"key"], @"a=b");
}

#pragma mark - urlDecode

- (void)testUrlDecode_Plain {
  XCTAssertEqualObjects([HttpParsing urlDecode:@"hello"], @"hello");
}

- (void)testUrlDecode_PercentEncoded {
  XCTAssertEqualObjects([HttpParsing urlDecode:@"hello%20world"],
                        @"hello world");
}

- (void)testUrlDecode_PlusToSpace {
  XCTAssertEqualObjects([HttpParsing urlDecode:@"hello+world"],
                        @"hello world");
}

- (void)testUrlDecode_SpecialChars {
  XCTAssertEqualObjects([HttpParsing urlDecode:@"%26%3D"], @"&=");
}

#pragma mark - methodFromString

- (void)testMethodFromString_GET {
  XCTAssertEqual([HttpParsing methodFromString:@"GET"], HttpMethodGET);
}

- (void)testMethodFromString_POST {
  XCTAssertEqual([HttpParsing methodFromString:@"POST"], HttpMethodPOST);
}

- (void)testMethodFromString_PUT {
  XCTAssertEqual([HttpParsing methodFromString:@"PUT"], HttpMethodPUT);
}

- (void)testMethodFromString_DELETE {
  XCTAssertEqual([HttpParsing methodFromString:@"DELETE"], HttpMethodDELETE);
}

- (void)testMethodFromString_PATCH {
  XCTAssertEqual([HttpParsing methodFromString:@"PATCH"], HttpMethodPATCH);
}

- (void)testMethodFromString_OPTIONS {
  XCTAssertEqual([HttpParsing methodFromString:@"OPTIONS"], HttpMethodOPTIONS);
}

- (void)testMethodFromString_HEAD {
  XCTAssertEqual([HttpParsing methodFromString:@"HEAD"], HttpMethodHEAD);
}

- (void)testMethodFromString_Unknown {
  XCTAssertEqual([HttpParsing methodFromString:@"TRACE"], HttpMethodUnknown);
}

- (void)testMethodFromString_Empty {
  XCTAssertEqual([HttpParsing methodFromString:@""], HttpMethodUnknown);
}

@end
