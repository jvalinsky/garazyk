#import <XCTest/XCTest.h>
#import "App/PDSApplication.h"
#import "App/PDSController.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/Pool/DatabasePool.h"
#import "Network/XrpcMethodRegistry.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"
#import "Repository/CAR.h"
#import "Repository/CBOR.h"
#import "Admin/PDSAdminAuth.h"
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>

@interface AdminAuthApplicationXrpcTests : XCTestCase
@property (nonatomic, strong) PDSApplication *application;
@property (nonatomic, strong) XrpcDispatcher *dispatcher;
@property (nonatomic, strong) NSURL *tempURL;
@property (nonatomic, copy) NSString *adminJwt;
@property (nonatomic, copy) NSString *userDid;
@property (nonatomic, copy) NSString *userJwt;
@end

@implementation AdminAuthApplicationXrpcTests

- (void)setUp {
    [super setUp];

    self.tempURL = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    self.tempURL = [self.tempURL URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtURL:self.tempURL
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:nil];

    self.application = [[PDSApplication alloc] initWithDataDirectory:self.tempURL.path];
    self.dispatcher = [[XrpcDispatcher alloc] init];
    [XrpcMethodRegistry registerMethodsWithDispatcher:self.dispatcher application:self.application];

    NSError *error = nil;
    NSDictionary *adminAccount = [self.application.legacyController createAccountForEmail:@"admin-app@example.com"
                                                                                  password:@"password"
                                                                                    handle:@"administrator.app.test"
                                                                                       did:nil
                                                                                     error:&error];
    XCTAssertNil(error);

    setenv("PDS_ADMIN_PASSWORD", "password", 1);
    NSError *adminAuthError = nil;
    BOOL adminAuthSuccess = [[PDSAdminAuth sharedAuth] authenticateWithPassword:@"password" error:&adminAuthError];
    XCTAssertTrue(adminAuthSuccess);
    XCTAssertNil(adminAuthError);
    self.adminJwt = [PDSAdminAuth sharedAuth].adminToken;
    XCTAssertTrue(self.adminJwt.length > 0);
    NSString *adminAuthHeader = [NSString stringWithFormat:@"Bearer %@", self.adminJwt];
    XCTAssertTrue([[PDSAdminAuth sharedAuth] isAuthenticatedWithRequest:@{@"authorization": adminAuthHeader}]);

    NSDictionary *userAccount = [self.application.legacyController createAccountForEmail:@"user-app@example.com"
                                                                                 password:@"password"
                                                                                   handle:@"user.app.test"
                                                                                      did:nil
                                                                                    error:&error];
    XCTAssertNil(error);
    self.userDid = userAccount[@"did"];
    self.userJwt = userAccount[@"accessJwt"];
    XCTAssertTrue(self.userDid.length > 0);
    XCTAssertTrue(self.userJwt.length > 0);
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtURL:self.tempURL error:nil];
    [super tearDown];
}

- (HttpResponse *)sendJsonRequestWithPath:(NSString *)path
                                     body:(NSDictionary *)body
                                  headers:(NSDictionary<NSString *, NSString *> *)headers {
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:body ?: @{} options:0 error:nil];
    NSMutableDictionary *allHeaders = [@{@"content-type": @"application/json"} mutableCopy];
    if (headers) {
        [allHeaders addEntriesFromDictionary:headers];
    }

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                                  methodString:@"POST"
                                                          path:path
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"1.1"
                                                       headers:allHeaders
                                                          body:bodyData
                                                 remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:request response:response];
    return response;
}

- (HttpResponse *)sendGetRequestWithPath:(NSString *)path
                              queryString:(NSString *)queryString
                              queryParams:(NSDictionary<NSString *, NSString *> *)queryParams
                                  headers:(NSDictionary<NSString *, NSString *> *)headers {
    NSMutableDictionary *allHeaders = [NSMutableDictionary dictionary];
    if (headers) {
        [allHeaders addEntriesFromDictionary:headers];
    }

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:path
                                                   queryString:queryString ?: @""
                                                   queryParams:queryParams ?: @{}
                                                       version:@"1.1"
                                                       headers:allHeaders
                                                          body:[NSData data]
                                                 remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:request response:response];
    return response;
}

- (nullable HttpServer *)startSocketServerWithError:(NSError **)error {
    HttpServer *server = [HttpServer serverWithPort:0];
    __weak typeof(self) weakSelf = self;
    [server setValue:^(HttpRequest *request, HttpResponse *response) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            response.statusCode = 500;
            [response setJsonBody:@{@"error": @"InternalServerError"}];
            return;
        }
        [strongSelf.dispatcher handleRequest:request response:response];
    } forKey:@"requestHandler"];
    if (![server startWithError:error]) {
        return nil;
    }
    return server;
}

- (nullable NSData *)rawHTTPResponseForPath:(NSString *)path
                                       port:(uint16_t)port
                                      error:(NSError **)error {
    return [self rawHTTPResponseForPath:path
                                    port:port
                       additionalHeaders:nil
                                   error:error];
}

- (nullable NSData *)rawHTTPResponseForPath:(NSString *)path
                                       port:(uint16_t)port
                          additionalHeaders:(NSDictionary<NSString *, NSString *> *)additionalHeaders
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
    timeout.tv_sec = 2;
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
    while (YES) {
        ssize_t n = recv(fd, buffer, sizeof(buffer), 0);
        if (n > 0) {
            [responseData appendBytes:buffer length:(NSUInteger)n];
            continue;
        }
        if (n == 0) {
            break;
        }
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            break;
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

- (nullable NSDictionary *)parseRawHTTPResponse:(NSData *)rawData error:(NSError **)error {
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

- (nullable NSDictionary *)decodeChunkedBody:(NSData *)chunkedData error:(NSError **)error {
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

- (NSString *)iso8601String {
    if (@available(macOS 10.12, iOS 10.0, *)) {
        NSISO8601DateFormatter *formatter = [[NSISO8601DateFormatter alloc] init];
        formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime;
        return [formatter stringFromDate:[NSDate date]];
    }
    return [[NSDate date] description];
}

- (void)testApplicationGetSubjectStatusRequiresAuth {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.admin.getSubjectStatus"
                                              queryString:[NSString stringWithFormat:@"did=%@", self.userDid]
                                              queryParams:@{@"did": self.userDid}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"AuthRequired");
}

- (void)testApplicationGetSubjectStatusNonAdminForbidden {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.admin.getSubjectStatus"
                                              queryString:[NSString stringWithFormat:@"did=%@", self.userDid]
                                              queryParams:@{@"did": self.userDid}
                                                  headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 403);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"Forbidden");
}

- (void)testApplicationGetSubjectStatusAdminSuccess {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.adminJwt];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.admin.getSubjectStatus"
                                              queryString:[NSString stringWithFormat:@"did=%@", self.userDid]
                                              queryParams:@{@"did": self.userDid}
                                                  headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertEqualObjects(response.jsonBody[@"subject"][@"did"], self.userDid);
}

- (void)testApplicationUpdateSubjectStatusRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.admin.updateSubjectStatus"
                                                      body:@{
                                                          @"subject": @{@"did": self.userDid},
                                                          @"reason": @"test"
                                                      }
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"AuthRequired");
}

- (void)testApplicationModerateAccountRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.admin.moderateAccount"
                                                      body:@{
                                                          @"did": self.userDid,
                                                          @"reason": @"test"
                                                      }
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"AuthRequired");
}

- (void)testApplicationModerateRecordRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.admin.moderateRecord"
                                                      body:@{
                                                          @"uri": [NSString stringWithFormat:@"at://%@/app.bsky.feed.post/1", self.userDid],
                                                          @"reason": @"test"
                                                      }
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"AuthRequired");
}

- (void)testApplicationCreateLabelRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.label.createLabel"
                                                      body:@{
                                                          @"src": self.userDid,
                                                          @"uri": [NSString stringWithFormat:@"at://%@/app.bsky.feed.post/1", self.userDid],
                                                          @"val": @"spam"
                                                      }
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"AuthRequired");
}

- (void)testApplicationGetLabelsRequiresAuth {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.label.getLabels"
                                              queryString:@"limit=10"
                                              queryParams:@{@"limit": @"10"}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"AuthRequired");
}

- (nullable NSString *)commitRevFromCARData:(NSData *)carData {
    NSError *carError = nil;
    CARReader *reader = [CARReader readFromData:carData error:&carError];
    XCTAssertNil(carError);
    XCTAssertNotNil(reader);
    if (!reader) {
        return nil;
    }

    CARBlock *commitBlock = [reader blockWithCID:reader.rootCID];
    XCTAssertNotNil(commitBlock);
    if (!commitBlock) {
        return nil;
    }

    CBORValue *commitValue = [CBORValue decode:commitBlock.data];
    XCTAssertNotNil(commitValue);
    XCTAssertEqual(commitValue.type, CBORTypeMap);
    if (!commitValue || commitValue.type != CBORTypeMap) {
        return nil;
    }

    CBORValue *revValue = commitValue.map[[CBORValue textString:@"rev"]];
    XCTAssertNotNil(revValue);
    XCTAssertEqual(revValue.type, CBORTypeTextString);
    return revValue.textString;
}

- (nullable CID *)commitDataCIDFromCARData:(NSData *)carData {
    NSError *carError = nil;
    CARReader *reader = [CARReader readFromData:carData error:&carError];
    XCTAssertNil(carError);
    XCTAssertNotNil(reader);
    if (!reader) {
        return nil;
    }

    CARBlock *commitBlock = [reader blockWithCID:reader.rootCID];
    XCTAssertNotNil(commitBlock);
    if (!commitBlock) {
        return nil;
    }

    CBORValue *commitValue = [CBORValue decode:commitBlock.data];
    XCTAssertNotNil(commitValue);
    XCTAssertEqual(commitValue.type, CBORTypeMap);
    if (!commitValue || commitValue.type != CBORTypeMap) {
        return nil;
    }

    CBORValue *dataValue = commitValue.map[[CBORValue textString:@"data"]];
    XCTAssertNotNil(dataValue);
    XCTAssertEqual(dataValue.type, CBORTypeTag);
    if (!dataValue || dataValue.type != CBORTypeTag) {
        return nil;
    }

    CBORValue *tagged = dataValue.tagValue;
    XCTAssertEqual(tagged.type, CBORTypeByteString);
    NSData *tagBytes = tagged.byteString;
    XCTAssertTrue(tagBytes.length > 1);
    if (tagged.type != CBORTypeByteString || tagBytes.length <= 1) {
        return nil;
    }

    NSData *rawCID = [tagBytes subdataWithRange:NSMakeRange(1, tagBytes.length - 1)];
    return [CID cidFromBytes:rawCID];
}

- (BOOL)carData:(NSData *)carData containsBlockWithCIDString:(NSString *)cidString {
    NSError *parseError = nil;
    CARReader *reader = [CARReader readFromData:carData error:&parseError];
    XCTAssertNil(parseError);
    XCTAssertNotNil(reader);
    if (!reader) {
        return NO;
    }

    for (CARBlock *block in reader.blocks) {
        if ([block.cid.stringValue isEqualToString:cidString]) {
            return YES;
        }
    }
    return NO;
}

- (void)testApplicationSyncGetRepoReturnsCARWithoutAuth {
    NSDictionary *record = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"application sync getRepo",
        @"createdAt": [self iso8601String]
    };
    NSDictionary *created = [self.application.legacyController createRecordForDid:self.userDid
                                                                        collection:@"app.bsky.feed.post"
                                                                            record:record
                                                                    validationMode:PDSValidationModeOff
                                                                             error:nil];
    XCTAssertNotNil(created);

    NSString *query = [NSString stringWithFormat:@"did=%@", self.userDid];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.getRepo"
                                              queryString:query
                                              queryParams:@{@"did": self.userDid}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertEqualObjects(response.contentType, @"application/vnd.ipld.car");
    XCTAssertEqual(response.bodyFilePath.length, 0U);
    XCTAssertNotNil(response.bodyChunkProducer);
    XCTAssertNotNil(response.body);
    XCTAssertTrue(response.body.length > 0);
    if (response.bodyFilePath.length > 0) {
        [[NSFileManager defaultManager] removeItemAtPath:response.bodyFilePath error:nil];
    }
}

- (void)testApplicationSyncGetRepoSinceCurrentRevReturnsEmptyDelta {
    NSDictionary *record = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"application sync since",
        @"createdAt": [self iso8601String]
    };
    NSDictionary *created = [self.application.legacyController createRecordForDid:self.userDid
                                                                        collection:@"app.bsky.feed.post"
                                                                            record:record
                                                                    validationMode:PDSValidationModeOff
                                                                             error:nil];
    XCTAssertNotNil(created);

    NSString *query = [NSString stringWithFormat:@"did=%@", self.userDid];
    HttpResponse *fullResponse = [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.getRepo"
                                                  queryString:query
                                                  queryParams:@{@"did": self.userDid}
                                                      headers:@{}];
    XCTAssertEqual(fullResponse.statusCode, 200);
    NSString *rev = [self commitRevFromCARData:fullResponse.body];
    XCTAssertNotNil(rev);
    if (fullResponse.bodyFilePath.length > 0) {
        [[NSFileManager defaultManager] removeItemAtPath:fullResponse.bodyFilePath error:nil];
    }

    NSString *deltaQuery = [NSString stringWithFormat:@"did=%@&since=%@", self.userDid, rev];
    HttpResponse *deltaResponse = [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.getRepo"
                                                   queryString:deltaQuery
                                                   queryParams:@{@"did": self.userDid, @"since": rev}
                                                       headers:@{}];
    XCTAssertEqual(deltaResponse.statusCode, 200);
    XCTAssertEqualObjects(deltaResponse.contentType, @"application/vnd.ipld.car");

    NSError *parseError = nil;
    CARReader *reader = [CARReader readFromData:deltaResponse.body error:&parseError];
    XCTAssertNil(parseError);
    XCTAssertNotNil(reader);
    XCTAssertEqual(reader.blocks.count, 0U);
    if (deltaResponse.bodyFilePath.length > 0) {
        [[NSFileManager defaultManager] removeItemAtPath:deltaResponse.bodyFilePath error:nil];
    }
}

- (void)testApplicationSyncGetRepoUnknownSinceFallsBackToFull {
    NSDictionary *record = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"application unknown since",
        @"createdAt": [self iso8601String]
    };
    NSDictionary *created = [self.application.legacyController createRecordForDid:self.userDid
                                                                        collection:@"app.bsky.feed.post"
                                                                            record:record
                                                                    validationMode:PDSValidationModeOff
                                                                             error:nil];
    XCTAssertNotNil(created);

    NSString *query = [NSString stringWithFormat:@"did=%@", self.userDid];
    HttpResponse *fullResponse = [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.getRepo"
                                                  queryString:query
                                                  queryParams:@{@"did": self.userDid}
                                                      headers:@{}];
    XCTAssertEqual(fullResponse.statusCode, 200);

    NSError *fullParseError = nil;
    CARReader *fullReader = [CARReader readFromData:fullResponse.body error:&fullParseError];
    XCTAssertNil(fullParseError);
    XCTAssertNotNil(fullReader);
    if (fullResponse.bodyFilePath.length > 0) {
        [[NSFileManager defaultManager] removeItemAtPath:fullResponse.bodyFilePath error:nil];
    }

    NSString *unknownSinceQuery = [NSString stringWithFormat:@"did=%@&since=%@", self.userDid, @"3jzfcijpj2z2a"];
    HttpResponse *unknownResponse = [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.getRepo"
                                                     queryString:unknownSinceQuery
                                                     queryParams:@{@"did": self.userDid, @"since": @"3jzfcijpj2z2a"}
                                                         headers:@{}];
    XCTAssertEqual(unknownResponse.statusCode, 200);
    XCTAssertEqualObjects(unknownResponse.contentType, @"application/vnd.ipld.car");

    NSError *unknownParseError = nil;
    CARReader *unknownReader = [CARReader readFromData:unknownResponse.body error:&unknownParseError];
    XCTAssertNil(unknownParseError);
    XCTAssertNotNil(unknownReader);
    XCTAssertEqual(unknownReader.blocks.count, fullReader.blocks.count);
    if (unknownResponse.bodyFilePath.length > 0) {
        [[NSFileManager defaultManager] removeItemAtPath:unknownResponse.bodyFilePath error:nil];
    }
}

- (void)testApplicationSyncGetRepoOlderSinceReturnsSmallerDeltaThanFull {
    for (NSUInteger i = 0; i < 30; i++) {
        NSDictionary *record = @{
            @"$type": @"app.bsky.feed.post",
            @"text": [NSString stringWithFormat:@"bulk-%lu", (unsigned long)i],
            @"createdAt": [self iso8601String]
        };
        NSDictionary *created = [self.application.legacyController createRecordForDid:self.userDid
                                                                            collection:@"app.bsky.feed.post"
                                                                                record:record
                                                                        validationMode:PDSValidationModeOff
                                                                                 error:nil];
        XCTAssertNotNil(created);
    }

    NSString *baselineQuery = [NSString stringWithFormat:@"did=%@", self.userDid];
    HttpResponse *baselineResponse = [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.getRepo"
                                                      queryString:baselineQuery
                                                      queryParams:@{@"did": self.userDid}
                                                          headers:@{}];
    XCTAssertEqual(baselineResponse.statusCode, 200);
    NSString *baselineRev = [self commitRevFromCARData:baselineResponse.body];
    XCTAssertNotNil(baselineRev);
    if (baselineResponse.bodyFilePath.length > 0) {
        [[NSFileManager defaultManager] removeItemAtPath:baselineResponse.bodyFilePath error:nil];
    }

    NSDictionary *deltaRecord = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"single-delta-change",
        @"createdAt": [self iso8601String]
    };
    NSDictionary *createdDelta = [self.application.legacyController createRecordForDid:self.userDid
                                                                             collection:@"app.bsky.feed.post"
                                                                                 record:deltaRecord
                                                                         validationMode:PDSValidationModeOff
                                                                                  error:nil];
    XCTAssertNotNil(createdDelta);

    NSString *deltaQuery = [NSString stringWithFormat:@"did=%@&since=%@", self.userDid, baselineRev];
    HttpResponse *deltaResponse = [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.getRepo"
                                                   queryString:deltaQuery
                                                   queryParams:@{@"did": self.userDid, @"since": baselineRev}
                                                       headers:@{}];
    XCTAssertEqual(deltaResponse.statusCode, 200);

    HttpResponse *fullAfterResponse = [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.getRepo"
                                                       queryString:baselineQuery
                                                       queryParams:@{@"did": self.userDid}
                                                           headers:@{}];
    XCTAssertEqual(fullAfterResponse.statusCode, 200);

    NSError *deltaParseError = nil;
    CARReader *deltaReader = [CARReader readFromData:deltaResponse.body error:&deltaParseError];
    XCTAssertNil(deltaParseError);
    XCTAssertNotNil(deltaReader);

    NSError *fullParseError = nil;
    CARReader *fullReader = [CARReader readFromData:fullAfterResponse.body error:&fullParseError];
    XCTAssertNil(fullParseError);
    XCTAssertNotNil(fullReader);
    XCTAssertLessThan(deltaReader.blocks.count, fullReader.blocks.count);

    if (deltaResponse.bodyFilePath.length > 0) {
        [[NSFileManager defaultManager] removeItemAtPath:deltaResponse.bodyFilePath error:nil];
    }
    if (fullAfterResponse.bodyFilePath.length > 0) {
        [[NSFileManager defaultManager] removeItemAtPath:fullAfterResponse.bodyFilePath error:nil];
    }
}

- (void)testApplicationSyncGetRepoSincePreDeleteRevOmitsDeletedRecordBlock {
    NSDictionary *record = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"delete-delta-target",
        @"createdAt": [self iso8601String]
    };
    NSDictionary *created = [self.application.legacyController createRecordForDid:self.userDid
                                                                        collection:@"app.bsky.feed.post"
                                                                            record:record
                                                                    validationMode:PDSValidationModeOff
                                                                             error:nil];
    XCTAssertNotNil(created);
    NSString *deletedCID = created[@"cid"];
    XCTAssertTrue(deletedCID.length > 0);

    NSString *fullQuery = [NSString stringWithFormat:@"did=%@", self.userDid];
    HttpResponse *beforeDeleteResponse = [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.getRepo"
                                                          queryString:fullQuery
                                                          queryParams:@{@"did": self.userDid}
                                                              headers:@{}];
    XCTAssertEqual(beforeDeleteResponse.statusCode, 200);
    NSString *beforeDeleteRev = [self commitRevFromCARData:beforeDeleteResponse.body];
    XCTAssertNotNil(beforeDeleteRev);
    if (beforeDeleteResponse.bodyFilePath.length > 0) {
        [[NSFileManager defaultManager] removeItemAtPath:beforeDeleteResponse.bodyFilePath error:nil];
    }

    NSString *uri = created[@"uri"];
    NSString *rkey = uri.pathComponents.lastObject;
    XCTAssertTrue(rkey.length > 0);
    BOOL deleted = [self.application.legacyController deleteRecordForDid:self.userDid
                                                              collection:@"app.bsky.feed.post"
                                                                    rkey:rkey
                                                                   error:nil];
    XCTAssertTrue(deleted);

    NSString *deltaQuery = [NSString stringWithFormat:@"did=%@&since=%@", self.userDid, beforeDeleteRev];
    HttpResponse *deltaResponse = [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.getRepo"
                                                   queryString:deltaQuery
                                                   queryParams:@{@"did": self.userDid, @"since": beforeDeleteRev}
                                                       headers:@{}];
    XCTAssertEqual(deltaResponse.statusCode, 200);
    XCTAssertFalse([self carData:deltaResponse.body containsBlockWithCIDString:deletedCID]);

    NSError *parseError = nil;
    CARReader *reader = [CARReader readFromData:deltaResponse.body error:&parseError];
    XCTAssertNil(parseError);
    XCTAssertNotNil(reader);
    XCTAssertGreaterThan(reader.blocks.count, 0U);

    CID *dataCID = [self commitDataCIDFromCARData:deltaResponse.body];
    XCTAssertNotNil(dataCID);
    XCTAssertNotNil([reader blockWithCID:dataCID]);

    if (deltaResponse.bodyFilePath.length > 0) {
        [[NSFileManager defaultManager] removeItemAtPath:deltaResponse.bodyFilePath error:nil];
    }
}

- (void)testApplicationSyncGetRepoSinceApplyWritesCreateRevReturnsEmptyDelta {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    NSDictionary *createWrite = @{
        @"action": @"create",
        @"collection": @"app.bsky.feed.post",
        @"rkey": @"applywrites-since-create",
        @"value": @{
            @"$type": @"app.bsky.feed.post",
            @"text": @"applyWrites create rev baseline",
            @"createdAt": [self iso8601String]
        }
    };

    HttpResponse *applyResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.repo.applyWrites"
                                                           body:@{@"writes": @[createWrite], @"validate": @NO}
                                                        headers:@{@"authorization": authHeader}];
    XCTAssertEqual(applyResponse.statusCode, 200);
    NSDictionary *applyCommit = applyResponse.jsonBody[@"commit"];
    XCTAssertNotNil(applyCommit);
    XCTAssertTrue([applyCommit[@"cid"] length] > 0);
    XCTAssertTrue([applyCommit[@"rev"] length] > 0);

    PDSActorStore *store = [self.application.userDatabasePool storeForDid:self.userDid error:nil];
    XCTAssertNotNil(store);
    NSString *commitRev = [store latestMutationRevisionWithError:nil];
    XCTAssertNotNil(commitRev);
    XCTAssertTrue(commitRev.length > 0);
    XCTAssertEqualObjects(applyCommit[@"rev"], commitRev);

    NSString *query = [NSString stringWithFormat:@"did=%@&since=%@", self.userDid, commitRev];
    HttpResponse *deltaResponse = [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.getRepo"
                                                   queryString:query
                                                   queryParams:@{@"did": self.userDid, @"since": commitRev}
                                                       headers:@{}];
    XCTAssertEqual(deltaResponse.statusCode, 200);

    NSError *parseError = nil;
    CARReader *reader = [CARReader readFromData:deltaResponse.body error:&parseError];
    XCTAssertNil(parseError);
    XCTAssertNotNil(reader);
    XCTAssertEqual(reader.blocks.count, 0U);
    if (deltaResponse.bodyFilePath.length > 0) {
        [[NSFileManager defaultManager] removeItemAtPath:deltaResponse.bodyFilePath error:nil];
    }
}

- (void)testApplicationSyncGetRepoSinceApplyWritesDeleteRevReturnsEmptyDelta {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    NSDictionary *createWrite = @{
        @"action": @"create",
        @"collection": @"app.bsky.feed.post",
        @"rkey": @"applywrites-since-delete",
        @"value": @{
            @"$type": @"app.bsky.feed.post",
            @"text": @"applyWrites delete rev baseline",
            @"createdAt": [self iso8601String]
        }
    };
    HttpResponse *createResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.repo.applyWrites"
                                                            body:@{@"writes": @[createWrite], @"validate": @NO}
                                                         headers:@{@"authorization": authHeader}];
    XCTAssertEqual(createResponse.statusCode, 200);
    NSDictionary *createCommit = createResponse.jsonBody[@"commit"];
    XCTAssertNotNil(createCommit);
    XCTAssertTrue([createCommit[@"cid"] length] > 0);
    XCTAssertTrue([createCommit[@"rev"] length] > 0);

    NSDictionary *deleteWrite = @{
        @"action": @"delete",
        @"collection": @"app.bsky.feed.post",
        @"rkey": @"applywrites-since-delete"
    };
    HttpResponse *deleteResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.repo.applyWrites"
                                                            body:@{@"writes": @[deleteWrite], @"validate": @NO}
                                                         headers:@{@"authorization": authHeader}];
    XCTAssertEqual(deleteResponse.statusCode, 200);
    NSDictionary *deleteCommit = deleteResponse.jsonBody[@"commit"];
    XCTAssertNotNil(deleteCommit);
    XCTAssertTrue([deleteCommit[@"cid"] length] > 0);
    XCTAssertTrue([deleteCommit[@"rev"] length] > 0);

    PDSActorStore *store = [self.application.userDatabasePool storeForDid:self.userDid error:nil];
    XCTAssertNotNil(store);
    NSString *deleteRev = [store latestMutationRevisionWithError:nil];
    XCTAssertNotNil(deleteRev);
    XCTAssertTrue(deleteRev.length > 0);
    XCTAssertEqualObjects(deleteCommit[@"rev"], deleteRev);

    NSString *query = [NSString stringWithFormat:@"did=%@&since=%@", self.userDid, deleteRev];
    HttpResponse *deltaResponse = [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.getRepo"
                                                   queryString:query
                                                   queryParams:@{@"did": self.userDid, @"since": deleteRev}
                                                       headers:@{}];
    XCTAssertEqual(deltaResponse.statusCode, 200);

    NSError *parseError = nil;
    CARReader *reader = [CARReader readFromData:deltaResponse.body error:&parseError];
    XCTAssertNil(parseError);
    XCTAssertNotNil(reader);
    XCTAssertEqual(reader.blocks.count, 0U);
    if (deltaResponse.bodyFilePath.length > 0) {
        [[NSFileManager defaultManager] removeItemAtPath:deltaResponse.bodyFilePath error:nil];
    }
}

- (void)testApplicationSyncGetRepoSocketStreamingUsesChunkedTransferEncoding {
    NSDictionary *record = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"socket streaming getRepo",
        @"createdAt": [self iso8601String]
    };
    NSDictionary *created = [self.application.legacyController createRecordForDid:self.userDid
                                                                        collection:@"app.bsky.feed.post"
                                                                            record:record
                                                                    validationMode:PDSValidationModeOff
                                                                             error:nil];
    XCTAssertNotNil(created);

    NSError *startError = nil;
    HttpServer *server = [self startSocketServerWithError:&startError];
    if (!server) {
        XCTSkip(@"Socket listener unavailable in this environment: %@",
                startError.localizedDescription ?: @"unknown error");
        return;
    }

    NSString *encodedDid = [self.userDid stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    NSString *path = [NSString stringWithFormat:@"/xrpc/com.atproto.sync.getRepo?did=%@", encodedDid ?: self.userDid];

    NSError *requestError = nil;
    NSData *rawResponse = [self rawHTTPResponseForPath:path port:(uint16_t)server.port error:&requestError];
    [server stop];
    XCTAssertNil(requestError);
    XCTAssertNotNil(rawResponse);
    if (!rawResponse) {
        return;
    }

    NSError *parseError = nil;
    NSDictionary *parsed = [self parseRawHTTPResponse:rawResponse error:&parseError];
    XCTAssertNil(parseError);
    XCTAssertNotNil(parsed);
    if (!parsed) {
        return;
    }

    XCTAssertEqual([parsed[@"statusCode"] integerValue], (NSInteger)200);
    NSDictionary<NSString *, NSString *> *headers = parsed[@"headers"];
    XCTAssertEqualObjects([headers[@"content-type"] lowercaseString], @"application/vnd.ipld.car");
    XCTAssertEqualObjects([headers[@"transfer-encoding"] lowercaseString], @"chunked");
    XCTAssertNil(headers[@"content-length"]);

    NSDictionary *chunked = [self decodeChunkedBody:parsed[@"body"] error:&parseError];
    XCTAssertNil(parseError);
    XCTAssertNotNil(chunked);
    if (!chunked) {
        return;
    }

    NSArray<NSNumber *> *chunkSizes = chunked[@"chunkSizes"];
    XCTAssertTrue(chunkSizes.count > 1, @"Expected multiple streamed chunks");
    NSData *carData = chunked[@"payload"];
    XCTAssertTrue(carData.length > 0);

    NSError *carError = nil;
    CARReader *reader = [CARReader readFromData:carData error:&carError];
    XCTAssertNil(carError);
    XCTAssertNotNil(reader);
    XCTAssertNotNil(reader.rootCID);
    XCTAssertTrue(reader.blocks.count > 0);
}

- (void)testApplicationSyncGetBlobSocketRangeUsesChunkedPartialContent {
    NSData *blobData = [@"socket-range-blob" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *uploadError = nil;
    NSDictionary *uploadResult = [self.application.legacyController uploadBlob:blobData
                                                                         forDid:self.userDid
                                                                       mimeType:@"text/plain"
                                                                          error:&uploadError];
    XCTAssertNil(uploadError);
    XCTAssertNotNil(uploadResult);
    NSString *cid = uploadResult[@"blob"][@"ref"][@"$link"];
    XCTAssertTrue(cid.length > 0);
    if (cid.length == 0) {
        return;
    }

    NSError *startError = nil;
    HttpServer *server = [self startSocketServerWithError:&startError];
    if (!server) {
        XCTSkip(@"Socket listener unavailable in this environment: %@",
                startError.localizedDescription ?: @"unknown error");
        return;
    }

    NSString *encodedDid = [self.userDid stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    NSString *encodedCID = [cid stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    NSString *path = [NSString stringWithFormat:@"/xrpc/com.atproto.sync.getBlob?did=%@&cid=%@",
                      encodedDid ?: self.userDid,
                      encodedCID ?: cid];

    NSError *requestError = nil;
    NSData *rawResponse = [self rawHTTPResponseForPath:path
                                                   port:(uint16_t)server.port
                                      additionalHeaders:@{@"Range": @"bytes=1-5"}
                                                  error:&requestError];
    [server stop];
    XCTAssertNil(requestError);
    XCTAssertNotNil(rawResponse);
    if (!rawResponse) {
        return;
    }

    NSError *parseError = nil;
    NSDictionary *parsed = [self parseRawHTTPResponse:rawResponse error:&parseError];
    XCTAssertNil(parseError);
    XCTAssertNotNil(parsed);
    if (!parsed) {
        return;
    }

    XCTAssertEqual([parsed[@"statusCode"] integerValue], (NSInteger)206);
    NSDictionary<NSString *, NSString *> *headers = parsed[@"headers"];
    XCTAssertEqualObjects([headers[@"accept-ranges"] lowercaseString], @"bytes");
    XCTAssertEqualObjects([headers[@"transfer-encoding"] lowercaseString], @"chunked");
    NSString *expectedContentRange = [NSString stringWithFormat:@"bytes 1-5/%lu",
                                      (unsigned long)blobData.length];
    XCTAssertEqualObjects([headers[@"content-range"] lowercaseString],
                          [expectedContentRange lowercaseString]);

    NSDictionary *chunked = [self decodeChunkedBody:parsed[@"body"] error:&parseError];
    XCTAssertNil(parseError);
    XCTAssertNotNil(chunked);
    if (!chunked) {
        return;
    }

    NSData *payload = chunked[@"payload"];
    NSData *expected = [blobData subdataWithRange:NSMakeRange(1, 5)];
    XCTAssertEqualObjects(payload, expected);
}

@end
