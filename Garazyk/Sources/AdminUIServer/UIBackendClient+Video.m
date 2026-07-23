// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/UIBackendClient+Video.h"
#import "AdminUIServer/UIBackendClient_Internal.h"
#import "AdminUIServer/UIServiceConfig.h"
#import "Network/ATProtoSafeHTTPClient.h"

@implementation UIBackendClient (Video)

- (NSDictionary *)fetchVideoJobsWithState:(NSString *)state limit:(NSUInteger)limit cursor:(nullable NSString *)cursor {
    NSMutableDictionary *queryItems = [NSMutableDictionary dictionary];
    if (state.length > 0) {
        queryItems[@"state"] = state;
    }
    if (limit > 0) {
        queryItems[@"limit"] = [NSString stringWithFormat:@"%lu", (unsigned long)limit];
    }
    if (cursor.length > 0) {
        queryItems[@"cursor"] = cursor;
    }
    NSURL *url = [self URLByAppendingPath:@"/admin/api/video/jobs"
                              queryItems:queryItems
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url method:@"GET" body:nil statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"video_jobs_failed", @"message": error.localizedDescription ?: @"Failed to fetch video jobs"};
    }
    return response ?: @{@"jobs": @[]};
}

- (NSDictionary *)fetchVideoJobById:(NSString *)jobId {
    if (!jobId || jobId.length == 0) {
        return @{@"error": @"invalid_params", @"message": @"Job ID required"};
    }
    NSURL *url = [self URLByAppendingPath:@"/xrpc/app.bsky.video.getJobStatus"
                              queryItems:@{@"jobId": jobId}
                                 baseURL:self.configuration.videoBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"GET" body:nil bearerToken:self.configuration.videoAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300 || !response) {
        return @{@"error": @"video_job_failed", @"message": error.localizedDescription ?: @"Failed to fetch video job"};
    }
    return response;
}

- (NSDictionary *)fetchVideoUploadLimits {
    NSURL *url = [self URLByAppendingPath:@"/xrpc/app.bsky.video.getUploadLimits"
                              queryItems:nil
                                 baseURL:self.configuration.videoBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"GET" body:nil bearerToken:self.configuration.videoAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300 || !response) {
        return @{@"error": @"video_limits_failed", @"message": error.localizedDescription ?: @"Failed to fetch video upload limits"};
    }
    return response;
}

- (NSDictionary *)fetchVideoHealth {
    NSURL *url = [self URLByAppendingPath:@"/_health"
                              queryItems:nil
                                 baseURL:self.configuration.videoBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"GET" body:nil bearerToken:self.configuration.videoAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300 || !response) {
        return @{@"status": @"error", @"error": error.localizedDescription ?: @"Unreachable"};
    }
    NSMutableDictionary *result = [response mutableCopy];
    result[@"status"] = @"online";
    return [result copy];
}

- (NSDictionary *)retryVideoJobWithId:(NSString *)jobId {
    if (!jobId || jobId.length == 0) {
        return @{@"error": @"invalid_params", @"message": @"Job ID required"};
    }
    NSURL *url = [self URLByAppendingPath:[NSString stringWithFormat:@"/admin/api/video/jobs/%@/retry", jobId]
                              queryItems:nil
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url method:@"POST" body:nil statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"video_retry_failed", @"message": error.localizedDescription ?: @"Failed to retry video job"};
    }
    return response ?: @{};
}

@end
