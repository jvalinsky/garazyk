// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/UIServerRuntime.h"
#import "AdminUIServer/UIServerRuntime+Private.h"
#import "AdminUIServer/UIAuthManager.h"
#import "AdminUIServer/UIBackendClient.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"

@implementation UIServerRuntime (VideoRoutes)

- (void)registerVideoRoutes {
    __weak typeof(self) weakSelf = self;

    // Video: Health
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/video-health" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *result = [weakSelf.backendClient fetchVideoHealth];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderVideoHealthPartial:result]];
    }];

    // Video: Job list
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/video-jobs" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *state = [request queryParamForKey:@"state"];
        NSString *cursor = [request queryParamForKey:@"cursor"];
        if (state.length == 0) state = nil;
        NSDictionary *result = [weakSelf.backendClient fetchVideoJobsWithState:state limit:25 cursor:cursor];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderVideoJobsPartial:result]];
    }];

    // Video: Job detail
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/video-job-detail" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *jobId = [request queryParamForKey:@"jobId"];
        NSDictionary *result = [weakSelf.backendClient fetchVideoJobById:jobId];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderVideoJobDetailPartial:result]];
    }];

    // Video: Upload quotas
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/video-quotas" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *result = [weakSelf.backendClient fetchVideoUploadLimits];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderVideoQuotasPartial:result]];
    }];

    // Video: Retry job
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/video-retry-job" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *jobId = request.jsonBody[@"jobId"] ?: @"";
        // Retry via PDS admin: incrementVideoJobRetry
        NSDictionary *result = [weakSelf.backendClient retryVideoJobWithId:jobId];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Job queued for retry.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];
}

@end
