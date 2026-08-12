// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Network/GZHttpContentEncoding.h"
#import "Network/GZHttpStreamCompressor.h"
#import "Network/HttpResponse.h"

#include <string.h>
#include <stdlib.h>
#include <zlib.h>
#include <zstd.h>

@interface HttpContentEncodingTests : XCTestCase
@end

@implementation HttpContentEncodingTests

- (void)tearDown {
    unsetenv("PDS_HTTP_CONTENT_ENCODING");
    [super tearDown];
}

- (void)testNegotiateEmptyIsIdentity {
    XCTAssertEqual(GZHttpContentEncodingFromAcceptEncoding(nil), GZHttpContentEncodingIdentity);
    XCTAssertEqual(GZHttpContentEncodingFromAcceptEncoding(@""), GZHttpContentEncodingIdentity);
}

- (void)testNegotiatePrefersZstdOnTie {
    XCTAssertEqual(GZHttpContentEncodingFromAcceptEncoding(@"gzip, zstd"), GZHttpContentEncodingZstd);
    XCTAssertEqual(GZHttpContentEncodingFromAcceptEncoding(@"*"), GZHttpContentEncodingZstd);
}

- (void)testNegotiateRespectsQValues {
    XCTAssertEqual(GZHttpContentEncodingFromAcceptEncoding(@"gzip;q=1.0, zstd;q=0.5"),
                   GZHttpContentEncodingGzip);
    XCTAssertEqual(GZHttpContentEncodingFromAcceptEncoding(@"zstd;q=0, gzip;q=0.8"),
                   GZHttpContentEncodingGzip);
    XCTAssertEqual(GZHttpContentEncodingFromAcceptEncoding(@"zstd;q=0, gzip;q=0"),
                   GZHttpContentEncodingIdentity);
}

- (void)testNegotiateEnvForcesIdentity {
    setenv("PDS_HTTP_CONTENT_ENCODING", "0", 1);
    XCTAssertEqual(GZHttpContentEncodingFromAcceptEncoding(@"zstd"), GZHttpContentEncodingIdentity);
}

- (void)testHeaderValues {
    XCTAssertNil(GZHttpContentEncodingHeaderValue(GZHttpContentEncodingIdentity));
    XCTAssertEqualObjects(GZHttpContentEncodingHeaderValue(GZHttpContentEncodingGzip), @"gzip");
    XCTAssertEqualObjects(GZHttpContentEncodingHeaderValue(GZHttpContentEncodingZstd), @"zstd");
}

- (NSData *)collectProducer:(HttpResponseBodyChunkProducer)producer {
    NSMutableData *all = [NSMutableData data];
    while (YES) {
        NSError *error = nil;
        NSData *chunk = producer(&error);
        XCTAssertNil(error);
        if (chunk.length == 0) {
            break;
        }
        [all appendData:chunk];
    }
    return [all copy];
}

- (NSData *)decompressZstd:(NSData *)data {
    unsigned long long bound = ZSTD_getFrameContentSize(data.bytes, data.length);
    XCTAssertNotEqual(bound, ZSTD_CONTENTSIZE_ERROR);
    if (bound == ZSTD_CONTENTSIZE_UNKNOWN) {
        bound = data.length * 8 + 64;
    }
    NSMutableData *out = [NSMutableData dataWithLength:(NSUInteger)bound];
    size_t written = ZSTD_decompress(out.mutableBytes, out.length, data.bytes, data.length);
    XCTAssertFalse(ZSTD_isError(written), @"%s", ZSTD_getErrorName(written));
    out.length = written;
    return [out copy];
}

- (NSData *)decompressGzip:(NSData *)data {
    z_stream strm;
    memset(&strm, 0, sizeof(strm));
    XCTAssertEqual(inflateInit2(&strm, 15 + 16), Z_OK);
    strm.next_in = (Bytef *)data.bytes;
    strm.avail_in = (uInt)data.length;
    NSMutableData *out = [NSMutableData data];
    uint8_t buf[4096];
    int rc;
    do {
        strm.next_out = buf;
        strm.avail_out = sizeof(buf);
        rc = inflate(&strm, Z_NO_FLUSH);
        XCTAssertTrue(rc == Z_OK || rc == Z_STREAM_END, @"inflate rc=%d", rc);
        [out appendBytes:buf length:(sizeof(buf) - strm.avail_out)];
    } while (rc != Z_STREAM_END);
    inflateEnd(&strm);
    return [out copy];
}

- (void)testZstdCompressorRoundTrip {
    NSError *error = nil;
    GZHttpStreamCompressor *compressor =
        [[GZHttpStreamCompressor alloc] initWithEncoding:GZHttpContentEncodingZstd error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(compressor);

    NSMutableData *compressed = [NSMutableData data];
    NSData *part1 = [@"hello " dataUsingEncoding:NSUTF8StringEncoding];
    NSData *part2 = [@"world-zstd-compress" dataUsingEncoding:NSUTF8StringEncoding];
    [compressed appendData:[compressor compressChunk:part1 error:&error]];
    XCTAssertNil(error);
    [compressed appendData:[compressor compressChunk:part2 error:&error]];
    XCTAssertNil(error);
    [compressed appendData:[compressor finishWithError:&error]];
    XCTAssertNil(error);
    XCTAssertGreaterThan(compressed.length, 0u);

    NSMutableData *plain = [NSMutableData data];
    [plain appendData:part1];
    [plain appendData:part2];
    XCTAssertEqualObjects([self decompressZstd:compressed], plain);
}

- (void)testGzipCompressorRoundTrip {
    NSError *error = nil;
    GZHttpStreamCompressor *compressor =
        [[GZHttpStreamCompressor alloc] initWithEncoding:GZHttpContentEncodingGzip error:&error];
    XCTAssertNil(error);

    NSData *plain = [@"gzip-round-trip-payload-0123456789" dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *compressed = [NSMutableData data];
    [compressed appendData:[compressor compressChunk:plain error:&error]];
    XCTAssertNil(error);
    [compressed appendData:[compressor finishWithError:&error]];
    XCTAssertNil(error);
    XCTAssertEqualObjects([self decompressGzip:compressed], plain);
}

- (void)testCompressingProducerRoundTripZstd {
    NSData *plain = [@"chunked-export-body-abcdefghijklmnopqrstuvwxyz" dataUsingEncoding:NSUTF8StringEncoding];
    __block BOOL sent = NO;
    HttpResponseBodyChunkProducer inner = ^NSData *(NSError **error) {
        (void)error;
        if (sent) {
            return [NSData data];
        }
        sent = YES;
        return plain;
    };
    HttpResponseBodyChunkProducer wrapped =
        GZHttpCompressingBodyChunkProducer(inner, GZHttpContentEncodingZstd);
    NSData *compressed = [self collectProducer:wrapped];
    XCTAssertEqualObjects([self decompressZstd:compressed], plain);
}

- (void)testResponseHelperSetsHeaders {
    ATProtoHttpResponse *response = [[ATProtoHttpResponse alloc] init];
    __block BOOL sent = NO;
    HttpResponseBodyChunkProducer inner = ^NSData *(NSError **error) {
        (void)error;
        if (sent) {
            return [NSData data];
        }
        sent = YES;
        return [@"abc" dataUsingEncoding:NSUTF8StringEncoding];
    };
    GZHttpResponseSetExportBodyChunkProducer(response, inner, @"zstd");
    XCTAssertEqualObjects([response headerForKey:@"Content-Encoding"], @"zstd");
    XCTAssertEqualObjects([response headerForKey:@"Vary"], @"Accept, Accept-Encoding");
    XCTAssertTrue(response.chunkedTransferEncoding);
    XCTAssertNotNil(response.bodyChunkProducer);
}

@end
