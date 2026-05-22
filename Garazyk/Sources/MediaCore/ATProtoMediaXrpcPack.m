// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "MediaCore/ATProtoMediaXrpcPack.h"
#import "MediaCore/ATProtoMediaJobStore.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcRoutePackServices.h"
#import "Blob/PDSBlobProvider.h"
#import "Core/CID.h"
#import "Debug/GZLogger.h"

@implementation ATProtoMediaXrpcPack

+ (NSString *)routePackIdentifier {
    return @"com.atproto.mediacore";
}

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                      services:(id<XrpcRoutePackServices>)services {
    // Legacy: instantiate with defaults; callers using parameterized mapping
    // should alloc/init and call registerWithDispatcher:services: directly.
    ATProtoMediaXrpcPack *pack = [[ATProtoMediaXrpcPack alloc] init];
    [pack registerWithDispatcher:dispatcher services:services];
}

- (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                      services:(id<XrpcRoutePackServices>)services {
    id<ATProtoMediaJobStore> jobStore = (id<ATProtoMediaJobStore>)services.videoJobStore;
    id<PDSBlobProvider> blobProvider = services.blobProvider;

    NSDictionary *mappings = self.methodMappings;
    if (!mappings) {
        GZ_LOG_WARN(@"ATProtoMediaXrpcPack: no methodMappings set, XRPC routes not registered");
        return;
    }

    NSString *getJobStatusNSID    = mappings[@"getJobStatus"];
    NSString *uploadNSID          = mappings[@"upload"];
    NSString *getUploadLimitsNSID = mappings[@"getUploadLimits"];

    // getJobStatus
    if (getJobStatusNSID.length > 0) {
        [dispatcher registerMethod:getJobStatusNSID handler:^(HttpRequest *request, HttpResponse *response) {
            NSString *jobId = [request queryParamForKey:@"jobId"];
            if (!jobId) {
                [XrpcErrorHelper setValidationError:response message:@"Missing jobId parameter"];
                return;
            }
            NSError *error = nil;
            NSDictionary *job = [jobStore getJobById:jobId error:&error];
            if (!job) {
                [XrpcErrorHelper setNotFoundError:response message:@"Job not found"];
                return;
            }
            response.statusCode = HttpStatusOK;
            [response setJsonBody:@{@"jobStatus": [self formatJobResponse:job]}];
        }];
    }

    // uploadMedia
    if (uploadNSID.length > 0) {
        [dispatcher registerMethod:uploadNSID handler:^(HttpRequest *request, HttpResponse *response) {
            if (request.body.length == 0) {
                [XrpcErrorHelper setValidationError:response message:@"Missing request body"];
                return;
            }
            if (request.body.length > 100 * 1024 * 1024) {
                [XrpcErrorHelper setValidationError:response message:@"File exceeds 100MB limit"];
                return;
            }

            NSString *mimeType = [request headerForKey:@"Content-Type"] ?: @"application/octet-stream";

            // Content type sniffing
            if (self.contentValidator && !self.contentValidator(request.body, mimeType)) {
                [XrpcErrorHelper setValidationError:response message:@"Invalid content: file does not appear to be valid media"];
                return;
            }

            if (!blobProvider) {
                [XrpcErrorHelper setInternalServerError:response message:@"Blob provider not configured"];
                return;
            }

            NSError *error = nil;
            NSString *jobId = [[NSUUID UUID] UUIDString];
            NSNumber *fileSize = @(request.body.length);
            CID *cid = [CID sha256:request.body];
            NSString *blobCid = cid.stringValue;

            BOOL stored = [blobProvider storeBlobData:request.body forCID:cid error:&error];
            if (!stored) {
                GZ_LOG_ERROR(@"Failed to store media blob: %@", error);
                [XrpcErrorHelper setInternalServerError:response message:@"Failed to store media"];
                return;
            }

            // Derive DID from auth token or use anonymous
            NSString *did = @"did:plc:anonymous";
            NSString *workerToken = [request headerForKey:@"X-Garazyk-Access-JWT"];
            if (workerToken.length == 0) {
                workerToken = [request headerForKey:@"X-Garazyk-Access-Token"];
            }
            NSString *authHeader = [request headerForKey:@"Authorization"];
            if (workerToken.length == 0 && authHeader.length > 7 && [[authHeader substringToIndex:7] isEqualToString:@"Bearer "]) {
                workerToken = [authHeader substringFromIndex:7];
            }

            BOOL created = [jobStore createJobWithId:jobId did:did blobCid:blobCid mimeType:mimeType fileSize:fileSize serviceAuthToken:workerToken error:&error];
            if (!created) {
                GZ_LOG_ERROR(@"Failed to create media job: %@", error);
                [XrpcErrorHelper setInternalServerError:response message:@"Failed to create job"];
                return;
            }
            GZ_LOG_INFO(@"Created media job %@ for did %@", jobId, did);
            response.statusCode = HttpStatusOK;
            [response setJsonBody:@{@"jobStatus": @{@"jobId": jobId, @"did": did, @"state": @"JOB_STATE_PENDING", @"progress": @0}}];
        }];
    }

    // getUploadLimits
    if (getUploadLimitsNSID.length > 0) {
        [dispatcher registerMethod:getUploadLimitsNSID handler:^(HttpRequest *request, HttpResponse *response) {
            response.statusCode = HttpStatusOK;
            [response setJsonBody:@{
                @"canUpload": @YES,
                @"remainingDailyVideos": @25,
                @"remainingDailyBytes": @(50 * 1024 * 1024),
                @"message": @""
            }];
        }];
    }
}

#pragma mark - Response Formatting

- (NSDictionary *)formatJobResponse:(NSDictionary *)job {
    NSString *state = job[@"state"];
    NSString *jobState = @"JOB_STATE_PENDING";
    if ([state isEqualToString:@"PROCESSING"]) jobState = @"JOB_STATE_PROCESSING";
    else if ([state isEqualToString:@"COMPLETED"]) jobState = @"JOB_STATE_COMPLETED";
    else if ([state isEqualToString:@"FAILED"]) jobState = @"JOB_STATE_FAILED";

    NSMutableDictionary *resp = [NSMutableDictionary dictionary];
    resp[@"jobId"] = job[@"job_id"] ?: @"";
    resp[@"did"] = job[@"did"] ?: @"";
    resp[@"state"] = jobState;
    resp[@"progress"] = job[@"progress"] ?: @0;

    // Parse results_json for completed jobs
    NSString *resultsJson = job[@"results_json"];
    if (resultsJson && ![resultsJson isEqual:[NSNull null]]) {
        NSData *data = [resultsJson dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *results = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (results) {
            NSString *processedCid = results[@"processedCid"];
            if (processedCid) {
                resp[@"blob"] = @{
                    @"$type": @"blob",
                    @"ref": @{@"$link": processedCid},
                    @"mimeType": job[@"mime_type"] ?: @"application/octet-stream",
                    @"size": job[@"file_size"] ?: @0
                };
            }
            NSDictionary *metadata = results[@"metadata"];
            if (metadata) {
                resp[@"metadata"] = metadata;
            }
        }
    }

    NSString *errorMsg = job[@"error_message"];
    if (errorMsg && ![errorMsg isEqual:[NSNull null]]) resp[@"error"] = errorMsg;

    NSString *message = job[@"message"];
    if (message && ![message isEqual:[NSNull null]]) resp[@"message"] = message;

    return resp;
}

@end
