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
static MikrusDatabase *MikrusOpenDB(XCTestCase *t) {
    NSError *e = nil;
    MikrusDatabase *db = [[MikrusDatabase alloc] initWithPath:MDBPath(t.name) error:&e];
    XCTAssertNotNil(db, @"%@", e);
    XCTAssertTrue([db runMigrations:&e], @"%@", e);
    return db;
}

@interface MikrusMetricsTests : XCTestCase
@end
@implementation MikrusMetricsTests
- (void)testCountersAggregate {
    MikrusMetrics *m = [[MikrusMetrics alloc] init];
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
    MikrusDatabase *db = MikrusOpenDB(self);
    MikrusMetrics *m = [[MikrusMetrics alloc] init];
    MikrusConfiguration *c = [MikrusConfiguration defaultConfiguration];
    c.ingestEnabled = NO;
    GZMikrusAdminSnapshot *snap = [[GZMikrusAdminSnapshot alloc] initWithDatabase:db metrics:m configuration:c ingestEngine:nil];
    NSDictionary *v = [snap snapshot];
    XCTAssertEqualObjects(v[@"health"], @"ok");
    [db close];
}
- (void)testDatabasePressure {
    MikrusDatabase *db = MikrusOpenDB(self);
    GZMikrusAdminSnapshot *snap = [[GZMikrusAdminSnapshot alloc] initWithDatabase:db metrics:[[MikrusMetrics alloc] init] configuration:[MikrusConfiguration defaultConfiguration] ingestEngine:nil];
    XCTAssertGreaterThan([[snap snapshot][@"database"][@"storageBytes"] longLongValue], (long long)0);
    [db close];
}
@end

@interface MikrusAdminUIPackTests : XCTestCase
@property(nonatomic,strong) GZAdminUIServiceConfig *config;
@property(nonatomic,strong) GZAdminUIHost *host;
@property(nonatomic,strong) GZMikrusAdminSnapshot *snapshot;
@property(nonatomic,strong) MikrusDatabase *db;
@property(nonatomic,strong) MikrusMetrics *metrics;
@end
@implementation MikrusAdminUIPackTests
- (void)setUp {
    [super setUp];
    self.db = MikrusOpenDB(self);
    self.metrics = [[MikrusMetrics alloc] init];
    self.config = [[GZAdminUIServiceConfig alloc] init];
    self.config.host = @"127.0.0.1"; self.config.port = 0;
    self.config.adminPassword = @"mikrus-admin";
    self.config.serviceIdentifier = @"mikrus";
    self.host = [[GZAdminUIHost alloc] initWithConfiguration:self.config packs:@[GZMikrusAdminUIPack.class]];
    self.snapshot = [[GZMikrusAdminSnapshot alloc] initWithDatabase:self.db metrics:self.metrics configuration:[MikrusConfiguration defaultConfiguration] ingestEngine:nil];
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
- (void)testMetricsRequiresScopedSession {
    NSString *t = [self.host.authManager createSessionToken];
    NSDictionary *hdr = @{@"Cookie":[NSString stringWithFormat:@"gz_admin_mikrus_token=%@",t]};
    ATProtoHttpResponse *res = [self.host dispatchRequestForTesting:[self r:@"GET" path:@"/admin/partials/mikrus-metrics" headers:hdr body:nil]];
    XCTAssertEqual(res.statusCode, HttpStatusOK);
    XCTAssertTrue([res.bodyString containsString:@"Health"]);
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
@end
