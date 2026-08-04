// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file UITileExecutionPolicy.m

 @abstract Web Tiles execution-policy header implementation.

 @copyright Copyright (c) 2026 Jack Valinsky
 */

#import "AdminUIServer/UITileExecutionPolicy.h"

NSString *UITileExecutionContentSecurityPolicy(void) {
    return @"default-src 'self' blob: data:; "
           "script-src 'self' blob: data: 'unsafe-inline' 'wasm-unsafe-eval'; "
           "script-src-attr 'none'; "
           "style-src 'self' blob: data: 'unsafe-inline'; "
           "form-src 'self'; "
           "manifest-src 'none'; "
           "object-src 'none'; "
           "base-uri 'none'; "
           "sandbox allow-downloads allow-forms allow-modals allow-popups allow-popups-to-escape-sandbox allow-same-origin allow-scripts";
}

NSDictionary<NSString *, NSString *> *UITileExecutionSecurityHeaders(void) {
    return @{
        @"content-security-policy": UITileExecutionContentSecurityPolicy(),
        @"cross-origin-opener-policy": @"same-origin",
        @"cross-origin-resource-policy": @"cross-origin",
        @"origin-agent-cluster": @"?1",
        @"permissions-policy": @"interest-cohort=(), browsing-topics=()",
        @"referrer-policy": @"no-referrer",
        @"x-content-type-options": @"nosniff",
        @"x-dns-prefetch-control": @"off",
    };
}
