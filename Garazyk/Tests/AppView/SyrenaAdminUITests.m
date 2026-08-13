// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "AppView/Server/AdminUI/SyrenaAdminUIPack.h"
#import "AppView/Server/AdminUI/SyrenaAdminSnapshot.h"
#import "AppView/Server/AdminUI/SyrenaMetrics.h"
#import "AppView/Server/AppViewDatabase.h"
#import "AppView/Server/Config/AppViewConfiguration.h"
#import "AppView/Server/Ingest/AppViewIngestEngine.h"
#import "AdminUIServer/GZAdminUIHost+Private.h"
#import "AdminUIServer/GZAdminUIHost.h"
#import "AdminUIServer/UIAuthManager.h"
#import "AdminUIServer/UIServiceConfig.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"

@interface SyrenaAdminUITests : XCTestCase
@property (nonatomic, strong) GZSyrenaMetrics *metrics;
@property (nonatomic, strong) GZSyrenaAdminSnapshot *snapshot;
@property (nonatomic, strong) GZAdminUIServiceConfig *config;
@property (nonatomic, strong) GZAdminUIHost *host;
@end

@implementation SyrenaAdminUITests

- (void)setUp {
    self.metrics = [[GZSyrenaMetrics alloc] init];
    [self.metrics recordIngestEvent];
    [self.metrics recordIngestCommit];
    [self.metrics recordIngestOp];
    [self.metrics recordBackfillCompleted];
    [self.metrics recordQuery:@"identity"];
    [self.metrics recordQueryError];

    GZAppViewConfiguration *avConfig = [GZAppViewConfiguration defaultConfiguration];
    avConfig.relayURLs = @[@"wss://test.example.com"];

    self.snapshot = [[GZSyrenaAdminSnapshot alloc] initWithDatabase:nil
                                                             metrics:self.metrics
                                                       configuration:avConfig
                                                        ingestEngine:nil
                                                 backfillOrchestrator:nil];

    self.config = [[GZAdminUIServiceConfig alloc] init];
    self.config.adminPassword = @"test";
    self.config.serviceIdentifier = @"syrena-test";
    self.host = [[GZAdminUIHost alloc] initWithConfiguration:self.config
                                                        packs:@[GZSyrenaAdminUIPack.class]];
    [GZSyrenaAdminUIPack configureHost:self.host snapshot:self.snapshot];
}

- (ATProtoHttpRequest *)r:(NSString *)method path:(NSString *)path headers:(NSDictionary *)h body:(NSData *)body {
    NSMutableDictionary *headers = [h mutableCopy] ?: [NSMutableDictionary dictionary];
    if (body) headers[@"Content-Type"] = @"application/json";
    return [[ATProtoHttpRequest alloc] initWithMethod:[method isEqualToString:@"POST"] ? HttpMethodPOST : HttpMethodGET
                                          methodString:method
                                                 path:path
                                          queryString:@""
                                           queryParams:@{}
                                              version:@"HTTP/1.1"
                                               headers:headers
                                                  body:body
                                        remoteAddress:@"127.0.0.1"];
}

#pragma mark - Metrics

- (void)testMetricsSnapshotReturnsIngestEvent {
    NSDictionary *snap = [self.metrics snapshotDictionary];
    XCTAssertEqualObjects(snap[@"ingest"][@"events"], @(1));
    XCTAssertEqualObjects(snap[@"ingest"][@"commits"], @(1));
    XCTAssertEqualObjects(snap[@"ingest"][@"ops"], @(1));
    XCTAssertEqualObjects(snap[@"backfill"][@"completed"], @(1));
}

- (void)testMetricsStartsAtZeroForUnrecorded {
    GZSyrenaMetrics *m = [[GZSyrenaMetrics alloc] init];
    NSDictionary *snap = [m snapshotDictionary];
    XCTAssertEqualObjects(snap[@"ingest"][@"events"], @(0));
    XCTAssertEqualObjects(snap[@"queries"][@"errors"], @(0));
    XCTAssertEqualObjects(snap[@"rateLimitRejects"], @(0));
}

- (void)testMetricsQueryFamilies {
    [self.metrics recordQuery:@"backlink"];
    [self.metrics recordQuery:@"backlink"];
    [self.metrics recordQuery:@"manyToMany"];
    [self.metrics recordQuery:@"identity"];
    [self.metrics recordQuery:@"record"];
    [self.metrics recordQuery:@"unknown"];
    NSDictionary *snap = [self.metrics snapshotDictionary];
    XCTAssertEqualObjects(snap[@"queries"][@"backlink"], @(2));
    XCTAssertEqualObjects(snap[@"queries"][@"manyToMany"], @(1));
    XCTAssertEqualObjects(snap[@"queries"][@"total"], @(7)); // +1 from setUp
}

#pragma mark - Snapshot

- (void)testSnapshotReturnsHealthWhenIngestAbsent {
    NSDictionary *s = [self.snapshot snapshot];
    XCTAssertEqualObjects(s[@"health"], @"degraded");  // ingestEngine is nil → not running
}

- (void)testSnapshotHasRequiredKeys {
    NSDictionary *s = [self.snapshot snapshot];
    XCTAssertNotNil(s[@"health"]);
    XCTAssertNotNil(s[@"uptimeSeconds"]);
    XCTAssertNotNil(s[@"lanes"]);
    XCTAssertNotNil(s[@"ingest"]);
    XCTAssertNotNil(s[@"backfill"]);
    XCTAssertNotNil(s[@"coverage"]);
    XCTAssertNotNil(s[@"exceptions"]);
    XCTAssertNotNil(s[@"indexes"]);
    XCTAssertNotNil(s[@"queries"]);
    XCTAssertNotNil(s[@"database"]);
}

- (void)testSnapshotLanesIncludeFirehoseSyncServing {
    NSDictionary *lanes = [self.snapshot snapshot][@"lanes"];
    XCTAssertEqualObjects(lanes[@"firehose"], @"down");
    XCTAssertEqualObjects(lanes[@"sync"], @"idle");
    XCTAssertNotNil(lanes[@"serving"]);
}

- (void)testSnapshotConfigReflectsRelays {
    NSDictionary *s = [self.snapshot snapshot];
    NSArray *relays = s[@"config"][@"relayURLs"];
    XCTAssertEqual(relays.count, 1u);
    XCTAssertEqualObjects(relays[0], @"wss://test.example.com");
}

- (void)testEnqueueWithoutOrchestratorFailsClosed {
    NSDictionary *result = [self.snapshot enqueueDIDs:@[@"did:plc:abc"]];
    XCTAssertEqualObjects(result[@"error"], @"BackfillDisabled");
}

#pragma mark - Pack auth + scoping

- (void)testUnauthRedirects {
    ATProtoHttpResponse *res = [self.host dispatchRequestForTesting:
        [self r:@"GET" path:@"/admin/partials/appview-serving" headers:@{} body:nil]];
    XCTAssertEqual(res.statusCode, 302);
}

- (void)testSessionAuthGrantsAllPartialRoutes {
    NSString *token = [self.host.authManager createSessionToken];
    NSString *cookie = [NSString stringWithFormat:@"%@=%@", self.host.authManager.sessionCookieName, token];
    NSDictionary *h = @{@"Cookie": cookie};

    for (NSString *path in @[@"/admin/partials/appview-serving",
                              @"/admin/partials/appview-firehose",
                              @"/admin/partials/appview-reposync",
                              @"/admin/partials/appview-coverage",
                              @"/admin/partials/appview-queue",
                              // compatibility aliases
                              @"/admin/partials/appview-metrics",
                              @"/admin/partials/ingest-health",
                              @"/admin/partials/appview-backfill",
                              @"/admin/partials/appview-indexes"]) {
        ATProtoHttpResponse *res = [self.host dispatchRequestForTesting:
            [self r:@"GET" path:path headers:h body:nil]];
        XCTAssertEqual(res.statusCode, 200, @"path %@", path);
    }
}

- (void)testMutationRequiresCSRF {
    NSString *token = [self.host.authManager createSessionToken];
    NSString *cookie = [NSString stringWithFormat:@"%@=%@", self.host.authManager.sessionCookieName, token];
    NSData *body = [NSJSONSerialization dataWithJSONObject:@{@"dids": @[@"did:plc:abc"]} options:0 error:nil];
    ATProtoHttpResponse *res = [self.host dispatchRequestForTesting:
        [self r:@"POST" path:@"/admin/actions/appview-enqueue-dids" headers:@{@"Cookie": cookie} body:body]];
    XCTAssertEqual(res.statusCode, 403);
}

#pragma mark - HTML output

- (void)testServingHTMLContainsPipelineAndQueries {
    NSDictionary *s = [self.snapshot snapshot];
    NSString *html = [GZSyrenaAdminUIPack servingHTML:s];
    XCTAssertTrue([html containsString:@"Pipeline"]);
    XCTAssertTrue([html containsString:@"Serving health"]);
    XCTAssertTrue([html containsString:@"Query families"]);
    XCTAssertTrue([html containsString:@"Exceptions"]);
    XCTAssertTrue([html containsString:@"Degraded"] || [html containsString:@"degraded"] || [html containsString:@"badge"]);
}

- (void)testRepoSyncHTMLShowsDisabledWhenNilOrch {
    NSDictionary *s = [self.snapshot snapshot];
    NSString *html = [GZSyrenaAdminUIPack repoSyncHTML:s queue:@{@"entries": @[], @"enabled": @NO}];
    XCTAssertTrue([html containsString:@"no"]);
    XCTAssertTrue([html containsString:@"Enqueue DIDs"]);
    XCTAssertTrue([html containsString:@"Rebuild scope"]);
}

#pragma mark - Password helper

- (void)testPasswordFromEnv {
    setenv("SYRENA_ADMIN_PASSWORD", "secret123", 1);
    NSString *pw = GZSyrenaAdminPassword(nil);
    XCTAssertEqualObjects(pw, @"secret123");
    unsetenv("SYRENA_ADMIN_PASSWORD");
}

- (void)testPasswordReturnsNilWhenUnset {
    unsetenv("SYRENA_ADMIN_PASSWORD");
    unsetenv("SYRENA_ADMIN_PASSWORD_FILE");
    XCTAssertNil(GZSyrenaAdminPassword(nil));
}

#pragma mark - Sidebar sections

- (void)testSidebarSectionsMatchPartialRoutes {
    NSArray *sections = [GZSyrenaAdminUIPack sidebarSections];
    XCTAssertEqual(sections.count, 7u);
    NSArray *expectedIds = @[@"appview-serving", @"appview-firehose", @"appview-reposync",
                             @"appview-coverage", @"appview-exceptions", @"appview-probe", @"appview-actor"];
    for (NSUInteger i = 0; i < sections.count; i++) {
        XCTAssertEqualObjects(sections[i][@"tabIdentifier"], expectedIds[i]);
    }
    NSArray *labels = @[@"Serving", @"Firehose", @"Repo sync", @"Coverage", @"Exceptions", @"Probe", @"Actor dig"];
    for (NSUInteger i = 0; i < sections.count; i++) {
        XCTAssertEqualObjects(sections[i][@"displayName"], labels[i]);
    }
}

- (void)testProbeCatalogAndHealthMethod {
    NSArray *catalog = [self.snapshot probeCatalog];
    XCTAssertGreaterThanOrEqual(catalog.count, 3u);
    NSDictionary *health = [self.snapshot probeMethod:@"_admin.health" params:@{}];
    XCTAssertEqualObjects(health[@"method"], @"_admin.health");
    XCTAssertNotNil(health[@"result"][@"lanes"]);
    NSDictionary *denied = [self.snapshot probeMethod:@"com.atproto.sync.getBlob" params:@{}];
    XCTAssertEqualObjects(denied[@"error"], @"MethodNotAllowed");
}

- (void)testExceptionsAndActorDigWithoutDatabase {
    NSDictionary *exceptions = [self.snapshot exceptionsWithLimit:10];
    XCTAssertEqual([(NSArray *)exceptions[@"validation"] count], 0u);
    NSDictionary *missing = [self.snapshot actorDigForIdentifier:@"did:plc:nobody"];
    XCTAssertEqualObjects(missing[@"error"], @"Unavailable");
}

- (void)testNewPartialsRequireSession {
    NSString *token = [self.host.authManager createSessionToken];
    NSString *cookie = [NSString stringWithFormat:@"%@=%@", self.host.authManager.sessionCookieName, token];
    NSDictionary *h = @{@"Cookie": cookie};
    for (NSString *path in @[@"/admin/partials/appview-exceptions",
                              @"/admin/partials/appview-probe",
                              @"/admin/partials/appview-actor"]) {
        ATProtoHttpResponse *res = [self.host dispatchRequestForTesting:
            [self r:@"GET" path:path headers:h body:nil]];
        XCTAssertEqual(res.statusCode, 200, @"path %@", path);
    }
    NSString *html = [GZSyrenaAdminUIPack exceptionsHTML:@{
        @"counts": @{@"deadLetter": @1, @"hookDeadLetter": @2, @"pendingIndex": @3},
        @"validation": @[@{@"createdAt": @"t", @"did": @"did:plc:x", @"collection": @"c", @"seq": @1, @"error": @"e"}],
        @"hooks": @[],
    }];
    XCTAssertTrue([html containsString:@"Validation dead letters"]);
    XCTAssertTrue([html containsString:@"did:plc:x"]);
    XCTAssertFalse([html containsString:@"raw_record"]);
}

@end
