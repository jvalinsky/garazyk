// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Video/VideoXrpcPack.h"
#import "Video/VideoJobStore.h"
#import "Video/VideoAuthProvider.h"
#import "Video/VideoWorker.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/XrpcHandler.h"
#import "Blob/PDSBlobProvider.h"
#import "Core/CID.h"
#import "Debug/PDSLogger.h"

@implementation ATProtoVideoXrpcPack

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                       jobStore:(id<VideoJobStore>)jobStore
                   authProvider:(id<VideoAuthProvider>)authProvider
                  blobProvider:(id<PDSBlobProvider>)blobProvider {

  [dispatcher registerMethod:@"app.bsky.video.getJobStatus"
                      handler:^(HttpRequest *request, HttpResponse *response) {
    NSString *jobId = [request queryParamForKey:@"jobId"];
    if (!jobId) {
      [XrpcErrorHelper setValidationError:response message:@"Missing jobId parameter"];
      return;
    }

    NSError *error = nil;
    NSDictionary *job = [jobStore getVideoJobById:jobId error:&error];
    if (!job) {
      [XrpcErrorHelper setNotFoundError:response message:@"Job not found"];
      return;
    }

    response.statusCode = HttpStatusOK;
    [response setJsonBody:[self formatJobResponse:job]];
  }];

  [dispatcher registerMethod:@"app.bsky.video.uploadVideo"
                       handler:^(HttpRequest *request, HttpResponse *response) {
    NSString *did = [authProvider authenticateRequest:request response:response];
    if (!did) {
      if (response.statusCode == HttpStatusOK) {
        response.statusCode = HttpStatusUnauthorized;
        [response setJsonBody:@{
          @"error" : @"AuthRequired",
          @"message" : @"Valid authorization required"
        }];
      }
      return;
    }

    if (request.body.length == 0) {
      [XrpcErrorHelper setValidationError:response message:@"Missing request body"];
      return;
    }

    if (request.body.length > 100 * 1024 * 1024) {
      [XrpcErrorHelper setValidationError:response message:@"File exceeds 100MB limit"];
      return;
    }

    NSString *mimeType = [request headerForKey:@"Content-Type"];
    if (!mimeType) {
      mimeType = @"video/mp4";
    }

    // Content type sniffing: verify the blob is actually video data
    if (![self validateVideoContentType:request.body declaredMimeType:mimeType]) {
      [XrpcErrorHelper setValidationError:response message:@"Invalid video content: file does not appear to be a valid video"];
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
      PDS_LOG_ERROR(@"Failed to store video blob: %@", error);
      [XrpcErrorHelper setInternalServerError:response message:@"Failed to store video"];
      return;
    }

    // Extract Service Auth token from Authorization header for later blob upload
    NSString *authHeader = [request headerForKey:@"Authorization"];
    NSString *serviceToken = nil;
    if (authHeader.length > 7 && [[authHeader substringToIndex:7] isEqualToString:@"Bearer "]) {
        serviceToken = [authHeader substringFromIndex:7];
    }

    BOOL created = [jobStore createVideoJobWithId:jobId
                                               did:did
                                            blobCid:blobCid
                                           mimeType:mimeType
                                           fileSize:fileSize
                                    serviceAuthToken:serviceToken
                                              error:&error];
    if (!created) {
      PDS_LOG_ERROR(@"Failed to create video job: %@", error);
      [XrpcErrorHelper setInternalServerError:response message:@"Failed to create job"];
      return;
    }

    PDS_LOG_INFO(@"Created video job %@ for did %@", jobId, did);

    response.statusCode = HttpStatusOK;
    [response setJsonBody:@{
      @"jobStatus" : @{
        @"jobId" : jobId,
        @"did" : did,
        @"state" : @"JOB_STATE_PENDING",
        @"progress" : @0
      }
    }];
  }];

  [dispatcher registerMethod:@"app.bsky.video.getUploadLimits"
                      handler:^(HttpRequest *request, HttpResponse *response) {
    NSString *did = [authProvider authenticateRequest:request response:response];
    if (!did) {
      // Unauthenticated users get default limits
      response.statusCode = HttpStatusOK;
      [response setJsonBody:@{
        @"canUpload" : @YES,
        @"remainingDailyVideos" : @25,
        @"remainingDailyBytes" : @(50 * 1024 * 1024),
        @"message" : @""
      }];
      return;
    }

    NSDictionary *limits = [self getUploadLimitsForDid:did jobStore:jobStore];
    response.statusCode = HttpStatusOK;
    [response setJsonBody:limits];
  }];
}

+ (NSDictionary *)formatJobResponse:(NSDictionary *)job {
  NSString *state = job[@"state"];
  NSString *jobState;

  if ([state isEqualToString:@"PENDING"]) {
    jobState = @"JOB_STATE_PENDING";
  } else if ([state isEqualToString:@"PROCESSING"]) {
    jobState = @"JOB_STATE_PROCESSING";
  } else if ([state isEqualToString:@"COMPLETED"]) {
    jobState = @"JOB_STATE_COMPLETED";
  } else if ([state isEqualToString:@"FAILED"]) {
    jobState = @"JOB_STATE_FAILED";
  } else {
    jobState = @"JOB_STATE_PENDING";
  }

  NSMutableDictionary *resp = [NSMutableDictionary dictionary];
  resp[@"jobId"] = job[@"job_id"] ?: @"";
  resp[@"did"] = job[@"did"] ?: @"";
  resp[@"state"] = jobState;
  resp[@"progress"] = job[@"progress"] ?: @0;

  NSString *processedCid = job[@"processed_blob_cid"];
  if (processedCid && ![processedCid isEqual:[NSNull null]]) {
    // Lexicon defines this as "blob" (type: blob), not "blobRef"
    resp[@"blob"] = @{
      @"$type": @"blob",
      @"ref": @{
        @"$link": processedCid
      },
      @"mimeType": job[@"mime_type"] ?: @"video/mp4",
      @"size": job[@"file_size"] ?: @0
    };
  }

  NSString *errorMessage = job[@"error_message"];
  if (errorMessage && ![errorMessage isEqual:[NSNull null]]) {
    resp[@"error"] = errorMessage;
  }

  NSString *message = job[@"message"];
  if (message && ![message isEqual:[NSNull null]]) {
    resp[@"message"] = message;
  }

  // Include aspect ratio if available
  NSNumber *width = job[@"width"];
  NSNumber *height = job[@"height"];
  if (width && height && ![width isEqual:[NSNull null]] && ![height isEqual:[NSNull null]] &&
      [width integerValue] > 0 && [height integerValue] > 0) {
    resp[@"aspectRatio"] = @{
      @"width": width,
      @"height": height
    };
  }

  return resp;
}

+ (NSDictionary *)getUploadLimitsForDid:(NSString *)did
                                jobStore:(id<VideoJobStore>)jobStore {
  return @{
    @"canUpload" : @YES,
    @"remainingDailyVideos" : @(25),
    @"remainingDailyBytes" : @(50 * 1024 * 1024),
    @"message" : @""
  };
}

+ (BOOL)validateVideoContentType:(NSData *)data declaredMimeType:(NSString *)mimeType {
    if (data.length < 12) {
        return NO;
    }

    // MP4/MOV files start with an ftyp box: 4 bytes size + "ftyp"
    const uint8_t *bytes = (const uint8_t *)data.bytes;

    // Check for ftyp box at offset 4 (after the 4-byte box size)
    if (bytes[4] == 'f' && bytes[5] == 't' && bytes[6] == 'y' && bytes[7] == 'p') {
        return YES;
    }

    // Check for Matroska/WebM container
    if (data.length >= 4 &&
        bytes[0] == 0x1A && bytes[1] == 0x45 && bytes[2] == 0xDF && bytes[3] == 0xA3) {
        return YES;
    }

    return NO;
}

@end
