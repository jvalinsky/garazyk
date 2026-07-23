// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/UIBackendClient+AppView.h"
#import "AdminUIServer/UIBackendClient_Internal.h"
#import "AdminUIServer/UIServiceConfig.h"
#import "Network/ATProtoSafeHTTPClient.h"

@implementation UIBackendClient (AppView)

- (NSDictionary *)fetchAppViewMetrics {
    NSURL *url = [self URLByAppendingPath:@"/admin/appview/metrics/stats" queryItems:nil baseURL:self.configuration.appViewBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"GET" body:nil bearerToken:self.configuration.appViewAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300 || !response) {
        return @{@"error": @"appview_metrics_failed", @"message": error.localizedDescription ?: @"AppView metrics failed"};
    }
    return response;
}

- (NSDictionary *)fetchIngestHealth {
    NSURL *url = [self URLByAppendingPath:@"/admin/ingest/health" queryItems:nil baseURL:self.configuration.appViewBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"GET" body:nil bearerToken:self.configuration.appViewAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300 || !response) {
        return @{@"error": @"ingest_health_failed", @"message": error.localizedDescription ?: @"Ingest health failed"};
    }
    return response;
}

- (NSDictionary *)fetchBackfillQueueWithStatus:(NSString *)status limit:(NSUInteger)limit cursor:(NSString *)cursor {
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    params[@"limit"] = [@(limit ?: 25) stringValue];
    if (status.length > 0) params[@"status"] = status;
    if (cursor.length > 0) params[@"cursor"] = cursor;
    
    NSURL *url = [self URLByAppendingPath:@"/admin/backfill/queue" queryItems:params baseURL:self.configuration.appViewBaseURL];
    NSInteger httpStatus = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"GET" body:nil bearerToken:self.configuration.appViewAdminToken statusCode:&httpStatus error:&error];
    if (httpStatus < 200 || httpStatus >= 300 || !response) {
        return @{@"error": @"backfill_queue_failed", @"message": error.localizedDescription ?: @"Fetch backfill queue failed", @"entries": @[]};
    }
    return response;
}

- (NSDictionary *)retryBackfillForDID:(NSString *)did {
    if (did.length == 0) return @{@"error": @"invalid_did", @"message": @"DID required"};
    NSURL *url = [self URLByAppendingPath:[NSString stringWithFormat:@"/admin/backfill/repos/%@/retry", did] queryItems:nil baseURL:self.configuration.appViewBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"POST" body:nil bearerToken:self.configuration.appViewAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"backfill_retry_failed", @"message": error.localizedDescription ?: @"Retry failed"};
    }
    return response ?: @{};
}

- (NSDictionary *)cancelBackfillForDID:(NSString *)did {
    if (did.length == 0) return @{@"error": @"invalid_did", @"message": @"DID required"};
    NSURL *url = [self URLByAppendingPath:[NSString stringWithFormat:@"/admin/backfill/repos/%@/cancel", did] queryItems:nil baseURL:self.configuration.appViewBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"POST" body:nil bearerToken:self.configuration.appViewAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"backfill_cancel_failed", @"message": error.localizedDescription ?: @"Cancel failed"};
    }
    return response ?: @{};
}

- (NSDictionary *)enqueueBackfillDIDs:(NSArray<NSString *> *)dids {
    if (dids.count == 0) return @{@"error": @"invalid_dids", @"message": @"DIDs required"};
    NSURL *url = [self URLByAppendingPath:@"/admin/backfill/repos" queryItems:nil baseURL:self.configuration.appViewBaseURL];
    NSDictionary *body = @{@"dids": dids};
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"POST" body:body bearerToken:self.configuration.appViewAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"enqueue_failed", @"message": error.localizedDescription ?: @"Enqueue failed"};
    }
    return response ?: @{};
}

- (NSDictionary *)rebuildBackfillScope {
    NSURL *url = [self URLByAppendingPath:@"/admin/backfill/scope/rebuild" queryItems:nil baseURL:self.configuration.appViewBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"POST" body:nil bearerToken:self.configuration.appViewAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"rebuild_scope_failed", @"message": error.localizedDescription ?: @"Rebuild scope failed"};
    }
    return response ?: @{};
}

@end
