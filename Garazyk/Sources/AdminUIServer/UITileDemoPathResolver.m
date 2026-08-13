// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/UITileDemoPathResolver.h"

@implementation GZAdminUIDemoTilePathResolver

- (NSDictionary *)handleTileRequest:(NSDictionary *)request {
    id requestId = request[@"requestId"];
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    if (requestId) out[@"requestId"] = requestId;

    if (![request[@"type"] isEqual:@"resolve-path"]) {
        out[@"error"] = @"unknown request type";
        return out;
    }
    NSString *path = request[@"path"];
    if (![path isKindOfClass:[NSString class]]) {
        out[@"error"] = @"path required";
        return out;
    }
    NSString *clean = [[path componentsSeparatedByString:@"?"] firstObject];
    clean = [[clean componentsSeparatedByString:@"#"] firstObject];

    if ([clean isEqualToString:@"/"] || [clean isEqualToString:@""]) {
        NSString *html =
            @"<!DOCTYPE html><html><head><title>Demo Tile</title></head>"
            @"<body><h1>Demo Tile</h1>"
            @"<script type=\"module\">"
            @"import { listen, sendData, addDataHandler } from '/.well-known/web-tiles/data.js';"
            @"addDataHandler((p) => sendData({ echo: p }));"
            @"listen();"
            @"</script></body></html>";
        out[@"response"] = @{
            @"status": @200,
            @"headers": @{@"content-type": @"text/html; charset=utf-8"},
            @"body": html,
        };
        return out;
    }
    if ([clean isEqualToString:@"/app.js"]) {
        out[@"response"] = @{
            @"status": @200,
            @"headers": @{@"content-type": @"application/javascript; charset=utf-8"},
            @"body": @"console.log('garazyk-demo-tile');",
        };
        return out;
    }
    out[@"response"] = @{
        @"status": @404,
        @"headers": @{},
        @"body": @"",
    };
    return out;
}

@end
