// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/UIServerRuntime.h"
#import "AdminUIServer/UIServerRuntime+Private.h"
#import "AdminUIServer/UIAuthManager.h"
#import "AdminUIServer/UIBackendClient.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"
#import "AdminUIServer/UITileDataProtocol.h"
#import "AdminUIServer/UITileExecutionPolicy.h"

@implementation UIServerRuntime (LabRoutes)

- (void)registerLabRoutes {
    __weak typeof(self) weakSelf = self;

    // Lab: Public OAuth2 user self-service portal (no admin auth required)
    [self.httpServer addRoute:@"GET" path:@"/lab" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *nonce = UIGenerateNonce();
        UIApplyNonceCSP(response, nonce, [weakSelf.configuration.pdsBaseURL absoluteString]);
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf labShellHTML:nonce]];
    }];

    [self.httpServer addRoute:@"GET" path:@"/lab/callback" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *nonce = UIGenerateNonce();
        UIApplyNonceCSP(response, nonce, [weakSelf.configuration.pdsBaseURL absoluteString]);
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf labShellHTML:nonce]];
    }];

    [self.httpServer addRoute:@"GET" path:@"/lab/client-metadata.json" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = 200;
        response.contentType = @"application/json; charset=utf-8";
        [response setBodyString:[weakSelf labClientMetadataJSON]];
    }];

    // Reserved Web Tiles protocol endpoint. It serves only the host-selected
    // data-passing module; it does not serve tile resources or grant network
    // access to a tile. Execution-policy headers belong on the tile document,
    // not this JavaScript module response; no tile document route exists yet.
    [self.httpServer addRoute:@"GET" path:@"/.well-known/web-tiles/data.js" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = 200;
        response.contentType = @"application/javascript; charset=utf-8";
        [response setBodyString:UITileDataProtocolJavaScript()];
    }];

    [self.httpServer addRoute:@"GET" path:@"/.well-known/web-tiles/index.html" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = 404;
        response.contentType = @"text/plain; charset=utf-8";
        [response setBodyString:@"Not Found\n"];
    }];
}

@end
