// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/GZAdminUIHost.h"
#import "AdminUIServer/GZAdminUIHost+Private.h"
#import "AdminUIServer/Packs/GZAdminUILabPack.h"
#import "AdminUIServer/UIAuthManager.h"
#import "AdminUIServer/GZAdminUIBackendClient.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"
#import "AdminUIServer/UITileDataProtocol.h"
#import "AdminUIServer/UITileExecutionPolicy.h"
#import "AdminUIServer/UITileLoadingHost.h"
#import "AdminUIServer/UITileDemoPathResolver.h"
#import "AdminUIServer/UITilePathResolver.h"

@implementation GZAdminUIHost (LabRoutes)

- (id<GZAdminUITilePathResolver>)effectiveTilePathResolver {
    if ([self.tilePathResolver conformsToProtocol:@protocol(GZAdminUITilePathResolver)]) {
        return self.tilePathResolver;
    }
    static GZAdminUIDemoTilePathResolver *demo;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        demo = [[GZAdminUIDemoTilePathResolver alloc] init];
    });
    return demo;
}

- (void)registerLabRoutes {
    __weak typeof(self) weakSelf = self;

    // Lab: Public OAuth2 user self-service portal (no admin auth required)
    [self.httpServer addRoute:@"GET" path:@"/lab" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        NSString *nonce = GZAdminUIGenerateNonce();
        GZAdminUIApplyNonceCSP(response, nonce, [weakSelf.configuration.pdsBaseURL absoluteString]);
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[GZAdminUILabPack labShellHTMLWithNonce:nonce configuration:weakSelf.configuration]];
    }];

    [self.httpServer addRoute:@"GET" path:@"/lab/callback" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        NSString *nonce = GZAdminUIGenerateNonce();
        GZAdminUIApplyNonceCSP(response, nonce, [weakSelf.configuration.pdsBaseURL absoluteString]);
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[GZAdminUILabPack labShellHTMLWithNonce:nonce configuration:weakSelf.configuration]];
    }];

    [self.httpServer addRoute:@"GET" path:@"/lab/client-metadata.json" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        response.statusCode = 200;
        response.contentType = @"application/json; charset=utf-8";
        [response setBodyString:[GZAdminUILabPack labClientMetadataJSONWithConfiguration:weakSelf.configuration]];
    }];

    // Live tile embed (parent page). Requires tilesBaseHost.
    [self.httpServer addRoute:@"GET" path:@"/lab/tiles/embed" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        NSString *baseHost = weakSelf.configuration.tilesBaseHost;
        if (baseHost.length == 0) {
            response.statusCode = 503;
            response.contentType = @"text/plain; charset=utf-8";
            [response setBodyString:@"tilesBaseHost is not configured\n"];
            return;
        }
        NSString *scheme = [request headerForKey:@"X-Forwarded-Proto"];
        if (scheme.length == 0) scheme = @"http";
        NSString *hostHeader = [request headerForKey:@"Host"];
        NSString *parentOrigin = [NSString stringWithFormat:@"%@://%@", scheme,
                                  hostHeader.length > 0 ? hostHeader : @"localhost"];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:GZAdminUITileEmbedHTML(scheme, baseHost, parentOrigin)];
    }];

    // Mothership HTTP boundary for resolve-path (injected or demo fixture).
    [self.httpServer addRoute:@"POST" path:@"/lab/tiles/mothership" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        NSError *jsonError = nil;
        id body = request.body.length > 0
            ? [NSJSONSerialization JSONObjectWithData:request.body options:0 error:&jsonError]
            : @{};
        if (![body isKindOfClass:[NSDictionary class]]) {
            response.statusCode = 400;
            response.contentType = @"application/json; charset=utf-8";
            [response setBodyString:@"{\"error\":\"expected JSON object\"}"];
            return;
        }
        NSDictionary *reply = [[weakSelf effectiveTilePathResolver] handleTileRequest:body];
        NSData *out = [NSJSONSerialization dataWithJSONObject:reply options:0 error:nil];
        response.statusCode = 200;
        response.contentType = @"application/json; charset=utf-8";
        [response setBodyData:out ?: [@"{\"error\":\"encode failed\"}" dataUsingEncoding:NSUTF8StringEncoding]];
    }];

    // Reserved Web Tiles protocol endpoint. Optional ?trustedOrigin= gates
    // postMessage peers (used by unique-origin embeds).
    [self.httpServer addRoute:@"GET" path:@"/.well-known/web-tiles/data.js" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        NSString *trusted = request.queryParams[@"trustedOrigin"];
        if (![trusted isKindOfClass:[NSString class]] || trusted.length == 0) {
            trusted = nil;
        }
        response.statusCode = 200;
        response.contentType = @"application/javascript; charset=utf-8";
        [response setBodyString:GZAdminUITileDataProtocolJavaScriptWithTrustedOrigin(trusted)];
    }];

    // Unique-origin shuttle shell. When tilesBaseHost is configured, Host
    // `load.<base>` redirects 303 to a random 20-letter subdomain; unique-origin
    // hosts receive the shuttle HTML with execution-policy headers. Without a
    // configured base host this remains 404 (same as before this slice).
    [self.httpServer addRoute:@"GET" path:@"/.well-known/web-tiles/" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        [weakSelf handleWebTilesDocumentRequest:request response:response];
    }];
    [self.httpServer addRoute:@"GET" path:@"/.well-known/web-tiles/index.html" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        [weakSelf handleWebTilesDocumentRequest:request response:response];
    }];
    [self.httpServer addRoute:@"GET" path:@"/.well-known/web-tiles/shuttle.js" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        [weakSelf handleWebTilesScriptRequest:request
                                     response:response
                                         body:GZAdminUITileShuttleJavaScript()];
    }];
    [self.httpServer addRoute:@"GET" path:@"/.well-known/web-tiles/worker.js" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        [weakSelf handleWebTilesScriptRequest:request
                                     response:response
                                         body:GZAdminUITileServiceWorkerJavaScript()];
    }];
}

- (NSString *)webTilesHostnameFromRequest:(ATProtoHttpRequest *)request {
    NSString *hostname = [request headerForKey:@"Host"];
    NSRange colon = [hostname rangeOfString:@":"];
    if (colon.location != NSNotFound) {
        hostname = [hostname substringToIndex:colon.location];
    }
    return hostname;
}

- (void)handleWebTilesScriptRequest:(ATProtoHttpRequest *)request
                           response:(ATProtoHttpResponse *)response
                               body:(NSString *)body {
    NSString *baseHost = self.configuration.tilesBaseHost;
    NSString *hostname = [self webTilesHostnameFromRequest:request];
    if (baseHost.length == 0 || !GZAdminUITileIsUniqueOriginHost(hostname, baseHost)) {
        response.statusCode = 404;
        response.contentType = @"text/plain; charset=utf-8";
        [response setBodyString:@"Not Found\n"];
        return;
    }
    GZAdminUITileApplyUniqueOriginHeaders(response);
    response.statusCode = 200;
    response.contentType = @"application/javascript; charset=utf-8";
    [response setBodyString:body];
}

- (void)handleWebTilesDocumentRequest:(ATProtoHttpRequest *)request
                             response:(ATProtoHttpResponse *)response {
    NSString *baseHost = self.configuration.tilesBaseHost;
    if (baseHost.length == 0) {
        response.statusCode = 404;
        response.contentType = @"text/plain; charset=utf-8";
        [response setBodyString:@"Not Found\n"];
        return;
    }

    NSString *hostname = [self webTilesHostnameFromRequest:request];

    if (GZAdminUITileIsLoadHost(hostname, baseHost)) {
        NSString *scheme = [request headerForKey:@"X-Forwarded-Proto"];
        if (scheme.length == 0) {
            scheme = @"http";
        }
        NSString *path = request.path.length > 0 ? request.path : @"/.well-known/web-tiles/";
        if (request.queryString.length > 0) {
            path = [path stringByAppendingFormat:@"?%@", request.queryString];
        }
        NSString *location = GZAdminUITileUniqueOriginRedirectURL(scheme, baseHost, path);
        response.statusCode = 303;
        [response setHeader:location forKey:@"Location"];
        response.contentType = @"text/plain; charset=utf-8";
        [response setBodyString:@""];
        return;
    }

    if (!GZAdminUITileIsUniqueOriginHost(hostname, baseHost)) {
        response.statusCode = 404;
        response.contentType = @"text/plain; charset=utf-8";
        [response setBodyString:@"Not Found\n"];
        return;
    }

    GZAdminUITileApplyUniqueOriginHeaders(response);
    response.statusCode = 200;
    response.contentType = @"text/html; charset=utf-8";
    [response setBodyString:GZAdminUITileShuttleHTML()];
}

@end
