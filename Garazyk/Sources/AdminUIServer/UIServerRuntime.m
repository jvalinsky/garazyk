// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/UIServerRuntime.h"

#import "AdminUIServer/UIAuthManager.h"
#import "AdminUIServer/UIBackendClient.h"
#import "AdminUIServer/UIServiceConfig.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"

static NSString *UIEscaped(NSString *value) {
    if (![value isKindOfClass:[NSString class]]) {
        return @"";
    }
    NSString *escaped = [value stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"];
    return escaped;
}

/// Safely extract a string from a dictionary, treating NSNull and non-string values as nil.
static NSString * _Nullable UIStringFromDict(NSDictionary *dict, NSString *key) {
    id value = dict[key];
    if ([value isKindOfClass:[NSString class]]) {
        return value;
    }
    return nil;
}

/// Safely convert any value (including NSNull) to an NSString, returning fallback for non-strings.
static NSString *UISafe(id value, NSString *fallback) {
    if ([value isKindOfClass:[NSString class]]) {
        return value;
    }
    return fallback ?: @"";
}

/// Safely get .length from a value that might be NSNull.
static NSUInteger UISafeLength(id value) {
    if ([value isKindOfClass:[NSString class]]) {
        return [(NSString *)value length];
    }
    return 0;
}

/// Authorization guard macro: checks auth and returns early if unauthorized.
/// Returns the result of ensureAuthorized so the caller can use `if (AUTH_GUARD(...)) return;`
#define AUTH_GUARD(weakSelf, request, response) \
    if (![weakSelf ensureAuthorized:request response:response]) return

@interface UIServerRuntime ()

@property(nonatomic, strong) HttpServer *httpServer;
@property(nonatomic, strong, readwrite) UIServiceConfig *configuration;
@property(nonatomic, strong) UIAuthManager *authManager;
@property(nonatomic, strong) UIBackendClient *backendClient;
@property(nonatomic, assign, readwrite, getter=isRunning) BOOL running;

@end

@interface HttpServer (UIServerRuntimeTesting)
- (HttpResponse *)dispatchRequest:(HttpRequest *)request;
@end

@implementation UIServerRuntime

- (instancetype)initWithConfiguration:(UIServiceConfig *)configuration {
    self = [super init];
    if (self) {
        _configuration = configuration;
        _authManager = [[UIAuthManager alloc] initWithPassword:configuration.adminPassword ?: @""];
        _backendClient = [[UIBackendClient alloc] initWithConfiguration:configuration];
        // Auto-obtain PDS admin JWT if a password is configured but no token
        if (configuration.pdsAdminPassword.length > 0 && configuration.pdsAdminToken.length == 0) {
            [_backendClient refreshPDSAdminToken];
        }
    }
    return self;
}

- (BOOL)startWithError:(NSError **)error {
    if (self.running) {
        return YES;
    }

    self.httpServer = [HttpServer serverWithHost:self.configuration.host port:self.configuration.port];
    if (!self.httpServer) {
        if (error) {
            *error = [NSError errorWithDomain:@"UIServerRuntime"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to create HTTP server"}];
        }
        return NO;
    }

    [HttpResponse setDefaultServerHeader:@"garazyk-ui/1.0.0"];
    [self registerRoutes];

    NSError *startError = nil;
    if (![self.httpServer startWithError:&startError]) {
        if (error) *error = startError;
        return NO;
    }

    self.running = YES;
    return YES;
}

- (void)stop {
    if (!self.running) {
        return;
    }
    [self.httpServer stop];
    self.running = NO;
}

- (HttpResponse *)dispatchRequestForTesting:(HttpRequest *)request {
    if (!self.httpServer) {
        self.httpServer = [HttpServer serverWithHost:self.configuration.host port:self.configuration.port];
        [self registerRoutes];
    }
    return [self.httpServer dispatchRequest:request];
}

- (void)registerRoutes {
    __weak typeof(self) weakSelf = self;

    // Static asset serving: /css/*, /js/*, /img/* (prefix routes via addHandlerForPath)
    [self.httpServer addHandlerForPath:@"/css/" handler:^(HttpRequest *request, HttpResponse *response) {
        [weakSelf serveStaticAssetForPath:request.path response:response];
    }];
    [self.httpServer addHandlerForPath:@"/js/" handler:^(HttpRequest *request, HttpResponse *response) {
        [weakSelf serveStaticAssetForPath:request.path response:response];
    }];
    [self.httpServer addHandlerForPath:@"/img/" handler:^(HttpRequest *request, HttpResponse *response) {
        [weakSelf serveStaticAssetForPath:request.path response:response];
    }];

    [self.httpServer addRoute:@"GET" path:@"/" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = 302;
        [response setHeader:@"/admin" forKey:@"Location"];
        response.contentType = @"text/plain; charset=utf-8";
        [response setBodyString:@"Redirecting\n"];
    }];

    [self.httpServer addRoute:@"GET" path:@"/admin/login" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf loginPageHTML]];
    }];

    [self.httpServer addRoute:@"POST" path:@"/admin/login" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *password = request.jsonBody[@"password"];
        if (![weakSelf.authManager validatePassword:password]) {
            response.statusCode = 401;
            [response setJsonBody:@{@"ok": @NO, @"error": @"invalid_credentials"}];
            return;
        }
        NSString *token = [weakSelf.authManager createSessionToken];
        // Use secure cookie helper — omit Secure flag for HTTP localhost
        NSString *cookie = [weakSelf.authManager cookieHeaderValueForToken:token secure:NO];
        [response setHeader:cookie forKey:@"Set-Cookie"];
        response.statusCode = 200;
        [response setJsonBody:@{@"ok": @YES}];
    }];

    [self.httpServer addRoute:@"POST" path:@"/admin/logout" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *token = [weakSelf.authManager extractTokenFromRequest:request];
        [weakSelf.authManager invalidateSessionToken:token];
        [response setHeader:@"ui_admin_token=; Path=/; Max-Age=0; HttpOnly; SameSite=Strict" forKey:@"Set-Cookie"];
        response.statusCode = 200;
        [response setJsonBody:@{@"ok": @YES}];
    }];

    [self.httpServer addRoute:@"GET" path:@"/admin" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf adminShellHTML]];
    }];

    [self.httpServer addRoute:@"GET" path:@"/admin/partials/overview" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *overview = [weakSelf.backendClient fetchServiceOverview];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderOverviewPartial:overview]];
    }];

    [self.httpServer addRoute:@"GET" path:@"/admin/partials/connections" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderConnectionsPartial]];
    }];

    [self.httpServer addRoute:@"GET" path:@"/admin/partials/accounts" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *query = [request queryParamForKey:@"q"] ?: @"";
        NSDictionary *result = [weakSelf.backendClient searchAccountsWithQuery:query];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderAccountsPartial:result]];
    }];

    [self.httpServer addRoute:@"GET" path:@"/admin/partials/invites" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *result = [weakSelf.backendClient fetchInviteCodes];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderInvitesPartial:result]];
    }];

    [self.httpServer addRoute:@"POST" path:@"/admin/actions/disable-invites" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *account = request.jsonBody[@"account"] ?: [request queryParamForKey:@"account"];
        NSDictionary *result = [weakSelf.backendClient disableInvitesForAccount:account ?: @""];
        if (result[@"error"]) {
            response.statusCode = 400;
        } else {
            response.statusCode = 200;
        }
        response.contentType = @"text/html; charset=utf-8";
        NSString *message = result[@"error"]
            ? [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])]
            : @"<div class=\"alert alert-success\">Invites disabled for account.</div>";
        [response setBodyString:message];
    }];

    [self.httpServer addRoute:@"POST" path:@"/admin/actions/bulk-takedown" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSArray *dids = request.jsonBody[@"dids"];
        NSDictionary *result = [weakSelf.backendClient bulkTakedownAccounts:dids ?: @[]];
        response.statusCode = 200;
        response.contentType = @"application/json";
        [response setJsonBody:result];
    }];

    [self.httpServer addRoute:@"POST" path:@"/admin/actions/bulk-delete" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSArray *dids = request.jsonBody[@"dids"];
        NSDictionary *result = [weakSelf.backendClient bulkDeleteAccounts:dids ?: @[]];
        response.statusCode = 200;
        response.contentType = @"application/json";
        [response setJsonBody:result];
    }];

    [self.httpServer addRoute:@"GET" path:@"/admin/partials/appview-metrics" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *result = [weakSelf.backendClient fetchAppViewMetrics];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderAppViewMetricsPartial:result]];
    }];

    [self.httpServer addRoute:@"GET" path:@"/admin/partials/appview-ingest" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *result = [weakSelf.backendClient fetchIngestHealth];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderIngestHealthPartial:result]];
    }];

    [self.httpServer addRoute:@"GET" path:@"/admin/partials/appview-queue" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *status = [request queryParamForKey:@"status"];
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSDictionary *result = [weakSelf.backendClient fetchBackfillQueueWithStatus:status limit:25 cursor:cursor];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderBackfillQueuePartial:result]];
    }];

    [self.httpServer addRoute:@"POST" path:@"/admin/actions/appview-retry-repo" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = request.jsonBody[@"did"] ?: [request queryParamForKey:@"did"];
        NSDictionary *result = [weakSelf.backendClient retryBackfillForDID:did ?: @""];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? result[@"message"] : @"Retry enqueued.";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert alert-success\">%@</div>", UIEscaped(msg)]];
    }];

    [self.httpServer addRoute:@"POST" path:@"/admin/actions/appview-cancel-repo" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = request.jsonBody[@"did"] ?: [request queryParamForKey:@"did"];
        NSDictionary *result = [weakSelf.backendClient cancelBackfillForDID:did ?: @""];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? result[@"message"] : @"Cancel requested.";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert alert-success\">%@</div>", UIEscaped(msg)]];
    }];

    [self.httpServer addRoute:@"GET" path:@"/admin/partials/relay-metrics" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *result = [weakSelf.backendClient fetchRelayMetrics];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderRelayMetricsPartial:result]];
    }];

    // PDS: Account detail
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/account-detail" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = [request queryParamForKey:@"did"] ?: @"";
        NSDictionary *result = [weakSelf.backendClient fetchAccountInfoForDID:did];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderAccountDetailPartial:result]];
    }];

    // PDS: Server stats
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/pds-stats" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *result = [weakSelf.backendClient fetchServerStats];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderServerStatsPartial:result]];
    }];

    // PDS: Audit log
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/audit-log" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSDictionary *result = [weakSelf.backendClient fetchAuditLogWithCursor:cursor limit:25];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderAuditLogPartial:result]];
    }];

    [self.httpServer addRoute:@"GET" path:@"/admin/partials/blobs" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = [request queryParamForKey:@"did"];
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSDictionary *result = did && did.length > 0 ? [weakSelf.backendClient fetchBlobsForDID:did limit:25 cursor:cursor] : @{@"blobs": @[]};
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderBlobsPartial:result did:did]];
    }];

    [self.httpServer addRoute:@"POST" path:@"/admin/actions/enable-invites" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *account = request.jsonBody[@"account"] ?: [request queryParamForKey:@"account"];
        NSDictionary *result = [weakSelf.backendClient enableInvitesForAccount:account ?: @""];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Invites enabled for account.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];

    // PDS: Update handle action
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/update-handle" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = request.jsonBody[@"did"] ?: @"";
        NSString *handle = request.jsonBody[@"handle"] ?: @"";
        NSDictionary *result = [weakSelf.backendClient updateAccountHandle:handle forDID:did];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Handle updated.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];

    // Relay: Upstreams
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/relay-upstreams" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *result = [weakSelf.backendClient fetchRelayUpstreams];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderRelayUpstreamsPartial:result]];
    }];

    // Relay: Health check
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/relay-health" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *result = [weakSelf.backendClient fetchRelayHealth];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderRelayHealthPartial:result]];
    }];

    // Relay: Request crawl action
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/request-crawl" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *hostname = request.jsonBody[@"hostname"] ?: [request queryParamForKey:@"hostname"];
        NSDictionary *result = [weakSelf.backendClient requestCrawlForHostname:hostname ?: @""];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Crawl requested.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];

    // PLC: DID lookup
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/plc-did" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = [request queryParamForKey:@"did"] ?: @"";
        NSDictionary *result = [weakSelf.backendClient lookupDID:did];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderPLCDIDPartial:result]];
    }];

    // PLC: DID log
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/plc-log" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = [request queryParamForKey:@"did"] ?: @"";
        NSDictionary *result = [weakSelf.backendClient fetchPLCLogForDID:did];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderPLCLogPartial:result]];
    }];

    // PLC: Health check
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/plc-health" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *result = [weakSelf.backendClient fetchPLCHealth];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderPLCHealthPartial:result]];
    }];

    // PLC: Metrics
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/plc-metrics" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *result = [weakSelf.backendClient fetchPLCMetrics];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderPLCMetricsPartial:result]];
    }];

    // PLC: List DIDs
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/plc-list" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSDictionary *result = [weakSelf.backendClient fetchPLCList];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderPLCListPartial:result cursor:cursor]];
    }];

    // PLC: Export action
    [self.httpServer addRoute:@"GET" path:@"/admin/actions/plc-export" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *after = [request queryParamForKey:@"after"];
        NSString *countStr = [request queryParamForKey:@"count"] ?: @"1000";
        NSUInteger count = [countStr integerValue] ?: 1000;
        NSDictionary *result = [weakSelf.backendClient fetchPLCExportWithAfter:after count:count];
        if (result[@"error"]) {
            response.statusCode = 400;
            response.contentType = @"text/html; charset=utf-8";
            [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])]];
        } else {
            response.statusCode = 200;
            response.contentType = @"text/plain; charset=utf-8";
            [response setBodyString:result[@"text"] ?: @""];
        }
    }];

    // Explorer: Describe repo
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/describe-repo" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = [request queryParamForKey:@"did"] ?: @"";
        NSDictionary *result = [weakSelf.backendClient describeRepo:did];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderDescribeRepoPartial:result]];
    }];

    // Explorer: List records
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/list-records" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = [request queryParamForKey:@"did"] ?: @"";
        NSString *collection = [request queryParamForKey:@"collection"];
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSDictionary *result = [weakSelf.backendClient listRecordsForDID:did collection:collection limit:25 cursor:cursor];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderListRecordsPartial:result]];
    }];

    // Explorer: Get record
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/get-record" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = [request queryParamForKey:@"did"] ?: @"";
        NSString *collection = [request queryParamForKey:@"collection"] ?: @"";
        NSString *rkey = [request queryParamForKey:@"rkey"] ?: @"";
        NSDictionary *result = [weakSelf.backendClient getRecordForDID:did collection:collection rkey:rkey];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderGetRecordPartial:result]];
    }];

    // Lab: Public OAuth2 user self-service portal (no admin auth required)
    [self.httpServer addRoute:@"GET" path:@"/lab" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *pdsOrigin = [weakSelf.configuration.pdsBaseURL absoluteString];
        [response setHeader:[NSString stringWithFormat:@"default-src 'self'; script-src 'self' 'unsafe-inline' https://unpkg.com; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self' %@;", pdsOrigin]
                      forKey:@"content-security-policy"];
        [response setBodyString:[weakSelf labShellHTML]];
    }];

    [self.httpServer addRoute:@"GET" path:@"/lab/callback" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *pdsOrigin = [weakSelf.configuration.pdsBaseURL absoluteString];
        [response setHeader:[NSString stringWithFormat:@"default-src 'self'; script-src 'self' 'unsafe-inline' https://unpkg.com; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self' %@;", pdsOrigin]
                      forKey:@"content-security-policy"];
        [response setBodyString:[weakSelf labShellHTML]];
    }];

    [self.httpServer addRoute:@"GET" path:@"/lab/client-metadata.json" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = 200;
        response.contentType = @"application/json; charset=utf-8";
        [response setBodyString:[weakSelf labClientMetadataJSON]];
    }];

    // Ozone: Moderation statuses
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/ozone-statuses" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSDictionary *result = [weakSelf.backendClient fetchOzoneStatusesWithCursor:cursor limit:50];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderOzoneStatusesPartial:result]];
    }];

    // Ozone: Moderation events
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/ozone-events" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSDictionary *result = [weakSelf.backendClient fetchOzoneEventsWithCursor:cursor limit:50];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderOzoneEventsPartial:result]];
    }];

    // Ozone: Subject status
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/ozone-subject" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = [request queryParamForKey:@"did"];
        NSDictionary *result = [weakSelf.backendClient fetchSubjectStatusForDID:did];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderOzoneSubjectPartial:result]];
    }];

    // Ozone: Moderation reports
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/ozone-reports" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSDictionary *result = [weakSelf.backendClient fetchModerationReportsWithCursor:cursor limit:50];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderOzoneModerationReportsPartial:result]];
    }];

    // Ozone: Scheduled actions
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/ozone-scheduled" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSDictionary *result = [weakSelf.backendClient fetchScheduledActionsWithStatuses:nil cursor:cursor limit:50];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderOzoneScheduledPartial:result]];
    }];

    // Ozone: Schedule action
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/ozone-schedule-action" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *actionSpec = request.jsonBody;
        NSDictionary *result = [weakSelf.backendClient scheduleAction:actionSpec ?: @{}];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Action scheduled.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];

    // Ozone: Cancel scheduled actions
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/ozone-cancel-scheduled" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSArray *subjects = request.jsonBody[@"subjects"] ?: @[];
        NSDictionary *result = [weakSelf.backendClient cancelScheduledActionsForSubjects:subjects];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Scheduled actions cancelled.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];

    // Ozone: Verification
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/ozone-verification" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *result = [weakSelf.backendClient listOzoneVerifications];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderOzoneVerificationPartial:result]];
    }];

    // Ozone: Grant verification
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/ozone-grant-verification" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = request.jsonBody[@"did"];
        NSString *displayName = request.jsonBody[@"displayName"] ?: @"";
        if (!did || did.length == 0) {
            response.statusCode = 400;
            response.contentType = @"text/html; charset=utf-8";
            [response setBodyString:@"<div class=\"alert alert-destructive\">DID required</div>"];
            return;
        }
        NSDictionary *verification = @{@"did": did, @"displayName": displayName};
        NSDictionary *result = [weakSelf.backendClient grantOzoneVerifications:@[verification]];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Verification granted.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];

    // Ozone: Revoke verification
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/ozone-revoke-verification" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSArray *dids = request.jsonBody[@"dids"] ?: @[];
        NSDictionary *result = [weakSelf.backendClient revokeOzoneVerifications:dids];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Verification revoked.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];

    // Ozone: Safelinks
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/ozone-safelinks" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *result = [weakSelf.backendClient fetchSafelinkRules];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderOzoneSafelinksPartial:result]];
    }];

    // Ozone: Add safelink rule
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/add-safelink-rule" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *rule = request.jsonBody ?: @{};
        NSDictionary *result = [weakSelf.backendClient addSafelinkRule:rule];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Safelink rule added.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];

    // Ozone: Remove safelink rule
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/remove-safelink-rule" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *url = request.jsonBody[@"url"] ?: @"";
        NSString *pattern = request.jsonBody[@"pattern"] ?: @"";
        NSDictionary *result = [weakSelf.backendClient removeSafelinkRule:url pattern:pattern];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Safelink rule removed.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];

    // Ozone: Settings
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/ozone-settings" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *result = [weakSelf.backendClient listOzoneSettings];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderOzoneSettingsPartial:result]];
    }];

    // Ozone: Upsert setting
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/upsert-ozone-setting" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *option = request.jsonBody ?: @{};
        NSDictionary *result = [weakSelf.backendClient upsertOzoneSetting:option];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Setting updated.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];

    // Ozone: Signatures
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/ozone-signatures" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderOzoneSignaturesPartial:nil]];
    }];

    // Ozone: Find related accounts
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/ozone-find-related" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = request.jsonBody[@"did"] ?: @"";
        NSDictionary *result = [weakSelf.backendClient findRelatedAccounts:did];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderOzoneSignatureResultsPartial:result]];
    }];

    // Ozone: Find correlation
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/ozone-find-correlation" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSArray *dids = request.jsonBody[@"dids"] ?: @[];
        NSDictionary *result = [weakSelf.backendClient findSignatureCorrelation:dids];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderOzoneSignatureResultsPartial:result]];
    }];

    // Ozone: Hosting history
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/ozone-hosting" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = [request queryParamForKey:@"did"];
        NSDictionary *result = did && did.length > 0 ? [weakSelf.backendClient fetchHostingHistoryForDID:did] : @{@"entries": @[]};
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderOzoneHostingPartial:result did:did]];
    }];

    // Ozone: Team members
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/ozone-team" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *result = [weakSelf.backendClient fetchOzoneTeamMembers];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderOzoneTeamPartial:result]];
    }];

    // Ozone: Sets
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/ozone-sets" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSDictionary *result = [weakSelf.backendClient fetchOzoneSetsWithCursor:cursor limit:50];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderOzoneSetsPartial:result]];
    }];

    // Ozone: Templates
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/ozone-templates" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *result = [weakSelf.backendClient fetchOzoneTemplates];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderOzoneTemplatesPartial:result]];
    }];

    // Ozone: Config
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/ozone-config" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *result = [weakSelf.backendClient fetchOzoneConfig];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderOzoneConfigPartial:result]];
    }];

    // Ozone: Emit moderation event
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/emit-moderation-event" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *event = request.jsonBody;
        NSDictionary *result = [weakSelf.backendClient emitModerationEvent:event];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Event emitted.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];

    // Ozone: Delete set
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/delete-ozone-set" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *name = request.jsonBody[@"name"] ?: @"";
        NSDictionary *result = [weakSelf.backendClient deleteOzoneSet:name];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Set deleted.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];

    // Ozone: Delete template
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/delete-ozone-template" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *name = request.jsonBody[@"name"] ?: @"";
        NSDictionary *result = [weakSelf.backendClient deleteOzoneTemplate:name];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Template deleted.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];

    // Ozone: Remove team member
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/remove-team-member" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = request.jsonBody[@"did"] ?: @"";
        NSDictionary *result = [weakSelf.backendClient removeOzoneTeamMember:did];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Member removed.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];

    // Security: Active sessions
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/sessions" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = [request queryParamForKey:@"did"];
        NSDictionary *result = [weakSelf.backendClient fetchActiveSessionsForDID:did];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderSessionsPartial:result]];
    }];

    // Security: App passwords
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/app-passwords" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = [request queryParamForKey:@"did"];
        NSDictionary *result = [weakSelf.backendClient fetchAppPasswordsForDID:did];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderAppPasswordsPartial:result]];
    }];

    // Security: Revoke session
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/revoke-session" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = request.jsonBody[@"did"] ?: @"";
        NSString *sessionID = request.jsonBody[@"id"] ?: @"";
        NSDictionary *result = [weakSelf.backendClient revokeSessionForDID:did sessionID:sessionID];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Session revoked.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];

    // Security: Delete app password
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/delete-app-password" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = request.jsonBody[@"did"] ?: @"";
        NSString *name = request.jsonBody[@"name"] ?: @"";
        NSDictionary *result = [weakSelf.backendClient deleteAppPasswordForDID:did passwordName:name];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"App password deleted.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];

    // PDS: Delete account
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/delete-account" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = request.jsonBody[@"did"] ?: @"";
        NSDictionary *result = [weakSelf.backendClient deleteAccount:did];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Account deleted.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];

    // PDS: Fetch reports
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/pds-reports" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSDictionary *result = [weakSelf.backendClient fetchReportsWithCursor:cursor limit:25];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderPDSReportsPartial:result]];
    }];

    // PDS: Resolve report
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/resolve-pds-report" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *reportID = request.jsonBody[@"reportID"] ?: @"";
        NSString *action = request.jsonBody[@"action"] ?: @"";
        NSDictionary *result = [weakSelf.backendClient resolveReport:reportID action:action];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Report resolved.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];

    // Chat: Get conversations
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/chat-convos" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSDictionary *result = [weakSelf.backendClient fetchChatConvosWithLimit:25 cursor:cursor];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderChatConvosPartial:result]];
    }];

    // Chat: Get messages for conversation
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/chat-messages" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *convoID = [request queryParamForKey:@"convoID"];
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSDictionary *result = [weakSelf.backendClient fetchChatMessagesForConvoID:convoID limit:50 cursor:cursor];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderChatMessagesPartial:result]];
    }];

    // Chat: Lock conversation
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/lock-chat-convo" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *convoID = request.jsonBody[@"convoID"] ?: @"";
        NSDictionary *result = [weakSelf.backendClient lockChatConvo:convoID];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Conversation locked.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];

    // Video: Health
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/video-health" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *result = [weakSelf.backendClient fetchVideoHealth];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderVideoHealthPartial:result]];
    }];

    // Video: Job list
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/video-jobs" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *state = [request queryParamForKey:@"state"];
        NSString *cursor = [request queryParamForKey:@"cursor"];
        if (state.length == 0) state = nil;
        NSDictionary *result = [weakSelf.backendClient fetchVideoJobsWithState:state limit:25 cursor:cursor];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderVideoJobsPartial:result]];
    }];

    // Video: Job detail
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/video-job-detail" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *jobId = [request queryParamForKey:@"jobId"];
        NSDictionary *result = [weakSelf.backendClient fetchVideoJobById:jobId];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderVideoJobDetailPartial:result]];
    }];

    // Video: Upload quotas
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/video-quotas" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *result = [weakSelf.backendClient fetchVideoUploadLimits];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderVideoQuotasPartial:result]];
    }];

    // Video: Retry job
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/video-retry-job" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *jobId = request.jsonBody[@"jobId"] ?: @"";
        // Retry via PDS admin: incrementVideoJobRetry
        NSDictionary *result = [weakSelf.backendClient retryVideoJobWithId:jobId];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Job queued for retry.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];

    // Connections: Update service URLs and tokens
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/update-connections" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *body = request.jsonBody;
        if (![body isKindOfClass:[NSDictionary class]]) {
            response.statusCode = 400;
            response.contentType = @"text/html; charset=utf-8";
            [response setBodyString:@"<div class=\"alert alert-destructive\">Invalid request body.</div>"];
            return;
        }
        BOOL valid = [weakSelf.configuration updateWithDictionary:body];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        if (valid) {
            [response setBodyString:@"<div class=\"alert alert-success\">Connections updated. Changes apply immediately but are not persisted across restarts.</div>"];
        } else {
            [response setBodyString:@"<div class=\"alert alert-destructive\">Some URLs were invalid and could not be applied. Other values were saved.</div>"];
        }
        // Re-render the form with updated values
        [response setBodyString:[response.bodyString stringByAppendingString:[weakSelf renderConnectionsPartial]]];
    }];

    [self.httpServer addRoute:@"POST" path:@"/admin/actions/test-connection" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *body = request.jsonBody;
        NSString *service = [body[@"service"] isKindOfClass:[NSString class]] ? body[@"service"] : @"";
        NSString *urlString = [body[@"url"] isKindOfClass:[NSString class]] ? body[@"url"] : @"";
        NSString *token = [body[@"token"] isKindOfClass:[NSString class]] ? body[@"token"] : nil;
        NSURL *url = [NSURL URLWithString:urlString ?: @""];
        if (service.length == 0 || url.scheme.length == 0 || url.host.length == 0) {
            response.statusCode = 400;
            [response setJsonBody:@{@"name": service ?: @"", @"status": @"error", @"error": @"Valid service and URL are required"}];
            return;
        }
        NSDictionary *result = [weakSelf.backendClient testConnectionForService:service baseURL:url adminToken:token];
        response.statusCode = 200;
        [response setJsonBody:result ?: @{}];
    }];

    // AppView: Rebuild backfill scope
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/appview-rebuild-scope" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *result = [weakSelf.backendClient rebuildBackfillScope];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Rebuilding backfill scope.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];

    // AppView: Enqueue DIDs for backfill
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/appview-enqueue-dids" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSArray *dids = request.jsonBody[@"dids"];
        NSDictionary *result = [weakSelf.backendClient enqueueBackfillDIDs:dids ?: @[]];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : [NSString stringWithFormat:@"Enqueued %lu DIDs.", dids.count];
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];

    // Security: Create app password
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/create-app-password" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = request.jsonBody[@"did"] ?: @"";
        NSString *name = request.jsonBody[@"name"] ?: @"";
        NSDictionary *result = [weakSelf.backendClient createAppPasswordForDID:did name:name];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"App password created.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];

    // Ozone: Add team member
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/add-ozone-team-member" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *member = request.jsonBody[@"member"];
        NSDictionary *result = [weakSelf.backendClient addOzoneTeamMember:member ?: @{}];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Team member added.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];

    // Ozone: Create/update set
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/upsert-ozone-set" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *setSpec = request.jsonBody[@"setSpec"];
        NSDictionary *result = [weakSelf.backendClient upsertOzoneSet:setSpec ?: @{}];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Set created/updated.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];

    // Ozone: Create template
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/create-ozone-template" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *template = request.jsonBody[@"template"];
        NSDictionary *result = [weakSelf.backendClient createOzoneTemplate:template ?: @{}];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Template created.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];

    // Ozone: Update config
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/update-ozone-config" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *config = request.jsonBody[@"config"];
        NSDictionary *result = [weakSelf.backendClient updateOzoneConfig:config ?: @{}];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Config updated.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];

    // MST Viewer: Accounts list
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/mst-accounts" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *result = [weakSelf.backendClient fetchMSTAccounts];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderMSTAccountsPartial:result]];
    }];

    // MST Viewer: Tree for DID
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/mst-tree" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = [request queryParamForKey:@"did"];
        NSDictionary *result = [weakSelf.backendClient fetchMSTTreeForDID:did];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderMSTTreePartial:result]];
    }];

    // MST Viewer: Stats for DID
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/mst-stats" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = [request queryParamForKey:@"did"];
        NSDictionary *result = [weakSelf.backendClient fetchMSTStatsForDID:did];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderMSTStatsPartial:result]];
    }];

    // MST Viewer: Export
    [self.httpServer addRoute:@"GET" path:@"/admin/actions/mst-export" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = [request queryParamForKey:@"did"];
        NSString *format = [request queryParamForKey:@"format"] ?: @"json";
        NSData *data = [weakSelf.backendClient fetchMSTExportForDID:did format:format];
        if (data) {
            response.statusCode = 200;
            if ([format isEqualToString:@"dot"]) {
                response.contentType = @"text/vnd.graphviz; charset=utf-8";
            } else if ([format isEqualToString:@"svg"]) {
                response.contentType = @"image/svg+xml";
            } else {
                response.contentType = @"application/json";
            }
            [response setBodyData:data];
        } else {
            response.statusCode = 500;
            [response setJsonBody:@{@"error": @"Export failed"}];
        }
    }];
}

- (BOOL)ensureAuthorized:(HttpRequest *)request response:(HttpResponse *)response {
    if ([self.authManager isAuthorizedRequest:request]) {
        return YES;
    }
    NSString *htmxRequest = [request headerForKey:@"HX-Request"];
    if ([htmxRequest isEqualToString:@"true"]) {
        response.statusCode = 401;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:@"<div class=\"alert alert-destructive\">Session expired. <a href=\"/admin/login\">Sign in</a></div>"];
        return NO;
    }
    response.statusCode = 302;
    [response setHeader:@"/admin/login" forKey:@"Location"];
    response.contentType = @"text/plain; charset=utf-8";
    [response setBodyString:@"Authentication required\n"];
    return NO;
}

- (NSString *)loginPageHTML {
    return @"<!doctype html><html><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
    "<title>Garazyk UI Login</title>"
    "<link rel=\"stylesheet\" href=\"/css/system.css\">"
    "<style>.login-shell{display:flex;justify-content:center;align-items:center;min-height:100vh;background:var(--color-bg-primary)}"
    ".login-card{background:var(--color-bg-secondary);border:1px solid var(--separator-color);border-radius:var(--radius-lg);padding:var(--space-xl);width:320px;box-shadow:var(--shadow-lg)}"
    ".login-card h2{margin-bottom:var(--space-sm)}.login-card p{color:var(--color-text-secondary);margin-bottom:var(--space-lg)}"
    ".login-card input{width:100%;margin-bottom:var(--space-sm)}.login-card button{width:100%}"
    ".login-error{color:var(--color-destructive);margin-top:var(--space-sm);font-size:var(--font-size-sm)}</style>"
    "</head><body><div class=\"login-shell\"><div class=\"login-card\">"
    "<h2>Admin UI Service</h2><p>Sign in to continue.</p>"
    "<form id=\"login-form\"><input id=\"password\" type=\"password\" placeholder=\"Admin password\" required/>"
    "<button type=\"submit\" class=\"btn btn-primary\">Sign in</button></form>"
    "<p id=\"error\" class=\"login-error\"></p></div></div>"
    "<script>document.getElementById('login-form').addEventListener('submit',async(e)=>{e.preventDefault();"
    "const password=document.getElementById('password').value;"
    "const resp=await fetch('/admin/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({password})});"
    "if(resp.ok){window.location='/admin';return;}document.getElementById('error').textContent='Invalid credentials';});</script>"
    "</body></html>";
}

- (NSString *)adminShellHTML {
    return @"<!doctype html><html><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
    "<title>Garazyk UI Service</title>"
    "<link rel=\"stylesheet\" href=\"/css/system.css\">"
    "<script src=\"https://unpkg.com/htmx.org@1.9.12\" integrity=\"sha384-ujb1lZYygJmzgSwoxRggbCHcjc0rB2XoQrxeTUQyRjrOnlCoYta87iKBWq3EsdM2\" crossorigin=\"anonymous\"></script>"
    "</head><body><div class=\"admin-shell\">"
    "<header class=\"admin-header\"><div class=\"admin-header-title\">Garazyk UI Service</div>"
    "<nav class=\"service-segments\" id=\"nav-tabs\">"
    "<button class=\"service-segment active\" data-tab=\"overview\" onclick=\"switchTab('overview')\">Overview</button>"
    "<button class=\"service-segment\" data-tab=\"connections\" onclick=\"switchTab('connections')\">Connections</button>"
    "<button class=\"service-segment\" data-tab=\"pds\" onclick=\"switchTab('pds')\">PDS</button>"
    "<button class=\"service-segment\" data-tab=\"appview\" onclick=\"switchTab('appview')\">AppView</button>"
    "<button class=\"service-segment\" data-tab=\"relay\" onclick=\"switchTab('relay')\">Relay</button>"
    "<button class=\"service-segment\" data-tab=\"plc\" onclick=\"switchTab('plc')\">PLC</button>"
    "<button class=\"service-segment\" data-tab=\"explorer\" onclick=\"switchTab('explorer')\">Explorer</button>"
    "<button class=\"service-segment\" data-tab=\"ozone\" onclick=\"switchTab('ozone')\">Ozone</button>"
    "<button class=\"service-segment\" data-tab=\"security\" onclick=\"switchTab('security')\">Security</button>"
    "<button class=\"service-segment\" data-tab=\"mst\" onclick=\"switchTab('mst')\">MST</button>"
    "<button class=\"service-segment\" data-tab=\"chat\" onclick=\"switchTab('chat')\">Chat</button>"
    "<button class=\"service-segment\" data-tab=\"video\" onclick=\"switchTab('video')\">Video</button>"
    "</nav>"
    "<div class=\"admin-header-right\">"
    "<form method=\"post\" action=\"/admin/logout\" onsubmit=\"fetch('/admin/logout',{method:'POST'}).then(()=>location='/admin/login');return false;\">"
    "<button type=\"submit\" class=\"btn btn-secondary btn-sm\">Logout</button></form></div></header>"
    "<main class=\"admin-content\">"
    /* Overview tab */
    "<div id=\"tab-overview\" class=\"tab-pane\">"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">Service Status</h3>"
    "<div id=\"overview\" hx-get=\"/admin/partials/overview\" hx-trigger=\"load, every 20s\"></div></section></div>"
    /* Connections tab */
    "<div id=\"tab-connections\" class=\"tab-pane\" style=\"display:none\">"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">Service Connections</h3>\""
    "<p class=\"text-secondary text-sm mb-lg\">Configure URLs and admin tokens for each AT Protocol service. Changes apply immediately but are not persisted across restarts.</p>\""
    "<div id=\"connections-form\" hx-get=\"/admin/partials/connections\" hx-trigger=\"load\"></div></section></div>"
    /* PDS tab */
    "<div id=\"tab-pds\" class=\"tab-pane\" style=\"display:none\">"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">Accounts</h3>"
    "<div class=\"search-row\"><form class=\"d-flex gap-sm flex-1\" hx-get=\"/admin/partials/accounts\" hx-target=\"#accounts\">"
    "<input type=\"text\" name=\"q\" placeholder=\"Search email or DID\" class=\"form-input flex-1\"/>"
    "<button type=\"submit\" class=\"btn btn-primary btn-sm\">Search</button></form></div>"
    "<div id=\"accounts\" hx-get=\"/admin/partials/accounts\" hx-trigger=\"load\"></div></section>"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">Invite Codes</h3>"
    "<div id=\"invites\" hx-get=\"/admin/partials/invites\" hx-trigger=\"load\"></div>"
    "<div class=\"action-row\"><input id=\"disable-account\" type=\"text\" placeholder=\"DID to disable invites\" class=\"form-input flex-1\"/>"
    "<button class=\"btn btn-destructive btn-sm\" onclick=\"disableInvites()\">Disable Invites</button></div>"
    "<div class=\"action-row mt-sm\"><input id=\"enable-account\" type=\"text\" placeholder=\"DID to enable invites\" class=\"form-input flex-1\"/>"
    "<button class=\"btn btn-primary btn-sm\" onclick=\"enableInvites()\">Enable Invites</button></div>"
    "<div id=\"invite-action-result\"></div></section>"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">Server Stats</h3>"
    "<div id=\"pds-stats\" hx-get=\"/admin/partials/pds-stats\" hx-trigger=\"load, every 30s\"></div></section>"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">Audit Log</h3>"
    "<div id=\"audit-log-content\" hx-get=\"/admin/partials/audit-log\" hx-trigger=\"load\"></div></section>"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">Blobs</h3>"
    "<div id=\"blobs-content\" hx-get=\"/admin/partials/blobs\" hx-trigger=\"load\"></div></section>"
    "</div>"
    /* AppView tab */
    "<div id=\"tab-appview\" class=\"tab-pane\" style=\"display:none\">"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">Metrics</h3>"
    "<div id=\"appview-metrics\" hx-get=\"/admin/partials/appview-metrics\" hx-trigger=\"load, every 30s\"></div></section>"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">Ingest Health</h3>"
    "<div id=\"appview-ingest\" hx-get=\"/admin/partials/appview-ingest\" hx-trigger=\"load, every 30s\"></div></section>"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">Backfill Queue</h3>"
    "<div id=\"appview-queue\" hx-get=\"/admin/partials/appview-queue\" hx-trigger=\"load, every 10s\"></div></section></div>"
    /* Relay tab */
    "<div id=\"tab-relay\" class=\"tab-pane\" style=\"display:none\">"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">Relay Metrics</h3>"
    "<div id=\"relay-metrics\" hx-get=\"/admin/partials/relay-metrics\" hx-trigger=\"load, every 30s\"></div></section>"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">Health</h3>"
    "<div id=\"relay-health\" hx-get=\"/admin/partials/relay-health\" hx-trigger=\"load, every 30s\"></div></section>"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">Upstreams</h3>"
    "<div id=\"relay-upstreams\" hx-get=\"/admin/partials/relay-upstreams\" hx-trigger=\"load, every 30s\"></div></section>"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">Request Crawl</h3>"
    "<div class=\"action-row\"><input id=\"crawl-hostname\" type=\"text\" placeholder=\"Hostname to crawl\" class=\"form-input flex-1\"/>"
    "<button class=\"btn btn-primary btn-sm\" onclick=\"requestCrawl()\">Request Crawl</button></div>"
    "<div id=\"crawl-result\"></div></section></div>"
    /* PLC tab */
    "<div id=\"tab-plc\" class=\"tab-pane\" style=\"display:none\">"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">Health</h3>"
    "<div id=\"plc-health\" hx-get=\"/admin/partials/plc-health\" hx-trigger=\"load\"></div></section>"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">Metrics</h3>"
    "<div id=\"plc-metrics\" hx-get=\"/admin/partials/plc-metrics\" hx-trigger=\"load\"></div></section>"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">All DIDs</h3>"
    "<div id=\"plc-list\" hx-get=\"/admin/partials/plc-list\" hx-trigger=\"load\"></div></section>"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">DID Lookup</h3>"
    "<div class=\"search-row\"><form class=\"d-flex gap-sm flex-1\" hx-get=\"/admin/partials/plc-did\" hx-target=\"#plc-did-result\">"
    "<input type=\"text\" name=\"did\" placeholder=\"did:plc:...\" class=\"form-input flex-1\"/>"
    "<button type=\"submit\" class=\"btn btn-primary btn-sm\">Lookup</button></form></div>"
    "<div id=\"plc-did-result\"></div></section>"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">DID Log</h3>"
    "<div class=\"search-row\"><form class=\"d-flex gap-sm flex-1\" hx-get=\"/admin/partials/plc-log\" hx-target=\"#plc-log-result\">"
    "<input type=\"text\" name=\"did\" placeholder=\"did:plc:...\" class=\"form-input flex-1\"/>"
    "<button type=\"submit\" class=\"btn btn-primary btn-sm\">View Log</button></form></div>"
    "<div id=\"plc-log-result\"></div></section></div>"
    /* Explorer tab */
    "<div id=\"tab-explorer\" class=\"tab-pane\" style=\"display:none\">"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">Repo Explorer</h3>"
    "<div class=\"search-row\"><form class=\"d-flex gap-sm flex-1\" hx-get=\"/admin/partials/describe-repo\" hx-target=\"#repo-detail\">"
    "<input type=\"text\" name=\"did\" placeholder=\"did:plc:... or handle\" class=\"form-input flex-1\"/>"
    "<button type=\"submit\" class=\"btn btn-primary btn-sm\">Describe</button></form></div>"
    "<div id=\"repo-detail\"></div></section>"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">List Records</h3>"
    "<div class=\"search-row\"><form class=\"d-flex gap-sm flex-1\" hx-get=\"/admin/partials/list-records\" hx-target=\"#records-list\">"
    "<input type=\"text\" name=\"did\" placeholder=\"did:plc:...\" class=\"form-input flex-1\"/>"
    "<input type=\"text\" name=\"collection\" placeholder=\"Collection (optional)\" class=\"form-input flex-1\"/>"
    "<button type=\"submit\" class=\"btn btn-primary btn-sm\">List</button></form></div>"
    "<div id=\"records-list\"></div></section>"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">Get Record</h3>"
    "<div class=\"search-row\"><form class=\"d-flex gap-sm flex-1\" hx-get=\"/admin/partials/get-record\" hx-target=\"#record-detail\">"
    "<input type=\"text\" name=\"did\" placeholder=\"did:plc:...\" class=\"form-input flex-1\"/>"
    "<input type=\"text\" name=\"collection\" placeholder=\"Collection\" class=\"form-input flex-1\"/>"
    "<input type=\"text\" name=\"rkey\" placeholder=\"Record key\" class=\"form-input flex-1\"/>"
    "<button type=\"submit\" class=\"btn btn-primary btn-sm\">Get</button></form></div>"
    "<div id=\"record-detail\"></div></section></div>"
    /* Ozone tab */
    "<div id=\"tab-ozone\" class=\"tab-pane\" style=\"display:none\">"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">Moderation Statuses</h3>"
    "<div id=\"ozone-statuses\" hx-get=\"/admin/partials/ozone-statuses\" hx-trigger=\"load, every 30s\"></div></section>"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">Moderation Events</h3>"
    "<div id=\"ozone-events\" hx-get=\"/admin/partials/ozone-events\" hx-trigger=\"load\"></div></section>"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">Subject Status</h3>"
    "<div class=\"search-row\"><form class=\"d-flex gap-sm flex-1\" hx-get=\"/admin/partials/ozone-subject\" hx-target=\"#ozone-subject-result\">"
    "<input type=\"text\" name=\"did\" placeholder=\"did:plc:...\" class=\"form-input flex-1\"/>"
    "<button type=\"submit\" class=\"btn btn-primary btn-sm\">Lookup</button></form></div>"
    "<div id=\"ozone-subject-result\"></div></section>"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">Moderation Reports</h3>"
    "<div id=\"ozone-reports\" hx-get=\"/admin/partials/ozone-reports\" hx-trigger=\"load\"></div></section>"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">Scheduled Actions</h3>"
    "<div id=\"ozone-scheduled\" hx-get=\"/admin/partials/ozone-scheduled\" hx-trigger=\"load\"></div></section>"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">Verification</h3>"
    "<div id=\"ozone-verification\" hx-get=\"/admin/partials/ozone-verification\" hx-trigger=\"load\"></div></section>"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">Safelinks</h3>"
    "<div id=\"ozone-safelinks\" hx-get=\"/admin/partials/ozone-safelinks\" hx-trigger=\"load\"></div></section>"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">Settings</h3>"
    "<div id=\"ozone-settings\" hx-get=\"/admin/partials/ozone-settings\" hx-trigger=\"load\"></div></section>"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">Signatures</h3>"
    "<div id=\"ozone-signatures\" hx-get=\"/admin/partials/ozone-signatures\" hx-trigger=\"load\"></div></section>"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">Hosting History</h3>"
    "<div id=\"ozone-hosting\" hx-get=\"/admin/partials/ozone-hosting\" hx-trigger=\"load\"></div></section>"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">Team Members</h3>"
    "<div id=\"ozone-team\" hx-get=\"/admin/partials/ozone-team\" hx-trigger=\"load\"></div></section>"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">Sets</h3>"
    "<div id=\"ozone-sets\" hx-get=\"/admin/partials/ozone-sets\" hx-trigger=\"load\"></div></section>"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">Templates</h3>"
    "<div id=\"ozone-templates\" hx-get=\"/admin/partials/ozone-templates\" hx-trigger=\"load\"></div></section>"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">Configuration</h3>"
    "<div id=\"ozone-config\" hx-get=\"/admin/partials/ozone-config\" hx-trigger=\"load\"></div></section></div>"
    /* Security tab */
    "<div id=\"tab-security\" class=\"tab-pane\" style=\"display:none\">"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">Active Sessions</h3>"
    "<div class=\"search-row\"><form class=\"d-flex gap-sm flex-1\" hx-get=\"/admin/partials/sessions\" hx-target=\"#sessions-result\">"
    "<input type=\"text\" name=\"did\" placeholder=\"did:plc:...\" class=\"form-input flex-1\"/>"
    "<button type=\"submit\" class=\"btn btn-primary btn-sm\">Lookup</button></form></div>"
    "<div id=\"sessions-result\"></div></section>"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">App Passwords</h3>"
    "<div class=\"search-row\"><form class=\"d-flex gap-sm flex-1\" hx-get=\"/admin/partials/app-passwords\" hx-target=\"#app-passwords-result\">"
    "<input type=\"text\" name=\"did\" placeholder=\"did:plc:...\" class=\"form-input flex-1\"/>"
    "<button type=\"submit\" class=\"btn btn-primary btn-sm\">Lookup</button></form></div>"
    "<div id=\"app-passwords-result\"></div></section></div>"
    /* MST Viewer tab */
    "<div id=\"tab-mst\" class=\"tab-pane\" style=\"display:none\">"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">MST Accounts</h3>"
    "<div id=\"mst-accounts\" hx-get=\"/admin/partials/mst-accounts\" hx-trigger=\"load\"></div></section>"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">MST Tree</h3>"
    "<div class=\"search-row\"><form class=\"d-flex gap-sm flex-1\" hx-get=\"/admin/partials/mst-tree\" hx-target=\"#mst-tree-result\">"
    "<input type=\"text\" name=\"did\" placeholder=\"did:plc:...\" class=\"form-input flex-1\"/>"
    "<button type=\"submit\" class=\"btn btn-primary btn-sm\">View Tree</button></form></div>"
    "<div id=\"mst-tree-result\"></div></section>"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">MST Statistics</h3>"
    "<div class=\"search-row\"><form class=\"d-flex gap-sm flex-1\" hx-get=\"/admin/partials/mst-stats\" hx-target=\"#mst-stats-result\">"
    "<input type=\"text\" name=\"did\" placeholder=\"did:plc:...\" class=\"form-input flex-1\"/>"
    "<button type=\"submit\" class=\"btn btn-primary btn-sm\">View Stats</button></form></div>"
    "<div id=\"mst-stats-result\"></div></section>"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">Export MST</h3>"
    "<div class=\"action-row\"><input id=\"mst-export-did\" type=\"text\" placeholder=\"did:plc:...\" class=\"form-input flex-1\"/>"
    "<select id=\"mst-export-format\" class=\"form-input flex-none\"><option value=\"json\">JSON</option><option value=\"dot\">DOT</option><option value=\"svg\">SVG</option></select>"
    "<button class=\"btn btn-primary btn-sm\" onclick=\"exportMST()\">Export</button></div>"
    "<div id=\"mst-export-result\"></div></section></div>"
    /* Chat tab */
    "<div id=\"tab-chat\" class=\"tab-pane\" style=\"display:none\">"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">Conversations</h3>"
    "<div id=\"chat-convos\" hx-get=\"/admin/partials/chat-convos\" hx-trigger=\"load, every 20s\"></div></section>"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">Messages</h3>"
    "<div class=\"action-row\"><input id=\"chat-convo-id\" type=\"text\" placeholder=\"Conversation ID\" class=\"form-input flex-1\"/>"
    "<button class=\"btn btn-primary btn-sm\" onclick=\"loadChatMessages()\">Load Messages</button></div>"
    "<div id=\"chat-messages\" hx-trigger=\"load\"></div>"
    "<div id=\"chat-action-result\"></div></section></div>"
    /* Video tab */
    "<div id=\"tab-video\" class=\"tab-pane\" style=\"display:none\">"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">Service Health</h3>"
    "<div id=\"video-health\" hx-get=\"/admin/partials/video-health\" hx-trigger=\"load, every 30s\"></div></section>"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">Job Queue</h3>"
    "<div class=\"action-row\">"
    "<button class=\"btn btn-secondary btn-sm\" onclick=\"filterVideoJobs('')\">All</button>"
    "<button class=\"btn btn-secondary btn-sm\" onclick=\"filterVideoJobs('PENDING')\">Pending</button>"
    "<button class=\"btn btn-secondary btn-sm\" onclick=\"filterVideoJobs('PROCESSING')\">Processing</button>"
    "<button class=\"btn btn-secondary btn-sm\" onclick=\"filterVideoJobs('COMPLETED')\">Completed</button>"
    "<button class=\"btn btn-secondary btn-sm\" onclick=\"filterVideoJobs('FAILED')\">Failed</button>"
    "</div>"
    "<div id=\"video-jobs\" hx-get=\"/admin/partials/video-jobs\" hx-trigger=\"load, every 10s\"></div></section>"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">Upload Quotas</h3>"
    "<div id=\"video-quotas\" hx-get=\"/admin/partials/video-quotas\" hx-trigger=\"load\"></div></section>"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">Job Lookup</h3>"
    "<div class=\"action-row\"><input id=\"video-job-id\" type=\"text\" placeholder=\"Job ID\" class=\"form-input flex-1\"/>"
    "<button class=\"btn btn-primary btn-sm\" onclick=\"loadVideoJobDetail()\">Look Up</button></div>"
    "<div id=\"video-job-detail\"></div></section></div>"
    "</main>"
    "<footer class=\"admin-footer\"><span class=\"version-info\"></span>"
    "<span id=\"footer-status\"></span></footer>"
    "</div>"
    "<script>"
    "function switchTab(name){"
    "document.querySelectorAll('.tab-pane').forEach(p=>p.style.display='none');"
    "document.querySelectorAll('.service-segment').forEach(s=>s.classList.remove('active'));"
    "var pane=document.getElementById('tab-'+name);if(pane)pane.style.display='block';"
    "var btn=document.querySelector('[data-tab=\"'+name+'\"]');if(btn)btn.classList.add('active');"
    "}"
    "function activeTabPane(){return Array.from(document.querySelectorAll('.tab-pane')).find(p=>getComputedStyle(p).display!=='none')||document;}"
    "function didFromText(text){const m=(text||'').match(/\\bdid:[a-z0-9]+:[A-Za-z0-9._:%-]+/);return m?m[0]:'';}"
    "function didFieldHint(el){let hint=[el.id,el.name,el.placeholder,el.getAttribute('aria-label')].filter(Boolean).join(' ');"
    "const group=el.closest('.form-group');if(group){const label=group.querySelector('label');if(label)hint+=' '+label.textContent;}"
    "return hint.toLowerCase();}"
    "function inputExpectsDID(el){if(!el||el.disabled||el.readOnly)return false;"
    "if(el.tagName==='INPUT'){const type=(el.type||'text').toLowerCase();if(['hidden','checkbox','radio','button','submit','reset','password'].includes(type))return false;}"
    "else if(el.tagName!=='TEXTAREA'){return false;}return didFieldHint(el).includes('did');}"
    "function fillVisibleDIDInputs(did){if(!did)return false;const scope=activeTabPane();let filled=false;"
    "scope.querySelectorAll('input,textarea').forEach(el=>{if(inputExpectsDID(el)){el.value=did;el.dispatchEvent(new Event('input',{bubbles:true}));el.dispatchEvent(new Event('change',{bubbles:true}));filled=true;}});return filled;}"
    "document.addEventListener('click',function(e){if(e.target.closest('button,a,input,select,textarea,label'))return;"
    "const node=e.target.closest('td,span,li,code,pre,div');if(!node)return;const did=didFromText(node.textContent);if(did)fillVisibleDIDInputs(did);});"
    "async function disableInvites(){const account=document.getElementById('disable-account').value;"
    "const resp=await fetch('/admin/actions/disable-invites',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({account})});"
    "document.getElementById('invite-action-result').innerHTML=await resp.text();htmx.ajax('GET','/admin/partials/invites','#invites');}"
    "async function enableInvites(){const account=document.getElementById('enable-account').value;"
    "const resp=await fetch('/admin/actions/enable-invites',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({account})});"
    "document.getElementById('invite-action-result').innerHTML=await resp.text();htmx.ajax('GET','/admin/partials/invites','#invites');}"
    "async function requestCrawl(){const hostname=document.getElementById('crawl-hostname').value;"
    "const resp=await fetch('/admin/actions/request-crawl',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({hostname})});"
    "document.getElementById('crawl-result').innerHTML=await resp.text();htmx.ajax('GET','/admin/partials/relay-upstreams','#relay-upstreams');}"
    "async function removeTeamMember(did){const resp=await fetch('/admin/actions/remove-team-member',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({did})});"
    "document.getElementById('ozone-team').innerHTML=await resp.text();htmx.ajax('GET','/admin/partials/ozone-team','#ozone-team');}"
    "async function deleteOzoneSet(name){const resp=await fetch('/admin/actions/delete-ozone-set',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({name})});"
    "document.getElementById('ozone-sets').innerHTML=await resp.text();htmx.ajax('GET','/admin/partials/ozone-sets','#ozone-sets');}"
    "async function deleteOzoneTemplate(name){const resp=await fetch('/admin/actions/delete-ozone-template',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({name})});"
    "document.getElementById('ozone-templates').innerHTML=await resp.text();htmx.ajax('GET','/admin/partials/ozone-templates','#ozone-templates');}"
    "async function revokeSession(did,id){const resp=await fetch('/admin/actions/revoke-session',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({did,id})});"
    "document.getElementById('sessions-result').innerHTML=await resp.text();}"
    "async function deleteAppPassword(did,name){const resp=await fetch('/admin/actions/delete-app-password',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({did,name})});"
    "document.getElementById('app-passwords-result').innerHTML=await resp.text();}"
    "async function exportMST(){const did=document.getElementById('mst-export-did').value;"
    "const format=document.getElementById('mst-export-format').value;"
    "window.open('/admin/actions/mst-export?did='+encodeURIComponent(did)+'&format='+format);}"
    "function toggleSelectAll(el){document.querySelectorAll('.account-checkbox').forEach(cb=>cb.checked=el.checked);}"
    "async function bulkAction(type){"
    "const selected=Array.from(document.querySelectorAll('.account-checkbox:checked')).map(cb=>cb.value);"
    "if(selected.length===0){alert('No accounts selected');return;}"
    "if(!confirm('Are you sure you want to '+type+' '+selected.length+' accounts?'))return;"
    "const resp=await fetch('/admin/actions/bulk-'+type,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({dids:selected})});"
    "const result=await resp.json(); alert(result.message || (result.success ? 'Success' : 'Failed'));"
    "htmx.ajax('GET','/admin/partials/accounts','#accounts');}"
    "async function deleteAccount(did){if(!confirm('Are you sure you want to delete this account?'))return;"
    "const resp=await fetch('/admin/actions/delete-account',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({did})});"
    "document.getElementById('account-detail-result').innerHTML=await resp.text();}"
    "async function rebuildAppViewScope(){if(!confirm('Rebuild the entire AppView relevance set?'))return;"
    "const resp=await fetch('/admin/actions/appview-rebuild-scope',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({})});"
    "document.getElementById('appview-result').innerHTML=await resp.text();}"
    "async function enqueueBackfillDIDs(){const input=document.getElementById('enqueue-dids-input').value;"
    "const dids=input.split('\\n').map(d=>d.trim()).filter(d=>d.length>0);"
    "if(dids.length===0){alert('No DIDs provided');return;}"
    "const resp=await fetch('/admin/actions/appview-enqueue-dids',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({dids})});"
    "document.getElementById('appview-result').innerHTML=await resp.text();}"
    "async function createAppPassword(){const did=document.getElementById('create-pwd-did').value;"
    "const name=document.getElementById('create-pwd-name').value;"
    "if(!did||!name){alert('DID and name required');return;}"
    "const resp=await fetch('/admin/actions/create-app-password',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({did,name})});"
    "document.getElementById('app-passwords-result').innerHTML=await resp.text();document.getElementById('create-pwd-did').value='';document.getElementById('create-pwd-name').value='';}"
    "async function addOzoneTeamMember(){const did=document.getElementById('add-member-did').value;"
    "const role=document.getElementById('add-member-role').value;"
    "if(!did){alert('DID required');return;}"
    "const resp=await fetch('/admin/actions/add-ozone-team-member',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({member:{did,role}})});"
    "document.getElementById('ozone-team').innerHTML=await resp.text();document.getElementById('add-member-did').value='';htmx.ajax('GET','/admin/partials/ozone-team','#ozone-team');}"
    "async function upsertOzoneSet(){const name=document.getElementById('create-set-name').value;"
    "const description=document.getElementById('create-set-desc').value;"
    "if(!name){alert('Set name required');return;}"
    "const resp=await fetch('/admin/actions/upsert-ozone-set',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({setSpec:{name,description}})});"
    "document.getElementById('ozone-sets').innerHTML=await resp.text();document.getElementById('create-set-name').value='';document.getElementById('create-set-desc').value='';htmx.ajax('GET','/admin/partials/ozone-sets','#ozone-sets');}"
    "async function createOzoneTemplate(){const name=document.getElementById('create-template-name').value;"
    "const subject=document.getElementById('create-template-subject').value;"
    "const content=document.getElementById('create-template-content').value;"
    "if(!name||!subject){alert('Name and subject required');return;}"
    "const resp=await fetch('/admin/actions/create-ozone-template',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({template:{name,subject,contentMarkdown:content}})});"
    "document.getElementById('ozone-templates').innerHTML=await resp.text();document.getElementById('create-template-name').value='';htmx.ajax('GET','/admin/partials/ozone-templates','#ozone-templates');}"
    "async function updateOzoneConfig(){const configJson=document.getElementById('config-json').value;"
    "try{const config=JSON.parse(configJson);const resp=await fetch('/admin/actions/update-ozone-config',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({config})});"
    "document.getElementById('ozone-config-result').innerHTML=await resp.text();}catch(e){alert('Invalid JSON: '+e.message);}}"
    "async function resolvePDSReport(){const reportID=document.getElementById('report-id').value;"
    "const action=document.getElementById('report-action').value;"
    "if(!reportID||!action){alert('Report ID and action required');return;}"
    "const resp=await fetch('/admin/actions/resolve-pds-report',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({reportID,action})});"
    "document.getElementById('pds-reports-result').innerHTML=await resp.text();}"
    "async function scheduleOzoneAction(){const did=document.getElementById('schedule-subject-did').value;"
    "const actionType=document.getElementById('schedule-action-type').value;"
    "if(!did){alert('Subject DID required');return;}"
    "const actionSpec={subject:did,action:actionType};"
    "const resp=await fetch('/admin/actions/ozone-schedule-action',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(actionSpec)});"
    "document.getElementById('schedule-subject-did').value='';htmx.ajax('GET','/admin/partials/ozone-scheduled','#ozone-scheduled');}"
    "async function cancelScheduledAction(subject){if(!confirm('Cancel this scheduled action?'))return;"
    "const resp=await fetch('/admin/actions/ozone-cancel-scheduled',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({subjects:[subject]})});"
    "htmx.ajax('GET','/admin/partials/ozone-scheduled','#ozone-scheduled');}"
    "async function grantOzoneVerification(){const did=document.getElementById('grant-verification-did').value;"
    "const displayName=document.getElementById('grant-verification-name').value;"
    "if(!did){alert('DID required');return;}"
    "const resp=await fetch('/admin/actions/ozone-grant-verification',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({did,displayName})});"
    "document.getElementById('grant-verification-did').value='';document.getElementById('grant-verification-name').value='';htmx.ajax('GET','/admin/partials/ozone-verification','#ozone-verification');}"
    "async function revokeOzoneVerification(did){if(!confirm('Revoke verification for this account?'))return;"
    "const resp=await fetch('/admin/actions/ozone-revoke-verification',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({dids:[did]})});"
    "htmx.ajax('GET','/admin/partials/ozone-verification','#ozone-verification');}"
    "async function addSafelinkRule(){const url=document.getElementById('add-safelink-url').value;"
    "const pattern=document.getElementById('add-safelink-pattern').value;"
    "const action=document.getElementById('add-safelink-action').value;"
    "const reason=document.getElementById('add-safelink-reason').value;"
    "const comment=document.getElementById('add-safelink-comment').value;"
    "if(!url){alert('URL required');return;}"
    "const resp=await fetch('/admin/actions/add-safelink-rule',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({url,pattern,action,reason,comment})});"
    "document.getElementById('add-safelink-url').value='';document.getElementById('add-safelink-comment').value='';htmx.ajax('GET','/admin/partials/ozone-safelinks','#ozone-safelinks');}"
    "async function removeSafelinkRule(url,pattern){if(!confirm('Remove this safelink rule?'))return;"
    "const resp=await fetch('/admin/actions/remove-safelink-rule',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({url,pattern})});"
    "htmx.ajax('GET','/admin/partials/ozone-safelinks','#ozone-safelinks');}"
    "async function findOzoneRelatedAccounts(){const did=document.getElementById('ozone-find-did').value;"
    "if(!did){alert('DID required');return;}"
    "const resp=await fetch('/admin/actions/ozone-find-related',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({did})});"
    "document.getElementById('ozone-signature-results').innerHTML=await resp.text();}"
    "function loadHostingHistory(){const did=document.getElementById('hosting-did-input').value;"
    "if(!did){alert('DID required');return;}"
    "htmx.ajax('GET','/admin/partials/ozone-hosting?did='+encodeURIComponent(did),'#ozone-hosting');}"
    "function loadBlobs(){const did=document.getElementById('blob-did-input').value;"
    "if(!did){alert('DID required');return;}"
    "htmx.ajax('GET','/admin/partials/blobs?did='+encodeURIComponent(did),'#blobs-content');}"
    "function loadChatMessages(){const convoID=document.getElementById('chat-convo-id').value;"
    "if(!convoID){alert('Conversation ID required');return;}"
    "htmx.ajax('GET','/admin/partials/chat-messages?convoID='+encodeURIComponent(convoID),'#chat-messages');}"
    "async function lockChatConvo(convoID){if(!confirm('Lock this conversation?'))return;"
    "const resp=await fetch('/admin/actions/lock-chat-convo',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({convoID})});"
    "document.getElementById('chat-action-result').innerHTML=await resp.text();htmx.ajax('GET','/admin/partials/chat-convos','#chat-convos');}"
    "function filterVideoJobs(state){"
    "var url='/admin/partials/video-jobs';if(state)url+='?state='+encodeURIComponent(state);"
    "htmx.ajax('GET',url,'#video-jobs');}"
    "function loadVideoJobDetail(){const jobId=document.getElementById('video-job-id').value;"
    "if(!jobId){alert('Job ID required');return;}"
    "htmx.ajax('GET','/admin/partials/video-job-detail?jobId='+encodeURIComponent(jobId),'#video-job-detail');}"
    "async function retryVideoJob(jobId){if(!confirm('Retry this job?'))return;"
    "const resp=await fetch('/admin/actions/video-retry-job',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({jobId})});"
    "document.getElementById('video-job-detail').innerHTML=await resp.text();htmx.ajax('GET','/admin/partials/video-jobs','#video-jobs');}"
    "async function saveConnections(){"
    "const services=[['pds','pds'],['plc','plc'],['relay','relay'],['appview','appView'],['chat','chat'],['video','video']];"
    "const body={};"
    "services.forEach(([id,key])=>{body[key+'URL']=document.getElementById('conn-'+id+'-url').value;body[key+'Token']=document.getElementById('conn-'+id+'-token').value;});"
    "const resp=await fetch('/admin/actions/update-connections',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});"
    "document.getElementById('connections-form').innerHTML=await resp.text();}"
    "async function testConnection(service){"
    "const url=document.getElementById('conn-'+service+'-url').value;"
    "const token=document.getElementById('conn-'+service+'-token').value;"
    "const resultEl=document.getElementById('conn-'+service+'-test-result');"
    "resultEl.textContent='Testing...';"
    "try{const resp=await fetch('/admin/actions/test-connection',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({service,url,token})});"
    "const result=await resp.json();"
    "if(result.status==='online'){resultEl.innerHTML='<span class=\"badge badge-success\">Connected</span>';}"
    "else{resultEl.innerHTML='<span class=\"badge badge-destructive\">'+(result.error||result.status||'Failed')+'</span>';}}"
    "catch(e){resultEl.innerHTML='<span class=\"badge badge-destructive\">Failed</span>';}}"
    "</script>"
    "</body></html>";
}

- (NSString *)renderAccountsPartial:(NSDictionary *)result {
    NSArray<NSDictionary *> *accounts = [result[@"accounts"] isKindOfClass:[NSArray class]] ? result[@"accounts"] : @[];
    NSMutableString *html = [NSMutableString stringWithString:@""];
    
    if (accounts.count > 0) {
        [html appendString:@"<div class=\"bulk-actions mb-sm d-flex gap-sm\">"
         "<button class=\"btn btn-secondary btn-sm\" onclick=\"bulkAction('takedown')\">Bulk Takedown</button>"
         "<button class=\"btn btn-destructive btn-sm\" onclick=\"bulkAction('delete')\">Bulk Delete</button>"
         "</div>"];
    }

    [html appendString:@"<table class=\"table\"><thead><tr><th><input type=\"checkbox\" id=\"select-all-accounts\" onclick=\"toggleSelectAll(this)\"></th><th>DID</th><th>Handle</th><th>Email</th></tr></thead><tbody>"];
    if (result[@"error"]) {
        NSString *message = UIEscaped(result[@"message"] ?: result[@"error"]);
        [html appendFormat:@"<tr><td colspan=\"4\" class=\"text-destructive\">%@</td></tr>", message];
    } else {
        for (NSDictionary *account in accounts) {
            NSString *did = UIEscaped(account[@"did"] ?: @"");
            NSString *handle = UIEscaped(account[@"handle"] ?: @"");
            NSString *email = UIEscaped(account[@"email"] ?: @"");
            [html appendFormat:@"<tr><td><input type=\"checkbox\" class=\"account-checkbox\" value=\"%@\"></td><td class=\"text-mono text-xs\">%@</td><td>%@</td><td>%@</td></tr>", did, did, handle, email];
        }
        if (accounts.count == 0) {
            [html appendString:@"<tr><td colspan=\"4\" class=\"text-center text-secondary p-lg\">No accounts found.</td></tr>"];
        }
    }
    [html appendString:@"</tbody></table>"];
    return html;
}

- (NSString *)renderInvitesPartial:(NSDictionary *)result {
    NSArray<NSDictionary *> *codes = [result[@"codes"] isKindOfClass:[NSArray class]] ? result[@"codes"] : @[];
    NSMutableString *html = [NSMutableString stringWithString:@"<table class=\"table\"><thead><tr><th>Code</th><th>Available</th><th>Uses</th></tr></thead><tbody>"];
    if (result[@"error"]) {
        NSString *message = UIEscaped(result[@"message"] ?: result[@"error"]);
        [html appendFormat:@"<tr><td colspan=\"3\" class=\"text-destructive\">%@</td></tr>", message];
    } else {
        for (NSDictionary *entry in codes) {
            NSString *code = UIEscaped(entry[@"code"] ?: @"");
            NSString *available = UIEscaped([entry[@"available"] stringValue] ?: @"0");
            NSString *uses = UIEscaped([entry[@"uses"] stringValue] ?: @"0");
            [html appendFormat:@"<tr><td class=\"text-mono text-xs\">%@</td><td>%@</td><td>%@</td></tr>", code, available, uses];
        }
        if (codes.count == 0) {
            [html appendString:@"<tr><td colspan=\"3\" class=\"text-center text-secondary p-lg\">No invite codes found.</td></tr>"];
        }
    }
    [html appendString:@"</tbody></table>"];
    return html;
}

- (NSString *)renderAppViewMetricsPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSMutableString *html = [NSMutableString stringWithString:@"<div class=\"metric-row\">"];
    NSDictionary *backfill = result[@"backfill"] ?: @{};
    NSDictionary *ingest = result[@"ingest"] ?: @{};
    NSDictionary *index = result[@"index"] ?: @{};

    [html appendFormat:@"<div class=\"metric\"><span class=\"metric-label\">Queue Depth</span><span class=\"metric-value\">%@</span></div>", UIEscaped([backfill[@"queue_depth"] stringValue] ?: @"0")];
    [html appendFormat:@"<div class=\"metric\"><span class=\"metric-label\">Active Workers</span><span class=\"metric-value\">%@</span></div>", UIEscaped([backfill[@"active_workers"] stringValue] ?: @"0")];
    [html appendFormat:@"<div class=\"metric\"><span class=\"metric-label\">Relays</span><span class=\"metric-value\">%@</span></div>", UIEscaped([ingest[@"relays"] stringValue] ?: @"0")];
    [html appendFormat:@"<div class=\"metric\"><span class=\"metric-label\">Index Records</span><span class=\"metric-value\">%@</span></div>", UIEscaped([index[@"total_records"] stringValue] ?: @"0")];
    [html appendString:@"</div>"];
    return html;
}

- (NSString *)renderIngestHealthPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSMutableString *html = [NSMutableString stringWithString:@"<table class=\"table\"><thead><tr><th>Relay</th><th>Lag</th><th>Throughput</th></tr></thead><tbody>"];
    NSArray<NSDictionary *> *relays = [result[@"relays"] isKindOfClass:[NSArray class]] ? result[@"relays"] : @[];
    for (NSDictionary *relay in relays) {
        NSString *url = UIEscaped(relay[@"url"] ?: @"");
        NSString *lag = UIEscaped([relay[@"lag"] stringValue] ?: @"0");
        NSString *tps = UIEscaped([relay[@"throughput"] stringValue] ?: @"0");
        [html appendFormat:@"<tr><td class=\"text-mono text-xs\">%@</td><td>%@</td><td>%@</td></tr>", url, lag, tps];
    }
    if (relays.count == 0) {
        [html appendString:@"<tr><td colspan=\"3\" class=\"text-center text-secondary p-lg\">No relay ingest data.</td></tr>"];
    }
    [html appendString:@"</tbody></table>"];
    return html;
}

- (NSString *)renderBackfillQueuePartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSMutableString *html = [NSMutableString stringWithString:@"<div id=\"appview-result\"></div><div class=\"mb-lg\"><button class=\"btn btn-secondary btn-sm\" onclick=\"rebuildAppViewScope()\">Rebuild Relevance Set</button></div><form class=\"form mb-lg\" onsubmit=\"enqueueBackfillDIDs();return false;\"><div class=\"form-group\"><label>Enqueue DIDs (one per line):</label><textarea id=\"enqueue-dids-input\" class=\"form-input\" placeholder=\"did:plc:...\"></textarea></div><button type=\"submit\" class=\"btn btn-primary btn-sm\">Enqueue</button></form><table class=\"table\" id=\"queue-table\"><thead><tr><th>DID</th><th>Status</th><th>Actions</th></tr></thead><tbody>"];
    NSArray<NSDictionary *> *entries = [result[@"entries"] isKindOfClass:[NSArray class]] ? result[@"entries"] : @[];
    for (NSDictionary *entry in entries) {
        NSString *did = UIEscaped(entry[@"did"] ?: @"");
        NSString *status = UIEscaped(entry[@"status"] ?: @"");
        NSString *statusBadge = [status isEqualToString:@"running"] ? @"badge badge-success" :
                                [status isEqualToString:@"failed"] ? @"badge badge-destructive" : @"badge badge-secondary";
        [html appendFormat:@"<tr><td class=\"text-mono text-xs\">%@</td><td><span class=\"%@\">%@</span></td><td>", did, statusBadge, status];
        [html appendFormat:@"<button class=\"btn btn-sm btn-primary\" onclick=\"fetch('/admin/actions/appview-retry-repo',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({did:'%@'})}).then(()=>htmx.ajax('GET','/admin/partials/appview-queue','#appview-queue'))\">Retry</button> ", did];
        [html appendFormat:@"<button class=\"btn btn-secondary btn-sm\" onclick=\"fetch('/admin/actions/appview-cancel-repo',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({did:'%@'})}).then(()=>htmx.ajax('GET','/admin/partials/appview-queue','#appview-queue'))\">Cancel</button>", did];
        [html appendString:@"</td></tr>"];
    }
    if (entries.count == 0) {
        [html appendString:@"<tr><td colspan=\"3\" class=\"text-center text-secondary p-lg\">Queue is empty.</td></tr>"];
    }
    [html appendString:@"</tbody></table>"];
    return html;
}

- (NSString *)renderRelayMetricsPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSMutableString *html = [NSMutableString stringWithString:@"<div class=\"metric-row\">"];

    NSDictionary *metrics = result[@"metrics"] ?: result;
    for (NSString *key in metrics) {
        if (![metrics[key] isKindOfClass:[NSString class]] && ![metrics[key] isKindOfClass:[NSNumber class]]) continue;
        NSString *val = [metrics[key] description];
        [html appendFormat:@"<div class=\"metric\"><span class=\"metric-label\">%@</span><span class=\"metric-value\">%@</span></div>", UIEscaped(key), UIEscaped(val)];
    }
    if (metrics.count == 0) {
        [html appendString:@"<div class=\"text-center text-secondary p-lg\">No metrics found.</div>"];
    }
    [html appendString:@"</div>"];
    return html;
}

- (NSString *)renderAccountDetailPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSString *did = result[@"did"] ?: @"";
    NSMutableString *html = [NSMutableString stringWithString:@"<div id=\"account-detail-result\"></div><div class=\"detail-grid\">"];
    NSArray *fields = @[@"did", @"handle", @"email", @"emailConfirmed", @"invitesDisabled", @"deactivatedAt"];
    for (NSString *key in fields) {
        id val = result[key];
        if (!val) continue;
        NSString *display = [val isKindOfClass:[NSString class]] ? UIEscaped(val) : UIEscaped([val description]);
        [html appendFormat:@"<div class=\"detail-field\"><span class=\"detail-label\">%@</span><span class=\"detail-value\">%@</span></div>", key, display];
    }
    [html appendFormat:@"</div><div class=\"mt-lg\"><button class=\"btn btn-destructive btn-sm\" onclick=\"deleteAccount('%@')\">Delete Account</button></div>", UIEscaped(did)];
    return html;
}

- (NSString *)renderBlobsPartial:(NSDictionary *)result did:(nullable NSString *)did {
    NSMutableString *html = [NSMutableString stringWithString:@"<div class=\"mb-lg\"><form class=\"d-flex gap-sm\" onsubmit=\"loadBlobs();return false;\"><input type=\"text\" id=\"blob-did-input\" class=\"form-input flex-1\" placeholder=\"did:plc:...\" value=\""];
    if (did && did.length > 0) {
        [html appendFormat:@"%@", UIEscaped(did)];
    }
    [html appendString:@"\"/><button type=\"submit\" class=\"btn btn-primary btn-sm\">Load Blobs</button></form></div>"];

    if (result[@"error"]) {
        [html appendFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    } else {
        [html appendString:@"<table class=\"table\"><thead><tr><th>CID</th><th>Size</th><th>Type</th></tr></thead><tbody>"];
        NSArray<NSDictionary *> *blobs = [result[@"blobs"] isKindOfClass:[NSArray class]] ? result[@"blobs"] : @[];
        for (NSDictionary *blob in blobs) {
            NSString *cid = UIEscaped(blob[@"cid"] ?: @"");
            NSString *size = UIEscaped([blob[@"size"] stringValue] ?: @"0");
            NSString *type = UIEscaped(blob[@"mimeType"] ?: @"");
            [html appendFormat:@"<tr><td class=\"text-mono text-xs\">%@</td><td>%@</td><td>%@</td></tr>", cid, size, type];
        }
        if (blobs.count == 0) {
            [html appendString:@"<tr><td colspan=\"3\" class=\"text-center text-secondary p-lg\">No blobs found.</td></tr>"];
        }
        [html appendString:@"</tbody></table>"];
        NSString *cursor = UIStringFromDict(result, @"cursor");
        if (cursor && cursor.length > 0) {
            [html appendFormat:@"<div class=\"mt-sm\"><button class=\"btn btn-secondary btn-sm\" hx-get=\"/admin/partials/blobs?did=%@&cursor=%@\" hx-target=\"#blobs-content\">Load More</button></div>", UIEscaped(did ?: @""), UIEscaped(cursor)];
        }
    }
    return html;
}

- (NSString *)renderServerStatsPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSMutableString *html = [NSMutableString stringWithString:@"<div class=\"detail-card\">"];
    [html appendFormat:@"<div class=\"detail-row\"><span class=\"detail-label\">Repos:</span> <span class=\"detail-value text-mono\">%@</span></div>", UIEscaped(result[@"repos"] ?: @"0")];
    [html appendFormat:@"<div class=\"detail-row\"><span class=\"detail-label\">Records:</span> <span class=\"detail-value text-mono\">%@</span></div>", UIEscaped(result[@"records"] ?: @"0")];
    [html appendFormat:@"<div class=\"detail-row\"><span class=\"detail-label\">Blobs:</span> <span class=\"detail-value text-mono\">%@</span></div>", UIEscaped(result[@"blobs"] ?: @"0")];
    [html appendString:@"</div>"];
    return html;
}

- (NSString *)renderAuditLogPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSArray<NSDictionary *> *events = [result[@"events"] isKindOfClass:[NSArray class]] ? result[@"events"] : @[];
    NSMutableString *html = [NSMutableString stringWithString:@"<table class=\"table\"><thead><tr><th>Time</th><th>Action</th><th>Subject</th><th>Created By</th></tr></thead><tbody>"];
    for (NSDictionary *event in events) {
        NSString *time = UIEscaped(event[@"createdAt"] ?: @"");
        NSString *action = UIEscaped(event[@"action"] ?: @"");
        NSString *subject = UIEscaped(event[@"subject"] ?: @"");
        NSString *createdBy = UIEscaped(event[@"createdBy"] ?: @"");
        [html appendFormat:@"<tr><td class=\"text-xs text-mono\">%@</td><td>%@</td><td class=\"text-mono text-xs\">%@</td><td class=\"text-xs\">%@</td></tr>", time, action, subject, createdBy];
    }
    if (events.count == 0) {
        [html appendString:@"<tr><td colspan=\"4\" class=\"text-center text-secondary p-lg\">No audit log entries.</td></tr>"];
    }
    [html appendString:@"</tbody></table>"];
    // Pagination
    id cursorObj = result[@"cursor"];
    NSString *cursor = [cursorObj isKindOfClass:[NSString class]] ? cursorObj : nil;
    if (cursor.length > 0) {
        [html appendFormat:@"<div class=\"d-flex justify-between mt-sm\"><button class=\"btn btn-secondary btn-sm\" hx-get=\"/admin/partials/audit-log?cursor=%@\" hx-target=\"#audit-log-content\">Load more</button></div>", UIEscaped(cursor)];
    }
    return html;
}

- (NSString *)renderPDSReportsPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSArray<NSDictionary *> *reports = [result[@"reports"] isKindOfClass:[NSArray class]] ? result[@"reports"] : @[];
    NSMutableString *html = [NSMutableString stringWithString:@"<div id=\"pds-reports-result\"></div><table class=\"table\"><thead><tr><th>ID</th><th>Created At</th><th>Status</th><th>Actions</th></tr></thead><tbody>"];
    for (NSDictionary *report in reports) {
        NSString *reportID = UIEscaped(report[@"id"] ?: @"");
        NSString *createdAt = UIEscaped(report[@"createdAt"] ?: @"");
        NSString *status = UIEscaped(report[@"status"] ?: @"unknown");
        [html appendFormat:@"<tr><td class=\"text-mono text-xs\">%@</td><td class=\"text-xs\">%@</td><td>%@</td><td><select class=\"form-input\" onchange=\"if(this.value)resolvePDSReport('%@')\"><option value=\"\">Resolve as...</option><option value=\"escalate\">Escalate</option><option value=\"mute\">Mute</option><option value=\"markResolved\">Mark Resolved</option></select></td></tr>", reportID, createdAt, status, UIEscaped(reportID)];
    }
    if (reports.count == 0) {
        [html appendString:@"<tr><td colspan=\"4\" class=\"text-center text-secondary p-lg\">No reports found.</td></tr>"];
    }
    [html appendString:@"</tbody></table>"];
    NSString *cursor = UIStringFromDict(result, @"cursor");
    if (cursor.length > 0) {
        [html appendFormat:@"<div class=\"d-flex justify-between mt-sm\"><button class=\"btn btn-secondary btn-sm\" hx-get=\"/admin/partials/pds-reports?cursor=%@\" hx-target=\"#pds-reports-content\">Load more</button></div>", UIEscaped(cursor)];
    }
    return html;
}

- (NSString *)renderRelayUpstreamsPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSArray<NSDictionary *> *upstreams = [result[@"upstreams"] isKindOfClass:[NSArray class]] ? result[@"upstreams"] : @[];
    NSMutableString *html = [NSMutableString stringWithString:@"<table class=\"table\"><thead><tr><th>Hostname</th><th>Status</th><th>Seq</th><th>Last Connected</th></tr></thead><tbody>"];
    for (NSDictionary *upstream in upstreams) {
        NSString *hostname = UIEscaped(upstream[@"hostname"] ?: @"");
        NSString *status = UIEscaped(upstream[@"status"] ?: @"");
        NSString *seq = UIEscaped([upstream[@"seq"] stringValue] ?: @"0");
        NSString *lastConnected = UIEscaped(upstream[@"lastConnected"] ?: @"");
        NSString *statusBadge = [status isEqualToString:@"connected"] ? @"badge badge-success" : @"badge badge-secondary";
        [html appendFormat:@"<tr><td class=\"text-mono text-xs\">%@</td><td><span class=\"%@\">%@</span></td><td>%@</td><td class=\"text-xs\">%@</td></tr>", hostname, statusBadge, status, seq, lastConnected];
    }
    if (upstreams.count == 0) {
        [html appendString:@"<tr><td colspan=\"4\" class=\"text-center text-secondary p-lg\">No upstreams found.</td></tr>"];
    }
    [html appendString:@"</tbody></table>"];
    return html;
}

- (NSString *)renderPLCDIDPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSMutableString *html = [NSMutableString stringWithString:@"<div class=\"detail-grid\">"];
    NSArray *fields = @[@"did", @"handle", @"service", @"rotationKeys", @"alsoKnownAs", @"createdAt"];
    for (NSString *key in fields) {
        id val = result[key];
        if (!val) continue;
        if ([val isKindOfClass:[NSArray class]]) {
            NSString *joined = [((NSArray *)val) componentsJoinedByString:@", "];
            [html appendFormat:@"<div class=\"detail-field\"><span class=\"detail-label\">%@</span><span class=\"detail-value text-mono text-xs\">%@</span></div>", key, UIEscaped(joined)];
        } else {
            NSString *display = [val isKindOfClass:[NSString class]] ? UIEscaped(val) : UIEscaped([val description]);
            [html appendFormat:@"<div class=\"detail-field\"><span class=\"detail-label\">%@</span><span class=\"detail-value text-mono text-xs\">%@</span></div>", key, display];
        }
    }
    [html appendString:@"</div>"];
    return html;
}

- (NSString *)renderPLCLogPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSArray<NSDictionary *> *entries = [result[@"log"] isKindOfClass:[NSArray class]] ? result[@"log"] : @[];
    NSMutableString *html = [NSMutableString stringWithString:@"<table class=\"table\"><thead><tr><th>Seq</th><th>Type</th><th>Time</th><th>Detail</th></tr></thead><tbody>"];
    for (NSDictionary *entry in entries) {
        NSString *seq = UIEscaped([entry[@"seq"] stringValue] ?: @"");
        NSString *type = UIEscaped(entry[@"type"] ?: @"");
        NSString *time = UIEscaped(entry[@"createdAt"] ?: @"");
        NSString *detail = UIEscaped(entry[@"detail"] ?: @"");
        [html appendFormat:@"<tr><td>%@</td><td><span class=\"badge badge-secondary\">%@</span></td><td class=\"text-xs text-mono\">%@</td><td class=\"text-xs\">%@</td></tr>", seq, type, time, detail];
    }
    if (entries.count == 0) {
        [html appendString:@"<tr><td colspan=\"4\" class=\"text-center text-secondary p-lg\">No log entries.</td></tr>"];
    }
    [html appendString:@"</tbody></table>"];
    return html;
}

- (NSString *)renderDescribeRepoPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSMutableString *html = [NSMutableString stringWithString:@"<div class=\"detail-grid\">"];
    NSArray *fields = @[@"handle", @"did", @"didDoc", @"collections", @"handleIsCorrect"];
    for (NSString *key in fields) {
        id val = result[key];
        if (!val) continue;
        if ([val isKindOfClass:[NSArray class]]) {
            NSString *joined = [((NSArray *)val) componentsJoinedByString:@", "];
            [html appendFormat:@"<div class=\"detail-field\"><span class=\"detail-label\">%@</span><span class=\"detail-value text-mono text-xs\">%@</span></div>", key, UIEscaped(joined)];
        } else if ([val isKindOfClass:[NSDictionary class]]) {
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:val options:0 error:nil];
            NSString *jsonStr = jsonData ? [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding] : @"{}";
            [html appendFormat:@"<div class=\"detail-field full-width\"><span class=\"detail-label\">%@</span><pre class=\"detail-value text-xs text-mono\">%@</pre></div>", key, UIEscaped(jsonStr)];
        } else {
            NSString *display = [val isKindOfClass:[NSString class]] ? UIEscaped(val) : UIEscaped([val description]);
            [html appendFormat:@"<div class=\"detail-field\"><span class=\"detail-label\">%@</span><span class=\"detail-value\">%@</span></div>", key, display];
        }
    }
    [html appendString:@"</div>"];
    return html;
}

- (NSString *)renderListRecordsPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSArray<NSDictionary *> *records = [result[@"records"] isKindOfClass:[NSArray class]] ? result[@"records"] : @[];
    NSMutableString *html = [NSMutableString stringWithString:@"<table class=\"table\"><thead><tr><th>URI</th><th>CID</th><th>Collection</th><th>Rkey</th></tr></thead><tbody>"];
    for (NSDictionary *record in records) {
        NSString *uri = UIEscaped(record[@"uri"] ?: @"");
        NSString *cid = UIEscaped(record[@"cid"] ?: @"");
        NSString *collection = UIEscaped(record[@"collection"] ?: @"");
        NSString *rkey = UIEscaped(record[@"rkey"] ?: @"");
        [html appendFormat:@"<tr><td class=\"text-mono text-xs\">%@</td><td class=\"text-mono text-xs\">%@</td><td>%@</td><td class=\"text-mono text-xs\">%@</td></tr>", uri, cid, collection, rkey];
    }
    if (records.count == 0) {
        [html appendString:@"<tr><td colspan=\"4\" class=\"text-center text-secondary p-lg\">No records found.</td></tr>"];
    }
    [html appendString:@"</tbody></table>"];
    NSString *cursor = UIStringFromDict(result, @"cursor");
    if (cursor.length > 0) {
        [html appendFormat:@"<div class=\"d-flex justify-between mt-sm\"><button class=\"btn btn-secondary btn-sm\" hx-get=\"/admin/partials/list-records?cursor=%@\" hx-target=\"#records-list\">Load more</button></div>", UIEscaped(cursor)];
    }
    return html;
}

- (NSString *)renderGetRecordPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSMutableString *html = [NSMutableString stringWithString:@"<div class=\"detail-grid\">"];
    NSArray *fields = @[@"uri", @"cid", @"value"];
    for (NSString *key in fields) {
        id val = result[key];
        if (!val) continue;
        if ([val isKindOfClass:[NSDictionary class]] || [val isKindOfClass:[NSArray class]]) {
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:val options:NSJSONWritingPrettyPrinted error:nil];
            NSString *jsonStr = jsonData ? [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding] : @"{}";
            [html appendFormat:@"<div class=\"detail-field full-width\"><span class=\"detail-label\">%@</span><pre class=\"detail-value text-xs text-mono\">%@</pre></div>", key, UIEscaped(jsonStr)];
        } else {
            NSString *display = [val isKindOfClass:[NSString class]] ? UIEscaped(val) : UIEscaped([val description]);
            [html appendFormat:@"<div class=\"detail-field\"><span class=\"detail-label\">%@</span><span class=\"detail-value\">%@</span></div>", key, display];
        }
    }
    [html appendString:@"</div>"];
    return html;
}

#pragma mark - Static Asset Serving

- (void)serveStaticAssetForPath:(NSString *)path response:(HttpResponse *)response {
    // Sanitize: only serve files from the assets directory, no path traversal
    NSString *filename = path;
    // Strip leading slashes
    while (filename.length > 0 && [filename hasPrefix:@"/"]) {
        filename = [filename substringFromIndex:1];
    }
    // Remove any path traversal attempts
    filename = [filename stringByReplacingOccurrencesOfString:@".." withString:@""];
    if (filename.length == 0) {
        response.statusCode = 403;
        [response setBodyString:@"Forbidden"];
        return;
    }

    NSString *assetsDir = self.configuration.assetsDirectory;
    if (!assetsDir) {
        // Fallback: try bundle path
        assetsDir = [[NSBundle mainBundle] resourcePath];
    }

    NSString *filePath = [assetsDir stringByAppendingPathComponent:filename];

    // Verify the resolved path is still within the assets directory
    NSString *resolvedPath = filePath.stringByStandardizingPath;
    NSString *resolvedBase = assetsDir.stringByStandardizingPath;
    if (![resolvedPath hasPrefix:resolvedBase]) {
        response.statusCode = 403;
        [response setBodyString:@"Forbidden"];
        return;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:filePath isDirectory:&isDir] || isDir) {
        response.statusCode = 404;
        [response setBodyString:@"Not Found"];
        return;
    }

    // Validate file size before loading into memory (10MB limit)
    NSError *attrError = nil;
    NSDictionary *attrs = [fm attributesOfItemAtPath:filePath error:&attrError];
    if (!attrs || attrs.fileSize > 10 * 1024 * 1024) {
        response.statusCode = 413;
        [response setBodyString:@"File Too Large"];
        return;
    }

    NSData *data = [NSData dataWithContentsOfFile:filePath];
    if (!data) {
        response.statusCode = 500;
        [response setBodyString:@"Internal Server Error"];
        return;
    }

    // Determine content type from extension
    NSString *extension = filePath.pathExtension.lowercaseString ?: @"";
    NSDictionary<NSString *, NSString *> *mimeTypes = @{
        @"css": @"text/css; charset=utf-8",
        @"js": @"application/javascript; charset=utf-8",
        @"png": @"image/png",
        @"jpg": @"image/jpeg",
        @"jpeg": @"image/jpeg",
        @"gif": @"image/gif",
        @"svg": @"image/svg+xml",
        @"ico": @"image/x-icon",
        @"woff": @"font/woff",
        @"woff2": @"font/woff2",
    };
    NSString *contentType = mimeTypes[extension] ?: @"application/octet-stream";

    response.statusCode = 200;
    response.contentType = contentType;
    [response setHeader:@"public, max-age=3600" forKey:@"Cache-Control"];
    [response setBodyData:data];
}

#pragma mark - Ozone Render Methods

- (NSString *)renderOzoneStatusesPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSArray *statuses = [result[@"subjectStatuses"] isKindOfClass:[NSArray class]] ? result[@"subjectStatuses"] : @[];
    NSMutableString *html = [NSMutableString stringWithString:@"<table class=\"table\"><thead><tr><th>DID</th><th>Status</th><th>Updated</th></tr></thead><tbody>"];
    for (NSDictionary *s in statuses) {
        [html appendFormat:@"<tr><td class=\"text-mono text-sm\">%@</td><td>%@</td><td class=\"text-sm\">%@</td></tr>",
            UIEscaped(s[@"did"] ?: @""), UIEscaped(s[@"reviewState"] ?: @""), UIEscaped(s[@"updatedAt"] ?: @"")];
    }
    [html appendString:@"</tbody></table>"];
    NSString *cursor = UIStringFromDict(result, @"cursor");
    if (cursor.length > 0) {
        [html appendFormat:@"<div class=\"mt-sm\"><button class=\"btn btn-secondary btn-sm\" hx-get=\"/admin/partials/ozone-statuses?cursor=%@\" hx-target=\"#ozone-statuses\">Load more</button></div>", UIEscaped(cursor)];
    }
    return html;
}

- (NSString *)renderOzoneEventsPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSArray *events = [result[@"events"] isKindOfClass:[NSArray class]] ? result[@"events"] : @[];
    NSMutableString *html = [NSMutableString stringWithString:@"<table class=\"table\"><thead><tr><th>Type</th><th>Subject</th><th>Created By</th><th>At</th></tr></thead><tbody>"];
    for (NSDictionary *e in events) {
        NSDictionary *subject = e[@"subject"];
        NSString *subjectStr = subject[@"did"] ?: subject[@"uri"] ?: @"";
        [html appendFormat:@"<tr><td>%@</td><td class=\"text-mono text-sm\">%@</td><td class=\"text-mono text-sm\">%@</td><td class=\"text-sm\">%@</td></tr>",
            UIEscaped(e[@"event"] ?: @""), UIEscaped(subjectStr), UIEscaped(e[@"createdBy"] ?: @""), UIEscaped(e[@"createdAt"] ?: @"")];
    }
    [html appendString:@"</tbody></table>"];
    NSString *cursor = UIStringFromDict(result, @"cursor");
    if (cursor.length > 0) {
        [html appendFormat:@"<div class=\"mt-sm\"><button class=\"btn btn-secondary btn-sm\" hx-get=\"/admin/partials/ozone-events?cursor=%@\" hx-target=\"#ozone-events\">Load more</button></div>", UIEscaped(cursor)];
    }
    return html;
}

- (NSString *)renderOzoneSubjectPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSMutableString *html = [NSMutableString stringWithString:@"<div class=\"detail-card\">"];
    [html appendFormat:@"<div class=\"detail-row\"><span class=\"detail-label\">DID</span><span class=\"text-mono text-sm\">%@</span></div>", UIEscaped(result[@"did"] ?: @"")];
    [html appendFormat:@"<div class=\"detail-row\"><span class=\"detail-label\">Review State</span><span>%@</span></div>", UIEscaped(result[@"reviewState"] ?: @"")];
    [html appendFormat:@"<div class=\"detail-row\"><span class=\"detail-label\">Updated</span><span>%@</span></div>", UIEscaped(result[@"updatedAt"] ?: @"")];
    [html appendString:@"</div>"];
    return html;
}

- (NSString *)renderOzoneTeamPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSArray *members = [result[@"members"] isKindOfClass:[NSArray class]] ? result[@"members"] : @[];
    NSMutableString *html = [NSMutableString stringWithString:@"<form class=\"form mb-lg\" onsubmit=\"addOzoneTeamMember();return false;\"><div class=\"form-group\"><label>DID:</label><input type=\"text\" id=\"add-member-did\" class=\"form-input\" placeholder=\"Enter DID\"></div><div class=\"form-group\"><label>Role:</label><select id=\"add-member-role\" class=\"form-input\"><option value=\"moderator\">Moderator</option><option value=\"admin\">Admin</option></select></div><button type=\"submit\" class=\"btn btn-primary btn-sm\">Add Member</button></form><table class=\"table\"><thead><tr><th>DID</th><th>Role</th><th>Actions</th></tr></thead><tbody>"];
    for (NSDictionary *m in members) {
        NSString *did = m[@"did"] ?: @"";
        [html appendFormat:@"<tr><td class=\"text-mono text-sm\">%@</td><td>%@</td>"
            "<td><button class=\"btn btn-destructive btn-sm\" onclick=\"removeTeamMember('%@')\">Remove</button></td></tr>",
            UIEscaped(did), UIEscaped(m[@"role"] ?: @""), UIEscaped(did)];
    }
    [html appendString:@"</tbody></table>"];
    return html;
}

- (NSString *)renderOzoneSetsPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSArray *sets = [result[@"sets"] isKindOfClass:[NSArray class]] ? result[@"sets"] : @[];
    NSMutableString *html = [NSMutableString stringWithString:@"<form class=\"form mb-lg\" onsubmit=\"upsertOzoneSet();return false;\"><div class=\"form-group\"><label>Set Name:</label><input type=\"text\" id=\"create-set-name\" class=\"form-input\" placeholder=\"Enter set name\"></div><div class=\"form-group\"><label>Description:</label><input type=\"text\" id=\"create-set-desc\" class=\"form-input\" placeholder=\"Enter description\"></div><button type=\"submit\" class=\"btn btn-primary btn-sm\">Create Set</button></form><table class=\"table\"><thead><tr><th>Name</th><th>Description</th><th>Size</th><th>Actions</th></tr></thead><tbody>"];
    for (NSDictionary *s in sets) {
        NSString *name = s[@"name"] ?: @"";
        [html appendFormat:@"<tr><td>%@</td><td>%@</td><td>%@</td>"
            "<td><button class=\"btn btn-destructive btn-sm\" onclick=\"deleteOzoneSet('%@')\">Delete</button></td></tr>",
            UIEscaped(name), UIEscaped(s[@"description"] ?: @""), UIEscaped(s[@"size"] ?: @""), UIEscaped(name)];
    }
    [html appendString:@"</tbody></table>"];
    return html;
}

- (NSString *)renderOzoneTemplatesPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSArray *templates = [result[@"templates"] isKindOfClass:[NSArray class]] ? result[@"templates"] : @[];
    NSMutableString *html = [NSMutableString stringWithString:@"<form class=\"form mb-lg\" onsubmit=\"createOzoneTemplate();return false;\"><div class=\"form-group\"><label>Template Name:</label><input type=\"text\" id=\"create-template-name\" class=\"form-input\" placeholder=\"Enter template name\"></div><div class=\"form-group\"><label>Subject:</label><input type=\"text\" id=\"create-template-subject\" class=\"form-input\" placeholder=\"Enter subject\"></div><div class=\"form-group\"><label>Content (Markdown):</label><textarea id=\"create-template-content\" class=\"form-input\" placeholder=\"Enter template content\"></textarea></div><button type=\"submit\" class=\"btn btn-primary btn-sm\">Create Template</button></form><table class=\"table\"><thead><tr><th>Name</th><th>Subject</th><th>Content</th><th>Actions</th></tr></thead><tbody>"];
    for (NSDictionary *t in templates) {
        NSString *name = t[@"name"] ?: @"";
        NSString *content = t[@"contentMarkdown"] ?: @"";
        if (content.length > 80) content = [[content substringToIndex:80] stringByAppendingString:@"..."];
        [html appendFormat:@"<tr><td>%@</td><td>%@</td><td class=\"text-sm\">%@</td>"
            "<td><button class=\"btn btn-destructive btn-sm\" onclick=\"deleteOzoneTemplate('%@')\">Delete</button></td></tr>",
            UIEscaped(name), UIEscaped(t[@"subject"] ?: @""), UIEscaped(content), UIEscaped(name)];
    }
    [html appendString:@"</tbody></table>"];
    return html;
}

- (NSString *)renderOzoneConfigPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSError *jsonError = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:&jsonError];
    NSString *jsonStr = jsonError ? @"" : [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    NSMutableString *html = [NSMutableString stringWithString:@"<div id=\"ozone-config-result\"></div><form class=\"form mb-lg\" onsubmit=\"updateOzoneConfig();return false;\"><div class=\"form-group\"><label>Config (JSON):</label><textarea id=\"config-json\" class=\"form-input\" placeholder=\"Enter config as JSON\">"];
    [html appendString:UIEscaped(jsonStr)];
    [html appendString:@"</textarea></div><button type=\"submit\" class=\"btn btn-primary btn-sm\">Update Config</button></form><div class=\"detail-card\">"];
    [result enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
        [html appendFormat:@"<div class=\"detail-row\"><span class=\"detail-label\">%@</span><span class=\"text-sm\">%@</span></div>",
            UIEscaped(key), UIEscaped([value description])];
    }];
    [html appendString:@"</div>"];
    return html;
}

#pragma mark - Security Render Methods

- (NSString *)renderSessionsPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSArray *sessions = [result[@"sessions"] isKindOfClass:[NSArray class]] ? result[@"sessions"] : @[];
    NSMutableString *html = [NSMutableString stringWithString:@"<table class=\"table\"><thead><tr><th>ID</th><th>Device</th><th>Created</th><th>Actions</th></tr></thead><tbody>"];
    for (NSDictionary *s in sessions) {
        NSString *sessionID = s[@"id"] ?: @"";
        NSString *did = s[@"did"] ?: @"";
        [html appendFormat:@"<tr><td class=\"text-mono text-sm\">%@</td><td>%@</td><td class=\"text-sm\">%@</td>"
            "<td><button class=\"btn btn-destructive btn-sm\" onclick=\"revokeSession('%@','%@')\">Revoke</button></td></tr>",
            UIEscaped(sessionID), UIEscaped(s[@"deviceInfo"] ?: @""), UIEscaped(s[@"createdAt"] ?: @""), UIEscaped(did), UIEscaped(sessionID)];
    }
    [html appendString:@"</tbody></table>"];
    return html;
}

- (NSString *)renderAppPasswordsPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSArray *passwords = [result[@"passwords"] isKindOfClass:[NSArray class]] ? result[@"passwords"] : @[];
    NSMutableString *html = [NSMutableString stringWithString:@"<div id=\"app-passwords-result\"></div><form class=\"form mb-lg\" onsubmit=\"createAppPassword();return false;\"><div class=\"form-group\"><label>DID:</label><input type=\"text\" id=\"create-pwd-did\" class=\"form-input\" placeholder=\"Enter DID\"></div><div class=\"form-group\"><label>Password Name:</label><input type=\"text\" id=\"create-pwd-name\" class=\"form-input\" placeholder=\"Enter password name\"></div><button type=\"submit\" class=\"btn btn-primary btn-sm\">Create</button></form><table class=\"table\"><thead><tr><th>Name</th><th>Created</th><th>Actions</th></tr></thead><tbody>"];
    for (NSDictionary *p in passwords) {
        NSString *name = p[@"name"] ?: @"";
        NSString *did = p[@"did"] ?: @"";
        [html appendFormat:@"<tr><td>%@</td><td class=\"text-sm\">%@</td>"
            "<td><button class=\"btn btn-destructive btn-sm\" onclick=\"deleteAppPassword('%@','%@')\">Delete</button></td></tr>",
            UIEscaped(name), UIEscaped(p[@"createdAt"] ?: @""), UIEscaped(did), UIEscaped(name)];
    }
    [html appendString:@"</tbody></table>"];
    return html;
}

#pragma mark - Chat Render Methods

- (NSString *)renderChatConvosPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSArray<NSDictionary *> *convos = [result[@"convos"] isKindOfClass:[NSArray class]] ? result[@"convos"] : @[];
    NSMutableString *html = [NSMutableString stringWithString:@"<table class=\"table\"><thead><tr><th>Conversation ID</th><th>Mode</th><th>Members</th><th>Last Message</th><th>Actions</th></tr></thead><tbody>"];
    for (NSDictionary *convo in convos) {
        NSString *convoID = UISafe(convo[@"id"], @"");

        // Mode column: show lock icon for E2EE
        NSString *mode = UISafe(convo[@"mode"], @"plaintext");
        NSString *modeDisplay = [mode isEqualToString:@"e2ee"]
            ? @"<span title=\"End-to-end encrypted\">&#128274; E2EE</span>"
            : @"<span class=\"text-secondary\">plaintext</span>";

        // Count members from the members array if memberCount is absent
        NSString *memberCount;
        if (convo[@"memberCount"] && [convo[@"memberCount"] respondsToSelector:@selector(stringValue)]) {
            memberCount = [convo[@"memberCount"] stringValue];
        } else {
            NSArray *members = [convo[@"members"] isKindOfClass:[NSArray class]] ? convo[@"members"] : nil;
            memberCount = members ? [NSString stringWithFormat:@"%lu", (unsigned long)members.count] : @"0";
        }
        id lastMsgObj = convo[@"lastMessage"];
        NSString *lastMsg = @"(none)";
        if ([lastMsgObj isKindOfClass:[NSDictionary class]]) {
            // Check if last message is encrypted
            if ([((NSDictionary *)lastMsgObj)[@"mode"] isEqualToString:@"e2ee"] ||
                ((NSDictionary *)lastMsgObj)[@"ciphertext"] != nil) {
                lastMsg = @"<em class=\"text-secondary\">&#128274; encrypted</em>";
            } else {
                lastMsg = UISafe(((NSDictionary *)lastMsgObj)[@"text"], @"(none)");
                if (lastMsg.length > 50) lastMsg = [[lastMsg substringToIndex:50] stringByAppendingString:@"..."];
            }
        } else if ([lastMsgObj isKindOfClass:[NSString class]]) {
            lastMsg = lastMsgObj;
            if (lastMsg.length > 50) lastMsg = [[lastMsg substringToIndex:50] stringByAppendingString:@"..."];
        }
        [html appendFormat:@"<tr><td class=\"text-mono text-sm\">%@</td><td>%@</td><td>%@</td><td class=\"text-sm\">%@</td><td><button class=\"btn btn-secondary btn-sm\" onclick=\"lockChatConvo('%@')\">Lock</button></td></tr>",
            UIEscaped(convoID), modeDisplay, UIEscaped(memberCount), lastMsg, UIEscaped(convoID)];
    }
    if (convos.count == 0) {
        [html appendString:@"<tr><td colspan=\"5\" class=\"text-center text-secondary p-lg\">No conversations found.</td></tr>"];
    }
    [html appendString:@"</tbody></table>"];
    NSString *cursor = UIStringFromDict(result, @"cursor");
    if (cursor.length > 0) {
        [html appendFormat:@"<div class=\"d-flex justify-between mt-sm\"><button class=\"btn btn-secondary btn-sm\" hx-get=\"/admin/partials/chat-convos?cursor=%@\" hx-target=\"#chat-convos\">Load more</button></div>", UIEscaped(cursor)];
    }
    return html;
}

- (NSString *)renderChatMessagesPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSArray<NSDictionary *> *messages = [result[@"messages"] isKindOfClass:[NSArray class]] ? result[@"messages"] : @[];
    NSMutableString *html = [NSMutableString stringWithString:@"<div class=\"chat-messages\">"];
    for (NSDictionary *msg in messages) {
        // sender may be a dict with "did" key, or a bare string "senderDid"
        NSString *sender;
        id senderObj = msg[@"sender"];
        if ([senderObj isKindOfClass:[NSDictionary class]]) {
            sender = UISafe(((NSDictionary *)senderObj)[@"did"], @"unknown");
        } else if ([senderObj isKindOfClass:[NSString class]]) {
            sender = senderObj;
        } else {
            sender = UISafe(msg[@"senderDid"], @"unknown");
        }
        // Shorten DID display: show last segment after colon
        if ([sender hasPrefix:@"did:plc:"] && sender.length > 20) {
            sender = [NSString stringWithFormat:@"did:plc:…%@", [sender substringFromIndex:sender.length - 8]];
        }

        // Check if this is an E2EE message (mode=e2ee or ciphertext present)
        NSString *mode = msg[@"mode"] ?: @"plaintext";
        BOOL isEncrypted = [mode isEqualToString:@"e2ee"] || msg[@"ciphertext"] != nil;

        NSString *text;
        NSString *lockIcon = @"";
        if (isEncrypted) {
            // E2EE message: show lock icon and placeholder
            lockIcon = @"<span class=\"text-secondary\" title=\"End-to-end encrypted\">&#128274;</span> ";
            text = @"<em class=\"text-secondary\">End-to-end encrypted message</em>";
        } else {
            text = UIEscaped(UISafe(msg[@"text"], @""));
        }

        NSString *createdAt = UISafe(msg[@"createdAt"] ?: msg[@"sentAt"], @"");
        [html appendFormat:@"<div class=\"message\"><div class=\"message-header\"><span class=\"message-sender\">%@</span><span class=\"message-time text-xs text-secondary\">%@</span></div><div class=\"message-body\">%@%@</div></div>",
            UIEscaped(sender), UIEscaped(createdAt), lockIcon, text];
    }
    if (messages.count == 0) {
        [html appendString:@"<div class=\"text-center text-secondary p-lg\">No messages found.</div>"];
    }
    [html appendString:@"</div>"];
    return html;
}

#pragma mark - Render Methods

- (NSString *)renderConnectionsPartial {
    NSMutableString *html = [NSMutableString stringWithString:@"<form class=\"form\" onsubmit=\"saveConnections();return false;\">"];
    
    NSDictionary *fields = @{
        @"pdsURL": UISafe([self.configuration.pdsBaseURL absoluteString], @""),
        @"pdsToken": UISafe(self.configuration.pdsAdminToken, @""),
        @"appViewURL": UISafe([self.configuration.appViewBaseURL absoluteString], @""),
        @"appViewToken": UISafe(self.configuration.appViewAdminToken, @""),
        @"relayURL": UISafe([self.configuration.relayBaseURL absoluteString], @""),
        @"relayToken": UISafe(self.configuration.relayAdminToken, @""),
        @"plcURL": UISafe([self.configuration.plcBaseURL absoluteString], @""),
        @"plcToken": UISafe(self.configuration.plcAdminToken, @""),
        @"chatURL": UISafe([self.configuration.chatBaseURL absoluteString], @""),
        @"chatToken": UISafe(self.configuration.chatAdminToken, @""),
        @"videoURL": UISafe([self.configuration.videoBaseURL absoluteString], @""),
        @"videoToken": UISafe(self.configuration.videoAdminToken, @"")
    };
    
    [html appendString:@"<div class=\"grid-2\">"];
    
    NSArray<NSDictionary *> *order = @[
        @{@"id": @"pds", @"key": @"pds", @"label": @"PDS"},
        @{@"id": @"appview", @"key": @"appView", @"label": @"APPVIEW"},
        @{@"id": @"relay", @"key": @"relay", @"label": @"RELAY"},
        @{@"id": @"plc", @"key": @"plc", @"label": @"PLC"},
        @{@"id": @"chat", @"key": @"chat", @"label": @"CHAT"},
        @{@"id": @"video", @"key": @"video", @"label": @"VIDEO"}
    ];
    for (NSDictionary *entry in order) {
        NSString *inputID = entry[@"id"];
        NSString *key = entry[@"key"];
        NSString *urlKey = [key stringByAppendingString:@"URL"];
        NSString *tokenKey = [key stringByAppendingString:@"Token"];
        
        [html appendFormat:@"<div class=\"card\">"];
        [html appendFormat:@"<div class=\"card-title mb-md\">%@ Service</div>", entry[@"label"]];
        
        [html appendFormat:@"<div class=\"form-group\">"];
        [html appendFormat:@"<label class=\"form-label\">Base URL</label>"];
        [html appendFormat:@"<input id=\"conn-%@-url\" type=\"text\" name=\"%@\" value=\"%@\" class=\"form-input\"/>", inputID, urlKey, UIEscaped(fields[urlKey])];
        [html appendString:@"</div>"];
        
        [html appendFormat:@"<div class=\"form-group\">"];
        [html appendFormat:@"<label class=\"form-label\">Admin Token</label>"];
        [html appendFormat:@"<input id=\"conn-%@-token\" type=\"password\" name=\"%@\" value=\"%@\" class=\"form-input\"/>", inputID, tokenKey, UIEscaped(fields[tokenKey])];
        [html appendString:@"</div>"];

        [html appendFormat:@"<div class=\"d-flex align-center gap-sm\"><button type=\"button\" class=\"btn btn-secondary btn-sm\" onclick=\"testConnection('%@')\">Test</button><span id=\"conn-%@-test-result\" class=\"text-sm text-secondary\"></span></div>", inputID, inputID];
        
        [html appendString:@"</div>"];
    }
    
    [html appendString:@"</div>"];
    [html appendString:@"<div id=\"connections-save-result\" class=\"mt-md\"></div>"];
    [html appendString:@"<div class=\"mt-lg d-flex justify-end\">"];
    [html appendString:@"<button type=\"submit\" class=\"btn btn-primary\">Save Cluster Configuration</button>"];
    [html appendString:@"</div></form>"];
    
    return html;
}

- (NSString *)renderOverviewPartial:(NSDictionary *)result {
    NSArray *services = [result[@"services"] isKindOfClass:[NSArray class]] ? result[@"services"] : @[];
    NSMutableString *html = [NSMutableString stringWithString:@"<div class=\"cluster-grid\">"];
    
    for (NSDictionary *svc in services) {
        NSString *name = UISafe(svc[@"name"], @"unknown");
        NSString *status = UISafe(svc[@"status"], @"unknown");
        NSString *url = UISafe(svc[@"url"], @"-");
        
        NSString *statusClass = @"status-unknown";
        if ([status isEqualToString:@"online"]) statusClass = @"status-online";
        else if ([status isEqualToString:@"offline"]) statusClass = @"status-offline";
        else if ([status isEqualToString:@"error"]) statusClass = @"status-error";
        
        [html appendFormat:@"<div class=\"service-card %@\">", statusClass];
        [html appendFormat:@"<div class=\"service-header\">"];
        [html appendFormat:@"<span class=\"service-name\">%@</span>", [name uppercaseString]];
        [html appendFormat:@"<span class=\"status-dot\"></span>"];
        [html appendString:@"</div>"];
        
        [html appendFormat:@"<div class=\"service-url\">%@</div>", UIEscaped(url)];
        
        if (svc[@"version"]) {
            [html appendFormat:@"<div class=\"service-meta\">Version: %@</div>", UIEscaped(svc[@"version"])];
        }
        
        if (svc[@"latency_ms"]) {
            [html appendFormat:@"<div class=\"service-meta\">Latency: %@ms</div>", svc[@"latency_ms"]];
        }
        
        if (svc[@"error"]) {
            [html appendFormat:@"<div class=\"text-xs text-destructive mt-xs\">%@</div>", UIEscaped(svc[@"error"])];
        }
        
        [html appendString:@"</div>"];
    }
    
    [html appendString:@"</div>"];
    
    if (result[@"generatedAt"]) {
        [html appendFormat:@"<div class=\"text-xs text-secondary mt-lg\">Last updated: %@</div>", UIEscaped(result[@"generatedAt"])];
    }
    
    return html;
}

- (NSString *)renderMSTAccountsPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSArray *accounts = [result[@"accounts"] isKindOfClass:[NSArray class]] ? result[@"accounts"] : @[];
    NSMutableString *html = [NSMutableString stringWithString:@"<table class=\"table\"><thead><tr><th>DID</th><th>Handle</th></tr></thead><tbody>"];
    for (NSDictionary *a in accounts) {
        [html appendFormat:@"<tr><td class=\"text-mono text-sm\">%@</td><td>%@</td></tr>",
            UIEscaped(a[@"did"] ?: @""), UIEscaped(a[@"handle"] ?: @"")];
    }
    [html appendString:@"</tbody></table>"];
    return html;
}

- (NSString *)renderMSTTreePartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSArray *nodes = [result[@"nodes"] isKindOfClass:[NSArray class]] ? result[@"nodes"] : @[];
    NSString *rootCID = result[@"rootCID"] ?: @"";
    NSNumber *nodeCount = result[@"nodeCount"] ?: @(0);
    NSNumber *entryCount = result[@"entryCount"] ?: @(0);
    NSNumber *maxDepth = result[@"maxDepth"] ?: @(0);

    if (nodes.count == 0 && rootCID.length == 0) {
        return @"<div class=\"alert alert-info\">No tree data available.</div>";
    }

    NSMutableString *html = [NSMutableString stringWithString:@"<div class=\"detail-card\">"];
    [html appendFormat:@"<div class=\"detail-row\"><span class=\"detail-label\">Root CID</span><span class=\"text-mono text-sm\">%@</span></div>", UIEscaped(rootCID)];
    [html appendFormat:@"<div class=\"detail-row\"><span class=\"detail-label\">Nodes</span><span>%@</span></div>", nodeCount];
    [html appendFormat:@"<div class=\"detail-row\"><span class=\"detail-label\">Entries</span><span>%@</span></div>", entryCount];
    [html appendFormat:@"<div class=\"detail-row\"><span class=\"detail-label\">Max Depth</span><span>%@</span></div>", maxDepth];
    [html appendString:@"</div>"];

    // Render node table
    if (nodes.count > 0) {
        [html appendString:@"<table class=\"table mt-sm\"><thead><tr><th>CID</th><th>Level</th><th>Kind</th><th>Entries</th></tr></thead><tbody>"];
        for (NSDictionary *node in nodes) {
            NSString *cid = node[@"cid"] ?: @"";
            NSNumber *level = node[@"level"] ?: @(0);
            NSString *kind = node[@"kind"] ?: @"";
            NSArray *entries = [node[@"entries"] isKindOfClass:[NSArray class]] ? node[@"entries"] : @[];
            [html appendFormat:@"<tr><td class=\"text-mono text-sm\">%@</td><td>%@</td><td>%@</td><td>%lu</td></tr>",
                UIEscaped(cid), level, UIEscaped(kind), (unsigned long)entries.count];
        }
        [html appendString:@"</tbody></table>"];

        // Render entries for each node
        for (NSDictionary *node in nodes) {
            NSArray *entries = [node[@"entries"] isKindOfClass:[NSArray class]] ? node[@"entries"] : @[];
            if (entries.count > 0) {
                NSString *cid = node[@"cid"] ?: @"";
                [html appendFormat:@"<h4 class=\"mt-md\">Node %@</h4>", UIEscaped([cid substringToIndex:MIN(16, cid.length)])];
                [html appendString:@"<table class=\"table\"><thead><tr><th>Key</th><th>Value</th></tr></thead><tbody>"];
                for (NSDictionary *e in entries) {
                    [html appendFormat:@"<tr><td class=\"text-mono text-sm\">%@</td><td class=\"text-mono text-sm\">%@</td></tr>",
                        UIEscaped(e[@"fullKey"] ?: @""), UIEscaped(e[@"value"] ?: @"")];
                }
                [html appendString:@"</tbody></table>"];
            }
        }
    }
    return html;
}

- (NSString *)renderMSTStatsPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSMutableString *html = [NSMutableString stringWithString:@"<div class=\"detail-card\">"];
    [result enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
        [html appendFormat:@"<div class=\"detail-row\"><span class=\"detail-label\">%@</span><span>%@</span></div>",
            UIEscaped(key), UIEscaped([value description])];
    }];
    [html appendString:@"</div>"];
    return html;
}

#pragma mark - Phase 1 Render Methods

- (NSString *)renderRelayHealthPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSString *status = result[@"status"] ?: @"unknown";
    NSString *statusBadge = [status isEqualToString:@"ok"] ? @"badge badge-success" :
                            [status isEqualToString:@"error"] ? @"badge badge-destructive" : @"badge badge-secondary";
    NSString *checkedAt = UISafe(result[@"checkedAt"], UISafe(result[@"lastChecked"], @""));
    NSMutableString *html = [NSMutableString stringWithString:@"<div class=\"detail-card\">"];
    [html appendFormat:@"<div class=\"detail-row\"><span class=\"detail-label\">Status</span><span class=\"%@\">%@</span></div>", statusBadge, UIEscaped(status)];
    if (checkedAt.length > 0) {
        [html appendFormat:@"<div class=\"detail-row\"><span class=\"detail-label\">Last Checked</span><span>%@</span></div>", UIEscaped(checkedAt)];
    }
    [html appendString:@"</div>"];
    return html;
}

- (NSString *)renderOzoneModerationReportsPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSMutableString *html = [NSMutableString stringWithString:@"<table class=\"table\"><thead><tr><th>Subject</th><th>Reason</th><th>Reported By</th><th>Resolved At</th></tr></thead><tbody>"];
    NSArray<NSDictionary *> *reports = [result[@"reports"] isKindOfClass:[NSArray class]] ? result[@"reports"] : @[];
    for (NSDictionary *report in reports) {
        NSString *subject = UIEscaped(report[@"subject"] ?: @"");
        NSString *reason = UIEscaped(report[@"reason"] ?: @"");
        NSString *reportedBy = UIEscaped(report[@"reportedBy"] ?: @"");
        NSString *resolvedAt = UIEscaped(report[@"resolvedAt"] ?: @"pending");
        [html appendFormat:@"<tr><td class=\"text-mono text-xs\">%@</td><td>%@</td><td class=\"text-mono text-xs\">%@</td><td>%@</td></tr>", subject, reason, reportedBy, resolvedAt];
    }
    if (reports.count == 0) {
        [html appendString:@"<tr><td colspan=\"4\" class=\"text-center text-secondary p-lg\">No moderation reports found.</td></tr>"];
    }
    [html appendString:@"</tbody></table>"];
    NSString *cursor = UIStringFromDict(result, @"cursor");
    if (cursor) {
        [html appendFormat:@"<div class=\"mt-sm\"><button class=\"btn btn-secondary btn-sm\" hx-get=\"/admin/partials/ozone-reports?cursor=%@\" hx-target=\"#ozone-reports\">Load More</button></div>", UIEscaped(cursor)];
    }
    return html;
}

#pragma mark - Phase 2 Render Methods

- (NSString *)renderPLCHealthPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSString *status = result[@"status"] ?: @"unknown";
    NSString *statusBadge = [status isEqualToString:@"ok"] ? @"badge badge-success" : @"badge badge-destructive";
    NSMutableString *html = [NSMutableString stringWithString:@"<div class=\"detail-card\">"];
    [html appendFormat:@"<div class=\"detail-row\"><span class=\"detail-label\">Status</span><span class=\"%@\">%@</span></div>", statusBadge, UIEscaped(status)];
    [html appendString:@"</div>"];
    return html;
}

- (NSString *)renderPLCMetricsPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSString *metricsText = result[@"text"] ?: @"";
    return [NSString stringWithFormat:@"<pre class=\"code-block\">%@</pre>", UIEscaped(metricsText)];
}

- (NSString *)renderPLCListPartial:(NSDictionary *)result cursor:(nullable NSString *)cursor {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSArray<NSString *> *dids = [result[@"dids"] isKindOfClass:[NSArray class]] ? result[@"dids"] : @[];
    NSMutableString *html = [NSMutableString stringWithString:@"<table class=\"table\"><thead><tr><th>DID</th></tr></thead><tbody>"];
    for (NSString *did in dids) {
        [html appendFormat:@"<tr><td class=\"text-mono text-xs\">%@</td></tr>", UIEscaped(did)];
    }
    if (dids.count == 0) {
        [html appendString:@"<tr><td class=\"text-center text-secondary p-lg\">No DIDs found.</td></tr>"];
    }
    [html appendString:@"</tbody></table>"];
    if (cursor && cursor.length > 0) {
        [html appendFormat:@"<div class=\"mt-sm\"><button class=\"btn btn-secondary btn-sm\" hx-get=\"/admin/partials/plc-list?cursor=%@\" hx-target=\"#plc-list\">Load More</button></div>", UIEscaped(cursor)];
    }
    return html;
}

#pragma mark - Phase 3 Render Methods

- (NSString *)renderOzoneScheduledPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSMutableString *html = [NSMutableString stringWithString:@"<div class=\"mb-lg\"><form class=\"form\" onsubmit=\"scheduleOzoneAction();return false;\"><div class=\"form-group\"><label>Subject DID(s):</label><input type=\"text\" id=\"schedule-subject-did\" class=\"form-input\" placeholder=\"did:plc:...\"/></div><div class=\"form-group\"><label>Action Type:</label><select id=\"schedule-action-type\" class=\"form-input\"><option value=\"takedown\">Takedown</option></select></div><button type=\"submit\" class=\"btn btn-primary btn-sm\">Schedule Action</button></form></div>"];

    [html appendString:@"<table class=\"table\"><thead><tr><th>Subject</th><th>Action</th><th>Status</th><th>Execute At</th><th>Actions</th></tr></thead><tbody>"];
    NSArray<NSDictionary *> *actions = [result[@"actions"] isKindOfClass:[NSArray class]] ? result[@"actions"] : @[];
    for (NSDictionary *action in actions) {
        NSString *subject = UIEscaped(action[@"subject"] ?: @"");
        NSString *actionType = UIEscaped(action[@"action"] ?: @"");
        NSString *status = UIEscaped(action[@"status"] ?: @"pending");
        NSString *executeAt = UIEscaped(action[@"executeAt"] ?: @"");
        [html appendFormat:@"<tr><td class=\"text-mono text-xs\">%@</td><td>%@</td><td><span class=\"badge\">%@</span></td><td>%@</td><td>", subject, actionType, status, executeAt];
        [html appendFormat:@"<button class=\"btn btn-sm btn-destructive\" onclick=\"cancelScheduledAction('%@')\">Cancel</button>", UIEscaped(subject)];
        [html appendString:@"</td></tr>"];
    }
    if (actions.count == 0) {
        [html appendString:@"<tr><td colspan=\"5\" class=\"text-center text-secondary p-lg\">No scheduled actions.</td></tr>"];
    }
    [html appendString:@"</tbody></table>"];
    NSString *cursor = UIStringFromDict(result, @"cursor");
    if (cursor && cursor.length > 0) {
        [html appendFormat:@"<div class=\"mt-sm\"><button class=\"btn btn-secondary btn-sm\" hx-get=\"/admin/partials/ozone-scheduled?cursor=%@\" hx-target=\"#ozone-scheduled\">Load More</button></div>", UIEscaped(cursor)];
    }
    return html;
}

- (NSString *)renderOzoneVerificationPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSMutableString *html = [NSMutableString stringWithString:@"<div class=\"mb-lg\"><form class=\"form\" onsubmit=\"grantOzoneVerification();return false;\"><div class=\"form-group\"><label>DID:</label><input type=\"text\" id=\"grant-verification-did\" class=\"form-input\" placeholder=\"did:plc:...\"/></div><div class=\"form-group\"><label>Display Name:</label><input type=\"text\" id=\"grant-verification-name\" class=\"form-input\" placeholder=\"Account display name\"/></div><button type=\"submit\" class=\"btn btn-primary btn-sm\">Grant Verification</button></form></div>"];

    [html appendString:@"<table class=\"table\"><thead><tr><th>DID</th><th>Display Name</th><th>Issuer</th><th>Created</th><th>Actions</th></tr></thead><tbody>"];
    NSArray<NSDictionary *> *verifications = [result[@"verifications"] isKindOfClass:[NSArray class]] ? result[@"verifications"] : @[];
    for (NSDictionary *verification in verifications) {
        NSString *did = UIEscaped(verification[@"did"] ?: @"");
        NSString *displayName = UIEscaped(verification[@"displayName"] ?: @"");
        NSString *issuer = UIEscaped(verification[@"issuer"] ?: @"");
        NSString *createdAt = UIEscaped(verification[@"createdAt"] ?: @"");
        [html appendFormat:@"<tr><td class=\"text-mono text-xs\">%@</td><td>%@</td><td class=\"text-xs\">%@</td><td class=\"text-xs\">%@</td><td>", did, displayName, issuer, createdAt];
        [html appendFormat:@"<button class=\"btn btn-sm btn-destructive\" onclick=\"revokeOzoneVerification('%@')\">Revoke</button>", UIEscaped(did)];
        [html appendString:@"</td></tr>"];
    }
    if (verifications.count == 0) {
        [html appendString:@"<tr><td colspan=\"5\" class=\"text-center text-secondary p-lg\">No verified accounts.</td></tr>"];
    }
    [html appendString:@"</tbody></table>"];
    return html;
}

- (NSString *)renderOzoneSafelinksPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSMutableString *html = [NSMutableString stringWithString:@"<div class=\"mb-lg\"><form class=\"form\" onsubmit=\"addSafelinkRule();return false;\"><div class=\"form-group\"><label>URL:</label><input type=\"text\" id=\"add-safelink-url\" class=\"form-input\" placeholder=\"https://example.com\"/></div><div class=\"form-group\"><label>Pattern Type:</label><select id=\"add-safelink-pattern\" class=\"form-input\"><option value=\"domain\">Domain</option><option value=\"url\">URL</option></select></div><div class=\"form-group\"><label>Action:</label><select id=\"add-safelink-action\" class=\"form-input\"><option value=\"block\">Block</option><option value=\"warn\">Warn</option><option value=\"whitelist\">Whitelist</option></select></div><div class=\"form-group\"><label>Reason:</label><select id=\"add-safelink-reason\" class=\"form-input\"><option value=\"csam\">CSAM</option><option value=\"spam\">Spam</option><option value=\"phishing\">Phishing</option><option value=\"none\">None</option></select></div><div class=\"form-group\"><label>Comment (optional):</label><input type=\"text\" id=\"add-safelink-comment\" class=\"form-input\"/></div><button type=\"submit\" class=\"btn btn-primary btn-sm\">Add Rule</button></form></div>"];

    [html appendString:@"<table class=\"table\"><thead><tr><th>URL</th><th>Pattern</th><th>Action</th><th>Reason</th><th>Actions</th></tr></thead><tbody>"];
    NSArray<NSDictionary *> *rules = [result[@"rules"] isKindOfClass:[NSArray class]] ? result[@"rules"] : @[];
    for (NSDictionary *rule in rules) {
        NSString *url = UIEscaped(rule[@"url"] ?: @"");
        NSString *pattern = UIEscaped(rule[@"pattern"] ?: @"domain");
        NSString *action = UIEscaped(rule[@"action"] ?: @"block");
        NSString *reason = UIEscaped(rule[@"reason"] ?: @"none");
        [html appendFormat:@"<tr><td class=\"text-mono text-xs\">%@</td><td>%@</td><td>%@</td><td>%@</td><td>", url, pattern, action, reason];
        [html appendFormat:@"<button class=\"btn btn-sm btn-destructive\" onclick=\"removeSafelinkRule('%@','%@')\">Remove</button>", UIEscaped(url), UIEscaped(pattern)];
        [html appendString:@"</td></tr>"];
    }
    if (rules.count == 0) {
        [html appendString:@"<tr><td colspan=\"5\" class=\"text-center text-secondary p-lg\">No safelink rules.</td></tr>"];
    }
    [html appendString:@"</tbody></table>"];
    return html;
}

#pragma mark - Phase 6 Render Methods

- (NSString *)renderOzoneSettingsPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSMutableString *html = [NSMutableString stringWithString:@"<table class=\"table\"><thead><tr><th>Key</th><th>Value</th></tr></thead><tbody>"];
    NSArray<NSDictionary *> *options = [result[@"options"] isKindOfClass:[NSArray class]] ? result[@"options"] : @[];
    for (NSDictionary *option in options) {
        NSString *key = UIEscaped(option[@"key"] ?: @"");
        NSString *value = UIEscaped(option[@"value"] ?: @"");
        [html appendFormat:@"<tr><td class=\"text-mono\">%@</td><td>%@</td></tr>", key, value];
    }
    if (options.count == 0) {
        [html appendString:@"<tr><td colspan=\"2\" class=\"text-center text-secondary p-lg\">No settings configured.</td></tr>"];
    }
    [html appendString:@"</tbody></table>"];
    return html;
}

- (NSString *)renderOzoneSignaturesPartial:(NSDictionary *)result {
    return @"<div class=\"mb-lg\"><form class=\"form\" onsubmit=\"findOzoneRelatedAccounts();return false;\"><div class=\"form-group\"><label>DID:</label><input type=\"text\" id=\"ozone-find-did\" class=\"form-input\" placeholder=\"did:plc:...\"/></div><button type=\"submit\" class=\"btn btn-primary btn-sm\">Find Related Accounts</button></form></div><div id=\"ozone-signature-results\"></div>";
}

- (NSString *)renderOzoneSignatureResultsPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSMutableString *html = [NSMutableString stringWithString:@"<div class=\"detail-card\">"];
    NSArray *related = [result[@"related"] isKindOfClass:[NSArray class]] ? result[@"related"] : @[];
    [html appendString:@"<div class=\"detail-row\"><span class=\"detail-label\">Related Accounts</span></div><ul>"];
    for (NSString *did in related) {
        [html appendFormat:@"<li class=\"text-mono text-xs\">%@</li>", UIEscaped(did)];
    }
    [html appendString:@"</ul></div>"];
    return html;
}

- (NSString *)renderOzoneHostingPartial:(NSDictionary *)result did:(nullable NSString *)did {
    NSMutableString *html = [NSMutableString stringWithString:@"<div class=\"mb-lg\"><form class=\"d-flex gap-sm\" onsubmit=\"loadHostingHistory();return false;\"><input type=\"text\" id=\"hosting-did-input\" class=\"form-input flex-1\" placeholder=\"did:plc:...\" value=\""];
    if (did && did.length > 0) {
        [html appendFormat:@"%@", UIEscaped(did)];
    }
    [html appendString:@"\"/><button type=\"submit\" class=\"btn btn-primary btn-sm\">Load History</button></form></div>"];

    if (result[@"error"]) {
        [html appendFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    } else {
        [html appendString:@"<table class=\"table\"><thead><tr><th>PDS</th><th>Status</th><th>Created At</th></tr></thead><tbody>"];
        NSArray<NSDictionary *> *entries = [result[@"entries"] isKindOfClass:[NSArray class]] ? result[@"entries"] : @[];
        for (NSDictionary *entry in entries) {
            NSString *pds = UIEscaped(entry[@"pds"] ?: @"");
            NSString *status = UIEscaped(entry[@"status"] ?: @"");
            NSString *createdAt = UIEscaped(entry[@"createdAt"] ?: @"");
            [html appendFormat:@"<tr><td class=\"text-mono text-xs\">%@</td><td>%@</td><td class=\"text-xs\">%@</td></tr>", pds, status, createdAt];
        }
        if (entries.count == 0) {
            [html appendString:@"<tr><td colspan=\"3\" class=\"text-center text-secondary p-lg\">No hosting history.</td></tr>"];
        }
        [html appendString:@"</tbody></table>"];
    }
    return html;
}

#pragma mark - Lab (AT Protocol OAuth2 Self-Service)

- (NSString *)labShellHTML {
    NSString *pdsBaseURL = [self.configuration.pdsBaseURL absoluteString];
    NSString *clientId = [NSString stringWithFormat:@"http://%@:%lu/lab/client-metadata.json",
                         self.configuration.host, (unsigned long)self.configuration.port];
    NSString *redirectUri = [NSString stringWithFormat:@"http://%@:%lu/lab/callback",
                            self.configuration.host, (unsigned long)self.configuration.port];

    return [NSString stringWithFormat:
    @"<!doctype html><html><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
    @"<title>Garazyk Lab - AT Protocol</title>"
    @"<link rel=\"stylesheet\" href=\"/css/system.css\">"
    @"<link rel=\"stylesheet\" href=\"/css/components.css\">"
    @"<style>"
    @".lab-shell { max-width: 800px; margin: 0 auto; padding: var(--space-lg); }"
    @".lab-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: var(--space-xl); padding-bottom: var(--space-lg); border-bottom: 1px solid var(--separator-color); }"
    @".lab-header h1 { margin: 0; }"
    @".lab-header a { color: var(--color-text-primary); text-decoration: none; font-size: var(--font-size-sm); }"
    @".lab-section { display: none; }"
    @".lab-section.active { display: block; }"
    @".login-form { margin-top: var(--space-lg); }"
    @".login-form .form-group { margin-bottom: var(--space-md); }"
    @".account-card { background: var(--color-bg-secondary); border: 1px solid var(--separator-color); border-radius: var(--radius-md); padding: var(--space-lg); margin-bottom: var(--space-lg); }"
    @".account-row { display: flex; justify-content: space-between; padding: var(--space-sm) 0; border-bottom: 1px solid var(--separator-color-secondary); }"
    @".account-row:last-child { border-bottom: none; }"
    @".account-label { font-weight: 500; color: var(--color-text-secondary); }"
    @".account-value { font-family: monospace; font-size: var(--font-size-sm); }"
    @".handle-update-form { margin-top: var(--space-lg); padding-top: var(--space-lg); border-top: 1px solid var(--separator-color); }"
    @".handle-update-form .form-group { margin-bottom: var(--space-md); }"
    @"</style>"
    @"</head><body class=\"lab-shell\">"
    @"<header class=\"lab-header\">"
    @"<h1>Garazyk Lab</h1>"
    @"<a href=\"/admin\">← Back to Admin</a>"
    @"</header>"
    @"<main>"
    @"<section class=\"lab-section active\" id=\"lab-login-section\">"
    @"<h2>Sign in with AT Protocol</h2>"
    @"<p class=\"text-secondary\">Enter your handle or DID to sign in to your account.</p>"
    @"<form class=\"login-form\" onsubmit=\"startOAuthFlow();return false;\">"
    @"<div class=\"form-group\">"
    @"<label for=\"lab-handle-input\">Handle or DID</label>"
    @"<input type=\"text\" id=\"lab-handle-input\" class=\"form-input\" placeholder=\"alice.example.com\" />"
    @"</div>"
    @"<button type=\"submit\" class=\"btn btn-primary\">Sign In with AT Protocol</button>"
    @"</form>"
    @"</section>"
    @"<section class=\"lab-section\" id=\"lab-account-section\">"
    @"<div class=\"account-card\">"
    @"<h2>Your Account</h2>"
    @"<div class=\"account-row\">"
    @"<span class=\"account-label\">DID</span>"
    @"<span class=\"account-value\" id=\"lab-did-display\">—</span>"
    @"</div>"
    @"<div class=\"account-row\">"
    @"<span class=\"account-label\">Handle</span>"
    @"<span class=\"account-value\" id=\"lab-handle-display\">—</span>"
    @"</div>"
    @"<div class=\"account-row\">"
    @"<span class=\"account-label\">Email</span>"
    @"<span class=\"account-value\" id=\"lab-email-display\">—</span>"
    @"</div>"
    @"</div>"
    @"<form class=\"handle-update-form\" onsubmit=\"updateHandleFlow();return false;\">"
    @"<h3>Update Handle</h3>"
    @"<p class=\"text-secondary text-sm\">Change your handle to a new one.</p>"
    @"<div class=\"form-group\">"
    @"<label for=\"lab-new-handle-input\">New Handle</label>"
    @"<input type=\"text\" id=\"lab-new-handle-input\" class=\"form-input\" placeholder=\"newhandle.com\" />"
    @"</div>"
    @"<button type=\"submit\" class=\"btn btn-primary btn-sm\">Update Handle</button>"
    @"<div id=\"lab-update-result\"></div>"
    @"</form>"
    @"<div style=\"margin-top:var(--space-xl);padding-top:var(--space-lg);border-top:1px solid var(--separator-color);\">"
    @"<button onclick=\"signOutOAuth()\" class=\"btn btn-secondary btn-sm\">Sign Out</button>"
    @"</div>"
    @"</section>"
    @"</main>"
    @"<script>"
    @"const LAB_CONFIG = { pdsUrl: '%@', clientId: '%@', redirectUri: '%@' };"
    @"</script>"
    @"<script src=\"/js/lab.js\"></script>"
    @"</body></html>",
    pdsBaseURL, clientId, redirectUri];
}

- (NSString *)labClientMetadataJSON {
    NSString *clientId = [NSString stringWithFormat:@"http://%@:%lu/lab/client-metadata.json",
                         self.configuration.host, (unsigned long)self.configuration.port];
    NSString *redirectUri = [NSString stringWithFormat:@"http://%@:%lu/lab/callback",
                            self.configuration.host, (unsigned long)self.configuration.port];

    NSDictionary *metadata = @{
        @"client_id": clientId,
        @"client_name": @"Garazyk Admin Lab",
        @"redirect_uris": @[redirectUri],
        @"scope": @"atproto transition:generic",
        @"grant_types": @[@"authorization_code", @"refresh_token"],
        @"response_types": @[@"code"],
        @"token_endpoint_auth_method": @"none",
        @"application_type": @"web",
        @"dpop_bound_access_tokens": @YES
    };

    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:metadata options:NSJSONWritingPrettyPrinted error:&error];
    if (error) {
        return @"{}";
    }
    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

#pragma mark - Video Render Methods

- (NSString *)renderVideoHealthPartial:(NSDictionary *)result {
    NSString *status = UISafe(result[@"status"], @"unknown");
    NSString *statusClass = @"status-unknown";
    if ([status isEqualToString:@"online"]) statusClass = @"status-online";
    else if ([status isEqualToString:@"offline"]) statusClass = @"status-offline";
    else if ([status isEqualToString:@"error"]) statusClass = @"status-error";

    NSMutableString *html = [NSMutableString stringWithString:@"<div class=\"cluster-grid\">"];
    [html appendFormat:@"<div class=\"service-card %@\">", statusClass];
    [html appendString:@"<div class=\"service-header\">"];
    [html appendFormat:@"<span class=\"service-name\">VIDEO</span>"];
    [html appendString:@"<span class=\"status-dot\"></span>"];
    [html appendString:@"</div>"];
    [html appendFormat:@"<div class=\"service-url\">%@</div>", UIEscaped([self.configuration.videoBaseURL absoluteString] ?: @"")];
    if (result[@"latency_ms"]) {
        [html appendFormat:@"<div class=\"service-meta\">Latency: %@ms</div>", result[@"latency_ms"]];
    }
    if (result[@"error"]) {
        [html appendFormat:@"<div class=\"text-xs text-destructive mt-xs\">%@</div>", UIEscaped(result[@"error"])];
    }
    [html appendString:@"</div></div>"];
    return html;
}

- (NSString *)renderVideoJobsPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSArray<NSDictionary *> *jobs = [result[@"jobs"] isKindOfClass:[NSArray class]] ? result[@"jobs"] : @[];
    NSMutableString *html = [NSMutableString stringWithString:@"<table class=\"table\"><thead><tr><th>Job ID</th><th>DID</th><th>State</th><th>Progress</th><th>MIME</th><th>Size</th><th>Retries</th><th>Created</th><th>Actions</th></tr></thead><tbody>"];

    for (NSDictionary *job in jobs) {
        NSString *jobId = UISafe(job[@"job_id"], @"");
        NSString *shortJobId = jobId.length > 8 ? [NSString stringWithFormat:@"%@...", [jobId substringToIndex:8]] : jobId;
        NSString *did = UISafe(job[@"did"], @"");
        NSString *shortDid = did;
        if ([did hasPrefix:@"did:plc:"] && did.length > 20) {
            shortDid = [NSString stringWithFormat:@"did:plc:...%@", [did substringFromIndex:did.length - 8]];
        }
        NSString *state = UISafe(job[@"state"], @"");
        NSString *stateBadge = @"badge-secondary";
        if ([state isEqualToString:@"PENDING"]) stateBadge = @"badge-warning";
        else if ([state isEqualToString:@"PROCESSING"] || [state isEqualToString:@"TRANSCODING"] || [state isEqualToString:@"GENERATING_THUMBNAIL"]) stateBadge = @"badge-info";
        else if ([state isEqualToString:@"COMPLETED"]) stateBadge = @"badge-success";
        else if ([state isEqualToString:@"FAILED"]) stateBadge = @"badge-destructive";

        NSNumber *progressNum = [job[@"progress"] isKindOfClass:[NSNumber class]] ? job[@"progress"] : @0;
        int progress = [progressNum intValue];
        NSString *progressBar = [NSString stringWithFormat:@"<div class=\"progress-bar\"><div class=\"progress-fill\" style=\"width:%d%%\"></div></div><span class=\"text-sm\">%d%%</span>", progress, progress];

        NSString *mimeType = UISafe(job[@"mime_type"], @"-");
        NSNumber *fileSizeNum = [job[@"file_size"] isKindOfClass:[NSNumber class]] ? job[@"file_size"] : nil;
        NSString *fileSize = @"-";
        if (fileSizeNum) {
            long long bytes = [fileSizeNum longLongValue];
            if (bytes >= 1048576) fileSize = [NSString stringWithFormat:@"%.1f MB", bytes / 1048576.0];
            else if (bytes >= 1024) fileSize = [NSString stringWithFormat:@"%.1f KB", bytes / 1024.0];
            else fileSize = [NSString stringWithFormat:@"%lld B", bytes];
        }
        NSNumber *retryCount = [job[@"retry_count"] isKindOfClass:[NSNumber class]] ? job[@"retry_count"] : @0;
        NSString *createdAt = UISafe(job[@"created_at"], @"-");

        NSString *actions = @"";
        if ([state isEqualToString:@"FAILED"]) {
            actions = [NSString stringWithFormat:@"<button class=\"btn btn-secondary btn-sm\" onclick=\"retryVideoJob('%@')\">Retry</button>", UIEscaped(jobId)];
        }

        [html appendFormat:@"<tr><td class=\"text-mono text-sm\" title=\"%@\">%@</td><td class=\"text-mono text-sm\" title=\"%@\">%@</td><td><span class=\"badge %@\">%@</span></td><td>%@</td><td class=\"text-sm\">%@</td><td class=\"text-sm\">%@</td><td>%@</td><td class=\"text-sm\">%@</td><td>%@</td></tr>",
            UIEscaped(jobId), UIEscaped(shortJobId),
            UIEscaped(did), UIEscaped(shortDid),
            stateBadge, UIEscaped(state),
            progressBar,
            UIEscaped(mimeType),
            UIEscaped(fileSize),
            retryCount,
            UIEscaped(createdAt),
            actions];
    }

    if (jobs.count == 0) {
        [html appendString:@"<tr><td colspan=\"9\" class=\"text-center text-secondary p-lg\">No video jobs found.</td></tr>"];
    }
    [html appendString:@"</tbody></table>"];

    NSString *cursor = UIStringFromDict(result, @"cursor");
    if (cursor.length > 0) {
        [html appendFormat:@"<div class=\"d-flex justify-between mt-sm\"><button class=\"btn btn-secondary btn-sm\" hx-get=\"/admin/partials/video-jobs?cursor=%@\" hx-target=\"#video-jobs\">Load more</button></div>", UIEscaped(cursor)];
    }
    return html;
}

- (NSString *)renderVideoJobDetailPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSDictionary *jobStatus = [result[@"jobStatus"] isKindOfClass:[NSDictionary class]] ? result[@"jobStatus"] : result;
    if (!jobStatus || ![jobStatus isKindOfClass:[NSDictionary class]]) {
        return @"<div class=\"text-secondary text-sm\">No job data returned.</div>";
    }

    NSMutableString *html = [NSMutableString stringWithString:@"<div class=\"detail-card\">"];
    [html appendString:@"<table class=\"table\"><thead><tr><th>Field</th><th>Value</th></tr></thead><tbody>"];

    NSArray *fields = @[
        @[@"Job ID", @"jobId"],
        @[@"DID", @"did"],
        @[@"State", @"state"],
        @[@"Progress", @"progress"],
        @[@"Error", @"error"],
        @[@"Message", @"message"],
    ];

    for (NSArray *field in fields) {
        NSString *label = field[0];
        NSString *key = field[1];
        id value = jobStatus[key];
        NSString *display = @"";
        if ([value isKindOfClass:[NSString class]]) {
            display = value;
        } else if ([value isKindOfClass:[NSNumber class]]) {
            display = [value stringValue];
        }
        if (display.length == 0) display = @"-";
        [html appendFormat:@"<tr><td class=\"text-sm\">%@</td><td class=\"text-mono text-sm\">%@</td></tr>", label, UIEscaped(display)];
    }

    // Blob info
    id blob = jobStatus[@"blob"];
    if ([blob isKindOfClass:[NSDictionary class]]) {
        NSDictionary *blobDict = blob;
        [html appendFormat:@"<tr><td class=\"text-sm\">Blob CID</td><td class=\"text-mono text-sm\">%@</td></tr>", UIEscaped(UISafe(blobDict[@"ref"][@"$link"], UISafe(blobDict[@"cid"], @"-")))];
        NSNumber *blobSize = [blobDict[@"size"] isKindOfClass:[NSNumber class]] ? blobDict[@"size"] : nil;
        if (blobSize) {
            long long bytes = [blobSize longLongValue];
            NSString *sizeStr = bytes >= 1048576 ? [NSString stringWithFormat:@"%.1f MB", bytes / 1048576.0] : [NSString stringWithFormat:@"%lld B", bytes];
            [html appendFormat:@"<tr><td class=\"text-sm\">Blob Size</td><td class=\"text-sm\">%@</td></tr>", UIEscaped(sizeStr)];
        }
    }

    [html appendString:@"</tbody></table>"];

    NSString *state = UISafe(jobStatus[@"state"], @"");
    if ([state isEqualToString:@"FAILED"]) {
        NSString *jobId = UISafe(jobStatus[@"jobId"], @"");
        [html appendFormat:@"<div class=\"mt-sm\"><button class=\"btn btn-secondary btn-sm\" onclick=\"retryVideoJob('%@')\">Retry Job</button></div>", UIEscaped(jobId)];
    }

    [html appendString:@"</div>"];
    return html;
}

- (NSString *)renderVideoQuotasPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }

    NSMutableString *html = [NSMutableString stringWithString:@"<div class=\"metric-row\">"];

    id canUpload = result[@"canUpload"];
    NSString *canUploadStr = @"-";
    if ([canUpload isKindOfClass:[NSNumber class]]) {
        canUploadStr = [canUpload boolValue] ? @"Yes" : @"No";
    } else if ([canUpload isKindOfClass:[NSString class]]) {
        canUploadStr = canUpload;
    }

    id remainingVideos = result[@"remainingDailyVideos"];
    NSString *remainingVideosStr = @"-";
    if ([remainingVideos isKindOfClass:[NSNumber class]]) {
        remainingVideosStr = [remainingVideos stringValue];
    }

    id remainingBytes = result[@"remainingDailyBytes"];
    NSString *remainingBytesStr = @"-";
    if ([remainingBytes isKindOfClass:[NSNumber class]]) {
        long long bytes = [remainingBytes longLongValue];
        if (bytes >= 1073741824) remainingBytesStr = [NSString stringWithFormat:@"%.1f GB", bytes / 1073741824.0];
        else if (bytes >= 1048576) remainingBytesStr = [NSString stringWithFormat:@"%.1f MB", bytes / 1048576.0];
        else remainingBytesStr = [NSString stringWithFormat:@"%lld B", bytes];
    }

    [html appendFormat:@"<div class=\"metric-card\"><div class=\"metric-value\">%@</div><div class=\"metric-label\">Can Upload</div></div>", UIEscaped(canUploadStr)];
    [html appendFormat:@"<div class=\"metric-card\"><div class=\"metric-value\">%@</div><div class=\"metric-label\">Remaining Daily Videos</div></div>", UIEscaped(remainingVideosStr)];
    [html appendFormat:@"<div class=\"metric-card\"><div class=\"metric-value\">%@</div><div class=\"metric-label\">Remaining Daily Bytes</div></div>", UIEscaped(remainingBytesStr)];

    [html appendString:@"</div>"];
    return html;
}

@end
