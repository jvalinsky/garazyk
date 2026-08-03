// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoHttpWellKnownRoutePackTests.m

 @abstract Live route-level tests for the RASL well-known endpoint.

 @discussion Starts the configured HTTP server on an ephemeral loopback port,
 retrieves a referenced blob through GET and HEAD, then corrupts the stored
 provider bytes and verifies that the route no longer serves them under the
 original CID.
 */

#import <XCTest/XCTest.h>
#import "App/PDSController.h"
#import "Core/CID.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/PDSDatabaseBlock.h"
#import "Database/Pool/DatabasePool.h"
#import "Network/ATProtoHttpServerBuilder.h"
#import "Network/HttpServer.h"
#import "Services/PDS/PDSBlobService.h"
#import "Services/PDS/PDSRecordService.h"

#import <arpa/inet.h>
#import <errno.h>
#import <netinet/in.h>
#import <sqlite3.h>
#import <sys/socket.h>
#import <unistd.h>

static NSDictionary *LiveRASLRawResponse(NSString *method, NSString *path,
                                         uint16_t port) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        return nil;
    }

    struct timeval timeout = {0, 100000};
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));

    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_port = htons(port);
    if (inet_pton(AF_INET, "127.0.0.1", &address.sin_addr) != 1 ||
        connect(fd, (struct sockaddr *)&address, sizeof(address)) != 0) {
        close(fd);
        return nil;
    }

    NSString *requestString = [NSString stringWithFormat:
        @"%@ %@ HTTP/1.1\r\nHost: 127.0.0.1:%hu\r\nConnection: close\r\n\r\n",
        method, path, port];
    NSData *requestData = [requestString dataUsingEncoding:NSUTF8StringEncoding];
    const uint8_t *requestBytes = requestData.bytes;
    NSUInteger sent = 0;
    while (sent < requestData.length) {
        ssize_t count = send(fd, requestBytes + sent, requestData.length - sent, 0);
        if (count <= 0) {
            close(fd);
            return nil;
        }
        sent += (NSUInteger)count;
    }

    NSMutableData *rawResponse = [NSMutableData data];
    uint8_t buffer[4096];
    NSUInteger timeoutRetries = 0;
    while (YES) {
        ssize_t count = recv(fd, buffer, sizeof(buffer), 0);
        if (count > 0) {
            [rawResponse appendBytes:buffer length:(NSUInteger)count];
            timeoutRetries = 0;
        } else if (count == 0) {
            break;
        } else if (errno == EAGAIN || errno == EWOULDBLOCK) {
            if (++timeoutRetries > 100) {
                close(fd);
                return nil;
            }
            usleep(5000);
        } else {
            close(fd);
            return nil;
        }
    }
    close(fd);

    const uint8_t *responseBytes = rawResponse.bytes;
    NSUInteger headerEnd = NSNotFound;
    for (NSUInteger i = 0; i + 3 < rawResponse.length; i++) {
        if (responseBytes[i] == '\r' && responseBytes[i + 1] == '\n' &&
            responseBytes[i + 2] == '\r' && responseBytes[i + 3] == '\n') {
            headerEnd = i;
            break;
        }
    }
    if (headerEnd == NSNotFound) {
        return nil;
    }

    NSData *headerData = [rawResponse subdataWithRange:NSMakeRange(0, headerEnd)];
    NSString *headerString = [[NSString alloc] initWithData:headerData
                                                    encoding:NSUTF8StringEncoding];
    NSArray<NSString *> *lines = [headerString componentsSeparatedByString:@"\r\n"];
    if (lines.count == 0) {
        return nil;
    }

    NSInteger statusCode = 0;
    NSArray<NSString *> *statusParts = [lines[0] componentsSeparatedByString:@" "];
    if (statusParts.count > 1) {
        statusCode = [statusParts[1] integerValue];
    }

    NSMutableDictionary<NSString *, NSString *> *headers = [NSMutableDictionary dictionary];
    for (NSUInteger i = 1; i < lines.count; i++) {
        NSRange colon = [lines[i] rangeOfString:@":"];
        if (colon.location == NSNotFound) {
            continue;
        }
        NSString *key = [[lines[i] substringToIndex:colon.location] lowercaseString];
        NSString *value = [[lines[i] substringFromIndex:colon.location + 1]
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        headers[key] = value;
    }

    NSData *body = [rawResponse subdataWithRange:
        NSMakeRange(headerEnd + 4, rawResponse.length - headerEnd - 4)];
    return @{
        @"statusCode": @(statusCode),
        @"headers": headers,
        @"body": body
    };
}

@interface ATProtoHttpWellKnownRoutePackTests : XCTestCase
@property(nonatomic, strong) PDSController *controller;
@property(nonatomic, strong) HttpServer *server;
@property(nonatomic, copy) NSString *testDirectory;
@end

@implementation ATProtoHttpWellKnownRoutePackTests

- (void)setUp {
    [super setUp];
    self.testDirectory = [NSTemporaryDirectory()
        stringByAppendingPathComponent:[NSString stringWithFormat:
                                           @"rasl-route-tests-%@", NSUUID.UUID.UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.testDirectory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    self.controller = [[PDSController alloc] initWithDirectory:self.testDirectory
                                                serviceMaxSize:10
                                              userDatabaseSize:10];
}

- (void)tearDown {
    [self.server stop];
    [self.controller stopServer];
    [[NSFileManager defaultManager] removeItemAtPath:self.testDirectory error:nil];
    self.server = nil;
    self.controller = nil;
    [super tearDown];
}

- (void)testLiveRASLGetAndHeadVerifyCIDAndRejectCorruptStoredBytes {
    NSString *handle = @"rasl-live.garazyk.xyz";
    NSString *did = @"did:web:rasl-live.garazyk.xyz";
    NSError *error = nil;
    NSDictionary *account = [self.controller createAccountForEmail:@"rasl-live@example.com"
                                                            password:@"test-password-123"
                                                              handle:handle
                                                                 did:did
                                                               error:&error];
    XCTAssertNotNil(account, @"Account setup failed: %@", error);
    if (!account) {
        return;
    }

    NSData *payload = [@"RASL live route payload" dataUsingEncoding:NSUTF8StringEncoding];
    CID *cid = [CID sha256:payload];
    NSString *cidString = cid.stringValue;

    // Store a repository block directly under its CID. Unlike BlobStorage's
    // read path, ActorStore block lookup does not verify the payload; the
    // route's explicit digest check must therefore be observable here.
    PDSActorStore *store = [self.controller.userDatabasePool storeForDid:did error:&error];
    XCTAssertNotNil(store, @"Actor store setup failed: %@", error);
    PDSDatabaseBlock *block = [[PDSDatabaseBlock alloc] init];
    block.cid = cid.bytes;
    block.repoDid = did;
    block.blockData = payload;
    block.size = payload.length;
    block.createdAt = [NSDate date];
    XCTAssertTrue([store putBlock:block forDid:did error:&error],
                  @"Block setup failed: %@", error);

    ATProtoHttpServerBuilder *builder = [[ATProtoHttpServerBuilder alloc] init];
    builder.controller = self.controller;
    builder.port = 0;
    builder.enableXrpc = NO;
    builder.enableOAuth = NO;
    builder.enableOAuthDemo = NO;
    builder.enableMSTViewer = NO;
    builder.enableNodeInfo = NO;

    self.server = [builder buildWithError:&error];
    XCTAssertNotNil(self.server, @"Server build failed: %@", error);
    if (!self.server) {
        return;
    }

    if (![self.server startWithError:&error]) {
        NSError *underlying = error.userInfo[NSUnderlyingErrorKey];
        if ([underlying.domain isEqualToString:NSPOSIXErrorDomain] &&
            underlying.code == EPERM) {
            XCTSkip(@"HttpServer cannot listen (EPERM) in this environment");
            return;
        }
        XCTFail(@"Server start failed: %@", error);
        return;
    }

    NSString *path = [@"/.well-known/rasl/" stringByAppendingString:cidString];
    NSDictionary *getResponse = LiveRASLRawResponse(@"GET", path, (uint16_t)self.server.port);
    XCTAssertNotNil(getResponse);
    XCTAssertEqual([getResponse[@"statusCode"] integerValue], 200);
    XCTAssertEqualObjects(getResponse[@"body"], payload);
    XCTAssertEqualObjects(getResponse[@"headers"][@"content-type"],
                          @"application/octet-stream");

    NSDictionary *headResponse = LiveRASLRawResponse(@"HEAD", path, (uint16_t)self.server.port);
    XCTAssertNotNil(headResponse);
    XCTAssertEqual([headResponse[@"statusCode"] integerValue], 200);
    XCTAssertEqual([headResponse[@"body"] length], 0U);
    XCTAssertEqualObjects(headResponse[@"headers"][@"content-type"],
                          @"application/octet-stream");

    // Corrupt the block bytes while retaining the original CID key. `putBlock:`
    // intentionally uses INSERT OR IGNORE, so update the existing row directly
    // through the actor-store transaction API.
    NSData *corruptPayload = [@"corrupt RASL payload" dataUsingEncoding:NSUTF8StringEncoding];
    BOOL corrupted = [store transactWithBlock:^(id<PDSActorStoreTransactor> transactor,
                                                 NSError **transactionError) {
        sqlite3_stmt *statement = [store prepareStatement:
            @"UPDATE ipld_blocks SET block = ?, size = ? WHERE cid = ?"
            error:transactionError];
        if (!statement) {
            return;
        }
        sqlite3_bind_blob(statement, 1, corruptPayload.bytes,
                          (int)corruptPayload.length, SQLITE_TRANSIENT);
        sqlite3_bind_int64(statement, 2, (sqlite3_int64)corruptPayload.length);
        NSData *cidBytes = cid.bytes;
        sqlite3_bind_blob(statement, 3, cidBytes.bytes,
                          (int)cidBytes.length, SQLITE_TRANSIENT);
        int result = sqlite3_step(statement);
        if (result != SQLITE_DONE || sqlite3_changes(sqlite3_db_handle(statement)) != 1) {
            if (transactionError) {
                *transactionError = [NSError errorWithDomain:@"RASLRouteTests"
                                                          code:1
                                                      userInfo:@{NSLocalizedDescriptionKey:
                                                                     @"Stored block corruption updated an unexpected row count"}];
            }
        }
        [store finalizeStatement:statement];
    } error:&error];
    XCTAssertTrue(corrupted, @"Corrupt block setup failed: %@", error);

    NSDictionary *corruptGet = LiveRASLRawResponse(@"GET", path, (uint16_t)self.server.port);
    XCTAssertNotNil(corruptGet);
    XCTAssertEqual([corruptGet[@"statusCode"] integerValue], 500);
    XCTAssertEqual([corruptGet[@"body"] length], 0U);

    NSDictionary *corruptHead = LiveRASLRawResponse(@"HEAD", path, (uint16_t)self.server.port);
    XCTAssertNotNil(corruptHead);
    XCTAssertEqual([corruptHead[@"statusCode"] integerValue], 500);
    XCTAssertEqual([corruptHead[@"body"] length], 0U);
}

@end
