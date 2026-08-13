// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/GZAdminUIHost.h"
#import "AdminUIServer/GZAdminUIHost+Private.h"
#import "AdminUIServer/Packs/GZAdminUIVideoPack.h"
#import "AdminUIServer/Packs/JelczAdminSnapshot.h"
#import "AdminUIServer/UIAuthManager.h"
#import "AdminUIServer/GZAdminUIBackendClient.h"
#import "AdminUIServer/Packs/GZAdminUIBackendClient+Video.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"

@implementation GZAdminUIHost (VideoRoutes)

- (void)registerVideoRoutes {
    __weak typeof(self) weakSelf = self;

    // Video: Overview (Slice 1 — snapshot from health + jobs + quotas)
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/video-metrics" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *health = [weakSelf.backendClient fetchVideoHealth];
        NSDictionary *jobsResult = [weakSelf.backendClient fetchVideoJobsWithState:nil limit:100 cursor:nil];
        NSArray *jobs = [jobsResult[@"jobs"] isKindOfClass:[NSArray class]] ? jobsResult[@"jobs"] : @[];
        NSDictionary *quotas = [weakSelf.backendClient fetchVideoUploadLimits];
        GZJelczAdminSnapshot *snap = [[GZJelczAdminSnapshot alloc] initWithHealth:health jobs:jobs quotas:quotas];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[GZAdminUIVideoPack renderVideoOverviewPartial:snap.snapshot]];
    }];

    // Video: Shell tab (admin shell requests /admin/partials/video for the
    // top-level tab identifier "video").
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/video" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *health = [weakSelf.backendClient fetchVideoHealth];
        NSDictionary *jobsResult = [weakSelf.backendClient fetchVideoJobsWithState:nil limit:100 cursor:nil];
        NSArray *jobs = [jobsResult[@"jobs"] isKindOfClass:[NSArray class]] ? jobsResult[@"jobs"] : @[];
        NSDictionary *quotas = [weakSelf.backendClient fetchVideoUploadLimits];
        GZJelczAdminSnapshot *snap = [[GZJelczAdminSnapshot alloc] initWithHealth:health jobs:jobs quotas:quotas];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[GZAdminUIVideoPack renderVideoOverviewPartial:snap.snapshot]];
    }];

    // Video: Health
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/video-health" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *result = [weakSelf.backendClient fetchVideoHealth];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[GZAdminUIVideoPack renderVideoHealthPartial:result]];
    }];

    // Video: Job list
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/video-jobs" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *state = [request queryParamForKey:@"state"];
        NSString *cursor = [request queryParamForKey:@"cursor"];
        if (state.length == 0) state = nil;
        NSDictionary *result = [weakSelf.backendClient fetchVideoJobsWithState:state limit:25 cursor:cursor];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[GZAdminUIVideoPack renderVideoJobsPartial:result]];
    }];

    // Video: Job detail
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/video-job-detail" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *jobId = [request queryParamForKey:@"jobId"];
        NSDictionary *result = [weakSelf.backendClient fetchVideoJobById:jobId];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[GZAdminUIVideoPack renderVideoJobDetailPartial:result]];
    }];

    // Video: Capacity
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/video-capacity" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *health = [weakSelf.backendClient fetchVideoHealth];
        NSDictionary *jobsResult = [weakSelf.backendClient fetchVideoJobsWithState:nil limit:100 cursor:nil];
        NSArray *jobs = [jobsResult[@"jobs"] isKindOfClass:[NSArray class]] ? jobsResult[@"jobs"] : @[];
        NSDictionary *quotas = [weakSelf.backendClient fetchVideoUploadLimits];
        GZJelczAdminSnapshot *snap = [[GZJelczAdminSnapshot alloc] initWithHealth:health jobs:jobs quotas:quotas];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[GZAdminUIVideoPack renderVideoCapacityPartial:snap.snapshot]];
    }];

    // Video: Distribution posture (flags only; remote hosts lack CA wiring)
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/video-distribution" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *health = [weakSelf.backendClient fetchVideoHealth];
        NSDictionary *jobsResult = [weakSelf.backendClient fetchVideoJobsWithState:nil limit:100 cursor:nil];
        NSArray *jobs = [jobsResult[@"jobs"] isKindOfClass:[NSArray class]] ? jobsResult[@"jobs"] : @[];
        NSDictionary *quotas = [weakSelf.backendClient fetchVideoUploadLimits];
        GZJelczAdminSnapshot *snap = [[GZJelczAdminSnapshot alloc] initWithHealth:health jobs:jobs quotas:quotas];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[GZAdminUIVideoPack renderVideoDistributionPartial:snap.snapshot]];
    }];

    // Video: Upload quotas
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/video-quotas" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *result = [weakSelf.backendClient fetchVideoUploadLimits];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[GZAdminUIVideoPack renderVideoQuotasPartial:result]];
    }];

    // Video: Retry job
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/video-retry-job" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *jobId = [request.jsonBody[@"jobId"] isKindOfClass:[NSString class]] ? request.jsonBody[@"jobId"] : @"";
        // Retry via PDS admin: incrementVideoJobRetry
        NSDictionary *result = [weakSelf.backendClient retryVideoJobWithId:jobId];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Job queued for retry.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, GZAdminUIEscaped(msg)]];
    }];
}

@end
