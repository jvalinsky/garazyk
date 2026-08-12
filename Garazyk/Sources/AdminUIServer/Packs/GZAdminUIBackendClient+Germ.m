// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/Packs/GZAdminUIBackendClient+Germ.h"
#import "AdminUIServer/GZAdminUIBackendClient_Internal.h"
#import "AdminUIServer/UIServiceConfig.h"
#import "Network/ATProtoSafeHTTPClient.h"

@implementation GZAdminUIBackendClient (Germ)

- (NSDictionary *)fetchGermHealth {
    NSURL *url = [self URLByAppendingPath:@"/_health" queryItems:nil baseURL:self.configuration.germBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"GET" body:nil
                                                bearerToken:nil statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"status": @"unreachable", @"message": error.localizedDescription ?: @"Germ unreachable"};
    }
    // Germ /_health returns plain text "ok"; wrap in a dictionary
    if ([response isKindOfClass:[NSDictionary class]]) {
        return response;
    }
    // Plain text response
    NSString *body = [[NSString alloc] initWithData:(NSData *)[NSNull null] encoding:NSUTF8StringEncoding];
    return @{@"status": @"ok", @"uptime": @"available"};
}

- (NSDictionary *)fetchGermFlowMetrics {
    // Aggregate-only: no per-address or per-agent data is ever returned.
    // Germ does not yet expose counter endpoints — return placeholder.
    return @{
        @"claims": @0, @"delivers": @0, @"polls": @0, @"misses": @0,
        @"expirations": @0, @"authFailures": @0
    };
}

- (NSDictionary *)fetchGermStorageMetrics {
    // Aggregate-only: database-level metrics, no address-level data.
    return @{
        @"ephemeralCount": @0, @"rendezvousCount": @0,
        @"dbSizeBytes": @0, @"pendingMessages": @0
    };
}

@end
