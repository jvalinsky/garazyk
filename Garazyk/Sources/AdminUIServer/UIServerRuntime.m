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

@interface UIServerRuntime ()

@property(nonatomic, strong) HttpServer *httpServer;
@property(nonatomic, strong, readwrite) UIServiceConfig *configuration;
@property(nonatomic, strong) UIAuthManager *authManager;
@property(nonatomic, strong) UIBackendClient *backendClient;
@property(nonatomic, assign, readwrite, getter=isRunning) BOOL running;

@end

@implementation UIServerRuntime

- (instancetype)initWithConfiguration:(UIServiceConfig *)configuration {
    self = [super init];
    if (self) {
        _configuration = configuration;
        _authManager = [[UIAuthManager alloc] initWithPassword:configuration.adminPassword ?: @""];
        _backendClient = [[UIBackendClient alloc] initWithConfiguration:configuration];
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
        // Omit Secure flag to allow HTTP localhost deployment; in production with TLS this should be added
        NSString *cookie = [NSString stringWithFormat:@"ui_admin_token=%@; Path=/; Max-Age=28800; HttpOnly; SameSite=Strict", token];
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
        if (![weakSelf ensureAuthorized:request response:response]) {
            return;
        }
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf adminShellHTML]];
    }];

    [self.httpServer addRoute:@"GET" path:@"/admin/partials/overview" handler:^(HttpRequest *request, HttpResponse *response) {
        if (![weakSelf ensureAuthorized:request response:response]) {
            return;
        }
        NSDictionary *overview = [weakSelf.backendClient fetchServiceOverview];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderOverviewPartial:overview]];
    }];

    [self.httpServer addRoute:@"GET" path:@"/admin/partials/accounts" handler:^(HttpRequest *request, HttpResponse *response) {
        if (![weakSelf ensureAuthorized:request response:response]) {
            return;
        }
        NSString *query = [request queryParamForKey:@"q"] ?: @"";
        NSDictionary *result = [weakSelf.backendClient searchAccountsWithQuery:query];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderAccountsPartial:result]];
    }];

    [self.httpServer addRoute:@"GET" path:@"/admin/partials/invites" handler:^(HttpRequest *request, HttpResponse *response) {
        if (![weakSelf ensureAuthorized:request response:response]) {
            return;
        }
        NSDictionary *result = [weakSelf.backendClient fetchInviteCodes];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderInvitesPartial:result]];
    }];

    [self.httpServer addRoute:@"POST" path:@"/admin/actions/disable-invites" handler:^(HttpRequest *request, HttpResponse *response) {
        if (![weakSelf ensureAuthorized:request response:response]) {
            return;
        }
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
        if (![weakSelf ensureAuthorized:request response:response]) return;
        NSArray *dids = request.jsonBody[@"dids"];
        NSDictionary *result = [weakSelf.backendClient bulkTakedownAccounts:dids ?: @[]];
        response.statusCode = 200;
        response.contentType = @"application/json";
        [response setJsonBody:result];
    }];

    [self.httpServer addRoute:@"POST" path:@"/admin/actions/bulk-delete" handler:^(HttpRequest *request, HttpResponse *response) {
        if (![weakSelf ensureAuthorized:request response:response]) return;
        NSArray *dids = request.jsonBody[@"dids"];
        NSDictionary *result = [weakSelf.backendClient bulkDeleteAccounts:dids ?: @[]];
        response.statusCode = 200;
        response.contentType = @"application/json";
        [response setJsonBody:result];
    }];

    [self.httpServer addRoute:@"GET" path:@"/admin/partials/appview-metrics" handler:^(HttpRequest *request, HttpResponse *response) {
        if (![weakSelf ensureAuthorized:request response:response]) return;
        NSDictionary *result = [weakSelf.backendClient fetchAppViewMetrics];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderAppViewMetricsPartial:result]];
    }];

    [self.httpServer addRoute:@"GET" path:@"/admin/partials/appview-ingest" handler:^(HttpRequest *request, HttpResponse *response) {
        if (![weakSelf ensureAuthorized:request response:response]) return;
        NSDictionary *result = [weakSelf.backendClient fetchIngestHealth];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderIngestHealthPartial:result]];
    }];

    [self.httpServer addRoute:@"GET" path:@"/admin/partials/appview-queue" handler:^(HttpRequest *request, HttpResponse *response) {
        if (![weakSelf ensureAuthorized:request response:response]) return;
        NSString *status = [request queryParamForKey:@"status"];
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSDictionary *result = [weakSelf.backendClient fetchBackfillQueueWithStatus:status limit:25 cursor:cursor];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderBackfillQueuePartial:result]];
    }];

    [self.httpServer addRoute:@"POST" path:@"/admin/actions/appview-retry-repo" handler:^(HttpRequest *request, HttpResponse *response) {
        if (![weakSelf ensureAuthorized:request response:response]) return;
        NSString *did = request.jsonBody[@"did"] ?: [request queryParamForKey:@"did"];
        NSDictionary *result = [weakSelf.backendClient retryBackfillForDID:did ?: @""];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? result[@"message"] : @"Retry enqueued.";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert alert-success\">%@</div>", UIEscaped(msg)]];
    }];

    [self.httpServer addRoute:@"POST" path:@"/admin/actions/appview-cancel-repo" handler:^(HttpRequest *request, HttpResponse *response) {
        if (![weakSelf ensureAuthorized:request response:response]) return;
        NSString *did = request.jsonBody[@"did"] ?: [request queryParamForKey:@"did"];
        NSDictionary *result = [weakSelf.backendClient cancelBackfillForDID:did ?: @""];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? result[@"message"] : @"Cancel requested.";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert alert-success\">%@</div>", UIEscaped(msg)]];
    }];

    [self.httpServer addRoute:@"GET" path:@"/admin/partials/relay-metrics" handler:^(HttpRequest *request, HttpResponse *response) {
        if (![weakSelf ensureAuthorized:request response:response]) return;
        NSDictionary *result = [weakSelf.backendClient fetchRelayMetrics];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderRelayMetricsPartial:result]];
    }];

    // PDS: Account detail
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/account-detail" handler:^(HttpRequest *request, HttpResponse *response) {
        if (![weakSelf ensureAuthorized:request response:response]) return;
        NSString *did = [request queryParamForKey:@"did"] ?: @"";
        NSDictionary *result = [weakSelf.backendClient fetchAccountInfoForDID:did];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderAccountDetailPartial:result]];
    }];

    // PDS: Server stats
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/pds-stats" handler:^(HttpRequest *request, HttpResponse *response) {
        if (![weakSelf ensureAuthorized:request response:response]) return;
        NSDictionary *result = [weakSelf.backendClient fetchServerStats];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderServerStatsPartial:result]];
    }];

    // PDS: Audit log
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/audit-log" handler:^(HttpRequest *request, HttpResponse *response) {
        if (![weakSelf ensureAuthorized:request response:response]) return;
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSDictionary *result = [weakSelf.backendClient fetchAuditLogWithCursor:cursor limit:25];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderAuditLogPartial:result]];
    }];

    [self.httpServer addRoute:@"GET" path:@"/admin/partials/blobs" handler:^(HttpRequest *request, HttpResponse *response) {
        if (![weakSelf ensureAuthorized:request response:response]) return;
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSDictionary *result = [weakSelf.backendClient fetchBlobListWithLimit:25 cursor:cursor];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderBlobsPartial:result]];
    }];

    [self.httpServer addRoute:@"POST" path:@"/admin/actions/enable-invites" handler:^(HttpRequest *request, HttpResponse *response) {
        if (![weakSelf ensureAuthorized:request response:response]) return;
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
        if (![weakSelf ensureAuthorized:request response:response]) return;
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
        if (![weakSelf ensureAuthorized:request response:response]) return;
        NSDictionary *result = [weakSelf.backendClient fetchRelayUpstreams];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderRelayUpstreamsPartial:result]];
    }];

    // Relay: Health check
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/relay-health" handler:^(HttpRequest *request, HttpResponse *response) {
        if (![weakSelf ensureAuthorized:request response:response]) return;
        NSDictionary *result = [weakSelf.backendClient fetchRelayHealth];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderRelayHealthPartial:result]];
    }];

    // Relay: Request crawl action
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/request-crawl" handler:^(HttpRequest *request, HttpResponse *response) {
        if (![weakSelf ensureAuthorized:request response:response]) return;
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
        if (![weakSelf ensureAuthorized:request response:response]) return;
        NSString *did = [request queryParamForKey:@"did"] ?: @"";
        NSDictionary *result = [weakSelf.backendClient lookupDID:did];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderPLCDIDPartial:result]];
    }];

    // PLC: DID log
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/plc-log" handler:^(HttpRequest *request, HttpResponse *response) {
        if (![weakSelf ensureAuthorized:request response:response]) return;
        NSString *did = [request queryParamForKey:@"did"] ?: @"";
        NSDictionary *result = [weakSelf.backendClient fetchPLCLogForDID:did];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderPLCLogPartial:result]];
    }];

    // PLC: Health check
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/plc-health" handler:^(HttpRequest *request, HttpResponse *response) {
        if (![weakSelf ensureAuthorized:request response:response]) return;
        NSDictionary *result = [weakSelf.backendClient fetchPLCHealth];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderPLCHealthPartial:result]];
    }];

    // PLC: Metrics
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/plc-metrics" handler:^(HttpRequest *request, HttpResponse *response) {
        if (![weakSelf ensureAuthorized:request response:response]) return;
        NSDictionary *result = [weakSelf.backendClient fetchPLCMetrics];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderPLCMetricsPartial:result]];
    }];

    // PLC: List DIDs
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/plc-list" handler:^(HttpRequest *request, HttpResponse *response) {
        if (![weakSelf ensureAuthorized:request response:response]) return;
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSDictionary *result = [weakSelf.backendClient fetchPLCList];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderPLCListPartial:result cursor:cursor]];
    }];

    // PLC: Export action
    [self.httpServer addRoute:@"GET" path:@"/admin/actions/plc-export" handler:^(HttpRequest *request, HttpResponse *response) {
        if (![weakSelf ensureAuthorized:request response:response]) return;
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
        if (![weakSelf ensureAuthorized:request response:response]) return;
        NSString *did = [request queryParamForKey:@"did"] ?: @"";
        NSDictionary *result = [weakSelf.backendClient describeRepo:did];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderDescribeRepoPartial:result]];
    }];

    // Explorer: List records
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/list-records" handler:^(HttpRequest *request, HttpResponse *response) {
        if (![weakSelf ensureAuthorized:request response:response]) return;
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
        if (![weakSelf ensureAuthorized:request response:response]) return;
        NSString *did = [request queryParamForKey:@"did"] ?: @"";
        NSString *collection = [request queryParamForKey:@"collection"] ?: @"";
        NSString *rkey = [request queryParamForKey:@"rkey"] ?: @"";
        NSDictionary *result = [weakSelf.backendClient getRecordForDID:did collection:collection rkey:rkey];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderGetRecordPartial:result]];
    }];

    // Explorer: Create record
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/create-record" handler:^(HttpRequest *request, HttpResponse *response) {
        if (![weakSelf ensureAuthorized:request response:response]) return;
        NSString *did = request.jsonBody[@"did"] ?: @"";
        NSString *collection = request.jsonBody[@"collection"] ?: @"";
        NSDictionary *record = request.jsonBody[@"record"];
        NSString *rkey = request.jsonBody[@"rkey"];
        NSDictionary *result = [weakSelf.backendClient createRecordForDID:did collection:collection record:record ?: @{} rkey:rkey];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Record created.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];

    // Explorer: Delete record
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/delete-record" handler:^(HttpRequest *request, HttpResponse *response) {
        if (![weakSelf ensureAuthorized:request response:response]) return;
        NSString *did = request.jsonBody[@"did"] ?: @"";
        NSString *collection = request.jsonBody[@"collection"] ?: @"";
        NSString *rkey = request.jsonBody[@"rkey"] ?: @"";
        NSDictionary *result = [weakSelf.backendClient deleteRecordForDID:did collection:collection rkey:rkey];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Record deleted.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];

    // Ozone: Moderation statuses
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/ozone-statuses" handler:^(HttpRequest *request, HttpResponse *response) {
        if (![weakSelf ensureAuthorized:request response:response]) return;
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSDictionary *result = [weakSelf.backendClient fetchOzoneStatusesWithCursor:cursor limit:50];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderOzoneStatusesPartial:result]];
    }];

    // Ozone: Moderation events
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/ozone-events" handler:^(HttpRequest *request, HttpResponse *response) {
        if (![weakSelf ensureAuthorized:request response:response]) return;
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSDictionary *result = [weakSelf.backendClient fetchOzoneEventsWithCursor:cursor limit:50];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderOzoneEventsPartial:result]];
    }];

    // Ozone: Subject status
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/ozone-subject" handler:^(HttpRequest *request, HttpResponse *response) {
        if (![weakSelf ensureAuthorized:request response:response]) return;
        NSString *did = [request queryParamForKey:@"did"];
        NSDictionary *result = [weakSelf.backendClient fetchSubjectStatusForDID:did];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderOzoneSubjectPartial:result]];
    }];

    // Ozone: Moderation reports
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/ozone-reports" handler:^(HttpRequest *request, HttpResponse *response) {
        if (![weakSelf ensureAuthorized:request response:response]) return;
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSDictionary *result = [weakSelf.backendClient fetchModerationReportsWithCursor:cursor limit:50];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderOzoneModerationReportsPartial:result]];
    }];

    // Ozone: Scheduled actions
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/ozone-scheduled" handler:^(HttpRequest *request, HttpResponse *response) {
        if (![weakSelf ensureAuthorized:request response:response]) return;
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSDictionary *result = [weakSelf.backendClient fetchScheduledActionsWithStatuses:nil cursor:cursor limit:50];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderOzoneScheduledPartial:result]];
    }];

    // Ozone: Schedule action
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/ozone-schedule-action" handler:^(HttpRequest *request, HttpResponse *response) {
        if (![weakSelf ensureAuthorized:request response:response]) return;
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
        if (![weakSelf ensureAuthorized:request response:response]) return;
        NSArray *subjects = request.jsonBody[@"subjects"] ?: @[];
        NSDictionary *result = [weakSelf.backendClient cancelScheduledActionsForSubjects:subjects];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Scheduled actions cancelled.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];

    // Ozone: Team members
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/ozone-team" handler:^(HttpRequest *request, HttpResponse *response) {
        if (![weakSelf ensureAuthorized:request response:response]) return;
        NSDictionary *result = [weakSelf.backendClient fetchOzoneTeamMembers];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderOzoneTeamPartial:result]];
    }];

    // Ozone: Sets
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/ozone-sets" handler:^(HttpRequest *request, HttpResponse *response) {
        if (![weakSelf ensureAuthorized:request response:response]) return;
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSDictionary *result = [weakSelf.backendClient fetchOzoneSetsWithCursor:cursor limit:50];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderOzoneSetsPartial:result]];
    }];

    // Ozone: Templates
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/ozone-templates" handler:^(HttpRequest *request, HttpResponse *response) {
        if (![weakSelf ensureAuthorized:request response:response]) return;
        NSDictionary *result = [weakSelf.backendClient fetchOzoneTemplates];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderOzoneTemplatesPartial:result]];
    }];

    // Ozone: Config
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/ozone-config" handler:^(HttpRequest *request, HttpResponse *response) {
        if (![weakSelf ensureAuthorized:request response:response]) return;
        NSDictionary *result = [weakSelf.backendClient fetchOzoneConfig];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderOzoneConfigPartial:result]];
    }];

    // Ozone: Emit moderation event
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/emit-moderation-event" handler:^(HttpRequest *request, HttpResponse *response) {
        if (![weakSelf ensureAuthorized:request response:response]) return;
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
        if (![weakSelf ensureAuthorized:request response:response]) return;
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
        if (![weakSelf ensureAuthorized:request response:response]) return;
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
        if (![weakSelf ensureAuthorized:request response:response]) return;
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
        if (![weakSelf ensureAuthorized:request response:response]) return;
        NSString *did = [request queryParamForKey:@"did"];
        NSDictionary *result = [weakSelf.backendClient fetchActiveSessionsForDID:did];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderSessionsPartial:result]];
    }];

    // Security: App passwords
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/app-passwords" handler:^(HttpRequest *request, HttpResponse *response) {
        if (![weakSelf ensureAuthorized:request response:response]) return;
        NSString *did = [request queryParamForKey:@"did"];
        NSDictionary *result = [weakSelf.backendClient fetchAppPasswordsForDID:did];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderAppPasswordsPartial:result]];
    }];

    // Security: Revoke session
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/revoke-session" handler:^(HttpRequest *request, HttpResponse *response) {
        if (![weakSelf ensureAuthorized:request response:response]) return;
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
        if (![weakSelf ensureAuthorized:request response:response]) return;
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
        if (![weakSelf ensureAuthorized:request response:response]) return;
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
        if (![weakSelf ensureAuthorized:request response:response]) return;
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSDictionary *result = [weakSelf.backendClient fetchReportsWithCursor:cursor limit:25];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderPDSReportsPartial:result]];
    }];

    // PDS: Resolve report
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/resolve-pds-report" handler:^(HttpRequest *request, HttpResponse *response) {
        if (![weakSelf ensureAuthorized:request response:response]) return;
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
        if (![weakSelf ensureAuthorized:request response:response]) return;
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSDictionary *result = [weakSelf.backendClient fetchChatConvosWithLimit:25 cursor:cursor];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderChatConvosPartial:result]];
    }];

    // Chat: Get messages for conversation
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/chat-messages" handler:^(HttpRequest *request, HttpResponse *response) {
        if (![weakSelf ensureAuthorized:request response:response]) return;
        NSString *convoID = [request queryParamForKey:@"convoID"];
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSDictionary *result = [weakSelf.backendClient fetchChatMessagesForConvoID:convoID limit:50 cursor:cursor];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderChatMessagesPartial:result]];
    }];

    // Chat: Lock conversation
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/lock-chat-convo" handler:^(HttpRequest *request, HttpResponse *response) {
        if (![weakSelf ensureAuthorized:request response:response]) return;
        NSString *convoID = request.jsonBody[@"convoID"] ?: @"";
        NSDictionary *result = [weakSelf.backendClient lockChatConvo:convoID];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Conversation locked.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];

    // AppView: Rebuild backfill scope
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/appview-rebuild-scope" handler:^(HttpRequest *request, HttpResponse *response) {
        if (![weakSelf ensureAuthorized:request response:response]) return;
        NSDictionary *result = [weakSelf.backendClient rebuildBackfillScope];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Rebuilding backfill scope.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];

    // AppView: Enqueue DIDs for backfill
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/appview-enqueue-dids" handler:^(HttpRequest *request, HttpResponse *response) {
        if (![weakSelf ensureAuthorized:request response:response]) return;
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
        if (![weakSelf ensureAuthorized:request response:response]) return;
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
        if (![weakSelf ensureAuthorized:request response:response]) return;
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
        if (![weakSelf ensureAuthorized:request response:response]) return;
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
        if (![weakSelf ensureAuthorized:request response:response]) return;
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
        if (![weakSelf ensureAuthorized:request response:response]) return;
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
        if (![weakSelf ensureAuthorized:request response:response]) return;
        NSDictionary *result = [weakSelf.backendClient fetchMSTAccounts];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderMSTAccountsPartial:result]];
    }];

    // MST Viewer: Tree for DID
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/mst-tree" handler:^(HttpRequest *request, HttpResponse *response) {
        if (![weakSelf ensureAuthorized:request response:response]) return;
        NSString *did = [request queryParamForKey:@"did"];
        NSDictionary *result = [weakSelf.backendClient fetchMSTTreeForDID:did];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderMSTTreePartial:result]];
    }];

    // MST Viewer: Stats for DID
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/mst-stats" handler:^(HttpRequest *request, HttpResponse *response) {
        if (![weakSelf ensureAuthorized:request response:response]) return;
        NSString *did = [request queryParamForKey:@"did"];
        NSDictionary *result = [weakSelf.backendClient fetchMSTStatsForDID:did];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderMSTStatsPartial:result]];
    }];

    // MST Viewer: Export
    [self.httpServer addRoute:@"GET" path:@"/admin/actions/mst-export" handler:^(HttpRequest *request, HttpResponse *response) {
        if (![weakSelf ensureAuthorized:request response:response]) return;
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
    "<button class=\"service-segment\" data-tab=\"pds\" onclick=\"switchTab('pds')\">PDS</button>"
    "<button class=\"service-segment\" data-tab=\"appview\" onclick=\"switchTab('appview')\">AppView</button>"
    "<button class=\"service-segment\" data-tab=\"relay\" onclick=\"switchTab('relay')\">Relay</button>"
    "<button class=\"service-segment\" data-tab=\"plc\" onclick=\"switchTab('plc')\">PLC</button>"
    "<button class=\"service-segment\" data-tab=\"explorer\" onclick=\"switchTab('explorer')\">Explorer</button>"
    "<button class=\"service-segment\" data-tab=\"ozone\" onclick=\"switchTab('ozone')\">Ozone</button>"
    "<button class=\"service-segment\" data-tab=\"security\" onclick=\"switchTab('security')\">Security</button>"
    "<button class=\"service-segment\" data-tab=\"mst\" onclick=\"switchTab('mst')\">MST</button>"
    "<button class=\"service-segment\" data-tab=\"chat\" onclick=\"switchTab('chat')\">Chat</button>"
    "</nav>"
    "<div class=\"admin-header-right\">"
    "<form method=\"post\" action=\"/admin/logout\" onsubmit=\"fetch('/admin/logout',{method:'POST'}).then(()=>location='/admin/login');return false;\">"
    "<button type=\"submit\" class=\"btn btn-secondary btn-sm\">Logout</button></form></div></header>"
    "<main class=\"admin-content\">"
    /* Overview tab */
    "<div id=\"tab-overview\" class=\"tab-pane\">"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">Service Status</h3>"
    "<div id=\"overview\" hx-get=\"/admin/partials/overview\" hx-trigger=\"load, every 20s\"></div></section></div>"
    /* PDS tab */
    "<div id=\"tab-pds\" class=\"tab-pane\" style=\"display:none\">"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">Accounts</h3>"
    "<div class=\"search-row\"><form class=\"d-flex gap-sm flex-1\" hx-get=\"/admin/partials/accounts\" hx-target=\"#accounts\">"
    "<input type=\"text\" name=\"q\" placeholder=\"Search email or DID\" class=\"flex-1\"/>"
    "<button type=\"submit\" class=\"btn btn-primary btn-sm\">Search</button></form></div>"
    "<div id=\"accounts\" hx-get=\"/admin/partials/accounts\" hx-trigger=\"load\"></div></section>"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">Invite Codes</h3>"
    "<div id=\"invites\" hx-get=\"/admin/partials/invites\" hx-trigger=\"load\"></div>"
    "<div class=\"action-row\"><input id=\"disable-account\" type=\"text\" placeholder=\"DID to disable invites\" class=\"flex-1\"/>"
    "<button class=\"btn btn-destructive btn-sm\" onclick=\"disableInvites()\">Disable Invites</button></div>"
    "<div class=\"action-row mt-sm\"><input id=\"enable-account\" type=\"text\" placeholder=\"DID to enable invites\" class=\"flex-1\"/>"
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
    "<div class=\"action-row\"><input id=\"crawl-hostname\" type=\"text\" placeholder=\"Hostname to crawl\" class=\"flex-1\"/>"
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
    "<input type=\"text\" name=\"did\" placeholder=\"did:plc:...\" class=\"flex-1\"/>"
    "<button type=\"submit\" class=\"btn btn-primary btn-sm\">Lookup</button></form></div>"
    "<div id=\"plc-did-result\"></div></section>"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">DID Log</h3>"
    "<div class=\"search-row\"><form class=\"d-flex gap-sm flex-1\" hx-get=\"/admin/partials/plc-log\" hx-target=\"#plc-log-result\">"
    "<input type=\"text\" name=\"did\" placeholder=\"did:plc:...\" class=\"flex-1\"/>"
    "<button type=\"submit\" class=\"btn btn-primary btn-sm\">View Log</button></form></div>"
    "<div id=\"plc-log-result\"></div></section></div>"
    /* Explorer tab */
    "<div id=\"tab-explorer\" class=\"tab-pane\" style=\"display:none\">"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">Repo Explorer</h3>"
    "<div class=\"search-row\"><form class=\"d-flex gap-sm flex-1\" hx-get=\"/admin/partials/describe-repo\" hx-target=\"#repo-detail\">"
    "<input type=\"text\" name=\"did\" placeholder=\"did:plc:... or handle\" class=\"flex-1\"/>"
    "<button type=\"submit\" class=\"btn btn-primary btn-sm\">Describe</button></form></div>"
    "<div id=\"repo-detail\"></div></section>"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">List Records</h3>"
    "<div class=\"search-row\"><form class=\"d-flex gap-sm flex-1\" hx-get=\"/admin/partials/list-records\" hx-target=\"#records-list\">"
    "<input type=\"text\" name=\"did\" placeholder=\"did:plc:...\" class=\"flex-1\"/>"
    "<input type=\"text\" name=\"collection\" placeholder=\"Collection (optional)\" class=\"flex-1\"/>"
    "<button type=\"submit\" class=\"btn btn-primary btn-sm\">List</button></form></div>"
    "<div id=\"records-list\"></div></section>"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">Get Record</h3>"
    "<div class=\"search-row\"><form class=\"d-flex gap-sm flex-1\" hx-get=\"/admin/partials/get-record\" hx-target=\"#record-detail\">"
    "<input type=\"text\" name=\"did\" placeholder=\"did:plc:...\" class=\"flex-1\"/>"
    "<input type=\"text\" name=\"collection\" placeholder=\"Collection\" class=\"flex-1\"/>"
    "<input type=\"text\" name=\"rkey\" placeholder=\"Record key\" class=\"flex-1\"/>"
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
    "<input type=\"text\" name=\"did\" placeholder=\"did:plc:...\" class=\"flex-1\"/>"
    "<button type=\"submit\" class=\"btn btn-primary btn-sm\">Lookup</button></form></div>"
    "<div id=\"ozone-subject-result\"></div></section>"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">Moderation Reports</h3>"
    "<div id=\"ozone-reports\" hx-get=\"/admin/partials/ozone-reports\" hx-trigger=\"load\"></div></section>"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">Scheduled Actions</h3>"
    "<div id=\"ozone-scheduled\" hx-get=\"/admin/partials/ozone-scheduled\" hx-trigger=\"load\"></div></section>"
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
    "<input type=\"text\" name=\"did\" placeholder=\"did:plc:...\" class=\"flex-1\"/>"
    "<button type=\"submit\" class=\"btn btn-primary btn-sm\">Lookup</button></form></div>"
    "<div id=\"sessions-result\"></div></section>"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">App Passwords</h3>"
    "<div class=\"search-row\"><form class=\"d-flex gap-sm flex-1\" hx-get=\"/admin/partials/app-passwords\" hx-target=\"#app-passwords-result\">"
    "<input type=\"text\" name=\"did\" placeholder=\"did:plc:...\" class=\"flex-1\"/>"
    "<button type=\"submit\" class=\"btn btn-primary btn-sm\">Lookup</button></form></div>"
    "<div id=\"app-passwords-result\"></div></section></div>"
    /* MST Viewer tab */
    "<div id=\"tab-mst\" class=\"tab-pane\" style=\"display:none\">"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">MST Accounts</h3>"
    "<div id=\"mst-accounts\" hx-get=\"/admin/partials/mst-accounts\" hx-trigger=\"load\"></div></section>"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">MST Tree</h3>"
    "<div class=\"search-row\"><form class=\"d-flex gap-sm flex-1\" hx-get=\"/admin/partials/mst-tree\" hx-target=\"#mst-tree-result\">"
    "<input type=\"text\" name=\"did\" placeholder=\"did:plc:...\" class=\"flex-1\"/>"
    "<button type=\"submit\" class=\"btn btn-primary btn-sm\">View Tree</button></form></div>"
    "<div id=\"mst-tree-result\"></div></section>"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">MST Statistics</h3>"
    "<div class=\"search-row\"><form class=\"d-flex gap-sm flex-1\" hx-get=\"/admin/partials/mst-stats\" hx-target=\"#mst-stats-result\">"
    "<input type=\"text\" name=\"did\" placeholder=\"did:plc:...\" class=\"flex-1\"/>"
    "<button type=\"submit\" class=\"btn btn-primary btn-sm\">View Stats</button></form></div>"
    "<div id=\"mst-stats-result\"></div></section>"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">Export MST</h3>"
    "<div class=\"action-row\"><input id=\"mst-export-did\" type=\"text\" placeholder=\"did:plc:...\" class=\"flex-1\"/>"
    "<select id=\"mst-export-format\" class=\"flex-none\"><option value=\"json\">JSON</option><option value=\"dot\">DOT</option><option value=\"svg\">SVG</option></select>"
    "<button class=\"btn btn-primary btn-sm\" onclick=\"exportMST()\">Export</button></div>"
    "<div id=\"mst-export-result\"></div></section></div>"
    /* Chat tab */
    "<div id=\"tab-chat\" class=\"tab-pane\" style=\"display:none\">"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">Conversations</h3>"
    "<div id=\"chat-convos\" hx-get=\"/admin/partials/chat-convos\" hx-trigger=\"load, every 20s\"></div></section>"
    "<section class=\"admin-section\"><h3 class=\"admin-section-title\">Messages</h3>"
    "<div class=\"action-row\"><input id=\"chat-convo-id\" type=\"text\" placeholder=\"Conversation ID\" class=\"flex-1\"/>"
    "<button class=\"btn btn-primary btn-sm\" onclick=\"loadChatMessages()\">Load Messages</button></div>"
    "<div id=\"chat-messages\" hx-trigger=\"load\"></div>"
    "<div id=\"chat-action-result\"></div></section></div>"
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
    "function loadChatMessages(){const convoID=document.getElementById('chat-convo-id').value;"
    "if(!convoID){alert('Conversation ID required');return;}"
    "htmx.ajax('GET','/admin/partials/chat-messages?convoID='+encodeURIComponent(convoID),'#chat-messages');}"
    "async function lockChatConvo(convoID){if(!confirm('Lock this conversation?'))return;"
    "const resp=await fetch('/admin/actions/lock-chat-convo',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({convoID})});"
    "document.getElementById('chat-action-result').innerHTML=await resp.text();htmx.ajax('GET','/admin/partials/chat-convos','#chat-convos');}"
    "</script>"
    "</body></html>";
}

- (NSString *)renderOverviewPartial:(NSDictionary *)overview {
    NSArray<NSDictionary *> *services = [overview[@"services"] isKindOfClass:[NSArray class]] ? overview[@"services"] : @[];
    NSMutableString *html = [NSMutableString stringWithString:@"<table class=\"table\"><thead><tr><th>Service</th><th>Status</th><th>Version</th><th>Root</th><th>XRPC</th><th>Detail</th></tr></thead><tbody>"];
    for (NSDictionary *service in services) {
        BOOL connected = [service[@"connected"] boolValue];
        NSString *name = UIEscaped(service[@"name"] ?: @"");
        NSString *version = UIEscaped(service[@"version"] ?: @"unknown");
        NSString *detail = UIEscaped(service[@"detail"] ?: @"");
        NSString *rootStatus = UIEscaped([service[@"rootStatus"] stringValue] ?: @"0");
        NSString *xrpcStatus = UIEscaped([service[@"xrpcStatus"] stringValue] ?: @"0");
        NSString *indicatorClass = connected ? @"status-indicator connected" : @"status-indicator disconnected";
        NSString *state = connected ? @"connected" : @"offline";
        NSString *badgeClass = connected ? @"badge badge-success" : @"badge badge-destructive";
        [html appendFormat:@"<tr><td><strong>%@</strong></td><td><span class=\"%@\"></span> <span class=\"%@\">%@</span></td><td>%@</td><td>%@</td><td>%@</td><td class=\"text-sm text-secondary\">%@</td></tr>",
         name, indicatorClass, badgeClass, state, version, rootStatus, xrpcStatus, detail];
    }
    if (services.count == 0) {
        [html appendString:@"<tr><td colspan=\"6\" class=\"text-center text-secondary p-lg\">No service data available.</td></tr>"];
    }
    [html appendString:@"</tbody></table>"];
    return html;
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
    NSMutableString *html = [NSMutableString stringWithString:@"<div id=\"appview-result\"></div><div class=\"mb-lg\"><button class=\"btn btn-sm btn-secondary\" onclick=\"rebuildAppViewScope()\">Rebuild Relevance Set</button></div><form class=\"form mb-lg\" onsubmit=\"enqueueBackfillDIDs();return false;\"><div class=\"form-group\"><label>Enqueue DIDs (one per line):</label><textarea id=\"enqueue-dids-input\" class=\"form-input\" placeholder=\"did:plc:...\"></textarea></div><button type=\"submit\" class=\"btn btn-primary btn-sm\">Enqueue</button></form><table class=\"table\" id=\"queue-table\"><thead><tr><th>DID</th><th>Status</th><th>Actions</th></tr></thead><tbody>"];
    NSArray<NSDictionary *> *entries = [result[@"entries"] isKindOfClass:[NSArray class]] ? result[@"entries"] : @[];
    for (NSDictionary *entry in entries) {
        NSString *did = UIEscaped(entry[@"did"] ?: @"");
        NSString *status = UIEscaped(entry[@"status"] ?: @"");
        NSString *statusBadge = [status isEqualToString:@"running"] ? @"badge badge-success" :
                                [status isEqualToString:@"failed"] ? @"badge badge-destructive" : @"badge badge-secondary";
        [html appendFormat:@"<tr><td class=\"text-mono text-xs\">%@</td><td><span class=\"%@\">%@</span></td><td>", did, statusBadge, status];
        [html appendFormat:@"<button class=\"btn btn-sm btn-primary\" onclick=\"fetch('/admin/actions/appview-retry-repo',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({did:'%@'})}).then(()=>htmx.ajax('GET','/admin/partials/appview-queue','#appview-queue'))\">Retry</button> ", did];
        [html appendFormat:@"<button class=\"btn btn-sm btn-secondary\" onclick=\"fetch('/admin/actions/appview-cancel-repo',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({did:'%@'})}).then(()=>htmx.ajax('GET','/admin/partials/appview-queue','#appview-queue'))\">Cancel</button>", did];
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

- (NSString *)renderBlobsPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSArray<NSDictionary *> *blobs = [result[@"blobs"] isKindOfClass:[NSArray class]] ? result[@"blobs"] : @[];
    NSMutableString *html = [NSMutableString stringWithString:@"<table class=\"table\"><thead><tr><th>CID</th><th>Size</th><th>Type</th></tr></thead><tbody>"];
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
    NSString *cursor = result[@"cursor"];
    if (cursor.length > 0) {
        [html appendFormat:@"<div class=\"d-flex justify-between mt-sm\"><button class=\"btn btn-sm btn-secondary\" hx-get=\"/admin/partials/audit-log?cursor=%@\" hx-target=\"#audit-log-content\">Load more</button></div>", UIEscaped(cursor)];
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
        [html appendFormat:@"<tr><td class=\"text-mono text-xs\">%@</td><td class=\"text-xs\">%@</td><td>%@</td><td><select id=\"report-action\" onchange=\"if(this.value)resolvePDSReport('%@')\"><option value=\"\">Resolve as...</option><option value=\"escalate\">Escalate</option><option value=\"mute\">Mute</option><option value=\"markResolved\">Mark Resolved</option></select></td></tr>", reportID, createdAt, status, UIEscaped(reportID)];
    }
    if (reports.count == 0) {
        [html appendString:@"<tr><td colspan=\"4\" class=\"text-center text-secondary p-lg\">No reports found.</td></tr>"];
    }
    [html appendString:@"</tbody></table>"];
    NSString *cursor = result[@"cursor"];
    if (cursor.length > 0) {
        [html appendFormat:@"<div class=\"d-flex justify-between mt-sm\"><button class=\"btn btn-sm btn-secondary\" hx-get=\"/admin/partials/pds-reports?cursor=%@\" hx-target=\"#pds-reports-content\">Load more</button></div>", UIEscaped(cursor)];
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
    NSString *cursor = result[@"cursor"];
    if (cursor.length > 0) {
        [html appendFormat:@"<div class=\"d-flex justify-between mt-sm\"><button class=\"btn btn-sm btn-secondary\" hx-get=\"/admin/partials/list-records?cursor=%@\" hx-target=\"#records-list\">Load more</button></div>", UIEscaped(cursor)];
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
    NSString *cursor = result[@"cursor"];
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
    NSString *cursor = result[@"cursor"];
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
    [result enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
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
    NSMutableString *html = [NSMutableString stringWithString:@"<table class=\"table\"><thead><tr><th>Conversation ID</th><th>Members</th><th>Last Message</th><th>Actions</th></tr></thead><tbody>"];
    for (NSDictionary *convo in convos) {
        NSString *convoID = convo[@"id"] ?: @"";
        NSString *memberCount = [[convo[@"memberCount"] description] ?: @"0"];
        NSString *lastMsg = convo[@"lastMessage"] ? [[convo[@"lastMessage"] isKindOfClass:[NSDictionary class]] ? convo[@"lastMessage"][@"text"] : convo[@"lastMessage"]] : @"(none)";
        if (lastMsg.length > 50) lastMsg = [[lastMsg substringToIndex:50] stringByAppendingString:@"..."];
        [html appendFormat:@"<tr><td class=\"text-mono text-sm\">%@</td><td>%@</td><td class=\"text-sm\">%@</td><td><button class=\"btn btn-sm btn-secondary\" onclick=\"lockChatConvo('%@')\">Lock</button></td></tr>",
            UIEscaped(convoID), UIEscaped(memberCount), UIEscaped(lastMsg), UIEscaped(convoID)];
    }
    if (convos.count == 0) {
        [html appendString:@"<tr><td colspan=\"4\" class=\"text-center text-secondary p-lg\">No conversations found.</td></tr>"];
    }
    [html appendString:@"</tbody></table>"];
    NSString *cursor = result[@"cursor"];
    if (cursor.length > 0) {
        [html appendFormat:@"<div class=\"d-flex justify-between mt-sm\"><button class=\"btn btn-sm btn-secondary\" hx-get=\"/admin/partials/chat-convos?cursor=%@\" hx-target=\"#chat-convos\">Load more</button></div>", UIEscaped(cursor)];
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
        NSString *sender = msg[@"sender"] ?: @"unknown";
        NSString *text = msg[@"text"] ?: @"";
        NSString *createdAt = msg[@"createdAt"] ?: @"";
        [html appendFormat:@"<div class=\"message\"><div class=\"message-header\"><span class=\"message-sender\">%@</span><span class=\"message-time text-xs text-secondary\">%@</span></div><div class=\"message-body\">%@</div></div>",
            UIEscaped(sender), UIEscaped(createdAt), UIEscaped(text)];
    }
    if (messages.count == 0) {
        [html appendString:@"<div class=\"text-center text-secondary p-lg\">No messages found.</div>"];
    }
    [html appendString:@"</div>"];
    return html;
}

#pragma mark - MST Viewer Render Methods

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
    NSDictionary *root = result[@"root"];
    if (!root) {
        return @"<div class=\"alert alert-info\">No tree data available.</div>";
    }
    NSMutableString *html = [NSMutableString stringWithString:@"<div class=\"detail-card\">"];
    [html appendFormat:@"<div class=\"detail-row\"><span class=\"detail-label\">DID</span><span class=\"text-mono text-sm\">%@</span></div>", UIEscaped(result[@"did"] ?: @"")];
    [html appendFormat:@"<div class=\"detail-row\"><span class=\"detail-label\">CID</span><span class=\"text-mono text-sm\">%@</span></div>", UIEscaped(root[@"cid"] ?: @"")];
    NSArray *entries = [root[@"entries"] isKindOfClass:[NSArray class]] ? root[@"entries"] : @[];
    [html appendFormat:@"<div class=\"detail-row\"><span class=\"detail-label\">Entries</span><span>%lu</span></div>", (unsigned long)entries.count];
    [html appendString:@"</div>"];
    if (entries.count > 0) {
        [html appendString:@"<table class=\"table mt-sm\"><thead><tr><th>Key</th><th>CID</th></tr></thead><tbody>"];
        for (NSDictionary *e in entries) {
            [html appendFormat:@"<tr><td class=\"text-mono text-sm\">%@</td><td class=\"text-mono text-sm\">%@</td></tr>",
                UIEscaped(e[@"key"] ?: @""), UIEscaped(e[@"cid"] ?: @"")];
        }
        [html appendString:@"</tbody></table>"];
    }
    return html;
}

- (NSString *)renderMSTStatsPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSMutableString *html = [NSMutableString stringWithString:@"<div class=\"detail-card\">"];
    [result enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
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
    NSString *checkedAt = result[@"checkedAt"] ?: result[@"lastChecked"] ?: @"";
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
    NSString *cursor = result[@"cursor"];
    if (cursor) {
        [html appendFormat:@"<div class=\"mt-sm\"><button class=\"btn btn-sm btn-secondary\" hx-get=\"/admin/partials/ozone-reports?cursor=%@\" hx-target=\"#ozone-reports\">Load More</button></div>", UIEscaped(cursor)];
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
        [html appendFormat:@"<div class=\"mt-sm\"><button class=\"btn btn-sm btn-secondary\" hx-get=\"/admin/partials/plc-list?cursor=%@\" hx-target=\"#plc-list\">Load More</button></div>", UIEscaped(cursor)];
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
    NSString *cursor = result[@"cursor"];
    if (cursor && cursor.length > 0) {
        [html appendFormat:@"<div class=\"mt-sm\"><button class=\"btn btn-sm btn-secondary\" hx-get=\"/admin/partials/ozone-scheduled?cursor=%@\" hx-target=\"#ozone-scheduled\">Load More</button></div>", UIEscaped(cursor)];
    }
    return html;
}

@end

