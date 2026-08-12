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

@implementation GZAdminUIHost (LabRoutes)

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

    // Reserved Web Tiles protocol endpoint. It serves only the host-selected
    // data-passing module; it does not serve tile resources or grant network
    // access to a tile. Execution-policy headers belong on the tile document,
    // not this JavaScript module response; no tile document route exists yet.
    [self.httpServer addRoute:@"GET" path:@"/.well-known/web-tiles/data.js" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        response.statusCode = 200;
        response.contentType = @"application/javascript; charset=utf-8";
        [response setBodyString:GZAdminUITileDataProtocolJavaScript()];
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

    NSString *hostname = [request headerForKey:@"Host"];
    // Strip optional port.
    NSRange colon = [hostname rangeOfString:@":"];
    if (colon.location != NSNotFound) {
        hostname = [hostname substringToIndex:colon.location];
    }

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
