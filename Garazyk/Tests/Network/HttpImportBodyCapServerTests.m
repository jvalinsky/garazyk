// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Network/HttpServer.h"
#import "Network/HttpResponse.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <sys/select.h>
#import <signal.h>

// End-to-end verification of the per-route body-size override (ADR 0035 B1)
// through a real listening HTTP server over raw sockets: a request body above
// the generic 50 MB parser cap must be admitted for a route whose
// bodySizeLimitProvider returns a larger cap (the com.atproto.repo.importRepo
// scenario), while the same body on an unrelated route is still rejected with
// 413 at the parser.
//
// Raw sockets are used deliberately: NSURLSession surfaces the server's
// reject-then-close as a connection error whose NSError lifetime races with
// session invalidation (a client-side CFNetwork bug observed while writing
// this test), which would crash the test process. A socket client also pins
// the HTTP-level contract directly.
//
// Socket-gated: binds a real loopback listener.
@interface HttpImportBodyCapServerTests : XCTestCase
@end

@implementation HttpImportBodyCapServerTests

- (int)connectSocketToPort:(NSUInteger)port {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    XCTAssertTrue(fd >= 0, @"socket() failed: %d", errno);
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons((uint16_t)port);
    XCTAssertEqual(inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr), 1);
    int rc = connect(fd, (struct sockaddr *)&addr, sizeof(addr));
    if (rc != 0) {
        XCTAssertEqual(rc, 0, @"connect() failed: %d", errno);
        close(fd);
        return -1;
    }
    return fd;
}

- (void)sendAllOnSocket:(int)fd bytes:(const void *)bytes length:(size_t)length {
    size_t sent = 0;
    while (sent < length) {
        ssize_t n = send(fd, (const char *)bytes + sent, length - sent, 0);
        if (n <= 0) {
            // EPIPE is expected on the reject path: the server closes the
            // connection after flushing the 413 while the client is still
            // uploading. Stop sending; the caller then reads the response.
            return;
        }
        sent += (size_t)n;
    }
}

- (void)sendBodyOnSocket:(int)fd totalBytes:(size_t)totalBytes chunkSize:(size_t)chunkSize {
    NSMutableData *chunk = [NSMutableData dataWithLength:chunkSize];
    memset(chunk.mutableBytes, 'x', chunk.length);
    size_t sent = 0;
    while (sent < totalBytes) {
        size_t thisChunk = MIN(chunkSize, totalBytes - sent);
        [self sendAllOnSocket:fd bytes:chunk.bytes length:thisChunk];
        sent += thisChunk;
    }
}

// Reads until the peer closes or the timeout elapses. Returns nil on timeout
// with no data at all (used to distinguish "no response" from a response).
- (NSData *)readResponseOnSocket:(int)fd withTimeout:(NSTimeInterval)timeout {
    NSMutableData *data = [NSMutableData data];
    NSTimeInterval deadline = [NSDate timeIntervalSinceReferenceDate] + timeout;
    char buffer[65536];
    while ([NSDate timeIntervalSinceReferenceDate] < deadline) {
        fd_set readfds;
        FD_ZERO(&readfds);
        FD_SET(fd, &readfds);
        struct timeval tv;
        tv.tv_sec = 0;
        tv.tv_usec = 200000; // 200 ms poll
        int sel = select(fd + 1, &readfds, NULL, NULL, &tv);
        XCTAssertGreaterThanOrEqual(sel, 0, @"select() failed: %d", errno);
        if (sel <= 0) {
            continue;
        }
        ssize_t n = recv(fd, buffer, sizeof(buffer), 0);
        if (n == 0) {
            break; // peer closed
        }
        if (n < 0) {
            break;
        }
        [data appendBytes:buffer length:(NSUInteger)n];
    }
    return data;
}

- (NSInteger)statusFromResponseData:(NSData *)data {
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (text.length == 0) {
        return 0;
    }
    NSArray<NSString *> *lines = [text componentsSeparatedByString:@"\r\n"];
    if (lines.count == 0) {
        return 0;
    }
    // "HTTP/1.1 200 OK" → 200
    NSArray<NSString *> *parts = [lines[0] componentsSeparatedByString:@" "];
    if (parts.count < 2) {
        return 0;
    }
    return [parts[1] integerValue];
}

- (void)testLargeBodyAdmittedOnOverridePathAndRejectedElsewhere {
    // Ignore SIGPIPE: the reject path closes the connection while the client
    // is still uploading, which would otherwise kill the test process.
    signal(SIGPIPE, SIG_IGN);

    ATProtoHttpServer *server = [ATProtoHttpServer serverWithHost:@"127.0.0.1" port:0];
    server.bodySizeLimitProvider = ^NSUInteger(NSString *path) {
        if ([path hasPrefix:@"/xrpc/com.atproto.repo.importRepo"]) {
            return 256 * 1024 * 1024; // 256 MB route cap
        }
        return 0; // generic parser cap
    };
    [server addRoute:@"POST" path:@"/xrpc/com.atproto.repo.importRepo"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"ok": @YES}];
    }];
    [server addRoute:@"POST" path:@"/small"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"ok": @YES}];
    }];

    NSError *startError = nil;
    XCTAssertTrue([server startWithError:&startError], @"%@", startError);
    NSUInteger port = server.port;
    XCTAssertGreaterThan(port, (NSUInteger)0);

    @try {
        // Override path: 60 MB — comfortably above the generic 50 MB cap.
        int fd = [self connectSocketToPort:port];
        XCTAssertGreaterThanOrEqual(fd, 0);
        if (fd >= 0) {
            NSString *requestHead = [NSString stringWithFormat:
                @"POST /xrpc/com.atproto.repo.importRepo HTTP/1.1\r\n"
                @"Host: 127.0.0.1:%lu\r\n"
                @"Content-Type: application/vnd.ipld.car\r\n"
                @"Content-Length: %lu\r\n"
                @"Connection: close\r\n"
                @"\r\n",
                (unsigned long)port,
                (unsigned long)(60 * 1024 * 1024)];
            NSData *headData = [requestHead dataUsingEncoding:NSUTF8StringEncoding];
            [self sendAllOnSocket:fd bytes:headData.bytes length:headData.length];
            [self sendBodyOnSocket:fd totalBytes:60 * 1024 * 1024 chunkSize:1024 * 1024];
            NSData *responseData = [self readResponseOnSocket:fd withTimeout:10.0];
            close(fd);
            XCTAssertEqual([self statusFromResponseData:responseData], 200,
                           @"The route-level cap must admit a body above the generic 50 MB limit");
        }

        // Non-override route: same body is refused at the generic 50 MB cap
        // as soon as the parser has seen more than 50 MB.
        fd = [self connectSocketToPort:port];
        XCTAssertGreaterThanOrEqual(fd, 0);
        if (fd >= 0) {
            NSString *requestHead = [NSString stringWithFormat:
                @"POST /small HTTP/1.1\r\n"
                @"Host: 127.0.0.1:%lu\r\n"
                @"Content-Type: application/vnd.ipld.car\r\n"
                @"Content-Length: %lu\r\n"
                @"Connection: close\r\n"
                @"\r\n",
                (unsigned long)port,
                (unsigned long)(60 * 1024 * 1024)];
            NSData *headData = [requestHead dataUsingEncoding:NSUTF8StringEncoding];
            [self sendAllOnSocket:fd bytes:headData.bytes length:headData.length];
            // Send just past the generic cap; the server rejects before the
            // full 60 MB arrives (and may close, so EPIPE is ignored above).
            [self sendBodyOnSocket:fd totalBytes:51 * 1024 * 1024 chunkSize:1024 * 1024];
            NSData *responseData = [self readResponseOnSocket:fd withTimeout:10.0];
            close(fd);
            XCTAssertEqual([self statusFromResponseData:responseData], 413,
                           @"A route without an override must keep the generic 50 MB cap");
        }
    } @finally {
        [server stop];
    }
}

@end
