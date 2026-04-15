#import "Network/XrpcAppBskyVideoPack.h"

#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcAuthHelper.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/XrpcHandler.h"

@implementation XrpcAppBskyVideoPack

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                     jwtMinter:(JWTMinter *)jwtMinter
               adminController:(id<PDSAdminController>)adminController {
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
                         [XrpcErrorHelper setValidationError:response
                                                    message:@"Missing request body"];
                         return;
                       }

                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{
                         @"jobStatus" : @{
                           @"jobId" : [[NSUUID UUID] UUIDString],
                           @"did" : did,
                           @"state" : @"JOB_STATE_COMPLETED",
                           @"progress" : @100
                         }
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
