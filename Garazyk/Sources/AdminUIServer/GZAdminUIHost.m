// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/GZAdminUIHost.h"

#import "AdminUIServer/GZAdminUIPack.h"
#import "AdminUIServer/GZHTML.h"
#import "AdminUIServer/UIAuthManager.h"
#import "AdminUIServer/GZAdminUIBackendClient.h"
#import "AdminUIServer/UIServiceConfig.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"
#import "Auth/Crypto/CryptoUtils.h"
#import "Debug/GZLogger.h"
#import "AdminUIServer/GZAdminUIHost+Private.h"
#import "AdminUIServer/UITemplateEngine.h"

NSString *GZAdminUIEscaped(NSString *value) {
    if (![value isKindOfClass:[NSString class]]) {
        return @"";
    }
    return [GZHTML escapedString:value];
}

NSString *GZAdminUIHealthBadge(NSString *health) {
    return [GZHTML healthBadge:health];
}

NSString *GZAdminUIConnectionBadge(NSString *status) {
    return [GZHTML connectionBadge:status];
}

NSString *GZAdminUIDetailRow(NSString *label, NSString *valueHTML) {
    return [GZHTML detailRowWithLabel:label valueHTML:valueHTML];
}

NSString *GZAdminUIJSONViewer(id value) {
    return [GZHTML jsonViewerWithValue:value];
}

NSString *GZAdminUIMonoValue(id value) {
    return [GZHTML monoValue:value];
}

static BOOL GZAdminUIRequestIsSecure(ATProtoHttpRequest *request) {
    NSString *forwarded = [request headerForKey:@"X-Forwarded-Proto"];
    if ([[forwarded lowercaseString] isEqualToString:@"https"]) {
        return YES;
    }
    return NO;
}

NSString *GZAdminUIDetailCardOpen(void) { return [GZHTML detailCardOpening]; }
NSString *GZAdminUIDetailCardClose(void) { return [GZHTML detailCardClosing]; }

NSString *GZAdminUISectionTitle(NSString *title) {
    return [GZHTML sectionTitle:title];
}

NSString *GZAdminUIFormatUptime(int64_t seconds) {
    return [GZHTML formatUptime:seconds];
}

NSString *GZAdminUIFormatMegabytes(int64_t bytes) {
    return [GZHTML formatMegabytes:bytes];
}

/// Safely extract a string from a dictionary, treating NSNull and non-string values as nil.
NSString * _Nullable GZAdminUIStringFromDict(NSDictionary *dict, NSString *key) {
    id value = dict[key];
    if ([value isKindOfClass:[NSString class]]) {
        return value;
    }
    return nil;
}

/// Safely convert any value (including NSNull) to an NSString, returning fallback for non-strings.
NSString *GZAdminUISafe(id value, NSString *fallback) {
    if ([value isKindOfClass:[NSString class]]) {
        return value;
    }
    return fallback ?: @"";
}

/// Safely get .length from a value that might be NSNull.
NSUInteger GZAdminUISafeLength(id value) {
    if ([value isKindOfClass:[NSString class]]) {
        return [(NSString *)value length];
    }
    return 0;
}


NSString *GZAdminUIGenerateNonce(void) {
    NSData *data = [ATProtoCryptoUtils randomBytes:16];
    return [ATProtoCryptoUtils base64URLEncode:data];
}

void GZAdminUIApplyNonceCSP(ATProtoHttpResponse *response, NSString *nonce, NSString *pdsOrigin) {
    NSString *csp;
    if (pdsOrigin) {
        csp = [NSString stringWithFormat:
            @"default-src 'self'; "
            "script-src 'self' 'nonce-%@' https://unpkg.com; "
            "script-src-attr 'none'; "
            "style-src 'self' 'unsafe-inline'; "
            "img-src 'self' data:; "
            "connect-src 'self' %@;",
            nonce, pdsOrigin];
    } else {
        csp = [NSString stringWithFormat:
            @"default-src 'self'; "
            "script-src 'self' 'nonce-%@' https://unpkg.com; "
            "script-src-attr 'none'; "
            "style-src 'self' 'unsafe-inline'; "
            "img-src 'self' data:;",
            nonce];
    }
    [response setHeader:csp forKey:@"content-security-policy"];
}

static NSString *GZAdminUIHxTriggerForRefreshSeconds(id refreshSeconds) {
    if ([refreshSeconds respondsToSelector:@selector(integerValue)]) {
        NSInteger seconds = [refreshSeconds integerValue];
        if (seconds <= 0) {
            return @"revealed";
        }
        return [NSString stringWithFormat:@"revealed, every %lds", (long)seconds];
    }
    // Interactive panes (forms, DID inputs) must not auto-reload — that wipes
    // in-progress operator input. Packs that want polling set refreshSeconds.
    return @"revealed";
}

static NSArray<NSDictionary<NSString *, NSString *> *> *GZAdminUIShellTabs(NSArray<Class> *packs,
                                                                            NSString * _Nullable serviceIdentifier) {
    NSMutableArray<NSDictionary<NSString *, NSString *> *> *tabs = [NSMutableArray array];
    // Service-scoped embeds (ADR 0033) drop fleet Overview/Connections from the
    // shared PDS pack; those panels belong to the compatibility host only.
    BOOL omitFleetTabs = serviceIdentifier.length > 0;
    for (Class<GZAdminUIPack> packClass in packs) {
        for (NSDictionary<NSString *, id> *section in [packClass sidebarSections]) {
            NSString *identifier = section[@"tabIdentifier"];
            NSString *displayName = section[@"displayName"];
            if (identifier.length == 0 || displayName.length == 0) {
                continue;
            }
            if (omitFleetTabs &&
                ([identifier isEqualToString:@"overview"] ||
                 [identifier isEqualToString:@"connections"])) {
                continue;
            }
            [tabs addObject:@{
                @"tabIdentifier": identifier,
                @"displayName": displayName,
                @"hxTrigger": GZAdminUIHxTriggerForRefreshSeconds(section[@"refreshSeconds"]),
            }];
        }
    }

    NSMutableArray<NSDictionary<NSString *, NSString *> *> *renderedTabs = [NSMutableArray arrayWithCapacity:tabs.count];
    [tabs enumerateObjectsUsingBlock:^(NSDictionary<NSString *, NSString *> *tab, NSUInteger index, BOOL *stop) {
        NSMutableDictionary<NSString *, NSString *> *renderedTab = [tab mutableCopy];
        BOOL active = index == 0;
        renderedTab[@"activeClass"] = active ? @" active" : @"";
        renderedTab[@"ariaSelected"] = active ? @"true" : @"false";
        renderedTab[@"tabIndex"] = active ? @"0" : @"-1";
        if (renderedTab[@"hxTrigger"].length == 0) {
            renderedTab[@"hxTrigger"] = @"revealed";
        }
        [renderedTabs addObject:[renderedTab copy]];
    }];
    return renderedTabs;
}


@interface ATProtoHttpServer (GZAdminUIHostTesting)
- (ATProtoHttpResponse *)dispatchRequest:(ATProtoHttpRequest *)request;
@end

@implementation GZAdminUIHost

- (instancetype)initWithConfiguration:(GZAdminUIServiceConfig *)configuration
                                 packs:(NSArray<Class> *)packs {
    self = [super init];
    if (self) {
        _configuration = configuration;
        _packs = [packs copy];
        _authManager = [[GZAdminUIAuthManager alloc] initWithPassword:configuration.adminPassword ?: @""
                                                     serviceIdentifier:configuration.serviceIdentifier];
        _backendClient = [[GZAdminUIBackendClient alloc] initWithConfiguration:configuration];
        // Auto-obtain PDS admin ATProtoJWT if a password is configured but no token
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

    self.httpServer = [ATProtoHttpServer serverWithHost:self.configuration.host
                                                    port:self.configuration.port
                                   maxConcurrentRequests:8];
    if (!self.httpServer) {
        if (error) {
            *error = [NSError errorWithDomain:@"GZAdminUIHost"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to create HTTP server"}];
        }
        return NO;
    }

    // Keep the compatibility consumer's two local discovery responses without
    // pulling the service XRPC dispatcher into the transport-only UI library.
    [self.httpServer addRoute:@"GET" path:@"/xrpc/_health" handler:^(ATProtoHttpRequest *req, ATProtoHttpResponse *res) {
        res.statusCode = 200;
        [res setJsonBody:@{@"version": @"1.0.0"}];
    }];

    [self.httpServer addRoute:@"GET" path:@"/xrpc/com.atproto.server.describeServer" handler:^(ATProtoHttpRequest *req, ATProtoHttpResponse *res) {
        res.statusCode = 200;
        [res setJsonBody:@{
            @"availableUserDomains": @[],
            @"inviteCodeRequired": @YES,
            @"phoneVerificationRequired": @NO
        }];
    }];

    [ATProtoHttpResponse setDefaultServerHeader:@"garazyk-admin/1.0.0"];
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

- (ATProtoHttpResponse *)dispatchRequestForTesting:(ATProtoHttpRequest *)request {
    if (!self.httpServer) {
        self.httpServer = [ATProtoHttpServer serverWithHost:self.configuration.host
                                                        port:self.configuration.port
                                       maxConcurrentRequests:8];
        [self registerRoutes];
    }
    return [self.httpServer dispatchRequest:request];
}

- (void)registerRoutes {
    __weak typeof(self) weakSelf = self;

    // Static asset serving: /css/*, /js/*, /img/* (prefix routes via addHandlerForPath)
    [self.httpServer addHandlerForPath:@"/css/" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        [weakSelf serveStaticAssetForPath:request.path response:response];
    }];

    [self.httpServer addHandlerForPath:@"/js/" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        [weakSelf serveStaticAssetForPath:request.path response:response];
    }];

    [self.httpServer addHandlerForPath:@"/img/" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        [weakSelf serveStaticAssetForPath:request.path response:response];
    }];

    [self.httpServer addRoute:@"GET" path:@"/" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        response.statusCode = 302;
        [response setHeader:@"/admin" forKey:@"Location"];
        response.contentType = @"text/plain; charset=utf-8";
        [response setBodyString:@"Redirecting\n"];
    }];

    [self.httpServer addRoute:@"GET" path:@"/admin/login" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        NSString *nonce = GZAdminUIGenerateNonce();
        NSString *csrfNonce, *csrfCookie;
        BOOL secure = GZAdminUIRequestIsSecure(request);
        [weakSelf.authManager createCSRFNonce:&csrfNonce cookie:&csrfCookie secure:secure];
        [response setHeader:csrfCookie forKey:@"Set-Cookie"];
        GZAdminUIApplyNonceCSP(response, nonce, nil);
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf loginPageHTML:nonce csrfNonce:csrfNonce]];
    }];

    [self.httpServer addRoute:@"POST" path:@"/admin/login" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        BOOL secure = GZAdminUIRequestIsSecure(request);
        // Always mint a fresh CSRF nonce for the next attempt. validateCSRF
        // consumes the presented nonce even when the password is wrong, so
        // retries on the same page would otherwise 403 and the browser UI
        // mislabels that as "Invalid credentials".
        void (^rotateCSRF)(void) = ^{
            NSString *nextNonce, *nextCookie;
            [weakSelf.authManager createCSRFNonce:&nextNonce cookie:&nextCookie secure:secure];
            [response setHeader:nextCookie forKey:@"Set-Cookie"];
            [response setHeader:nextNonce forKey:@"X-UI-Admin-Nonce"];
        };

        if (![weakSelf.authManager validateCSRFForRequest:request]) {
            rotateCSRF();
            response.statusCode = 403;
            [response setJsonBody:@{@"ok": @NO, @"error": @"invalid_csrf_token"}];
            return;
        }
        NSString *password = request.jsonBody[@"password"];
        if (![weakSelf.authManager validatePassword:password]) {
            rotateCSRF();
            response.statusCode = 401;
            [response setJsonBody:@{@"ok": @NO, @"error": @"invalid_credentials"}];
            return;
        }
        NSString *token = [weakSelf.authManager createSessionToken];
        NSString *cookie = [weakSelf.authManager cookieHeaderValueForToken:token secure:secure];
        [response setHeader:cookie forKey:@"Set-Cookie"];
        response.statusCode = 200;
        [response setJsonBody:@{@"ok": @YES}];
    }];

    [self.httpServer addRoute:@"POST" path:@"/admin/logout" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *token = [weakSelf.authManager extractTokenFromRequest:request];
        [weakSelf.authManager invalidateSessionToken:token];
        BOOL secure = GZAdminUIRequestIsSecure(request);
        NSString *clear = [NSString stringWithFormat:
                                @"%@=; Path=/; Max-Age=0; HttpOnly; SameSite=Strict%@",
                                weakSelf.authManager.sessionCookieName,
                                secure ? @"; Secure" : @""];
        [response setHeader:clear forKey:@"Set-Cookie"];
        response.statusCode = 200;
        [response setJsonBody:@{@"ok": @YES}];
    }];

    [self.httpServer addRoute:@"GET" path:@"/admin" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *nonce = GZAdminUIGenerateNonce();
        NSString *csrfNonce, *csrfCookie;
        BOOL secure = GZAdminUIRequestIsSecure(request);
        [weakSelf.authManager createCSRFNonce:&csrfNonce cookie:&csrfCookie secure:secure];
        [response setHeader:csrfCookie forKey:@"Set-Cookie"];
        GZAdminUIApplyNonceCSP(response, nonce, [weakSelf.configuration.pdsBaseURL absoluteString]);
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf adminShellHTML:nonce csrfNonce:csrfNonce]];
    }];
    for (Class packClass in self.packs) {
        [packClass registerRoutesWithHost:self];
    }
}

- (BOOL)ensureAuthorized:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response {
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
    BOOL secure = GZAdminUIRequestIsSecure(request);
    [self.authManager createCSRFNonce:&nextNonce cookie:&nextNonceCookie secure:secure];
    [response setHeader:nextNonceCookie forKey:@"Set-Cookie"];
    [response setHeader:nextNonce forKey:@"X-UI-Admin-Nonce"];
    return YES;
}

- (NSString *)loginPageHTML:(NSString *)nonce csrfNonce:(NSString *)csrfNonce {
    NSString *serviceDisplayName = @"Admin";
    NSString *packDisplayName = nil;
    if (self.packs.count == 1) {
        Class<GZAdminUIPack> packClass = self.packs.firstObject;
        packDisplayName = [packClass displayName];
    }
    if (packDisplayName.length > 0) {
        serviceDisplayName = packDisplayName;
    } else if (self.configuration.serviceIdentifier.length > 0) {
        serviceDisplayName = [self.configuration.serviceIdentifier uppercaseString];
    }
    return [GZAdminUITemplateEngine renderTemplate:@"login" context:@{
        @"nonce": nonce ?: @"",
        @"csrfNonce": csrfNonce ?: @"",
        @"serviceDisplayName": serviceDisplayName,
    }];
}

- (NSString *)adminShellHTML:(NSString *)nonce csrfNonce:(NSString *)csrfNonce {
    NSString *serviceIdentifier = self.configuration.serviceIdentifier;
    NSArray<NSDictionary<NSString *, NSString *> *> *tabs =
        GZAdminUIShellTabs(self.packs, serviceIdentifier);
    NSString *activeTabIdentifier = tabs.firstObject[@"tabIdentifier"] ?: @"pds";
    // One pack OR a service-scoped embed = single service surface.
    BOOL isSingleSurface = self.packs.count == 1 || serviceIdentifier.length > 0;
    NSString *shellTitle = @"Garazyk UI Service";
    NSString *packDisplayName = nil;
    if (self.packs.count == 1) {
        Class<GZAdminUIPack> packClass = self.packs.firstObject;
        packDisplayName = [packClass displayName];
    }
    if (self.packs.count == 1 && packDisplayName.length > 0) {
        shellTitle = packDisplayName;
    } else if (self.packs.count == 1 && tabs.firstObject[@"displayName"].length > 0) {
        shellTitle = tabs.firstObject[@"displayName"];
    } else if (serviceIdentifier.length > 0) {
        shellTitle = [serviceIdentifier uppercaseString];
    }

    NSSet<NSString *> *knownPanels = [NSSet setWithArray:@[
        @"pds", @"appview", @"relay", @"plc"
    ]];
    NSMutableSet<NSString *> *tabIdentifiers = [NSMutableSet set];
    for (NSDictionary<NSString *, NSString *> *tab in tabs) {
        NSString *identifier = tab[@"tabIdentifier"];
        if (identifier.length > 0) {
            [tabIdentifiers addObject:identifier];
        }
    }

    // Dynamic panes: tabs whose identifiers don't match a known hardcoded pane.
    // Embedded service packs (Mikrus, Beskid) use tabIdentifiers like "mikrus",
    // "beskid" that need a generic pane rendered from this list.
    NSMutableArray<NSDictionary<NSString *, NSString *> *> *dynamicPanes = [NSMutableArray array];
    for (NSDictionary<NSString *, NSString *> *tab in tabs) {
        NSString *identifier = tab[@"tabIdentifier"];
        if (identifier.length > 0 && ![knownPanels containsObject:identifier]) {
            BOOL active = [identifier isEqualToString:activeTabIdentifier];
            [dynamicPanes addObject:@{
                @"tabIdentifier": identifier,
                @"displayName": tab[@"displayName"] ?: identifier,
                @"activeClass": active ? @" active" : @"",
                @"hidden": active ? @"" : @"hidden",
                @"ariaLabelledby": [NSString stringWithFormat:@"tabbtn-%@", identifier],
                @"tabIndex": active ? @"0" : @"-1",
                @"hxTrigger": tab[@"hxTrigger"] ?: @"revealed",
            }];
        }
    }

    // Determine if the active tab is a dynamic pane (no known-panel match).
    // When YES the hardcoded panes are all hidden and the dynamic loop renders
    // the visible panes.
    BOOL activeIsDynamic = ![knownPanels containsObject:activeTabIdentifier];

    NSMutableDictionary<NSString *, id> *context = [@{
        @"nonce": nonce ?: @"",
        @"csrfNonce": csrfNonce ?: @"",
        @"tabs": tabs,
        @"isSingleSurface": @(isSingleSurface),
        @"shellTitle": shellTitle,
        @"peerLinks": self.configuration.peerLinks ?: @[],
        @"showPeerSwitcher": @(isSingleSurface),
        @"includePDSPanel": @([tabIdentifiers containsObject:@"pds"]),
        @"includeAppViewPanel": @([tabIdentifiers containsObject:@"appview"]),
        @"includeRelayPanel": @([tabIdentifiers containsObject:@"relay"]),
        @"includePLCPanel": @([tabIdentifiers containsObject:@"plc"]),
        @"dynamicPanes": dynamicPanes,
    } mutableCopy];
    NSDictionary<NSString *, NSString *> *panelContextKeys = @{
        @"pds": @"activePDS",
        @"appview": @"activeAppView",
        @"relay": @"activeRelay",
        @"plc": @"activePLC",
    };
    [panelContextKeys enumerateKeysAndObjectsUsingBlock:^(NSString *identifier, NSString *key, BOOL *stop) {
        context[key] = @(!activeIsDynamic && [identifier isEqualToString:activeTabIdentifier]);
    }];
    return [GZAdminUITemplateEngine renderTemplate:@"shell" context:context];
}

@end
