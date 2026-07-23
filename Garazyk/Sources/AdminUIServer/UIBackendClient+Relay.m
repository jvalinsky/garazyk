// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/UIBackendClient+Relay.h"
#import "AdminUIServer/UIBackendClient_Internal.h"
#import "AdminUIServer/UIServiceConfig.h"
#import "Network/ATProtoSafeHTTPClient.h"

@implementation UIBackendClient (Relay)

- (NSDictionary *)fetchRelayMetrics {
    NSURL *url = [self URLByAppendingPath:@"/api/relay/metrics" queryItems:nil baseURL:self.configuration.relayBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"GET" body:nil bearerToken:self.configuration.relayAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300 || !response) {
        return @{@"error": @"relay_metrics_failed", @"message": error.localizedDescription ?: @"Relay metrics failed"};
    }
    return response;
}

- (NSDictionary *)fetchRelayUpstreams {
    NSURL *url = [self URLByAppendingPath:@"/api/relay/upstreams" queryItems:nil baseURL:self.configuration.relayBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"GET" body:nil bearerToken:self.configuration.relayAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300 || !response) {
        return @{@"error": @"relay_upstreams_failed", @"message": error.localizedDescription ?: @"Relay upstreams failed"};
    }
    return response;
}

- (NSDictionary *)fetchRelayHealth {
    NSURL *url = [self URLByAppendingPath:@"/api/relay/health" queryItems:nil baseURL:self.configuration.relayBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"GET" body:nil bearerToken:self.configuration.relayAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300 || !response) {
        return @{@"error": @"relay_health_failed", @"message": error.localizedDescription ?: @"Relay health failed"};
    }
    return response;
}

- (NSDictionary *)requestCrawlForHostname:(NSString *)hostname {
    if (hostname.length == 0) return @{@"error": @"invalid_hostname", @"message": @"Hostname required"};
    NSURL *url = [self URLByAppendingPath:@"/api/relay/requestCrawl" queryItems:nil baseURL:self.configuration.relayBaseURL];
    NSDictionary *body = @{@"hostname": hostname};
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"POST" body:body bearerToken:self.configuration.relayAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"crawl_request_failed", @"message": error.localizedDescription ?: @"Crawl request failed"};
    }
    return response ?: @{};
}

@end
