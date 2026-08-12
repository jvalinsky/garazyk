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
    [self performJSONRequestWithURL:url method:@"GET" body:nil
                        bearerToken:nil statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"status": @"unreachable", @"message": error.localizedDescription ?: @"Germ unreachable"};
    }
    return @{@"status": @"ok", @"uptime": @"available"};
}

- (NSDictionary *)fetchGermFlowMetrics {
    // Fetch aggregate-only counters from Germ's admin metrics endpoint
    NSURL *url = [self URLByAppendingPath:@"/_admin/metrics" queryItems:nil baseURL:self.configuration.germBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"GET" body:nil
                                                bearerToken:nil statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"metrics_unavailable", @"message": error.localizedDescription ?: @"Metrics unavailable"};
    }
    return response ?: @{};
}

- (NSDictionary *)fetchGermStorageMetrics {
    // Reuse flow metrics which includes all aggregate counters
    return [self fetchGermFlowMetrics];
}

@end
