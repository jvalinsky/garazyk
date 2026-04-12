#import "Network/XrpcAppBskyVideoPack.h"

#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/XrpcHandler.h"

@implementation XrpcAppBskyVideoPack

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher {
  [dispatcher registerMethod:@"app.bsky.video.getJobStatus"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       NSString *jobId = [request queryParamForKey:@"jobId"];
                       if (!jobId) {
                         [XrpcErrorHelper
                             setValidationError:response
                                        message:@"Missing jobId parameter"];
                         return;
                       }

                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{
                         @"jobId" : jobId,
                         @"state" : @"JOB_STATE_COMPLETE",
                         @"blobRef" : [NSNull null]
                       }];
                     }];

  [dispatcher registerMethod:@"app.bsky.video.uploadVideo"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{
                         @"jobId" : [[NSUUID UUID] UUIDString],
                         @"state" : @"JOB_STATE_RUNNING"
                       }];
                     }];

  [dispatcher registerMethod:@"app.bsky.video.getUploadLimits"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{
                         @"canUpload" : @YES,
                         @"remainingDailyVideos" : @25,
                         @"remainingDailyBytes" : @(50 * 1024 * 1024),
                         @"message" : @""
                       }];
                     }];
}

@end
