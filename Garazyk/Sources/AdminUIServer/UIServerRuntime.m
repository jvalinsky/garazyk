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
            ? [NSString stringWithFormat:@"<p style=\"color:#b91c1c\">%@</p>", UIEscaped(result[@"message"] ?: result[@"error"])]
            : @"<p style=\"color:#166534\">Invites disabled for account.</p>";
        [response setBodyString:message];
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
        [response setBodyString:[NSString stringWithFormat:@"<p>%@</p>", UIEscaped(msg)]];
    }];

    [self.httpServer addRoute:@"POST" path:@"/admin/actions/appview-cancel-repo" handler:^(HttpRequest *request, HttpResponse *response) {
        if (![weakSelf ensureAuthorized:request response:response]) return;
        NSString *did = request.jsonBody[@"did"] ?: [request queryParamForKey:@"did"];
        NSDictionary *result = [weakSelf.backendClient cancelBackfillForDID:did ?: @""];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? result[@"message"] : @"Cancel requested.";
        [response setBodyString:[NSString stringWithFormat:@"<p>%@</p>", UIEscaped(msg)]];
    }];

    [self.httpServer addRoute:@"GET" path:@"/admin/partials/relay-metrics" handler:^(HttpRequest *request, HttpResponse *response) {
        if (![weakSelf ensureAuthorized:request response:response]) return;
        NSDictionary *result = [weakSelf.backendClient fetchRelayMetrics];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderRelayMetricsPartial:result]];
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
    return @"<!doctype html><html><head><meta charset=\"utf-8\"><title>Garazyk UI Login</title>"
    "<style>body{font-family:system-ui;background:#0f172a;color:#e2e8f0;display:flex;justify-content:center;align-items:center;min-height:100vh;margin:0}"
    ".card{background:#111827;border:1px solid #334155;border-radius:8px;padding:24px;width:320px}"
    "input,button{width:100%;padding:10px;border-radius:6px;border:1px solid #334155;margin-top:10px}"
    "button{background:#2563eb;color:#fff;border:none;cursor:pointer}</style></head><body>"
    "<div class=\"card\"><h2 style=\"margin:0 0 8px\">Admin UI Service</h2>"
    "<p style=\"margin:0 0 12px;color:#94a3b8\">Sign in to continue.</p>"
    "<form id=\"login-form\"><input id=\"password\" type=\"password\" placeholder=\"Admin password\" required/>"
    "<button type=\"submit\">Sign in</button></form><p id=\"error\" style=\"color:#ef4444\"></p></div>"
    "<script>document.getElementById('login-form').addEventListener('submit',async(e)=>{e.preventDefault();"
    "const password=document.getElementById('password').value;"
    "const resp=await fetch('/admin/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({password})});"
    "if(resp.ok){window.location='/admin';return;}document.getElementById('error').textContent='Invalid credentials';});</script>"
    "</body></html>";
}

- (NSString *)adminShellHTML {
    return @"<!doctype html><html><head><meta charset=\"utf-8\"><title>Garazyk UI Service</title>"
    "<script src=\"https://unpkg.com/htmx.org@1.9.12\" integrity=\"sha384-qKZVAvbtYRYoPh8Brc0l+qUjTj8SZ0FTaWGLfcqM1nPl6RNQBPBGzPPmKM9YoqWQ\" crossorigin=\"anonymous\"></script>"
    "<style>body{font-family:system-ui;margin:0;background:#f8fafc;color:#0f172a}"
    "header{display:flex;justify-content:space-between;align-items:center;padding:12px 20px;background:#0f172a;color:#e2e8f0}"
    "main{padding:20px;display:grid;gap:16px}.panel{background:white;border:1px solid #cbd5e1;border-radius:8px;padding:14px}"
    "table{border-collapse:collapse;width:100%}td,th{border-bottom:1px solid #e2e8f0;padding:8px;text-align:left}"
    ".row{display:flex;gap:8px;align-items:center}.light{width:10px;height:10px;border-radius:50%;display:inline-block}"
    "</style></head><body><header><div><strong>Garazyk UI Service</strong></div>"
    "<form method=\"post\" action=\"/admin/logout\" onsubmit=\"fetch('/admin/logout',{method:'POST'}).then(()=>location='/admin/login');return false;\">"
    "<button type=\"submit\">Logout</button></form></header>"
    "<main><section class=\"panel\"><h3 style=\"margin-top:0\">Service Status</h3>"
    "<div id=\"overview\" hx-get=\"/admin/partials/overview\" hx-trigger=\"load, every 20s\"></div></section>"
    "<section class=\"panel\"><h3 style=\"margin-top:0\">Accounts</h3>"
    "<form class=\"row\" hx-get=\"/admin/partials/accounts\" hx-target=\"#accounts\">"
    "<input type=\"text\" name=\"q\" placeholder=\"Search email\"/>"
    "<button type=\"submit\">Search</button></form><div id=\"accounts\" hx-get=\"/admin/partials/accounts\" hx-trigger=\"load\"></div></section>"
    "<section class=\"panel\"><h3 style=\"margin-top:0\">Invite Codes</h3>"
    "<div id=\"invites\" hx-get=\"/admin/partials/invites\" hx-trigger=\"load\"></div>"
    "<div class=\"row\" style=\"margin-top:10px\"><input id=\"disable-account\" type=\"text\" placeholder=\"DID to disable invites\"/>"
    "<button onclick=\"disableInvites()\">Disable Invites</button></div><div id=\"invite-action-result\"></div></section>"
    "<section class=\"panel\"><h3 style=\"margin-top:0\">AppView</h3>"
    "<div id=\"appview-metrics\" hx-get=\"/admin/partials/appview-metrics\" hx-trigger=\"load, every 30s\"></div>"
    "<div id=\"appview-ingest\" hx-get=\"/admin/partials/appview-ingest\" hx-trigger=\"load, every 30s\" style=\"margin-top:16px\"></div>"
    "<div style=\"margin-top:16px\"><h4 style=\"margin-bottom:8px;margin-top:0\">Backfill Queue</h4>"
    "<div id=\"appview-queue\" hx-get=\"/admin/partials/appview-queue\" hx-trigger=\"load, every 10s\"></div></div></section>"
    "<section class=\"panel\"><h3 style=\"margin-top:0\">Relay</h3>"
    "<div id=\"relay-metrics\" hx-get=\"/admin/partials/relay-metrics\" hx-trigger=\"load, every 30s\"></div></section>"
    "</main>"
    "<script>async function disableInvites(){const account=document.getElementById('disable-account').value;"
    "const resp=await fetch('/admin/actions/disable-invites',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({account})});"
    "document.getElementById('invite-action-result').innerHTML=await resp.text();htmx.ajax('GET','/admin/partials/invites','#invites');}</script>"
    "</body></html>";
}

- (NSString *)renderOverviewPartial:(NSDictionary *)overview {
    NSArray<NSDictionary *> *services = [overview[@"services"] isKindOfClass:[NSArray class]] ? overview[@"services"] : @[];
    NSMutableString *html = [NSMutableString stringWithString:@"<table><thead><tr><th>Service</th><th>Status</th><th>Version</th><th>Root</th><th>XRPC</th><th>Detail</th></tr></thead><tbody>"];
    for (NSDictionary *service in services) {
        BOOL connected = [service[@"connected"] boolValue];
        NSString *name = UIEscaped(service[@"name"] ?: @"");
        NSString *version = UIEscaped(service[@"version"] ?: @"unknown");
        NSString *detail = UIEscaped(service[@"detail"] ?: @"");
        NSString *rootStatus = UIEscaped([service[@"rootStatus"] stringValue] ?: @"0");
        NSString *xrpcStatus = UIEscaped([service[@"xrpcStatus"] stringValue] ?: @"0");
        NSString *color = connected ? @"#22c55e" : @"#ef4444";
        NSString *state = connected ? @"connected" : @"offline";
        [html appendFormat:@"<tr><td>%@</td><td><span class=\"row\"><span class=\"light\" style=\"background:%@\"></span>%@</span></td><td>%@</td><td>%@</td><td>%@</td><td>%@</td></tr>",
         name, color, state, version, rootStatus, xrpcStatus, detail];
    }
    if (services.count == 0) {
        [html appendString:@"<tr><td colspan=\"6\">No service data available.</td></tr>"];
    }
    [html appendString:@"</tbody></table>"];
    return html;
}

- (NSString *)renderAccountsPartial:(NSDictionary *)result {
    NSArray<NSDictionary *> *accounts = [result[@"accounts"] isKindOfClass:[NSArray class]] ? result[@"accounts"] : @[];
    NSMutableString *html = [NSMutableString stringWithString:@"<table><thead><tr><th>DID</th><th>Handle</th><th>Email</th></tr></thead><tbody>"];
    if (result[@"error"]) {
        NSString *message = UIEscaped(result[@"message"] ?: result[@"error"]);
        [html appendFormat:@"<tr><td colspan=\"3\" style=\"color:#b91c1c\">%@</td></tr>", message];
    } else {
        for (NSDictionary *account in accounts) {
            NSString *did = UIEscaped(account[@"did"] ?: @"");
            NSString *handle = UIEscaped(account[@"handle"] ?: @"");
            NSString *email = UIEscaped(account[@"email"] ?: @"");
            [html appendFormat:@"<tr><td>%@</td><td>%@</td><td>%@</td></tr>", did, handle, email];
        }
        if (accounts.count == 0) {
            [html appendString:@"<tr><td colspan=\"3\">No accounts found.</td></tr>"];
        }
    }
    [html appendString:@"</tbody></table>"];
    return html;
}

- (NSString *)renderInvitesPartial:(NSDictionary *)result {
    NSArray<NSDictionary *> *codes = [result[@"codes"] isKindOfClass:[NSArray class]] ? result[@"codes"] : @[];
    NSMutableString *html = [NSMutableString stringWithString:@"<table><thead><tr><th>Code</th><th>Available</th><th>Uses</th></tr></thead><tbody>"];
    if (result[@"error"]) {
        NSString *message = UIEscaped(result[@"message"] ?: result[@"error"]);
        [html appendFormat:@"<tr><td colspan=\"3\" style=\"color:#b91c1c\">%@</td></tr>", message];
    } else {
        for (NSDictionary *entry in codes) {
            NSString *code = UIEscaped(entry[@"code"] ?: @"");
            NSString *available = UIEscaped([entry[@"available"] stringValue] ?: @"0");
            NSString *uses = UIEscaped([entry[@"uses"] stringValue] ?: @"0");
            [html appendFormat:@"<tr><td>%@</td><td>%@</td><td>%@</td></tr>", code, available, uses];
        }
        if (codes.count == 0) {
            [html appendString:@"<tr><td colspan=\"3\">No invite codes found.</td></tr>"];
        }
    }
    [html appendString:@"</tbody></table>"];
    return html;
}

- (NSString *)renderAppViewMetricsPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div style=\"color:#ef4444\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSMutableString *html = [NSMutableString stringWithString:@"<table><thead><tr><th>Metric</th><th>Value</th></tr></thead><tbody>"];
    NSDictionary *backfill = result[@"backfill"] ?: @{};
    NSDictionary *ingest = result[@"ingest"] ?: @{};
    NSDictionary *index = result[@"index"] ?: @{};
    
    [html appendFormat:@"<tr><td>Queue Depth</td><td>%@</td></tr>", UIEscaped([backfill[@"queue_depth"] stringValue] ?: @"0")];
    [html appendFormat:@"<tr><td>Active Workers</td><td>%@</td></tr>", UIEscaped([backfill[@"active_workers"] stringValue] ?: @"0")];
    [html appendFormat:@"<tr><td>Relays</td><td>%@</td></tr>", UIEscaped([ingest[@"relays"] stringValue] ?: @"0")];
    [html appendFormat:@"<tr><td>Index Records</td><td>%@</td></tr>", UIEscaped([index[@"total_records"] stringValue] ?: @"0")];
    [html appendString:@"</tbody></table>"];
    return html;
}

- (NSString *)renderIngestHealthPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div style=\"color:#ef4444\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSMutableString *html = [NSMutableString stringWithString:@"<table><thead><tr><th>Relay</th><th>Lag</th><th>Throughput</th></tr></thead><tbody>"];
    NSArray<NSDictionary *> *relays = [result[@"relays"] isKindOfClass:[NSArray class]] ? result[@"relays"] : @[];
    for (NSDictionary *relay in relays) {
        NSString *url = UIEscaped(relay[@"url"] ?: @"");
        NSString *lag = UIEscaped([relay[@"lag"] stringValue] ?: @"0");
        NSString *tps = UIEscaped([relay[@"throughput"] stringValue] ?: @"0");
        [html appendFormat:@"<tr><td>%@</td><td>%@</td><td>%@</td></tr>", url, lag, tps];
    }
    if (relays.count == 0) {
        [html appendString:@"<tr><td colspan=\"3\">No relay ingest data.</td></tr>"];
    }
    [html appendString:@"</tbody></table>"];
    return html;
}

- (NSString *)renderBackfillQueuePartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div style=\"color:#ef4444\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSMutableString *html = [NSMutableString stringWithString:@"<table id=\"queue-table\"><thead><tr><th>DID</th><th>Status</th><th>Actions</th></tr></thead><tbody>"];
    NSArray<NSDictionary *> *entries = [result[@"entries"] isKindOfClass:[NSArray class]] ? result[@"entries"] : @[];
    for (NSDictionary *entry in entries) {
        NSString *did = UIEscaped(entry[@"did"] ?: @"");
        NSString *status = UIEscaped(entry[@"status"] ?: @"");
        [html appendFormat:@"<tr><td>%@</td><td>%@</td><td>", did, status];
        [html appendFormat:@"<button onclick=\"fetch('/admin/actions/appview-retry-repo',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({did:'%@'})}).then(()=>htmx.ajax('GET','/admin/partials/appview-queue','#appview-queue'))\">Retry</button> ", did];
        [html appendFormat:@"<button onclick=\"fetch('/admin/actions/appview-cancel-repo',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({did:'%@'})}).then(()=>htmx.ajax('GET','/admin/partials/appview-queue','#appview-queue'))\">Cancel</button>", did];
        [html appendString:@"</td></tr>"];
    }
    if (entries.count == 0) {
        [html appendString:@"<tr><td colspan=\"3\">Queue is empty.</td></tr>"];
    }
    [html appendString:@"</tbody></table>"];
    return html;
}

- (NSString *)renderRelayMetricsPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div style=\"color:#ef4444\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSMutableString *html = [NSMutableString stringWithString:@"<table><thead><tr><th>Metric</th><th>Value</th></tr></thead><tbody>"];
    
    NSDictionary *metrics = result[@"metrics"] ?: result;
    for (NSString *key in metrics) {
        if (![metrics[key] isKindOfClass:[NSString class]] && ![metrics[key] isKindOfClass:[NSNumber class]]) continue;
        NSString *val = [metrics[key] description];
        [html appendFormat:@"<tr><td>%@</td><td>%@</td></tr>", UIEscaped(key), UIEscaped(val)];
    }
    if (metrics.count == 0) {
        [html appendString:@"<tr><td colspan=\"2\">No metrics found.</td></tr>"];
    }
    [html appendString:@"</tbody></table>"];
    return html;
}

@end

