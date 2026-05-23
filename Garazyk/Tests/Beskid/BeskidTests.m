// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <XCTest/XCTest.h>

#import "Beskid/BeskidConfiguration.h"
#import "Beskid/BeskidDatabase.h"
#import "Beskid/BeskidRuntime.h"
#import "Beskid/BeskidXrpcRoutePack.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"

static NSString *BeskidTestDBPath(NSString *name) {
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"garazyk-beskid-%@-%@", name, NSUUID.UUID.UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                     error:nil];
    return [dir stringByAppendingPathComponent:@"test.db"];
}

static BeskidDatabase *BeskidOpenTestDB(XCTestCase *testCase) {
    NSError *error = nil;
    BeskidDatabase *db = [[BeskidDatabase alloc] initWithPath:BeskidTestDBPath(testCase.name)
                                                        error:&error];
    XCTAssertNotNil(db, @"open db: %@", error);
    XCTAssertTrue([db runMigrations:&error], @"migrate db: %@", error);
    return db;
}

static HttpRequest *BeskidRequest(NSString *path, NSDictionary *queryParams) {
    return [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                 methodString:@"GET"
                                         path:path
                                  queryString:@""
                                  queryParams:queryParams
                                      version:@"HTTP/1.1"
                                      headers:@{}
                                         body:[NSData data]
                                remoteAddress:@"127.0.0.1"];
}

@interface BeskidConfigurationTests : XCTestCase
@end

@implementation BeskidConfigurationTests

- (void)testConfigurationDefaults {
    BeskidConfiguration *config = [BeskidConfiguration defaultConfiguration];
    XCTAssertEqual(config.httpPort, 8085u);
    XCTAssertEqualObjects(config.domain, @"slingshot.microcosm.blue");
    XCTAssertEqual(config.cacheRecordTtlSeconds, 3600);
    XCTAssertEqual(config.cacheIdentityTtlSeconds, 86400);
    XCTAssertTrue(config.rateLimitEnabled);
    XCTAssertEqual(config.rateLimitIpLimit, 200);
}

- (void)testConfigurationValidation {
    BeskidConfiguration *config = [BeskidConfiguration defaultConfiguration];
    NSError *error = nil;
    XCTAssertTrue([config validate:&error]);

    config.dataDirectory = @"";
    XCTAssertFalse([config validate:&error]);
    XCTAssertEqual(error.code, 1);

    config.dataDirectory = @"/tmp";
    config.httpPort = 999999;
    XCTAssertFalse([config validate:&error]);
    XCTAssertEqual(error.code, 2);
}

@end

@interface BeskidDatabaseTests : XCTestCase
@property (nonatomic, strong) BeskidDatabase *db;
@end

@implementation BeskidDatabaseTests

- (void)setUp {
    [super setUp];
    self.db = BeskidOpenTestDB(self);
}

- (void)tearDown {
    [self.db close];
    self.db = nil;
    [super tearDown];
}

- (void)testRecordCacheInsertAndRead {
    NSError *error = nil;
    NSDictionary *record = @{@"$type": @"app.bsky.feed.post", @"text": @"Hello Beskid!"};

    XCTAssertTrue([self.db saveRecord:record
                                 did:@"did:plc:alice"
                          collection:@"app.bsky.feed.post"
                                rkey:@"one"
                                 cid:@"bafyreial"
                                 ttl:3600
                               error:&error], @"save record: %@", error);

    NSDictionary *cached = [self.db recordByURI:@"at://did:plc:alice/app.bsky.feed.post/one"
                                            cid:nil
                                          error:&error];
    XCTAssertNotNil(cached, @"read record: %@", error);
    XCTAssertEqualObjects(cached[@"cid"], @"bafyreial");
    XCTAssertEqualObjects(cached[@"value"][@"text"], @"Hello Beskid!");
}

- (void)testExpiredRecordCacheReturnsNil {
    NSError *error = nil;
    NSDictionary *record = @{@"$type": @"app.bsky.feed.post", @"text": @"Expired!"};

    // Cache with negative TTL (expired)
    XCTAssertTrue([self.db saveRecord:record
                                 did:@"did:plc:alice"
                          collection:@"app.bsky.feed.post"
                                rkey:@"one"
                                 cid:@"bafyreial"
                                 ttl:-10
                               error:&error], @"save record: %@", error);

    NSDictionary *cached = [self.db recordByURI:@"at://did:plc:alice/app.bsky.feed.post/one"
                                            cid:nil
                                          error:&error];
    XCTAssertNil(cached, @"expired cache should return nil");
    XCTAssertEqual(error.code, 410, @"error code should be GONE (410)");
}

- (void)testIdentityCacheInsertAndRead {
    NSError *error = nil;
    NSDictionary *rawDoc = @{@"id": @"did:plc:alice", @"alsoKnownAs": @[@"at://alice.com"]};

    XCTAssertTrue([self.db saveIdentity:@"did:plc:alice"
                                 handle:@"alice.com"
                            pdsEndpoint:@"https://pds.alice.com"
                             signingKey:@"zQ3sh"
                            rawDocument:rawDoc
                                    ttl:86400
                                  error:&error], @"save identity: %@", error);

    NSDictionary *cached = [self.db identityForDID:@"did:plc:alice" error:&error];
    XCTAssertNotNil(cached, @"read identity: %@", error);
    XCTAssertEqualObjects(cached[@"handle"], @"alice.com");
    XCTAssertEqualObjects(cached[@"pds"], @"https://pds.alice.com");
    XCTAssertEqualObjects(cached[@"signing_key"], @"zQ3sh");
}

- (void)testExpiredIdentityReturnsNil {
    NSError *error = nil;
    NSDictionary *rawDoc = @{@"id": @"did:plc:alice"};

    XCTAssertTrue([self.db saveIdentity:@"did:plc:alice"
                                 handle:@"alice.com"
                            pdsEndpoint:@"https://pds.alice.com"
                             signingKey:@"zQ3sh"
                            rawDocument:rawDoc
                                    ttl:-10
                                  error:&error], @"save identity: %@", error);

    NSDictionary *cached = [self.db identityForDID:@"did:plc:alice" error:&error];
    XCTAssertNil(cached, @"expired identity should return nil");
    XCTAssertEqual(error.code, 410);
}

@end

@interface BeskidXrpcRoutePackTests : XCTestCase
@property (nonatomic, strong) BeskidDatabase *db;
@property (nonatomic, strong) BeskidXrpcRoutePack *routes;
@end

@implementation BeskidXrpcRoutePackTests

- (void)setUp {
    [super setUp];
    self.db = BeskidOpenTestDB(self);
    self.routes = [[BeskidXrpcRoutePack alloc] initWithDatabase:self.db];
}

- (void)tearDown {
    [self.db close];
    self.routes = nil;
    self.db = nil;
    [super tearDown];
}

- (void)testPayloadTraverser {
    NSDictionary *payload = @{
        @"feed": @[
            @{@"post": @"at://did:plc:bob/app.bsky.feed.post/1"},
            @{@"post": @"at://did:plc:bob/app.bsky.feed.post/2"}
        ]
    };
    NSMutableSet *uris = [NSMutableSet set];
    // Cast/helper traversal call test
    BeskidXrpcRoutePack *routes = [[BeskidXrpcRoutePack alloc] initWithDatabase:self.db];
    
    // We call the traversal helper directly because it is intentionally private.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
    SEL selector = @selector(extractURIsFromJSON:path:collector:);
#pragma clang diagnostic pop
    NSMethodSignature *signature = [routes methodSignatureForSelector:selector];
    XCTAssertNotNil(signature);
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.target = routes;
    invocation.selector = selector;
    NSString *path = @"feed[].post";
    [invocation setArgument:&payload atIndex:2];
    [invocation setArgument:&path atIndex:3];
    [invocation setArgument:&uris atIndex:4];
    [invocation invoke];

    XCTAssertEqual(uris.count, 2u);
    XCTAssertTrue([uris containsObject:@"at://did:plc:bob/app.bsky.feed.post/1"]);
    XCTAssertTrue([uris containsObject:@"at://did:plc:bob/app.bsky.feed.post/2"]);
}

- (void)testGetRecordByUriRejectsInvalidRequest {
    HttpRequest *request = BeskidRequest(@"/xrpc/com.bad-example.repo.getUriRecord", @{});
    HttpResponse *response = [HttpResponse response];

    [self.routes registerRoutesWithServer:[HttpServer serverWithPort:0]]; // Route registration smoke test
    
    // Call record by URI directly to verify validation bounds
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
    [self.routes performSelector:@selector(handleGetRecordByUri:response:) withObject:request withObject:response];
#pragma clang diagnostic pop

    XCTAssertEqual(response.statusCode, HttpStatusBadRequest);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"InvalidRequest");
}

@end
