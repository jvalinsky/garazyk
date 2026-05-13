// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSHttpTestUtilities.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>

@implementation PDSHttpTestUtilities

+ (nullable HttpServer *)startSocketServerWithDispatcher:(XrpcDispatcher *)dispatcher error:(NSError **)error {
    HttpServer *server = [HttpServer serverWithPort:0];
    __weak XrpcDispatcher *weakDispatcher = dispatcher;
    
    [server setValue:^(HttpRequest *request, HttpResponse *response) {
        __strong XrpcDispatcher *strongDispatcher = weakDispatcher;
        if (!strongDispatcher) {
            response.statusCode = 500;
            [response setJsonBody:@{@"error": @"InternalServerError"}];
            return;
        }
        [strongDispatcher handleRequest:request response:response];
    } forKey:@"requestHandler"];
    
    if (![server startWithError:error]) {
        return nil;
    }
    return server;
}

+ (nullable NSData *)rawHTTPResponseForPath:(NSString *)path
                                       port:(uint16_t)port
                                      error:(NSError **)error {
    return [self rawHTTPResponseForPath:path
                                   port:port
                      additionalHeaders:nil
                                  error:error];
}

+ (nullable NSData *)rawHTTPResponseForPath:(NSString *)path
                                       port:(uint16_t)port
                          additionalHeaders:(nullable NSDictionary<NSString *, NSString *> *)additionalHeaders
                                      error:(NSError **)error {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"test.socket"
                                         code:errno
                                     userInfo:@{NSLocalizedDescriptionKey: @"socket() failed"}];
        }
        return nil;
    }

    struct timeval timeout;
    timeout.tv_sec = 10;
    timeout.tv_usec = 0;
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    if (inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr) != 1) {
        close(fd);
        if (error) {
            *error = [NSError errorWithDomain:@"test.socket"
                                         code:EINVAL
                                     userInfo:@{NSLocalizedDescriptionKey: @"inet_pton failed"}];
        }
        return nil;
    }

    if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
        int connectErrno = errno;
        close(fd);
        if (error) {
            *error = [NSError errorWithDomain:@"test.socket"
                                         code:connectErrno
                                     userInfo:@{NSLocalizedDescriptionKey: @"connect() failed"}];
        }
        return nil;
    }

    NSMutableString *requestString = [NSMutableString stringWithFormat:
                                      @"GET %@ HTTP/1.1\r\nHost: 127.0.0.1:%hu\r\nConnection: close\r\nAccept: */*\r\n",
                                      path,
                                      port];
    for (NSString *headerKey in additionalHeaders) {
        NSString *headerValue = additionalHeaders[headerKey];
        if (![headerValue isKindOfClass:[NSString class]]) {
            continue;
        }
        [requestString appendFormat:@"%@: %@\r\n", headerKey, headerValue];
    }
    [requestString appendString:@"\r\n"];
    NSData *requestData = [requestString dataUsingEncoding:NSUTF8StringEncoding];
    ssize_t writeResult = send(fd, requestData.bytes, requestData.length, 0);
    if (writeResult < 0 || (NSUInteger)writeResult != requestData.length) {
        int sendErrno = errno;
        close(fd);
        if (error) {
            *error = [NSError errorWithDomain:@"test.socket"
                                         code:sendErrno
                                     userInfo:@{NSLocalizedDescriptionKey: @"send() failed"}];
        }
        return nil;
    }

    NSMutableData *responseData = [NSMutableData data];
    uint8_t buffer[4096];
    int retryCount = 0;
    while (YES) {
        ssize_t n = recv(fd, buffer, sizeof(buffer), 0);
        if (n > 0) {
            [responseData appendBytes:buffer length:(NSUInteger)n];
            retryCount = 0;
            continue;
        }
        if (n == 0) {
            break;
        }
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            // Retry on EAGAIN — server may not have written headers yet for chunked responses
            retryCount++;
            if (retryCount > 50) {
                // Timeout after ~250ms (50 * 5ms) — fail fast so failures surface quickly
                break;
            }
            usleep(5000);
            continue;
        }
        int recvErrno = errno;
        close(fd);
        if (error) {
            *error = [NSError errorWithDomain:@"test.socket"
                                         code:recvErrno
                                     userInfo:@{NSLocalizedDescriptionKey: @"recv() failed"}];
        }
        return nil;
    }

    close(fd);
    return [responseData copy];
}

+ (nullable NSDictionary *)parseRawHTTPResponse:(NSData *)rawData error:(NSError **)error {
    const uint8_t *bytes = rawData.bytes;
    NSUInteger headerEnd = NSNotFound;
    for (NSUInteger i = 0; i + 3 < rawData.length; i++) {
        if (bytes[i] == '\r' && bytes[i + 1] == '\n' && bytes[i + 2] == '\r' && bytes[i + 3] == '\n') {
            headerEnd = i;
            break;
        }
    }
    if (headerEnd == NSNotFound) {
        if (error) {
            *error = [NSError errorWithDomain:@"test.http"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing HTTP headers"}];
        }
        return nil;
    }

    NSData *headerData = [rawData subdataWithRange:NSMakeRange(0, headerEnd)];
    NSData *bodyData = [rawData subdataWithRange:NSMakeRange(headerEnd + 4, rawData.length - (headerEnd + 4))];
    NSString *headerText = [[NSString alloc] initWithData:headerData encoding:NSUTF8StringEncoding];
    if (!headerText) {
        if (error) {
            *error = [NSError errorWithDomain:@"test.http"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Header decode failed"}];
        }
        return nil;
    }

    NSArray<NSString *> *lines = [headerText componentsSeparatedByString:@"\r\n"];
    if (lines.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"test.http"
                                         code:3
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing status line"}];
        }
        return nil;
    }

    NSString *statusLine = lines[0];
    NSInteger statusCode = 0;
    NSArray<NSString *> *statusParts = [statusLine componentsSeparatedByString:@" "];
    if (statusParts.count >= 2) {
        statusCode = [statusParts[1] integerValue];
    }

    NSMutableDictionary<NSString *, NSString *> *headers = [NSMutableDictionary dictionary];
    for (NSUInteger i = 1; i < lines.count; i++) {
        NSString *line = lines[i];
        NSRange colon = [line rangeOfString:@":"];
        if (colon.location == NSNotFound) {
            continue;
        }
        NSString *key = [[line substringToIndex:colon.location] lowercaseString];
        NSString *value = [[line substringFromIndex:colon.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (key.length > 0) {
            headers[key] = value ?: @"";
        }
    }

    return @{
        @"statusCode": @(statusCode),
        @"headers": headers,
        @"body": bodyData
    };
}

+ (nullable NSDictionary *)decodeChunkedBody:(NSData *)chunkedData error:(NSError **)error {
    NSMutableData *payload = [NSMutableData data];
    NSMutableArray<NSNumber *> *chunkSizes = [NSMutableArray array];
    NSUInteger offset = 0;

    while (YES) {
        NSUInteger lineEnd = NSNotFound;
        const uint8_t *bytes = chunkedData.bytes;
        for (NSUInteger i = offset; i + 1 < chunkedData.length; i++) {
            if (bytes[i] == '\r' && bytes[i + 1] == '\n') {
                lineEnd = i;
                break;
            }
        }
        if (lineEnd == NSNotFound || lineEnd <= offset) {
            if (error) {
                *error = [NSError errorWithDomain:@"test.http"
                                             code:10
                                         userInfo:@{NSLocalizedDescriptionKey: @"Incomplete chunk size line"}];
            }
            return nil;
        }

        NSData *sizeLineData = [chunkedData subdataWithRange:NSMakeRange(offset, lineEnd - offset)];
        NSString *sizeLine = [[NSString alloc] initWithData:sizeLineData encoding:NSUTF8StringEncoding];
        if (!sizeLine) {
            if (error) {
                *error = [NSError errorWithDomain:@"test.http"
                                             code:11
                                         userInfo:@{NSLocalizedDescriptionKey: @"Invalid chunk size encoding"}];
            }
            return nil;
        }

        NSString *hexSize = [[sizeLine componentsSeparatedByString:@";"] firstObject];
        unsigned long chunkSize = strtoul(hexSize.UTF8String, NULL, 16);
        offset = lineEnd + 2;

        if (chunkSize == 0) {
            if (offset + 2 > chunkedData.length) {
                if (error) {
                    *error = [NSError errorWithDomain:@"test.http"
                                                 code:12
                                             userInfo:@{NSLocalizedDescriptionKey: @"Missing final chunk terminator"}];
                }
                return nil;
            }
            if (bytes[offset] != '\r' || bytes[offset + 1] != '\n') {
                if (error) {
                    *error = [NSError errorWithDomain:@"test.http"
                                                 code:13
                                             userInfo:@{NSLocalizedDescriptionKey: @"Invalid final chunk terminator"}];
                }
                return nil;
            }
            offset += 2;
            return @{
                @"payload": payload,
                @"chunkSizes": chunkSizes,
                @"consumedBytes": @(offset)
            };
        }

        if (offset + chunkSize + 2 > chunkedData.length) {
            if (error) {
                *error = [NSError errorWithDomain:@"test.http"
                                             code:14
                                         userInfo:@{NSLocalizedDescriptionKey: @"Incomplete chunk payload"}];
            }
            return nil;
        }

        [payload appendData:[chunkedData subdataWithRange:NSMakeRange(offset, (NSUInteger)chunkSize)]];
        [chunkSizes addObject:@(chunkSize)];
        offset += (NSUInteger)chunkSize;

        if (bytes[offset] != '\r' || bytes[offset + 1] != '\n') {
            if (error) {
                *error = [NSError errorWithDomain:@"test.http"
                                             code:15
                                         userInfo:@{NSLocalizedDescriptionKey: @"Missing chunk CRLF"}];
            }
            return nil;
        }
        offset += 2;
    }
}

@end
