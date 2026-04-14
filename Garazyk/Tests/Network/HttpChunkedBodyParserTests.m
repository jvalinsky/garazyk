#import <XCTest/XCTest.h>
#import "Network/HttpChunkedBodyParser.h"

NS_ASSUME_NONNULL_BEGIN

@interface HttpChunkedBodyParserTests : XCTestCase
@end

@implementation HttpChunkedBodyParserTests

- (void)testSimpleChunk {
    HttpChunkedBodyParser *parser = [[HttpChunkedBodyParser alloc] init];

    NSData *chunk1 = [@"5\r\nHello\r\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    NSInteger result = [parser appendData:chunk1 error:&error];

    XCTAssertTrue(result);
    XCTAssertNil(error);
    XCTAssertFalse(parser.isComplete);
    XCTAssertEqual(parser.parsedLength, 5);
}

- (void)testCompleteSingleChunk {
    HttpChunkedBodyParser *parser = [[HttpChunkedBodyParser alloc] init];

    NSData *data = [@"5\r\nHello\r\n0\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    NSInteger result = [parser appendData:data error:&error];

    XCTAssertTrue(result);
    XCTAssertNil(error);
    XCTAssertTrue(parser.isComplete);
    XCTAssertEqualObjects(parser.parsedData, [@"Hello" dataUsingEncoding:NSUTF8StringEncoding]);
}

- (void)testMultipleChunks {
    HttpChunkedBodyParser *parser = [[HttpChunkedBodyParser alloc] init];

    NSData *data = [@"5\r\nHello\r\n6\r\n World\r\n0\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    NSInteger result = [parser appendData:data error:&error];

    XCTAssertTrue(result);
    XCTAssertNil(error);
    XCTAssertTrue(parser.isComplete);
    XCTAssertEqualObjects(parser.parsedData, [@"Hello World" dataUsingEncoding:NSUTF8StringEncoding]);
}

- (void)testIncrementalParsing {
    HttpChunkedBodyParser *parser = [[HttpChunkedBodyParser alloc] init];

    NSError *error = nil;

    [parser appendData:[@"5\r\nHel" dataUsingEncoding:NSUTF8StringEncoding] error:&error];
    XCTAssertNil(error);
    XCTAssertFalse(parser.isComplete);
    XCTAssertEqual(parser.parsedLength, 3);

    [parser appendData:[@"lo\r\n" dataUsingEncoding:NSUTF8StringEncoding] error:&error];
    XCTAssertNil(error);
    XCTAssertFalse(parser.isComplete);
    XCTAssertEqual(parser.parsedLength, 5);

    [parser appendData:[@"3\r\nBye\r\n0\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding] error:&error];
    XCTAssertNil(error);
    XCTAssertTrue(parser.isComplete);
    XCTAssertEqualObjects(parser.parsedData, [@"HelloBye" dataUsingEncoding:NSUTF8StringEncoding]);
}

- (void)testEmptyBody {
    HttpChunkedBodyParser *parser = [[HttpChunkedBodyParser alloc] init];

    NSData *data = [@"0\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    NSInteger result = [parser appendData:data error:&error];

    XCTAssertTrue(result);
    XCTAssertNil(error);
    XCTAssertTrue(parser.isComplete);
    XCTAssertEqual(parser.parsedData.length, 0);
}

- (void)testHexDigitsUpperCase {
    HttpChunkedBodyParser *parser = [[HttpChunkedBodyParser alloc] init];

    NSData *data = [@"A\r\nABCDEFGHIJ\r\n0\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    NSInteger result = [parser appendData:data error:&error];

    XCTAssertTrue(result);
    XCTAssertNil(error);
    XCTAssertTrue(parser.isComplete);
    XCTAssertEqualObjects(parser.parsedData, [@"ABCDEFGHIJ" dataUsingEncoding:NSUTF8StringEncoding]);
}

- (void)testMalformedChunkSize {
    HttpChunkedBodyParser *parser = [[HttpChunkedBodyParser alloc] init];

    NSData *data = [@"GG\r\nHello\r\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    NSInteger result = [parser appendData:data error:&error];

    XCTAssertEqual(result, -1);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, 400);
}

- (void)testMissingCRLF {
    HttpChunkedBodyParser *parser = [[HttpChunkedBodyParser alloc] init];

    NSData *data = [@"5\r\nHello world" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    NSInteger result = [parser appendData:data error:&error];

    XCTAssertEqual(result, -1);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, 400);
}

- (void)testMaxSizeExceeded {
    HttpChunkedBodyParser *parser = [[HttpChunkedBodyParser alloc] initWithMaxSize:10];

    NSData *data = [@"20\r\n0123456789ABCDEF\r\n0\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    NSInteger result = [parser appendData:data error:&error];

    XCTAssertEqual(result, -1);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, 413);
}

- (void)testParseChunkSizeClassMethod {
    NSData *data = [@"1A\r\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSUInteger size = 0;
    NSUInteger offset = [HttpChunkedBodyParser parseChunkSizeFromData:data offset:0 size:&size];

    XCTAssertEqual(offset, (NSUInteger)4);
    XCTAssertEqual(size, (NSUInteger)26);
}

- (void)testResetParserIsCompleteAndEqual {
    HttpChunkedBodyParser *parser = [[HttpChunkedBodyParser alloc] init];

    NSData *data1 = [@"5\r\nHello\r\n" dataUsingEncoding:NSUTF8StringEncoding];
    [parser appendData:data1 error:nil];

    [parser reset];

    NSData *data2 = [@"3\r\nBye\r\n0\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding];
    [parser appendData:data2 error:nil];

    XCTAssertTrue(parser.isComplete);
    XCTAssertEqualObjects(parser.parsedData, [@"Bye" dataUsingEncoding:NSUTF8StringEncoding]);
}

- (void)testChunkExtension {
    HttpChunkedBodyParser *parser = [[HttpChunkedBodyParser alloc] init];

    NSData *data = [@"5;name=value\r\nHello\r\n0\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    NSInteger result = [parser appendData:data error:&error];

    XCTAssertTrue(result);
    XCTAssertNil(error);
    XCTAssertTrue(parser.isComplete);
    XCTAssertEqualObjects(parser.parsedData, [@"Hello" dataUsingEncoding:NSUTF8StringEncoding]);
}

@end

NS_ASSUME_NONNULL_END
