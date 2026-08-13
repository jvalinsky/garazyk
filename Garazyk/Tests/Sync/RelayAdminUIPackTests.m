// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import <errno.h>

#import "AdminUIServer/GZAdminUIHost+Private.h"
#import "AdminUIServer/GZAdminUIBackendClient.h"
#import "AdminUIServer/GZAdminUIHost.h"
#import "AdminUIServer/UIAuthManager.h"
#import "AdminUIServer/UIServiceConfig.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Sync/Relay/AdminUI/RelayAdminSnapshot.h"
#import "Sync/Relay/AdminUI/RelayAdminUIPack.h"
#import "Sync/Relay/RelayMetrics.h"
#import "Sync/Relay/RelayUpstreamManager.h"

@interface RelayAdminUIPackTests : XCTestCase
@property(nonatomic, strong) GZAdminUIHost *host;
@property(nonatomic, strong) ATProtoRelayUpstreamManager *upstreams;
@property(nonatomic, strong) GZRelayAdminSnapshot *snapshot;
@end

@interface RelayAdminUIBackendStub : GZAdminUIBackendClient
@end

@implementation RelayAdminUIBackendStub
- (NSDictionary *)fetchRelayMetrics { return @{ @"metrics": @{ @"eventsReceived": @7, @"currentSequence": @11 } }; }
- (NSDictionary *)fetchRelayUpstreams { return @{ @"upstreams": @[@{ @"hostname": @"pds.example", @"status": @"connected", @"seq": @11 }] }; }
@end

@implementation RelayAdminUIPackTests

- (void)setUp {
    [super setUp];
    GZAdminUIServiceConfig *config = [[GZAdminUIServiceConfig alloc] init];
    config.host = @"127.0.0.1";
    config.port = 0;
    config.adminPassword = @"relay-password";
    config.serviceIdentifier = @"relay";
    self.upstreams = [[ATProtoRelayUpstreamManager alloc] initWithInitialURLs:@[]];
    self.host = [[GZAdminUIHost alloc] initWithConfiguration:config packs:@[GZRelayAdminUIPack.class]];
    self.snapshot = [[GZRelayAdminSnapshot alloc] initWithMetrics:[ATProtoRelayMetrics sharedMetrics]
                                                   upstreamManager:self.upstreams];
    [GZRelayAdminUIPack configureHost:self.host snapshot:self.snapshot];
}

- (void)tearDown {
    [self.host stop];
    [super tearDown];
}

- (ATProtoHttpRequest *)requestWithMethod:(NSString *)method path:(NSString *)path headers:(NSDictionary *)headers body:(NSDictionary *)body {
    NSData *data = body ? [NSJSONSerialization dataWithJSONObject:body options:0 error:nil] : NSData.data;
    NSMutableDictionary *requestHeaders = headers.mutableCopy ?: NSMutableDictionary.dictionary;
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
    NSString *nonce = nil;
    NSString *cookie = nil;
    [self.host.authManager createCSRFNonce:&nonce cookie:&cookie secure:NO];
    return nonce;
}

- (NSDictionary *)sessionHeadersWithNonce:(NSString *)nonce {
    NSString *token = [self.host.authManager createSessionToken];
    return @{
        @"Cookie": [NSString stringWithFormat:@"gz_admin_relay_token=%@; gz_admin_relay_nonce=%@", token, nonce],
        @"X-UI-Admin-Nonce": nonce,
    };
}

- (void)testEmbeddedHostUsesLoopbackScopedSessionAndConcurrencyEight {
    ATProtoHttpResponse *unauthenticated = [self.host dispatchRequestForTesting:[self requestWithMethod:@"GET" path:@"/admin/partials/relay-metrics" headers:@{} body:nil]];
    XCTAssertEqual(unauthenticated.statusCode, HttpStatusFound);
    NSString *token = [self.host.authManager createSessionToken];
    ATProtoHttpResponse *authenticated = [self.host dispatchRequestForTesting:[self requestWithMethod:@"GET" path:@"/admin/partials/relay-metrics" headers:@{ @"Cookie": [NSString stringWithFormat:@"gz_admin_relay_token=%@", token] } body:nil]];
    XCTAssertEqual(authenticated.statusCode, HttpStatusOK);
    XCTAssertTrue([authenticated.bodyString containsString:@"Sources online"]);
    XCTAssertEqualObjects(self.host.httpServer.host, @"127.0.0.1");
    XCTAssertEqual(self.host.httpServer.maxConcurrentRequests, (NSUInteger)8);

    ATProtoHttpResponse *foreign = [self.host dispatchRequestForTesting:[self requestWithMethod:@"GET" path:@"/admin/partials/relay-metrics" headers:@{ @"Cookie": [NSString stringWithFormat:@"gz_admin_plc_token=%@", token] } body:nil]];
    XCTAssertEqual(foreign.statusCode, HttpStatusFound);
}

- (void)testSnapshotCoversEmptyAndPopulatedSourcesWithoutTornValues {
    GZRelayAdminSnapshot *snapshot = [[GZRelayAdminSnapshot alloc] initWithMetrics:[ATProtoRelayMetrics sharedMetrics] upstreamManager:self.upstreams];
    XCTAssertEqual([(NSArray *)[snapshot snapshot][@"upstreams"] count], (NSUInteger)0);
    [self.upstreams addUpstream:@"wss://pds.example/xrpc/com.atproto.sync.subscribeRepos"];
    NSDictionary *value = [snapshot snapshot];
    NSArray *sources = value[@"upstreams"];
    XCTAssertEqual(sources.count, (NSUInteger)1);
    NSDictionary *source = sources.firstObject;
    XCTAssertEqualObjects(source[@"hostname"], @"pds.example");
    XCTAssertNotNil(source[@"crawlState"]);
    XCTAssertNotNil(source[@"reconnectAttempts"]);
    XCTAssertNotNil(source[@"eventsByKind"]);
    XCTAssertNotNil(source[@"lastEventAt"]);
    XCTAssertNotNil(source[@"connectedAt"]);
}

- (void)testSnapshotRemainsConsistentDuringConcurrentMetricUpdates {
    ATProtoRelayMetrics *metrics = [ATProtoRelayMetrics sharedMetrics];
    GZRelayAdminSnapshot *snapshot = [[GZRelayAdminSnapshot alloc] initWithMetrics:metrics upstreamManager:self.upstreams];
    __block BOOL invalid = NO;
    dispatch_apply(128, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(size_t index) {
        (void)index;
        [metrics recordEventReceived];
        NSDictionary *snap = [snapshot snapshot];
        id metricsObj = snap[@"metrics"];
        id upstreamsObj = snap[@"upstreams"];
        if (![metricsObj isKindOfClass:[NSDictionary class]] ||
            ![upstreamsObj isKindOfClass:[NSArray class]]) {
            @synchronized (self) { invalid = YES; }
        }
    });
    XCTAssertFalse(invalid);
    NSDictionary *finalMetrics = [snapshot snapshot][@"metrics"];
    XCTAssertGreaterThanOrEqual([finalMetrics[@"eventsReceived"] longLongValue], (int64_t)128);
}

- (void)testMutationsRejectMissingAndStaleCSRFThenRotateAcceptedNonce {
    NSString *token = [self.host.authManager createSessionToken];
    ATProtoHttpResponse *missing = [self.host dispatchRequestForTesting:[self requestWithMethod:@"POST" path:@"/admin/actions/relay-disconnect-all" headers:@{ @"Cookie": [NSString stringWithFormat:@"gz_admin_relay_token=%@", token] } body:@{}]];
    XCTAssertEqual(missing.statusCode, HttpStatusForbidden);

    NSString *nonce = [self newNonce];
    ATProtoHttpResponse *stale = [self.host dispatchRequestForTesting:[self requestWithMethod:@"POST" path:@"/admin/actions/relay-disconnect-all" headers:@{ @"Cookie": [NSString stringWithFormat:@"gz_admin_relay_token=%@; gz_admin_relay_nonce=%@", token, nonce], @"X-UI-Admin-Nonce": @"stale" } body:@{}]];
    XCTAssertEqual(stale.statusCode, HttpStatusForbidden);

    NSDictionary *validHeaders = [self sessionHeadersWithNonce:[self newNonce]];
    ATProtoHttpResponse *accepted = [self.host dispatchRequestForTesting:[self requestWithMethod:@"POST" path:@"/admin/actions/relay-disconnect-all" headers:validHeaders body:@{}]];
    XCTAssertEqual(accepted.statusCode, HttpStatusOK);
    XCTAssertTrue([accepted.bodyString containsString:@"All sources disconnected"]);
    XCTAssertNotNil([accepted headerForKey:@"X-UI-Admin-Nonce"]);
    NSArray *audit = [self.snapshot snapshot][@"adminAudit"];
    XCTAssertEqual(audit.count, (NSUInteger)1);
    XCTAssertEqualObjects(audit.lastObject[@"action"], @"disconnect-all");
    XCTAssertEqualObjects(audit.lastObject[@"succeeded"], @YES);
}

- (void)testRequestCrawlMutationIsAuthenticatedAndUpdatesSnapshot {
    NSDictionary *headers = [self sessionHeadersWithNonce:[self newNonce]];
    ATProtoHttpResponse *response = [self.host dispatchRequestForTesting:[self requestWithMethod:@"POST" path:@"/admin/actions/request-crawl" headers:headers body:@{ @"hostname": @"pds.example" }]];
    XCTAssertEqual(response.statusCode, HttpStatusOK);
    XCTAssertTrue([response.bodyString containsString:@"Crawl requested"]);
    NSString *token = [self.host.authManager createSessionToken];
    ATProtoHttpResponse *sources = [self.host dispatchRequestForTesting:[self requestWithMethod:@"GET" path:@"/admin/partials/relay-sources" headers:@{ @"Cookie": [NSString stringWithFormat:@"gz_admin_relay_token=%@", token] } body:nil]];
    XCTAssertTrue([sources.bodyString containsString:@"pds.example"]);
}

- (void)testCompatibilityHostServesTheSameRelayPackRoutes {
    GZAdminUIHost *compatibilityHost = [[GZAdminUIHost alloc] initWithConfiguration:self.host.configuration packs:@[GZRelayAdminUIPack.class]];
    compatibilityHost.backendClient = [[RelayAdminUIBackendStub alloc] initWithConfiguration:self.host.configuration];
    NSString *token = [compatibilityHost.authManager createSessionToken];
    NSDictionary *headers = @{ @"Cookie": [NSString stringWithFormat:@"gz_admin_relay_token=%@", token] };
    ATProtoHttpResponse *metrics = [compatibilityHost dispatchRequestForTesting:[self requestWithMethod:@"GET" path:@"/admin/partials/relay-metrics" headers:headers body:nil]];
    ATProtoHttpResponse *sources = [compatibilityHost dispatchRequestForTesting:[self requestWithMethod:@"GET" path:@"/admin/partials/relay-sources" headers:headers body:nil]];
    XCTAssertEqual(metrics.statusCode, HttpStatusOK);
    XCTAssertTrue([metrics.bodyString containsString:@"Sources online"]);
    XCTAssertEqual(sources.statusCode, HttpStatusOK);
    XCTAssertTrue([sources.bodyString containsString:@"pds.example"]);
}

- (void)testPasswordFileLoaderTrimsAndRedactsCredentials {
    NSString *secret = @"relay-systemd-credential";
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"relay-password-%@", NSUUID.UUID.UUIDString]];
    XCTAssertTrue([[secret stringByAppendingString:@"\n"] writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]);
    NSError *error = nil;
    XCTAssertEqualObjects(GZRelayAdminPasswordFromFile(path, &error), secret);
    XCTAssertNil(error);
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    XCTAssertNil(GZRelayAdminPasswordFromFile(path, &error));
    XCTAssertNotNil(error);
    XCTAssertFalse([error.localizedDescription containsString:secret]);
}

- (void)testAdminListenerStopsCleanly {
    NSError *error = nil;
    if (![self.host startWithError:&error]) {
        NSError *underlying = error.userInfo[NSUnderlyingErrorKey];
        if ([underlying.domain isEqualToString:NSPOSIXErrorDomain] && underlying.code == EPERM) {
            XCTSkip(@"Loopback listeners are unavailable in this environment");
            return;
        }
        XCTFail(@"Failed to start admin listener: %@", error);
        return;
    }
    XCTAssertTrue(self.host.isRunning);
    [self.host stop];
    XCTAssertFalse(self.host.isRunning);
}

@end
