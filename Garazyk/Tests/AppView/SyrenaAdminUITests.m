// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "AppView/Server/AdminUI/SyrenaAdminUIPack.h"
#import "AppView/Server/AdminUI/SyrenaAdminSnapshot.h"
#import "AppView/Server/AdminUI/SyrenaMetrics.h"
#import "AppView/Server/AppViewDatabase.h"
#import "AppView/Server/Config/AppViewConfiguration.h"
#import "AppView/Server/Ingest/AppViewIngestEngine.h"
#import "AdminUIServer/GZAdminUIHost.h"
#import "AdminUIServer/UIServiceConfig.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"

@interface SyrenaAdminUITests : XCTestCase
@property (nonatomic, strong) SyrenaMetrics *metrics;
@property (nonatomic, strong) GZSyrenaAdminSnapshot *snapshot;
@property (nonatomic, strong) GZAdminUIServiceConfig *config;
@property (nonatomic, strong) GZAdminUIHost *host;
@end

@implementation SyrenaAdminUITests

- (void)setUp {
    self.metrics = [[SyrenaMetrics alloc] init];
    [self.metrics recordIngestEvent];
    [self.metrics recordIngestCommit];
    [self.metrics recordIngestOp];
    [self.metrics recordBackfillCompleted];

    AppViewConfiguration *avConfig = [AppViewConfiguration defaultConfiguration];
    avConfig.relayURLs = @[@"wss://test.example.com"];

    // Snapshot without a real database — nil database means no repo sync counts
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

- (ATProtoHttpRequest *)r:(NSString *)method path:(NSString *)path headers:(NSDictionary *)h body:(NSData *)b {
    ATProtoHttpRequest *req = [[ATProtoHttpRequest alloc] init];
    req.methodString = method;
    req.path = path;
    for (NSString *k in h) { [req setHeader:h[k] forKey:k]; }
    if (b) req.body = b;
    return req;
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
    SyrenaMetrics *m = [[SyrenaMetrics alloc] init];
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
    XCTAssertEqualObjects(snap[@"queries"][@"total"], @(6));
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
    XCTAssertNotNil(s[@"ingest"]);
    XCTAssertNotNil(s[@"backfill"]);
    XCTAssertNotNil(s[@"indexes"]);
    XCTAssertNotNil(s[@"queries"]);
    XCTAssertNotNil(s[@"database"]);
}

- (void)testSnapshotConfigReflectsRelays {
    NSDictionary *s = [self.snapshot snapshot];
    NSArray *relays = s[@"config"][@"relayURLs"];
    XCTAssertEqual(relays.count, 1u);
    XCTAssertEqualObjects(relays[0], @"wss://test.example.com");
}

#pragma mark - Pack auth + scoping

- (void)testUnauthRedirects {
    ATProtoHttpResponse *res = [self.host dispatchRequestForTesting:
        [self r:@"GET" path:@"/admin/partials/appview-metrics" headers:@{} body:nil]];
    XCTAssertEqual(res.statusCode, 302);
}

- (void)testSessionAuthGrantsAllPartialRoutes {
    NSString *sessionCookie = [NSString stringWithFormat:@"%@=faketoken", self.host.authManager.sessionCookieName];
    NSDictionary *h = @{@"Cookie": sessionCookie};

    for (NSString *path in @[@"/admin/partials/appview-metrics",
                              @"/admin/partials/ingest-health",
                              @"/admin/partials/appview-backfill",
                              @"/admin/partials/appview-indexes"]) {
        ATProtoHttpResponse *res = [self.host dispatchRequestForTesting:
            [self r:@"GET" path:path headers:h body:nil]];
        XCTAssertEqual(res.statusCode, 200, @"path %@", path);
    }
}

#pragma mark - HTML output

- (void)testOverviewHTMLContainsMetrics {
    NSDictionary *s = [self.snapshot snapshot];
    NSString *html = [GZSyrenaAdminUIPack overviewHTML:s];
    XCTAssertTrue([html containsString:@"metric-label"]);
    XCTAssertTrue([html containsString:@"degraded"]);
}

- (void)testBackfillHTMLShowsDisabledWhenNilOrch {
    NSDictionary *s = [self.snapshot snapshot];
    NSString *html = [GZSyrenaAdminUIPack backfillHTML:s];
    XCTAssertTrue([html containsString:@"no"]);
}

- (void)testErrorUnavailableHTMLRenders {
    NSString *html = [GZSyrenaAdminUIPack errorUnavailableHTML];
    XCTAssertTrue([html containsString:@"unavailable"]);
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
    XCTAssertEqual(sections.count, 4u);
    NSArray *expectedIds = @[@"appview-metrics", @"ingest-health", @"appview-backfill", @"appview-indexes"];
    for (NSUInteger i = 0; i < sections.count; i++) {
        XCTAssertEqualObjects(sections[i][@"tabIdentifier"], expectedIds[i]);
    }
}

@end
