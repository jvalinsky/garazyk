// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>

#import "AdminUIServer/GZAdminUIHost+Private.h"
#import "AdminUIServer/GZAdminUIHost.h"
#import "AdminUIServer/UIAuthManager.h"
#import "AdminUIServer/UIServiceConfig.h"
#import "Beskid/AdminUI/BeskidAdminSnapshot.h"
#import "Beskid/AdminUI/BeskidAdminUIPack.h"
#import "Beskid/BeskidConfiguration.h"
#import "Beskid/BeskidDatabase.h"
#import "Beskid/BeskidMetrics.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"

static NSString *BeskidTestDBPath(NSString *name) {
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"garazyk-beskid-admin-%@-%@", name, NSUUID.UUID.UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir stringByAppendingPathComponent:@"test.db"];
}

static BeskidDatabase *BeskidAdminOpenTestDB(XCTestCase *test) {
    NSError *error = nil;
    BeskidDatabase *db = [[BeskidDatabase alloc] initWithPath:BeskidTestDBPath(test.name) error:&error];
    XCTAssertNotNil(db, @"open db: %@", error);
    XCTAssertTrue([db runMigrations:&error], @"migrate: %@", error);
    return db;
}

// ── BeskidMetricsTests ────────────────────────────────────────────

@interface BeskidMetricsTests : XCTestCase
@end

@implementation BeskidMetricsTests

- (void)testCountersAggregateAndSnapshot {
    BeskidMetrics *metrics = [[BeskidMetrics alloc] init];
    [metrics recordRecordHit];
    [metrics recordRecordHit];
    [metrics recordRecordMiss];
    [metrics recordRecordWriteWithExpiresAt:(int64_t)[[NSDate dateWithTimeIntervalSinceNow:3600] timeIntervalSince1970]];
    [metrics recordRecordExpiredRead];
    [metrics recordRecordDelete];
    [metrics recordIdentityHit];
    [metrics recordIdentityMiss];
    [metrics seedEntryGaugesWithRecordCount:1 identityCount:0];
    [metrics recordRateLimitReject];
    [metrics recordRateLimitReject];

    NSDictionary *snap = [metrics snapshotDictionary];
    NSDictionary *record = snap[@"record"];
    XCTAssertEqualObjects(record[@"hits"], @2);
    XCTAssertEqualObjects(record[@"misses"], @1);
    XCTAssertEqualObjects(record[@"expired"], @1);
    XCTAssertEqualObjects(record[@"writes"], @1);
    XCTAssertEqualObjects(record[@"deletes"], @1);
    XCTAssertEqualObjects(record[@"entries"], @1); // seeded 1 + write 1 - expired 1 - delete 1 = 1

    NSDictionary *identity = snap[@"identity"];
    XCTAssertEqualObjects(identity[@"hits"], @1);
    XCTAssertEqualObjects(identity[@"misses"], @1);

    NSDictionary *overall = snap[@"overall"];
    double ratio = [overall[@"hitRatio"] doubleValue];
    XCTAssertGreaterThan(ratio, 0.0);

    XCTAssertEqualObjects(snap[@"rateLimitRejects"], @2);
}

- (void)testUpstreamAggregationIsBounded {
    BeskidMetrics *metrics = [[BeskidMetrics alloc] init];
    for (int i = 0; i < 40; i++) {
        NSString *host = [NSString stringWithFormat:@"pds-%d.example.com", i];
        [metrics recordUpstreamRequestToHost:host];
        [metrics recordUpstreamSuccessToHost:host latencyMillis:10 + i];
    }
    NSArray *upstreams = [metrics snapshotDictionary][@"upstreams"];
    XCTAssertLessThanOrEqual(upstreams.count, 32u);
}

- (void)testConcurrentUpdatesAreConsistent {
    BeskidMetrics *metrics = [[BeskidMetrics alloc] init];
    dispatch_apply(128, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(size_t idx) {
        [metrics recordRecordHit];
        [metrics recordRecordWriteWithExpiresAt:(int64_t)([[NSDate date] timeIntervalSince1970] + 3600)];
        [metrics recordUpstreamRequestToHost:@"example.com"];
        [metrics recordUpstreamSuccessToHost:@"example.com" latencyMillis:5];
    });
    dispatch_apply(128, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(size_t idx) {
        [metrics recordRecordHit];
    });
    NSDictionary *snap = [metrics snapshotDictionary];
    int64_t hits = [snap[@"record"][@"hits"] longLongValue];
    XCTAssertGreaterThanOrEqual(hits, (int64_t)128);
    int64_t writes = [snap[@"record"][@"writes"] longLongValue];
    XCTAssertGreaterThanOrEqual(writes, (int64_t)128);
}

@end

// ── BeskidAdminSnapshotTests ──────────────────────────────────────

@interface BeskidAdminSnapshotTests : XCTestCase
@end

@implementation BeskidAdminSnapshotTests

- (void)testEmptyCacheSnapshotReportsOkAndZeroEntries {
    BeskidDatabase *db = BeskidAdminOpenTestDB(self);
    BeskidConfiguration *config = [BeskidConfiguration defaultConfiguration];
    BeskidMetrics *metrics = [[BeskidMetrics alloc] init];
    GZBeskidAdminSnapshot *snapshot = [[GZBeskidAdminSnapshot alloc] initWithDatabase:db metrics:metrics configuration:config];
    NSDictionary *value = [snapshot snapshot];
    XCTAssertEqualObjects(value[@"health"], @"ok");
    XCTAssertEqualObjects(value[@"cache"][@"overall"][@"entries"], @0);
    XCTAssertEqualObjects(value[@"cache"][@"record"][@"entries"], @0);
    [db close];
}

- (void)testSnapshotReflectsCacheOperations {
    BeskidDatabase *db = BeskidAdminOpenTestDB(self);
    BeskidConfiguration *config = [BeskidConfiguration defaultConfiguration];
    BeskidMetrics *metrics = [[BeskidMetrics alloc] init];
    db.metrics = metrics;

    NSError *error = nil;
    [db saveRecord:@{@"$type": @"test"} did:@"did:plc:x" collection:@"test.ns" rkey:@"one" cid:@"bafy123" ttl:3600 error:&error];
    [db recordByURI:@"at://did:plc:x/test.ns/one" cid:nil error:nil];
    [db recordByURI:@"at://did:plc:x/test.ns/two" cid:nil error:nil]; // miss

    GZBeskidAdminSnapshot *snapshot = [[GZBeskidAdminSnapshot alloc] initWithDatabase:db metrics:metrics configuration:config];
    NSDictionary *value = [snapshot snapshot];
    NSDictionary *record = value[@"cache"][@"record"];
    XCTAssertEqualObjects(record[@"hits"], @1);
    XCTAssertEqualObjects(record[@"misses"], @1);
    XCTAssertGreaterThan([record[@"entries"] longLongValue], (int64_t)0);
    [db close];
}

- (void)testSnapshotDoesNotLeakSensitiveData {
    BeskidDatabase *db = BeskidAdminOpenTestDB(self);
    BeskidConfiguration *config = [BeskidConfiguration defaultConfiguration];
    BeskidMetrics *metrics = [[BeskidMetrics alloc] init];
    db.metrics = metrics;

    [db saveRecord:@{@"$type": @"test", @"text": @"sensitive"} did:@"did:plc:x" collection:@"test.ns" rkey:@"one" cid:@"bafy" ttl:3600 error:nil];
    [db saveIdentity:@"did:plc:x" handle:@"x.com" pdsEndpoint:@"https://pds.x.com" signingKey:@"zQsecret" rawDocument:@{} ttl:86400 error:nil];

    GZBeskidAdminSnapshot *snapshot = [[GZBeskidAdminSnapshot alloc] initWithDatabase:db metrics:metrics configuration:config];
    NSDictionary *value = [snapshot snapshot];
    NSString *json = [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:value options:0 error:nil] encoding:NSUTF8StringEncoding];
    XCTAssertFalse([json containsString:@"sensitive"]);
    XCTAssertFalse([json containsString:@"zQsecret"]);
    [db close];
}

- (void)testSoonestExpiryReported {
    BeskidMetrics *metrics = [[BeskidMetrics alloc] init];
    int64_t soon = (int64_t)[[NSDate dateWithTimeIntervalSinceNow:60] timeIntervalSince1970];
    int64_t later = (int64_t)[[NSDate dateWithTimeIntervalSinceNow:3600] timeIntervalSince1970];
    [metrics recordRecordWriteWithExpiresAt:later];
    [metrics recordRecordWriteWithExpiresAt:soon];
    NSDictionary *snap = [metrics snapshotDictionary];
    XCTAssertEqualObjects(snap[@"record"][@"soonestExpiry"], @(soon));
}

- (void)testDatabasePressureBytesReported {
    BeskidDatabase *db = BeskidAdminOpenTestDB(self);
    BeskidConfiguration *config = [BeskidConfiguration defaultConfiguration];
    BeskidMetrics *metrics = [[BeskidMetrics alloc] init];
    GZBeskidAdminSnapshot *snapshot = [[GZBeskidAdminSnapshot alloc] initWithDatabase:db metrics:metrics configuration:config];
    NSDictionary *value = [snapshot snapshot];
    int64_t bytes = [value[@"database"][@"storageBytes"] longLongValue];
    XCTAssertGreaterThan(bytes, (int64_t)0);
    [db close];
}

@end

// ── BeskidAdminUIPackTests ────────────────────────────────────────

@interface BeskidAdminUIPackTests : XCTestCase
@property(nonatomic, strong) GZAdminUIServiceConfig *config;
@property(nonatomic, strong) GZAdminUIHost *host;
@property(nonatomic, strong) GZBeskidAdminSnapshot *snapshot;
@property(nonatomic, strong) BeskidDatabase *db;
@property(nonatomic, strong) BeskidMetrics *metrics;
@end

@implementation BeskidAdminUIPackTests

- (void)setUp {
    [super setUp];
    self.db = BeskidAdminOpenTestDB(self);
    self.metrics = [[BeskidMetrics alloc] init];
    self.db.metrics = self.metrics;
    self.config = [[GZAdminUIServiceConfig alloc] init];
    self.config.host = @"127.0.0.1";
    self.config.port = 0;
    self.config.adminPassword = @"beskid-admin-password";
    self.config.serviceIdentifier = @"beskid";
    self.config.pdsBaseURL = [NSURL URLWithString:@"http://127.0.0.1:2583"];
    self.host = [[GZAdminUIHost alloc] initWithConfiguration:self.config packs:@[GZBeskidAdminUIPack.class]];
    self.snapshot = [[GZBeskidAdminSnapshot alloc] initWithDatabase:self.db metrics:self.metrics configuration:[BeskidConfiguration defaultConfiguration]];
    [GZBeskidAdminUIPack configureHost:self.host snapshot:self.snapshot];
}

- (void)tearDown {
    [self.host stop];
    [self.db close];
    [super tearDown];
}

- (ATProtoHttpRequest *)requestWithMethod:(NSString *)method path:(NSString *)path headers:(NSDictionary *)headers body:(NSDictionary *)body {
    NSData *data = body ? [NSJSONSerialization dataWithJSONObject:body options:0 error:nil] : [NSData data];
    NSMutableDictionary *requestHeaders = [headers mutableCopy] ?: [NSMutableDictionary dictionary];
    if (body) requestHeaders[@"Content-Type"] = @"application/json";
    return [[ATProtoHttpRequest alloc] initWithMethod:[method isEqualToString:@"POST"] ? HttpMethodPOST : HttpMethodGET
                                          methodString:method
                                                  path:path
                                           queryString:@""
                                           queryParams:@{}
                                               version:@"HTTP/1.1"
                                               headers:requestHeaders
                                                  body:data
                                         remoteAddress:@"127.0.0.1"];
}

- (NSString *)newNonce {
    NSString *nonce = nil, *cookie = nil;
    [self.host.authManager createCSRFNonce:&nonce cookie:&cookie secure:NO];
    return nonce;
}

- (void)testUnauthenticatedPartialRedirects {
    ATProtoHttpResponse *response = [self.host dispatchRequestForTesting:[self requestWithMethod:@"GET" path:@"/admin/partials/beskid-metrics" headers:@{} body:nil]];
    XCTAssertEqual(response.statusCode, HttpStatusFound);
}

- (void)testMetricsPartialRequiresScopedSessionCookie {
    NSString *token = [self.host.authManager createSessionToken];
    NSDictionary *headers = @{ @"Cookie": [NSString stringWithFormat:@"gz_admin_beskid_token=%@", token] };
    ATProtoHttpResponse *response = [self.host dispatchRequestForTesting:[self requestWithMethod:@"GET" path:@"/admin/partials/beskid-metrics" headers:headers body:nil]];
    XCTAssertEqual(response.statusCode, HttpStatusOK);
    XCTAssertTrue([response.bodyString containsString:@"Health"]);
}

- (void)testCachePartialNeverRendersRecordContent {
    [self.db saveRecord:@{@"$type": @"test", @"secret": @"do-not-leak"} did:@"did:plc:x" collection:@"test.ns" rkey:@"one" cid:@"bafy" ttl:3600 error:nil];
    [self.db saveIdentity:@"did:plc:x" handle:@"x.com" pdsEndpoint:@"https://pds.x.com" signingKey:@"zQleaked" rawDocument:@{} ttl:86400 error:nil];

    NSString *token = [self.host.authManager createSessionToken];
    ATProtoHttpResponse *response = [self.host dispatchRequestForTesting:[self requestWithMethod:@"GET" path:@"/admin/partials/beskid-cache" headers:@{ @"Cookie": [NSString stringWithFormat:@"gz_admin_beskid_token=%@", token] } body:nil]];
    XCTAssertEqual(response.statusCode, HttpStatusOK);
    XCTAssertFalse([response.bodyString containsString:@"do-not-leak"]);
    XCTAssertFalse([response.bodyString containsString:@"zQleaked"]);
}

- (void)testSessionCookieRejectsSiblingServiceCookie {
    NSString *token = [self.host.authManager createSessionToken];
    ATProtoHttpResponse *response = [self.host dispatchRequestForTesting:[self requestWithMethod:@"GET" path:@"/admin/partials/beskid-metrics" headers:@{ @"Cookie": [NSString stringWithFormat:@"gz_admin_relay_token=%@", token] } body:nil]];
    XCTAssertEqual(response.statusCode, HttpStatusFound);
}

- (void)testLoginRejectsWrongPasswordAndIssuesScopedSession {
    NSString *nonce = [self newNonce];
    NSDictionary *headers = @{ @"Cookie": [NSString stringWithFormat:@"gz_admin_beskid_nonce=%@", nonce], @"X-UI-Admin-Nonce": nonce };
    ATProtoHttpResponse *wrong = [self.host dispatchRequestForTesting:[self requestWithMethod:@"POST" path:@"/admin/login" headers:headers body:@{ @"password": @"wrong" }]];
    XCTAssertEqual(wrong.statusCode, HttpStatusUnauthorized);

    NSString *freshNonce = [self newNonce];
    NSDictionary *freshHeaders = @{ @"Cookie": [NSString stringWithFormat:@"gz_admin_beskid_nonce=%@", freshNonce], @"X-UI-Admin-Nonce": freshNonce };
    ATProtoHttpResponse *correct = [self.host dispatchRequestForTesting:[self requestWithMethod:@"POST" path:@"/admin/login" headers:freshHeaders body:@{ @"password": @"beskid-admin-password" }]];
    XCTAssertEqual(correct.statusCode, HttpStatusOK);
    XCTAssertTrue([[correct headerForKey:@"Set-Cookie"] hasPrefix:@"gz_admin_beskid_token="]);
    XCTAssertTrue([[correct headerForKey:@"Set-Cookie"] containsString:@"HttpOnly"]);
}

- (void)testEmbeddedHostUsesLoopbackAndConcurrencyEight {
    ATProtoHttpResponse *response = [self.host dispatchRequestForTesting:[self requestWithMethod:@"GET" path:@"/admin/partials/beskid-metrics" headers:@{} body:nil]];
    XCTAssertEqual(response.statusCode, HttpStatusFound);
    XCTAssertEqualObjects(self.host.httpServer.host, @"127.0.0.1");
    XCTAssertEqual(self.host.httpServer.maxConcurrentRequests, (NSUInteger)8);
}

- (void)testUpstreamPartialShowsHostsNotCredentials {
    [self.metrics recordUpstreamRequestToHost:@"pds.example.com"];
    [self.metrics recordUpstreamSuccessToHost:@"pds.example.com" latencyMillis:12];

    NSString *token = [self.host.authManager createSessionToken];
    ATProtoHttpResponse *response = [self.host dispatchRequestForTesting:[self requestWithMethod:@"GET" path:@"/admin/partials/beskid-upstreams" headers:@{ @"Cookie": [NSString stringWithFormat:@"gz_admin_beskid_token=%@", token] } body:nil]];
    XCTAssertTrue([response.bodyString containsString:@"pds.example.com"]);
    XCTAssertFalse([response.bodyString containsString:@"query"]);
    XCTAssertFalse([response.bodyString containsString:@"token"]);
    XCTAssertFalse([response.bodyString containsString:@"credential"]);
}

- (void)testPasswordFileLoaderTrimsCredentialNewlinesAndRedactsErrors {
    NSString *secret = @"beskid-systemd-credential";
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"beskid-pw-%@", NSUUID.UUID.UUIDString]];
    XCTAssertTrue([[secret stringByAppendingString:@"\n"] writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]);
    NSError *error = nil;
    XCTAssertEqualObjects(GZBeskidAdminPasswordFromFile(path, &error), secret);
    XCTAssertNil(error);
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];

    NSString *missingPath = [path stringByAppendingString:@"-missing"];
    XCTAssertNil(GZBeskidAdminPasswordFromFile(missingPath, &error));
    XCTAssertNotNil(error);
    XCTAssertFalse([error.localizedDescription containsString:secret]);
}

@end
