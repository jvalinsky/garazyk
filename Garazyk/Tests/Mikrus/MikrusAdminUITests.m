// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>

#import "AdminUIServer/GZAdminUIHost+Private.h"
#import "AdminUIServer/GZAdminUIHost.h"
#import "AdminUIServer/UIAuthManager.h"
#import "AdminUIServer/UIServiceConfig.h"
#import "Mikrus/AdminUI/MikrusAdminSnapshot.h"
#import "Mikrus/AdminUI/MikrusAdminUIPack.h"
#import "Mikrus/MikrusConfiguration.h"
#import "Mikrus/MikrusDatabase.h"
#import "Mikrus/MikrusMetrics.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"

static NSString *MDBPath(NSString *name) {
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"garazyk-mikrus-%@-%@", name, NSUUID.UUID.UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir stringByAppendingPathComponent:@"test.db"];
}
static GZMikrusDatabase *MikrusOpenDB(XCTestCase *t) {
    NSError *e = nil;
    GZMikrusDatabase *db = [[GZMikrusDatabase alloc] initWithPath:MDBPath(t.name) error:&e];
    XCTAssertNotNil(db, @"%@", e);
    XCTAssertTrue([db runMigrations:&e], @"%@", e);
    return db;
}

@interface MikrusMetricsTests : XCTestCase
@end
@implementation MikrusMetricsTests
- (void)testCountersAggregate {
    GZMikrusMetrics *m = [[GZMikrusMetrics alloc] init];
    [m recordIngestEvent]; [m recordIngestCommit]; [m recordIngestOp];
    [m recordRecordIndexed]; [m recordRecordIndexed];
    [m recordIngestError]; [m recordRateLimitReject];
    [m recordQueryBacklink]; [m recordQueryManyToMany];
    NSDictionary *s = [m snapshotDictionary];
    XCTAssertEqualObjects(s[@"ingest"][@"events"], @1);
    XCTAssertEqualObjects(s[@"ingest"][@"recordsIndexed"], @2);
    XCTAssertEqualObjects(s[@"ingest"][@"errors"], @1);
    XCTAssertEqualObjects(s[@"rateLimitRejects"], @1);
}
@end

@interface MikrusAdminSnapshotTests : XCTestCase
@end
@implementation MikrusAdminSnapshotTests
- (void)testEmptySnapshotIsOk {
    GZMikrusDatabase *db = MikrusOpenDB(self);
    GZMikrusMetrics *m = [[GZMikrusMetrics alloc] init];
    GZMikrusConfiguration *c = [GZMikrusConfiguration defaultConfiguration];
    c.ingestEnabled = NO;
    GZMikrusAdminSnapshot *snap = [[GZMikrusAdminSnapshot alloc] initWithDatabase:db metrics:m configuration:c ingestEngine:nil];
    NSDictionary *v = [snap snapshot];
    XCTAssertEqualObjects(v[@"health"], @"ok");
    [db close];
}
- (void)testIdentityCountUsesHandlesTable {
    GZMikrusDatabase *db = MikrusOpenDB(self);
    NSError *error = nil;
    XCTAssertTrue([db saveHandle:@"alice.test" did:@"did:plc:alice" error:&error], @"%@", error);
    GZMikrusAdminSnapshot *snap = [[GZMikrusAdminSnapshot alloc] initWithDatabase:db
                                                                          metrics:[[GZMikrusMetrics alloc] init]
                                                                    configuration:[GZMikrusConfiguration defaultConfiguration]
                                                                     ingestEngine:nil];
    NSDictionary *identities = [snap indexFamilyStatistics][@"identities"];
    XCTAssertGreaterThan([identities[@"approxCount"] longLongValue], (long long)0);
    [db close];
}
- (void)testEnabledIngestWithoutEngineIsDegraded {
    GZMikrusDatabase *db = MikrusOpenDB(self);
    GZMikrusConfiguration *configuration = [GZMikrusConfiguration defaultConfiguration];
    configuration.ingestEnabled = YES;
    GZMikrusAdminSnapshot *snapshot = [[GZMikrusAdminSnapshot alloc] initWithDatabase:db
        metrics:[[GZMikrusMetrics alloc] init] configuration:configuration ingestEngine:nil];
    XCTAssertEqualObjects([snapshot snapshot][@"health"], @"degraded");
    [db close];
}
- (void)testRecentErrorsRedactFixturePayload {
    GZMikrusDatabase *db = MikrusOpenDB(self);
    NSError *error = nil;
    // The database intentionally has no public write API for this optional
    // event-log fixture; executeQuery is used here only to seed the test DB.
    NSArray *created = [db executeQuery:@"CREATE TABLE ingest_errors (timestamp INTEGER, relay_url TEXT, error_message TEXT, did TEXT, seq INTEGER)"
        params:@[] error:&error];
    XCTAssertNotNil(created, @"%@", error);
    NSArray *inserted = [db executeQuery:@"INSERT INTO ingest_errors (timestamp, relay_url, error_message, did, seq) VALUES (?, ?, ?, ?, ?)"
        params:@[@1, @"https://user:pass@relay.example/private?token=secret#frag", @"secret body /private/key", @"did:plc:secret", @2] error:&error];
    XCTAssertNotNil(inserted, @"%@", error);
    GZMikrusAdminSnapshot *snapshot = [[GZMikrusAdminSnapshot alloc] initWithDatabase:db
        metrics:[[GZMikrusMetrics alloc] init] configuration:[GZMikrusConfiguration defaultConfiguration]
        ingestEngine:nil];
    NSDictionary *row = [snapshot recentErrors:10].firstObject;
    XCTAssertEqualObjects(row[@"error_message"], @"Ingest error (details redacted)");
    XCTAssertEqualObjects(row[@"relay_url"], @"relay.example");
    XCTAssertEqual([row[@"seq"] integerValue], 2);
    NSString *json = [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:[snapshot snapshot] options:0 error:nil] encoding:NSUTF8StringEncoding];
    XCTAssertFalse([json containsString:@"secret body"]);
    XCTAssertFalse([json containsString:@"/private/key"]);
    XCTAssertFalse([json containsString:@"user:pass"]);
    XCTAssertFalse([json containsString:@"did:plc:secret"]);
    XCTAssertFalse([json containsString:@"token=secret"]);
    XCTAssertFalse([json containsString:@"/private"]);
    XCTAssertFalse([json containsString:@"#frag"]);
    XCTAssertEqual([snapshot recentErrors:1000].count, 1u);
    XCTAssertEqual([snapshot recentErrors:-1].count, 0u);
    [db close];
}
- (void)testExplorePageIsBoundedAndCursorReconciles {
    GZMikrusDatabase *db = MikrusOpenDB(self);
    NSError *error = nil;
    for (NSInteger i = 0; i < 105; i++) {
        NSString *rkey = [NSString stringWithFormat:@"%03ld", (long)i];
        BOOL indexed = [db indexRecord:@{@"$type": @"test"} did:@"did:plc:bounded"
            collection:@"test.collection" rkey:rkey cid:nil seq:i error:&error];
        XCTAssertTrue(indexed, @"%@", error);
    }
    GZMikrusAdminSnapshot *snapshot = [[GZMikrusAdminSnapshot alloc] initWithDatabase:db
        metrics:[[GZMikrusMetrics alloc] init] configuration:[GZMikrusConfiguration defaultConfiguration]
        ingestEngine:nil];
    NSString *cursor = nil;
    NSArray *first = [snapshot listRecordsInCollection:@"test.collection" limit:100 cursor:nil nextCursor:&cursor];
    XCTAssertEqual(first.count, 100u);
    XCTAssertNotNil(cursor);
    NSArray *second = [snapshot listRecordsInCollection:@"test.collection" limit:100 cursor:cursor nextCursor:nil];
    XCTAssertEqual([second count], 5u);
    [db close];
}
- (void)testDatabasePressure {
    GZMikrusDatabase *db = MikrusOpenDB(self);
    GZMikrusAdminSnapshot *snap = [[GZMikrusAdminSnapshot alloc] initWithDatabase:db metrics:[[GZMikrusMetrics alloc] init] configuration:[GZMikrusConfiguration defaultConfiguration] ingestEngine:nil];
    XCTAssertGreaterThan([[snap snapshot][@"database"][@"storageBytes"] longLongValue], (long long)0);
    [db close];
}
@end

@interface MikrusAdminUIPackTests : XCTestCase
@property(nonatomic,strong) GZAdminUIServiceConfig *config;
@property(nonatomic,strong) GZAdminUIHost *host;
@property(nonatomic,strong) GZMikrusAdminSnapshot *snapshot;
@property(nonatomic,strong) GZMikrusDatabase *db;
@property(nonatomic,strong) GZMikrusMetrics *metrics;
@end
@implementation MikrusAdminUIPackTests
- (void)setUp {
    [super setUp];
    self.db = MikrusOpenDB(self);
    self.metrics = [[GZMikrusMetrics alloc] init];
    self.config = [[GZAdminUIServiceConfig alloc] init];
    self.config.host = @"127.0.0.1"; self.config.port = 0;
    self.config.adminPassword = @"mikrus-admin";
    self.config.serviceIdentifier = @"mikrus";
    self.host = [[GZAdminUIHost alloc] initWithConfiguration:self.config packs:@[GZMikrusAdminUIPack.class]];
    self.snapshot = [[GZMikrusAdminSnapshot alloc] initWithDatabase:self.db metrics:self.metrics configuration:[GZMikrusConfiguration defaultConfiguration] ingestEngine:nil];
    [GZMikrusAdminUIPack configureHost:self.host snapshot:self.snapshot];
}
- (void)tearDown { [self.host stop]; [self.db close]; [super tearDown]; }

- (ATProtoHttpRequest *)r:(NSString *)method path:(NSString *)path headers:(NSDictionary *)hdrs body:(NSDictionary *)body {
    NSData *d = body ? [NSJSONSerialization dataWithJSONObject:body options:0 error:nil] : [NSData data];
    NSMutableDictionary *h = [hdrs mutableCopy] ?: [NSMutableDictionary dictionary];
    if (body) h[@"Content-Type"] = @"application/json";
    return [[ATProtoHttpRequest alloc] initWithMethod:[method isEqualToString:@"POST"]?HttpMethodPOST:HttpMethodGET methodString:method path:path queryString:@"" queryParams:@{} version:@"HTTP/1.1" headers:h body:d remoteAddress:@"127.0.0.1"];
}

- (void)testUnauthRedirects {
    ATProtoHttpResponse *res = [self.host dispatchRequestForTesting:[self r:@"GET" path:@"/admin/partials/mikrus-metrics" headers:@{} body:nil]];
    XCTAssertEqual(res.statusCode, HttpStatusFound);
}
- (void)testSingleSurfaceShellAndLogin {
    ATProtoHttpResponse *login = [self.host dispatchRequestForTesting:[self r:@"GET" path:@"/admin/login" headers:@{} body:nil]];
    XCTAssertEqual(login.statusCode, HttpStatusOK);
    XCTAssertTrue([login.bodyString containsString:@"Mikrus"]);
    XCTAssertTrue([login.bodyString containsString:@"login-panel"]);
    XCTAssertFalse([login.bodyString containsString:@"mesh-bg"]);
    XCTAssertFalse([login.bodyString containsString:@"background-clip: text"]);

    NSString *token = [self.host.authManager createSessionToken];
    NSDictionary *hdr = @{@"Cookie":[NSString stringWithFormat:@"gz_admin_mikrus_token=%@",token]};
    ATProtoHttpResponse *shell = [self.host dispatchRequestForTesting:[self r:@"GET" path:@"/admin" headers:hdr body:nil]];
    XCTAssertEqual(shell.statusCode, HttpStatusOK);
    XCTAssertTrue([shell.bodyString containsString:@"<h1 class=\"admin-header-title\">Mikrus</h1>"]);
    XCTAssertTrue([shell.bodyString containsString:@"<aside class=\"admin-sidebar\""]);
    XCTAssertTrue([shell.bodyString containsString:@"Overview"]);
    XCTAssertTrue([shell.bodyString containsString:@"Ingestion"]);
    XCTAssertTrue([shell.bodyString containsString:@"Indexes"]);
    XCTAssertTrue([shell.bodyString containsString:@"Explore"]);
    XCTAssertFalse([shell.bodyString containsString:@"<nav class=\"service-segments\""]);
}
- (void)testMetricsRequiresScopedSession {
    NSString *t = [self.host.authManager createSessionToken];
    NSDictionary *hdr = @{@"Cookie":[NSString stringWithFormat:@"gz_admin_mikrus_token=%@",t]};
    ATProtoHttpResponse *res = [self.host dispatchRequestForTesting:[self r:@"GET" path:@"/admin/partials/mikrus-metrics" headers:hdr body:nil]];
    XCTAssertEqual(res.statusCode, HttpStatusOK);
    XCTAssertTrue([res.bodyString containsString:@"Health"]);
}
- (void)testExploreSearchAndCollectionBrowse {
    NSError *error = nil;
    BOOL indexed = [self.db indexRecord:@{@"$type": @"app.bsky.feed.post", @"text": @"hello"}
                                    did:@"did:plc:explore1"
                             collection:@"app.bsky.feed.post"
                                   rkey:@"3jabc"
                                    cid:@"bafyreiabc"
                                    seq:42
                                  error:&error];
    XCTAssertTrue(indexed, @"%@", error);

    NSString *t = [self.host.authManager createSessionToken];
    NSDictionary *hdr = @{@"Cookie":[NSString stringWithFormat:@"gz_admin_mikrus_token=%@",t]};

    ATProtoHttpResponse *shell = [self.host dispatchRequestForTesting:[self r:@"GET" path:@"/admin/partials/mikrus-explore" headers:hdr body:nil]];
    XCTAssertEqual(shell.statusCode, HttpStatusOK);
    XCTAssertTrue([shell.bodyString containsString:@"Explore index"]);
    XCTAssertTrue([shell.bodyString containsString:@"mikrus-explore-results"]);

    ATProtoHttpRequest *searchReq = [[ATProtoHttpRequest alloc] initWithMethod:HttpMethodGET
                                                                  methodString:@"GET"
                                                                          path:@"/admin/partials/mikrus-explore-results"
                                                                   queryString:@"q=app.bsky.feed.post"
                                                                   queryParams:@{@"q": @"app.bsky.feed.post"}
                                                                       version:@"HTTP/1.1"
                                                                       headers:hdr
                                                                          body:[NSData data]
                                                                 remoteAddress:@"127.0.0.1"];
    ATProtoHttpResponse *search = [self.host dispatchRequestForTesting:searchReq];
    XCTAssertEqual(search.statusCode, HttpStatusOK);
    XCTAssertTrue([search.bodyString containsString:@"at://did:plc:explore1/app.bsky.feed.post/3jabc"]);

    ATProtoHttpRequest *detailReq = [[ATProtoHttpRequest alloc] initWithMethod:HttpMethodGET
                                                                   methodString:@"GET"
                                                                           path:@"/admin/partials/mikrus-explore-record"
                                                                    queryString:@"uri=at://did:plc:explore1/app.bsky.feed.post/3jabc"
                                                                    queryParams:@{@"uri": @"at://did:plc:explore1/app.bsky.feed.post/3jabc"}
                                                                        version:@"HTTP/1.1"
                                                                        headers:hdr
                                                                           body:[NSData data]
                                                                  remoteAddress:@"127.0.0.1"];
    ATProtoHttpResponse *detail = [self.host dispatchRequestForTesting:detailReq];
    XCTAssertEqual(detail.statusCode, HttpStatusOK);
    XCTAssertTrue([detail.bodyString containsString:@"hello"]);
    XCTAssertTrue([detail.bodyString containsString:@"code-block"]);
}
- (void)testSnapshotExploreAPIs {
    NSError *error = nil;
    BOOL indexed = [self.db indexRecord:@{@"$type": @"app.bsky.feed.like", @"subject": @{@"uri": @"at://did:plc:x/app.bsky.feed.post/1"}}
                                    did:@"did:plc:liker"
                             collection:@"app.bsky.feed.like"
                                   rkey:@"like1"
                                    cid:nil
                                    seq:7
                                  error:&error];
    XCTAssertTrue(indexed, @"%@", error);
    NSString *next = nil;
    NSArray *rows = [self.snapshot listRecordsInCollection:@"app.bsky.feed.like" limit:10 cursor:nil nextCursor:&next];
    XCTAssertEqual(rows.count, 1u);
    XCTAssertEqualObjects(rows.firstObject[@"rkey"], @"like1");
    NSDictionary *detail = [self.snapshot recordDetailForURI:@"at://did:plc:liker/app.bsky.feed.like/like1"];
    XCTAssertNotNil(detail[@"value"]);
    NSArray *didHits = [self.snapshot searchIndexWithQuery:@"did:plc:liker" limit:10];
    XCTAssertEqualObjects(didHits.firstObject[@"collection"], @"app.bsky.feed.like");
}
- (void)testSiblingCookieRejected {
    NSString *t = [self.host.authManager createSessionToken];
    NSDictionary *hdr = @{@"Cookie":[NSString stringWithFormat:@"gz_admin_relay_token=%@",t]};
    ATProtoHttpResponse *res = [self.host dispatchRequestForTesting:[self r:@"GET" path:@"/admin/partials/mikrus-metrics" headers:hdr body:nil]];
    XCTAssertEqual(res.statusCode, HttpStatusFound);
}
- (void)testLoginWrongPasswordRejected {
    NSString *nonce = [self newNonce];
    NSDictionary *h = @{@"Cookie":[NSString stringWithFormat:@"gz_admin_mikrus_nonce=%@",nonce],@"X-UI-Admin-Nonce":nonce};
    ATProtoHttpResponse *wrong = [self.host dispatchRequestForTesting:[self r:@"POST" path:@"/admin/login" headers:h body:@{@"password":@"wrong"}]];
    XCTAssertEqual(wrong.statusCode, HttpStatusUnauthorized);
    NSString *fn = [self newNonce];
    NSDictionary *fh = @{@"Cookie":[NSString stringWithFormat:@"gz_admin_mikrus_nonce=%@",fn],@"X-UI-Admin-Nonce":fn};
    ATProtoHttpResponse *ok = [self.host dispatchRequestForTesting:[self r:@"POST" path:@"/admin/login" headers:fh body:@{@"password":@"mikrus-admin"}]];
    XCTAssertEqual(ok.statusCode, HttpStatusOK);
    XCTAssertTrue([[ok headerForKey:@"Set-Cookie"] hasPrefix:@"gz_admin_mikrus_token="]);
}
- (NSString *)newNonce { NSString *n=nil,*c=nil; [self.host.authManager createCSRFNonce:&n cookie:&c secure:NO]; return n; }
- (void)testLoopbackAndConcurrency {
    [self.host dispatchRequestForTesting:[self r:@"GET" path:@"/admin/partials/mikrus-metrics" headers:@{} body:nil]];
    XCTAssertEqualObjects(self.host.httpServer.host, @"127.0.0.1");
    XCTAssertEqual(self.host.httpServer.maxConcurrentRequests, (NSUInteger)8);
}
- (void)testPasswordFileLoader {
    NSString *s = @"mikrus-secret";
    NSString *p = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"mikrus-pw-%@",NSUUID.UUID.UUIDString]];
    XCTAssertTrue([[s stringByAppendingString:@"\n"] writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil]);
    NSError *e = nil;
    XCTAssertEqualObjects(GZMikrusAdminPasswordFromFile(p,&e), s);
    XCTAssertNil(e);
    [[NSFileManager defaultManager] removeItemAtPath:p error:nil];
}
- (void)testAuthenticatedPollingSurvivesConcurrentIndexMutation {
    NSString *token = [self.host.authManager createSessionToken];
    NSDictionary *headers = @{ @"Cookie": [NSString stringWithFormat:@"gz_admin_mikrus_token=%@", token] };
    dispatch_group_t group = dispatch_group_create();
    for (NSInteger i = 0; i < 24; i++) {
        dispatch_group_async(group, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSError *error = nil;
            BOOL indexed = [self.db indexRecord:@{@"$type": @"test", @"body": @"private"}
                did:@"did:plc:poll" collection:@"test.poll" rkey:[NSString stringWithFormat:@"%ld", (long)i]
                cid:nil seq:i error:&error];
            XCTAssertTrue(indexed, @"%@", error);
            ATProtoHttpRequest *request = [[ATProtoHttpRequest alloc] initWithMethod:HttpMethodGET methodString:@"GET"
                path:@"/admin/partials/mikrus-indexes" queryString:@"" queryParams:@{} version:@"HTTP/1.1"
                headers:headers body:[NSData data] remoteAddress:@"127.0.0.1"];
            ATProtoHttpResponse *response = [self.host dispatchRequestForTesting:request];
            XCTAssertEqual(response.statusCode, HttpStatusOK);
            XCTAssertFalse([response.bodyString containsString:@"private"]);
        });
    }
    long waitResult = dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
    XCTAssertEqual(waitResult, 0L, @"concurrent Mikrus polling timed out");
}
@end
