// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/UIServerRuntime.h"

#import "AdminUIServer/UIAuthManager.h"
#import "AdminUIServer/UIBackendClient.h"
#import "AdminUIServer/UIServiceConfig.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"
#import "Network/XrpcHandler.h"
#import "Network/Generated/GZXrpcNSID.h"
#import "Auth/CryptoUtils.h"
#import "Debug/GZLogger.h"
#import "AdminUIServer/UIServerRuntime+Private.h"

NSString *UIEscaped(NSString *value) {
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
NSString * _Nullable UIStringFromDict(NSDictionary *dict, NSString *key) {
    id value = dict[key];
    if ([value isKindOfClass:[NSString class]]) {
        return value;
    }
    return nil;
}

/// Safely convert any value (including NSNull) to an NSString, returning fallback for non-strings.
NSString *UISafe(id value, NSString *fallback) {
    if ([value isKindOfClass:[NSString class]]) {
        return value;
    }
    return fallback ?: @"";
}

/// Safely get .length from a value that might be NSNull.
NSUInteger UISafeLength(id value) {
    if ([value isKindOfClass:[NSString class]]) {
        return [(NSString *)value length];
    }
    return 0;
}


NSString *UIGenerateNonce(void) {
    NSData *data = [CryptoUtils randomBytes:16];
    return [CryptoUtils base64URLEncode:data];
}

void UIApplyNonceCSP(HttpResponse *response, NSString *nonce, NSString *pdsOrigin) {
    NSString *csp;
    if (pdsOrigin) {
        csp = [NSString stringWithFormat:
            @"default-src 'self'; "
            "script-src 'self' 'nonce-%@' https://unpkg.com; "
            "script-src-attr 'none'; "
            "style-src 'self' 'nonce-%@'; "
            "img-src 'self' data:; "
            "connect-src 'self' %@;",
            nonce, nonce, pdsOrigin];
    } else {
        csp = [NSString stringWithFormat:
            @"default-src 'self'; "
            "script-src 'self' 'nonce-%@' https://unpkg.com; "
            "script-src-attr 'none'; "
            "style-src 'self' 'nonce-%@'; "
            "img-src 'self' data:;",
            nonce, nonce];
    }
    [response setHeader:csp forKey:@"content-security-policy"];
}


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

    self.xrpcDispatcher = [[XrpcDispatcher alloc] init];
    
    // Register standard health endpoint
    [self.xrpcDispatcher registerMethod:@"_health" handler:^(HttpRequest *req, HttpResponse *res) {
        res.statusCode = 200;
        [res setJsonBody:@{@"version": @"1.0.0"}];
    }];

    // Register com.atproto.server.describeServer
    [self.xrpcDispatcher registerMethod:kGZXrpcNSID_com_atproto_server_describeServer handler:^(HttpRequest *req, HttpResponse *res) {
        res.statusCode = 200;
        [res setJsonBody:@{
            @"availableUserDomains": @[],
            @"inviteCodeRequired": @YES,
            @"phoneVerificationRequired": @NO
        }];
    }];

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

    // XRPC API handler
    [self.httpServer addHandlerForPath:@"/xrpc" handler:^(HttpRequest *request, HttpResponse *response) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) {
            [strongSelf.xrpcDispatcher handleRequest:request response:response];
        }
    }];

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
        NSString *nonce = UIGenerateNonce();
        NSString *csrfNonce, *csrfCookie;
        [weakSelf.authManager createCSRFNonce:&csrfNonce cookie:&csrfCookie secure:NO];
        [response setHeader:csrfCookie forKey:@"Set-Cookie"];
        UIApplyNonceCSP(response, nonce, nil);
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf loginPageHTML:nonce csrfNonce:csrfNonce]];
    }];

    [self.httpServer addRoute:@"POST" path:@"/admin/login" handler:^(HttpRequest *request, HttpResponse *response) {
        if (![weakSelf.authManager validateCSRFForRequest:request]) {
            response.statusCode = 403;
            [response setJsonBody:@{@"ok": @NO, @"error": @"invalid_csrf_token"}];
            return;
        }
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
        AUTH_GUARD(weakSelf, request, response);
        NSString *token = [weakSelf.authManager extractTokenFromRequest:request];
        [weakSelf.authManager invalidateSessionToken:token];
        [response setHeader:@"ui_admin_token=; Path=/; Max-Age=0; HttpOnly; SameSite=Strict" forKey:@"Set-Cookie"];
        response.statusCode = 200;
        [response setJsonBody:@{@"ok": @YES}];
    }];

    [self.httpServer addRoute:@"GET" path:@"/admin" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *nonce = UIGenerateNonce();
        NSString *csrfNonce, *csrfCookie;
        [weakSelf.authManager createCSRFNonce:&csrfNonce cookie:&csrfCookie secure:NO];
        [response setHeader:csrfCookie forKey:@"Set-Cookie"];
        UIApplyNonceCSP(response, nonce, [weakSelf.configuration.pdsBaseURL absoluteString]);
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf adminShellHTML:nonce csrfNonce:csrfNonce]];
    }];
    [self registerPDSRoutes];
    [self registerAppViewRoutes];
    [self registerRelayRoutes];
    [self registerPLCRoutes];
    [self registerDataExplorerRoutes];
    [self registerLabRoutes];
    [self registerOzoneRoutes];
    [self registerSecurityRoutes];
    [self registerChatRoutes];
    [self registerVideoRoutes];
    [self registerMSTRoutes];
}

- (BOOL)ensureAuthorized:(HttpRequest *)request response:(HttpResponse *)response {
    if (![self.authManager isAuthorizedRequest:request]) {
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

    NSString *method = request.methodString.uppercaseString;
    BOOL isMutation = ![method isEqualToString:@"GET"] && ![method isEqualToString:@"HEAD"] && ![method isEqualToString:@"OPTIONS"];
    if (!isMutation) {
        return YES;
    }
    if (![self.authManager validateCSRFForRequest:request]) {
        response.statusCode = HttpStatusForbidden;
        [response setJsonBody:@{@"ok": @NO, @"error": @"invalid_csrf_token"}];
        return NO;
    }

    // CSRF nonces are one-time values. Rotate after every accepted mutation so
    // the external browser module can safely send the next request.
    NSString *nextNonce, *nextNonceCookie;
    [self.authManager createCSRFNonce:&nextNonce cookie:&nextNonceCookie secure:NO];
    [response setHeader:nextNonceCookie forKey:@"Set-Cookie"];
    [response setHeader:nextNonce forKey:@"X-UI-Admin-Nonce"];
    return YES;
}

- (NSString *)loginPageHTML:(NSString *)nonce csrfNonce:(NSString *)csrfNonce {
    return [NSString stringWithFormat:@"<!doctype html><html><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
    "<title>Garazyk UI Login</title>"
    "<link rel=\"stylesheet\" href=\"/css/system.css\">"
    "<meta name=\"csrf-nonce\" content=\"%@\">"
    "<style nonce=\"%@\">.login-shell{display:flex;justify-content:center;align-items:center;min-height:100vh;background:var(--color-bg-primary)}"
    ".login-card{background:var(--color-bg-secondary);border:1px solid var(--separator-color);border-radius:var(--radius-lg);padding:var(--space-xl);width:320px;box-shadow:var(--shadow-lg)}"
    ".login-card h2{margin-bottom:var(--space-sm)}.login-card p{color:var(--color-text-secondary);margin-bottom:var(--space-lg)}"
    ".login-card input{width:100%%;margin-bottom:var(--space-sm)}.login-card button{width:100%%}"
    ".login-error{color:var(--color-destructive);margin-top:var(--space-sm);font-size:var(--font-size-sm)}</style>"
    "</head><body><div class=\"login-shell\"><div class=\"login-card\">"
    "<h1>Admin UI Service</h1><p>Sign in to continue.</p>"
    "<form id=\"login-form\" data-ui-form=\"login\"><input id=\"password\" type=\"password\" placeholder=\"Admin password\" required/>"
    "<button type=\"submit\" class=\"btn btn-primary\">Sign in</button></form>"
    "<p id=\"error\" class=\"login-error\" role=\"alert\"></p></div></div>"
    "<script type=\"module\" src=\"/js/admin-ui.js\"></script>"
    "</body></html>", csrfNonce, nonce];
}

- (NSString *)adminShellHTML:(NSString *)nonce csrfNonce:(NSString *)csrfNonce {
    return [NSString stringWithFormat:@"<!doctype html><html><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
    "<title>Garazyk UI Service</title>"
    "<link rel=\"stylesheet\" href=\"/css/system.css\">"
    "<meta name=\"csrf-nonce\" content=\"%@\">"
    "<script nonce=\"%@\" src=\"https://unpkg.com/htmx.org@1.9.12\" integrity=\"sha384-ujb1lZYygJmzgSwoxRggbCHcjc0rB2XoQrxeTUQyRjrOnlCoYta87iKBWq3EsdM2\" crossorigin=\"anonymous\"></script>"
    "</head><body><div class=\"admin-shell\">"
    "<header class=\"admin-header\"><h1 class=\"admin-header-title\">Garazyk UI Service</h1>"
    "<nav class=\"service-segments\" id=\"nav-tabs\" role=\"tablist\" aria-label=\"Service sections\">"
    "<button class=\"service-segment active\" data-tab=\"overview\" data-ui-action=\"switch-tab\" role=\"tab\" id=\"tabbtn-overview\" aria-controls=\"tab-overview\" aria-selected=\"true\" tabindex=\"0\">Overview</button>"
    "<button class=\"service-segment\" data-tab=\"connections\" data-ui-action=\"switch-tab\" role=\"tab\" id=\"tabbtn-connections\" aria-controls=\"tab-connections\" aria-selected=\"false\" tabindex=\"-1\">Connections</button>"
    "<button class=\"service-segment\" data-tab=\"pds\" data-ui-action=\"switch-tab\" role=\"tab\" id=\"tabbtn-pds\" aria-controls=\"tab-pds\" aria-selected=\"false\" tabindex=\"-1\">PDS</button>"
    "<button class=\"service-segment\" data-tab=\"appview\" data-ui-action=\"switch-tab\" role=\"tab\" id=\"tabbtn-appview\" aria-controls=\"tab-appview\" aria-selected=\"false\" tabindex=\"-1\">AppView</button>"
    "<button class=\"service-segment\" data-tab=\"relay\" data-ui-action=\"switch-tab\" role=\"tab\" id=\"tabbtn-relay\" aria-controls=\"tab-relay\" aria-selected=\"false\" tabindex=\"-1\">Relay</button>"
    "<button class=\"service-segment\" data-tab=\"plc\" data-ui-action=\"switch-tab\" role=\"tab\" id=\"tabbtn-plc\" aria-controls=\"tab-plc\" aria-selected=\"false\" tabindex=\"-1\">PLC</button>"
    "<button class=\"service-segment\" data-tab=\"explorer\" data-ui-action=\"switch-tab\" role=\"tab\" id=\"tabbtn-explorer\" aria-controls=\"tab-explorer\" aria-selected=\"false\" tabindex=\"-1\">Explorer</button>"
    "<button class=\"service-segment\" data-tab=\"ozone\" data-ui-action=\"switch-tab\" role=\"tab\" id=\"tabbtn-ozone\" aria-controls=\"tab-ozone\" aria-selected=\"false\" tabindex=\"-1\">Ozone</button>"
    "<button class=\"service-segment\" data-tab=\"security\" data-ui-action=\"switch-tab\" role=\"tab\" id=\"tabbtn-security\" aria-controls=\"tab-security\" aria-selected=\"false\" tabindex=\"-1\">Security</button>"
    "<button class=\"service-segment\" data-tab=\"mst\" data-ui-action=\"switch-tab\" role=\"tab\" id=\"tabbtn-mst\" aria-controls=\"tab-mst\" aria-selected=\"false\" tabindex=\"-1\">MST</button>"
    "<button class=\"service-segment\" data-tab=\"chat\" data-ui-action=\"switch-tab\" role=\"tab\" id=\"tabbtn-chat\" aria-controls=\"tab-chat\" aria-selected=\"false\" tabindex=\"-1\">Chat</button>"
    "<button class=\"service-segment\" data-tab=\"video\" data-ui-action=\"switch-tab\" role=\"tab\" id=\"tabbtn-video\" aria-controls=\"tab-video\" aria-selected=\"false\" tabindex=\"-1\">Video</button>"
    "</nav>"
    "<div class=\"admin-header-right\">"
    "<form method=\"post\" action=\"/admin/logout\" data-ui-form=\"logout\">"
    "<button type=\"submit\" class=\"btn btn-secondary btn-sm\">Logout</button></form></div></header>"
    "<main class=\"admin-content\">"
    /* Overview tab */
    "<div id=\"tab-overview\" class=\"tab-pane\" role=\"tabpanel\" aria-labelledby=\"tabbtn-overview\" tabindex=\"0\">"
    "<section class=\"admin-section\"><h2 class=\"admin-section-title\">Service Status</h2>"
    "<div id=\"overview\" hx-get=\"/admin/partials/overview\" hx-trigger=\"load, every 20s\"></div></section></div>"
    /* Connections tab */
    "<div id=\"tab-connections\" class=\"tab-pane\" role=\"tabpanel\" aria-labelledby=\"tabbtn-connections\" tabindex=\"0\" hidden>"
    "<section class=\"admin-section\"><h2 class=\"admin-section-title\">Service Connections</h2>\""
    "<p class=\"text-secondary text-sm mb-lg\">Configure URLs and admin tokens for each AT Protocol service. Changes apply immediately but are not persisted across restarts.</p>\""
    "<div id=\"connections-form\" hx-get=\"/admin/partials/connections\" hx-trigger=\"load\"></div></section></div>"
    /* PDS tab */
    "<div id=\"tab-pds\" class=\"tab-pane\" role=\"tabpanel\" aria-labelledby=\"tabbtn-pds\" tabindex=\"0\" hidden>"
    "<section class=\"admin-section\"><h2 class=\"admin-section-title\">Accounts</h2>"
    "<div class=\"search-row\"><form class=\"d-flex gap-sm flex-1\" hx-get=\"/admin/partials/accounts\" hx-target=\"#accounts\">"
    "<input type=\"text\" name=\"q\" placeholder=\"Search email or DID\" class=\"form-input flex-1\"/>"
    "<button type=\"submit\" class=\"btn btn-primary btn-sm\">Search</button></form></div>"
    "<div id=\"accounts\" hx-get=\"/admin/partials/accounts\" hx-trigger=\"load\"></div></section>"
    "<section class=\"admin-section\"><h2 class=\"admin-section-title\">Invite Codes</h2>"
    "<div id=\"invites\" hx-get=\"/admin/partials/invites\" hx-trigger=\"load\"></div>"
    "<div class=\"action-row\"><input id=\"disable-account\" type=\"text\" placeholder=\"DID to disable invites\" class=\"form-input flex-1\"/>"
    "<button class=\"btn btn-destructive btn-sm\" data-ui-action=\"disable-invites\">Disable Invites</button></div>"
    "<div class=\"action-row mt-sm\"><input id=\"enable-account\" type=\"text\" placeholder=\"DID to enable invites\" class=\"form-input flex-1\"/>"
    "<button class=\"btn btn-primary btn-sm\" data-ui-action=\"enable-invites\">Enable Invites</button></div>"
    "<div id=\"invite-action-result\" aria-live=\"polite\"></div></section>"
    "<section class=\"admin-section\"><h2 class=\"admin-section-title\">Server Stats</h2>"
    "<div id=\"pds-stats\" hx-get=\"/admin/partials/pds-stats\" hx-trigger=\"load, every 30s\"></div></section>"
    "<section class=\"admin-section\"><h2 class=\"admin-section-title\">Audit Log</h2>"
    "<div id=\"audit-log-content\" hx-get=\"/admin/partials/audit-log\" hx-trigger=\"load\"></div></section>"
    "<section class=\"admin-section\"><h2 class=\"admin-section-title\">Blobs</h2>"
    "<div id=\"blobs-content\" hx-get=\"/admin/partials/blobs\" hx-trigger=\"load\"></div></section>"
    "</div>"
    /* AppView tab */
    "<div id=\"tab-appview\" class=\"tab-pane\" role=\"tabpanel\" aria-labelledby=\"tabbtn-appview\" tabindex=\"0\" hidden>"
    "<section class=\"admin-section\"><h2 class=\"admin-section-title\">Metrics</h2>"
    "<div id=\"appview-metrics\" hx-get=\"/admin/partials/appview-metrics\" hx-trigger=\"load, every 30s\"></div></section>"
    "<section class=\"admin-section\"><h2 class=\"admin-section-title\">Ingest Health</h2>"
    "<div id=\"appview-ingest\" hx-get=\"/admin/partials/appview-ingest\" hx-trigger=\"load, every 30s\"></div></section>"
    "<section class=\"admin-section\"><h2 class=\"admin-section-title\">Backfill Queue</h2>"
    "<div id=\"appview-queue\" hx-get=\"/admin/partials/appview-queue\" hx-trigger=\"load, every 10s\"></div></section></div>"
    /* Relay tab */
    "<div id=\"tab-relay\" class=\"tab-pane\" role=\"tabpanel\" aria-labelledby=\"tabbtn-relay\" tabindex=\"0\" hidden>"
    "<section class=\"admin-section\"><h2 class=\"admin-section-title\">Relay Metrics</h2>"
    "<div id=\"relay-metrics\" hx-get=\"/admin/partials/relay-metrics\" hx-trigger=\"load, every 30s\"></div></section>"
    "<section class=\"admin-section\"><h2 class=\"admin-section-title\">Health</h2>"
    "<div id=\"relay-health\" hx-get=\"/admin/partials/relay-health\" hx-trigger=\"load, every 30s\"></div></section>"
    "<section class=\"admin-section\"><h2 class=\"admin-section-title\">Upstreams</h2>"
    "<div id=\"relay-upstreams\" hx-get=\"/admin/partials/relay-upstreams\" hx-trigger=\"load, every 30s\"></div></section>"
    "<section class=\"admin-section\"><h2 class=\"admin-section-title\">Request Crawl</h2>"
    "<div class=\"action-row\"><input id=\"crawl-hostname\" type=\"text\" placeholder=\"Hostname to crawl\" class=\"form-input flex-1\"/>"
    "<button class=\"btn btn-primary btn-sm\" data-ui-action=\"request-crawl\">Request Crawl</button></div>"
    "<div id=\"crawl-result\" aria-live=\"polite\"></div></section></div>"
    /* PLC tab */
    "<div id=\"tab-plc\" class=\"tab-pane\" role=\"tabpanel\" aria-labelledby=\"tabbtn-plc\" tabindex=\"0\" hidden>"
    "<section class=\"admin-section\"><h2 class=\"admin-section-title\">Health</h2>"
    "<div id=\"plc-health\" hx-get=\"/admin/partials/plc-health\" hx-trigger=\"load\"></div></section>"
    "<section class=\"admin-section\"><h2 class=\"admin-section-title\">Metrics</h2>"
    "<div id=\"plc-metrics\" hx-get=\"/admin/partials/plc-metrics\" hx-trigger=\"load\"></div></section>"
    "<section class=\"admin-section\"><h2 class=\"admin-section-title\">All DIDs</h2>"
    "<div id=\"plc-list\" hx-get=\"/admin/partials/plc-list\" hx-trigger=\"load\"></div></section>"
    "<section class=\"admin-section\"><h2 class=\"admin-section-title\">DID Lookup</h2>"
    "<div class=\"search-row\"><form class=\"d-flex gap-sm flex-1\" hx-get=\"/admin/partials/plc-did\" hx-target=\"#plc-did-result\">"
    "<input type=\"text\" name=\"did\" placeholder=\"did:plc:...\" class=\"form-input flex-1\"/>"
    "<button type=\"submit\" class=\"btn btn-primary btn-sm\">Lookup</button></form></div>"
    "<div id=\"plc-did-result\" aria-live=\"polite\"></div></section>"
    "<section class=\"admin-section\"><h2 class=\"admin-section-title\">DID Log</h2>"
    "<div class=\"search-row\"><form class=\"d-flex gap-sm flex-1\" hx-get=\"/admin/partials/plc-log\" hx-target=\"#plc-log-result\">"
    "<input type=\"text\" name=\"did\" placeholder=\"did:plc:...\" class=\"form-input flex-1\"/>"
    "<button type=\"submit\" class=\"btn btn-primary btn-sm\">View Log</button></form></div>"
    "<div id=\"plc-log-result\" aria-live=\"polite\"></div></section></div>"
    /* Explorer tab */
    "<div id=\"tab-explorer\" class=\"tab-pane\" role=\"tabpanel\" aria-labelledby=\"tabbtn-explorer\" tabindex=\"0\" hidden>"
    "<section class=\"admin-section\"><h2 class=\"admin-section-title\">Repo Explorer</h2>"
    "<div class=\"search-row\"><form class=\"d-flex gap-sm flex-1\" hx-get=\"/admin/partials/describe-repo\" hx-target=\"#repo-detail\">"
    "<input type=\"text\" name=\"did\" placeholder=\"did:plc:... or handle\" class=\"form-input flex-1\"/>"
    "<button type=\"submit\" class=\"btn btn-primary btn-sm\">Describe</button></form></div>"
    "<div id=\"repo-detail\"></div></section>"
    "<section class=\"admin-section\"><h2 class=\"admin-section-title\">List Records</h2>"
    "<div class=\"search-row\"><form class=\"d-flex gap-sm flex-1\" hx-get=\"/admin/partials/list-records\" hx-target=\"#records-list\">"
    "<input type=\"text\" name=\"did\" placeholder=\"did:plc:...\" class=\"form-input flex-1\"/>"
    "<input type=\"text\" name=\"collection\" placeholder=\"Collection (optional)\" class=\"form-input flex-1\"/>"
    "<button type=\"submit\" class=\"btn btn-primary btn-sm\">List</button></form></div>"
    "<div id=\"records-list\"></div></section>"
    "<section class=\"admin-section\"><h2 class=\"admin-section-title\">Get Record</h2>"
    "<div class=\"search-row\"><form class=\"d-flex gap-sm flex-1\" hx-get=\"/admin/partials/get-record\" hx-target=\"#record-detail\">"
    "<input type=\"text\" name=\"did\" placeholder=\"did:plc:...\" class=\"form-input flex-1\"/>"
    "<input type=\"text\" name=\"collection\" placeholder=\"Collection\" class=\"form-input flex-1\"/>"
    "<input type=\"text\" name=\"rkey\" placeholder=\"Record key\" class=\"form-input flex-1\"/>"
    "<button type=\"submit\" class=\"btn btn-primary btn-sm\">Get</button></form></div>"
    "<div id=\"record-detail\"></div></section></div>"
    /* Ozone tab */
    "<div id=\"tab-ozone\" class=\"tab-pane\" role=\"tabpanel\" aria-labelledby=\"tabbtn-ozone\" tabindex=\"0\" hidden>"
    "<section class=\"admin-section\"><h2 class=\"admin-section-title\">Moderation Statuses</h2>"
    "<div id=\"ozone-statuses\" hx-get=\"/admin/partials/ozone-statuses\" hx-trigger=\"load, every 30s\"></div></section>"
    "<section class=\"admin-section\"><h2 class=\"admin-section-title\">Moderation Events</h2>"
    "<div id=\"ozone-events\" hx-get=\"/admin/partials/ozone-events\" hx-trigger=\"load\"></div></section>"
    "<section class=\"admin-section\"><h2 class=\"admin-section-title\">Subject Status</h2>"
    "<div class=\"search-row\"><form class=\"d-flex gap-sm flex-1\" hx-get=\"/admin/partials/ozone-subject\" hx-target=\"#ozone-subject-result\">"
    "<input type=\"text\" name=\"did\" placeholder=\"did:plc:...\" class=\"form-input flex-1\"/>"
    "<button type=\"submit\" class=\"btn btn-primary btn-sm\">Lookup</button></form></div>"
    "<div id=\"ozone-subject-result\" aria-live=\"polite\"></div></section>"
    "<section class=\"admin-section\"><h2 class=\"admin-section-title\">Moderation Reports</h2>"
    "<div id=\"ozone-reports\" hx-get=\"/admin/partials/ozone-reports\" hx-trigger=\"load\"></div></section>"
    "<section class=\"admin-section\"><h2 class=\"admin-section-title\">Scheduled Actions</h2>"
    "<div id=\"ozone-scheduled\" hx-get=\"/admin/partials/ozone-scheduled\" hx-trigger=\"load\"></div></section>"
    "<section class=\"admin-section\"><h2 class=\"admin-section-title\">Verification</h2>"
    "<div id=\"ozone-verification\" hx-get=\"/admin/partials/ozone-verification\" hx-trigger=\"load\"></div></section>"
    "<section class=\"admin-section\"><h2 class=\"admin-section-title\">Safelinks</h2>"
    "<div id=\"ozone-safelinks\" hx-get=\"/admin/partials/ozone-safelinks\" hx-trigger=\"load\"></div></section>"
    "<section class=\"admin-section\"><h2 class=\"admin-section-title\">Settings</h2>"
    "<div id=\"ozone-settings\" hx-get=\"/admin/partials/ozone-settings\" hx-trigger=\"load\"></div></section>"
    "<section class=\"admin-section\"><h2 class=\"admin-section-title\">Signatures</h2>"
    "<div id=\"ozone-signatures\" hx-get=\"/admin/partials/ozone-signatures\" hx-trigger=\"load\"></div></section>"
    "<section class=\"admin-section\"><h2 class=\"admin-section-title\">Hosting History</h2>"
    "<div id=\"ozone-hosting\" hx-get=\"/admin/partials/ozone-hosting\" hx-trigger=\"load\"></div></section>"
    "<section class=\"admin-section\"><h2 class=\"admin-section-title\">Team Members</h2>"
    "<div id=\"ozone-team\" hx-get=\"/admin/partials/ozone-team\" hx-trigger=\"load\"></div></section>"
    "<section class=\"admin-section\"><h2 class=\"admin-section-title\">Sets</h2>"
    "<div id=\"ozone-sets\" hx-get=\"/admin/partials/ozone-sets\" hx-trigger=\"load\"></div></section>"
    "<section class=\"admin-section\"><h2 class=\"admin-section-title\">Templates</h2>"
    "<div id=\"ozone-templates\" hx-get=\"/admin/partials/ozone-templates\" hx-trigger=\"load\"></div></section>"
    "<section class=\"admin-section\"><h2 class=\"admin-section-title\">Configuration</h2>"
    "<div id=\"ozone-config\" hx-get=\"/admin/partials/ozone-config\" hx-trigger=\"load\"></div></section></div>"
    /* Security tab */
    "<div id=\"tab-security\" class=\"tab-pane\" role=\"tabpanel\" aria-labelledby=\"tabbtn-security\" tabindex=\"0\" hidden>"
    "<section class=\"admin-section\"><h2 class=\"admin-section-title\">Active Sessions</h2>"
    "<div class=\"search-row\"><form class=\"d-flex gap-sm flex-1\" hx-get=\"/admin/partials/sessions\" hx-target=\"#sessions-result\">"
    "<input type=\"text\" name=\"did\" placeholder=\"did:plc:...\" class=\"form-input flex-1\"/>"
    "<button type=\"submit\" class=\"btn btn-primary btn-sm\">Lookup</button></form></div>"
    "<div id=\"sessions-result\" aria-live=\"polite\"></div></section>"
    "<section class=\"admin-section\"><h2 class=\"admin-section-title\">App Passwords</h2>"
    "<div class=\"search-row\"><form class=\"d-flex gap-sm flex-1\" hx-get=\"/admin/partials/app-passwords\" hx-target=\"#app-passwords-result\">"
    "<input type=\"text\" name=\"did\" placeholder=\"did:plc:...\" class=\"form-input flex-1\"/>"
    "<button type=\"submit\" class=\"btn btn-primary btn-sm\">Lookup</button></form></div>"
    "<div id=\"app-passwords-result\" aria-live=\"polite\"></div></section></div>"
    /* MST Viewer tab */
    "<div id=\"tab-mst\" class=\"tab-pane\" role=\"tabpanel\" aria-labelledby=\"tabbtn-mst\" tabindex=\"0\" hidden>"
    "<section class=\"admin-section\"><h2 class=\"admin-section-title\">MST Accounts</h2>"
    "<div id=\"mst-accounts\" hx-get=\"/admin/partials/mst-accounts\" hx-trigger=\"load\"></div></section>"
    "<section class=\"admin-section\"><h2 class=\"admin-section-title\">MST Tree</h2>"
    "<div class=\"search-row\"><form class=\"d-flex gap-sm flex-1\" hx-get=\"/admin/partials/mst-tree\" hx-target=\"#mst-tree-result\">"
    "<input type=\"text\" name=\"did\" placeholder=\"did:plc:...\" class=\"form-input flex-1\"/>"
    "<button type=\"submit\" class=\"btn btn-primary btn-sm\">View Tree</button></form></div>"
    "<div id=\"mst-tree-result\" aria-live=\"polite\"></div></section>"
    "<section class=\"admin-section\"><h2 class=\"admin-section-title\">MST Statistics</h2>"
    "<div class=\"search-row\"><form class=\"d-flex gap-sm flex-1\" hx-get=\"/admin/partials/mst-stats\" hx-target=\"#mst-stats-result\">"
    "<input type=\"text\" name=\"did\" placeholder=\"did:plc:...\" class=\"form-input flex-1\"/>"
    "<button type=\"submit\" class=\"btn btn-primary btn-sm\">View Stats</button></form></div>"
    "<div id=\"mst-stats-result\" aria-live=\"polite\"></div></section>"
    "<section class=\"admin-section\"><h2 class=\"admin-section-title\">Export MST</h2>"
    "<div class=\"action-row\"><input id=\"mst-export-did\" type=\"text\" placeholder=\"did:plc:...\" class=\"form-input flex-1\"/>"
    "<select id=\"mst-export-format\" class=\"form-input flex-none\"><option value=\"json\">JSON</option><option value=\"dot\">DOT</option><option value=\"svg\">SVG</option></select>"
    "<button class=\"btn btn-primary btn-sm\" data-ui-action=\"export-mst\">Export</button></div>"
    "<div id=\"mst-export-result\" aria-live=\"polite\"></div></section></div>"
    /* Chat tab */
    "<div id=\"tab-chat\" class=\"tab-pane\" role=\"tabpanel\" aria-labelledby=\"tabbtn-chat\" tabindex=\"0\" hidden>"
    "<section class=\"admin-section\"><h2 class=\"admin-section-title\">Conversations</h2>"
    "<div id=\"chat-convos\" hx-get=\"/admin/partials/chat-convos\" hx-trigger=\"load, every 20s\"></div></section>"
    "<section class=\"admin-section\"><h2 class=\"admin-section-title\">Messages</h2>"
    "<div class=\"action-row\"><input id=\"chat-convo-id\" type=\"text\" placeholder=\"Conversation ID\" class=\"form-input flex-1\"/>"
    "<button class=\"btn btn-primary btn-sm\" data-ui-action=\"load-chat-messages\">Load Messages</button></div>"
    "<div id=\"chat-messages\" hx-trigger=\"load\"></div>"
    "<div id=\"chat-action-result\" aria-live=\"polite\"></div></section></div>"
    /* Video tab */
    "<div id=\"tab-video\" class=\"tab-pane\" role=\"tabpanel\" aria-labelledby=\"tabbtn-video\" tabindex=\"0\" hidden>"
    "<section class=\"admin-section\"><h2 class=\"admin-section-title\">Service Health</h2>"
    "<div id=\"video-health\" hx-get=\"/admin/partials/video-health\" hx-trigger=\"load, every 30s\"></div></section>"
    "<section class=\"admin-section\"><h2 class=\"admin-section-title\">Job Queue</h2>"
    "<div class=\"action-row\">"
    "<button class=\"btn btn-secondary btn-sm\" data-ui-action=\"filter-video-jobs\" data-ui-state=\"\">All</button>"
    "<button class=\"btn btn-secondary btn-sm\" data-ui-action=\"filter-video-jobs\" data-ui-state=\"PENDING\">Pending</button>"
    "<button class=\"btn btn-secondary btn-sm\" data-ui-action=\"filter-video-jobs\" data-ui-state=\"PROCESSING\">Processing</button>"
    "<button class=\"btn btn-secondary btn-sm\" data-ui-action=\"filter-video-jobs\" data-ui-state=\"COMPLETED\">Completed</button>"
    "<button class=\"btn btn-secondary btn-sm\" data-ui-action=\"filter-video-jobs\" data-ui-state=\"FAILED\">Failed</button>"
    "</div>"
    "<div id=\"video-jobs\" hx-get=\"/admin/partials/video-jobs\" hx-trigger=\"load, every 10s\"></div></section>"
    "<section class=\"admin-section\"><h2 class=\"admin-section-title\">Upload Quotas</h2>"
    "<div id=\"video-quotas\" hx-get=\"/admin/partials/video-quotas\" hx-trigger=\"load\"></div></section>"
    "<section class=\"admin-section\"><h2 class=\"admin-section-title\">Job Lookup</h2>"
    "<div class=\"action-row\"><input id=\"video-job-id\" type=\"text\" placeholder=\"Job ID\" class=\"form-input flex-1\"/>"
    "<button class=\"btn btn-primary btn-sm\" data-ui-action=\"load-video-job-detail\">Look Up</button></div>"
    "<div id=\"video-job-detail\"></div></section></div>"
    "</main>"
    "<footer class=\"admin-footer\"><span class=\"version-info\"></span>"
    "<span id=\"footer-status\"></span></footer>"
    "</div>"
    "<script type=\"module\" src=\"/js/admin-ui.js\"></script>"
    "</body></html>", csrfNonce, nonce];
}

- (NSString *)renderAccountsPartial:(NSDictionary *)result {
    NSArray<NSDictionary *> *accounts = [result[@"accounts"] isKindOfClass:[NSArray class]] ? result[@"accounts"] : @[];
    NSMutableString *html = [NSMutableString stringWithString:@""];
    
    if (accounts.count > 0) {
        [html appendString:@"<div class=\"bulk-actions mb-sm d-flex gap-sm\">"
         "<button class=\"btn btn-secondary btn-sm\" data-ui-action=\"bulk-action\" data-ui-action-kind=\"takedown\">Bulk Takedown</button>"
         "<button class=\"btn btn-destructive btn-sm\" data-ui-action=\"bulk-action\" data-ui-action-kind=\"delete\">Bulk Delete</button>"
         "</div>"];
    }

    [html appendString:@"<table class=\"table\"><thead><tr><th><input type=\"checkbox\" id=\"select-all-accounts\" data-ui-action=\"toggle-select-all\"></th><th>DID</th><th>Handle</th><th>Email</th></tr></thead><tbody>"];
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
    NSMutableString *html = [NSMutableString stringWithString:@"<div id=\"appview-result\" aria-live=\"polite\"></div><div class=\"mb-lg\"><button class=\"btn btn-secondary btn-sm\" data-ui-action=\"rebuild-appview-scope\">Rebuild Relevance Set</button></div><form class=\"form mb-lg\" data-ui-form=\"enqueue-backfill\"><div class=\"form-group\"><label for=\"enqueue-dids-input\">Enqueue DIDs (one per line):</label><textarea id=\"enqueue-dids-input\" class=\"form-input\" placeholder=\"did:plc:...\"></textarea></div><button type=\"submit\" class=\"btn btn-primary btn-sm\">Enqueue</button></form><table class=\"table\" id=\"queue-table\"><thead><tr><th>DID</th><th>Status</th><th>Actions</th></tr></thead><tbody>"];
    NSArray<NSDictionary *> *entries = [result[@"entries"] isKindOfClass:[NSArray class]] ? result[@"entries"] : @[];
    for (NSDictionary *entry in entries) {
        NSString *did = UIEscaped(entry[@"did"] ?: @"");
        NSString *status = UIEscaped(entry[@"status"] ?: @"");
        NSString *statusBadge = [status isEqualToString:@"running"] ? @"badge badge-success" :
                                [status isEqualToString:@"failed"] ? @"badge badge-destructive" : @"badge badge-secondary";
        [html appendFormat:@"<tr><td class=\"text-mono text-xs\">%@</td><td><span class=\"%@\">%@</span></td><td>", did, statusBadge, status];
        [html appendFormat:@"<button class=\"btn btn-sm btn-primary\" data-ui-action=\"appview-retry-repo\" data-ui-did=\"%@\">Retry</button> ", did];
        [html appendFormat:@"<button class=\"btn btn-secondary btn-sm\" data-ui-action=\"appview-cancel-repo\" data-ui-did=\"%@\">Cancel</button>", did];
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
    NSMutableString *html = [NSMutableString stringWithString:@"<div id=\"account-detail-result\" aria-live=\"polite\"></div><div class=\"detail-grid\">"];
    NSArray *fields = @[@"did", @"handle", @"email", @"emailConfirmed", @"invitesDisabled", @"deactivatedAt"];
    for (NSString *key in fields) {
        id val = result[key];
        if (!val) continue;
        NSString *display = [val isKindOfClass:[NSString class]] ? UIEscaped(val) : UIEscaped([val description]);
        [html appendFormat:@"<div class=\"detail-field\"><span class=\"detail-label\">%@</span><span class=\"detail-value\">%@</span></div>", key, display];
    }
    [html appendFormat:@"</div><div class=\"mt-lg\"><button class=\"btn btn-destructive btn-sm\" data-ui-action=\"delete-account\" data-ui-did=\"%@\">Delete Account</button></div>", UIEscaped(did)];
    return html;
}

- (NSString *)renderBlobsPartial:(NSDictionary *)result did:(nullable NSString *)did {
    NSMutableString *html = [NSMutableString stringWithString:@"<div class=\"mb-lg\"><form class=\"d-flex gap-sm\" data-ui-form=\"load-blobs\"><input type=\"text\" id=\"blob-did-input\" class=\"form-input flex-1\" placeholder=\"did:plc:...\" value=\""];
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
    NSMutableString *html = [NSMutableString stringWithString:@"<div id=\"pds-reports-result\" aria-live=\"polite\"></div><table class=\"table\"><thead><tr><th>ID</th><th>Created At</th><th>Status</th><th>Actions</th></tr></thead><tbody>"];
    for (NSDictionary *report in reports) {
        NSString *reportID = UIEscaped(report[@"id"] ?: @"");
        NSString *createdAt = UIEscaped(report[@"createdAt"] ?: @"");
        NSString *status = UIEscaped(report[@"status"] ?: @"unknown");
        [html appendFormat:@"<tr><td class=\"text-mono text-xs\">%@</td><td class=\"text-xs\">%@</td><td>%@</td><td><select class=\"form-input\" data-ui-action=\"resolve-pds-report\" data-ui-report-id=\"%@\"><option value=\"\">Resolve as...</option><option value=\"escalate\">Escalate</option><option value=\"mute\">Mute</option><option value=\"markResolved\">Mark Resolved</option></select></td></tr>", reportID, createdAt, status, reportID];
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


@end
