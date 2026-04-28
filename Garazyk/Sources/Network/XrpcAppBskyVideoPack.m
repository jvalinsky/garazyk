#import "Network/XrpcAppBskyVideoPack.h"

#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcAuthHelper.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/XrpcHandler.h"
#import "Database/PDSDatabase.h"
#import "Database/Service/ServiceDatabases.h"
#import "Debug/PDSLogger.h"

@implementation XrpcAppBskyVideoPack

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
               serviceDatabases:(PDSServiceDatabases *)serviceDatabases
                   appViewDatabase:(PDSDatabase *)appViewDatabase
                        jwtMinter:(JWTMinter *)jwtMinter
                   adminController:(id<PDSAdminController>)adminController
                      blobProvider:(id<PDSBlobProvider>)blobProvider {

  [dispatcher registerMethod:@"app.bsky.video.getJobStatus"

                      handler:^(HttpRequest *request, HttpResponse *response) {
    NSString *jobId = [request queryParamForKey:@"jobId"];
    if (!jobId) {
      [XrpcErrorHelper setValidationError:response message:@"Missing jobId parameter"];
      return;
    }

    NSError *error = nil;
    NSDictionary *job = [appViewDatabase getVideoJobById:jobId error:&error];
    if (!job) {
      [XrpcErrorHelper setNotFoundError:response message:@"Job not found"];
      return;
    }

    response.statusCode = HttpStatusOK;
    [response setJsonBody:[self formatJobResponse:job]];
  }];

  [dispatcher registerMethod:@"app.bsky.video.uploadVideo"
                       handler:^(HttpRequest *request, HttpResponse *response) {
    NSString *authHeader = [request headerForKey:@"Authorization"];
    NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
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

    NSError *error = nil;
    NSString *jobId = [[NSUUID UUID] UUIDString];
    NSNumber *fileSize = @(request.body.length);

    CID *cid = [CID sha256:request.body];
    NSString *blobCid = cid.nsString;

    BOOL stored = [blobProvider storeBlobData:request.body forCID:cid error:&error];
    if (!stored) {
      PDS_LOG_ERROR(@"Failed to store video blob: %@", error);
      [XrpcErrorHelper setInternalServerError:response message:@"Failed to store video"];
      return;
    }

    BOOL created = [appViewDatabase createVideoJobWithId:jobId
                                               did:did
                                            blobCid:blobCid
                                          mimeType:mimeType
                                          fileSize:fileSize
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
    NSString *authHeader = [request headerForKey:@"Authorization"];
    NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                          jwtMinter:jwtMinter
                                                    adminController:adminController
                                                            request:request
                                                           response:response];
    if (!did) {
      response.statusCode = HttpStatusOK;
      [response setJsonBody:@{
        @"canUpload" : @YES,
        @"remainingDailyVideos" : @25,
        @"remainingDailyBytes" : @(50 * 1024 * 1024),
        @"message" : @""
      }];
      return;
    }

    NSError *error = nil;
    NSDictionary *limits = [self getUploadLimitsForDid:did database:appViewDatabase error:&error];
    if (!limits) {
      limits = @{
        @"canUpload" : @YES,
        @"remainingDailyVideos" : @25,
        @"remainingDailyBytes" : @(50 * 1024 * 1024),
        @"message" : @""
      };
    }

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
    resp[@"blobRef"] = @{
      @"cid": processedCid,
      @"mimeType": job[@"mime_type"] ?: @"video/mp4"
    };
  } else {
    resp[@"blobRef"] = [NSNull null];
  }

  NSString *errorMessage = job[@"error_message"];
  if (errorMessage && ![errorMessage isEqual:[NSNull null]]) {
    resp[@"error"] = errorMessage;
  }

  return resp;
}

+ (NSDictionary *)getUploadLimitsForDid:(NSString *)did
                                database:(PDSDatabase *)database
                                   error:(NSError **)error {
  NSString *sql = @"SELECT COUNT(*) as count, COALESCE(SUM(file_size), 0) as total_bytes "
                   @"FROM video_jobs WHERE did = ? AND date(created_at) = date('now')";

  NSArray *results = [database executeParameterizedQuery:sql params:@[did] error:error];
  if (results.count == 0) {
    return nil;
  }

  NSDictionary *row = results.firstObject;
  NSInteger videosToday = [row[@"count"] integerValue];
  NSInteger bytesToday = [row[@"total_bytes"] integerValue];

  NSInteger maxDailyVideos = 25;
  NSInteger maxDailyBytes = 50 * 1024 * 1024;

  NSInteger remainingVideos = MAX(0, maxDailyVideos - videosToday);
  NSInteger remainingBytes = MAX(0, maxDailyBytes - bytesToday);

  return @{
    @"canUpload" : @(remainingVideos > 0 && remainingBytes > 0),
    @"remainingDailyVideos" : @(remainingVideos),
    @"remainingDailyBytes" : @(remainingBytes),
    @"message" : @""
  };
}

@end