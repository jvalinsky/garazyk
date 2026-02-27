#import "Network/XrpcModerationMethods.h"
#import "Network/XrpcAuthHelper.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcHandler.h"
#import "Admin/PDSAdminController.h"
#import "Core/ATProtoValidator.h"
#import "Debug/PDSLogger.h"

@implementation XrpcModerationMethods

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                     jwtMinter:(JWTMinter *)jwtMinter
               adminController:(id<PDSAdminController>)adminController
              serviceDatabases:(PDSServiceDatabases *)serviceDatabases {

    [dispatcher registerComAtprotoModerationCreateReport:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                       jwtMinter:jwtMinter
                                                 adminController:adminController
                                                         request:request
                                                        response:response];
        if (!did) return;

        if (request.method != HttpMethodPOST) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"POST" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed", @"message": @"Expected POST"}];
            return;
        }

        NSDictionary *body = request.jsonBody;
        if (![body isKindOfClass:[NSDictionary class]]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing request body"}];
            return;
        }

        NSString *reasonType = body[@"reasonType"];
        id subject = body[@"subject"];

        if (![reasonType isKindOfClass:[NSString class]] || reasonType.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"reasonType is required"}];
            return;
        }

        if (![subject isKindOfClass:[NSDictionary class]]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"subject is required"}];
            return;
        }

        // Map XRPC input to admin service/controller input
        NSMutableDictionary *reportParams = [NSMutableDictionary dictionary];
        reportParams[@"reason_type"] = reasonType;
        reportParams[@"reason"] = body[@"reason"];
        reportParams[@"reported_by_did"] = did;

        NSString *subjectType = subject[@"$type"];
        if ([subjectType isEqualToString:@"com.atproto.admin.defs#repoRef"]) {
            reportParams[@"subject_type"] = @"account";
            reportParams[@"subject_did"] = subject[@"did"];
        } else if ([subjectType isEqualToString:@"com.atproto.repo.strongRef"]) {
           reportParams[@"subject_type"] = @"record";
           reportParams[@"subject_uri"] = subject[@"uri"];
           // Safe extraction of DID from URI
           NSArray *uriParts = [subject[@"uri"] componentsSeparatedByString:@"/"];
           if (uriParts.count >= 3) {
               reportParams[@"subject_did"] = uriParts[2];
           }
        } else {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Invalid subject type"}];
            return;
        }

        NSError *error = nil;
        NSDictionary *result = [adminController createReport:reportParams error:&error];
        if (!result) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"InternalError", @"message": error.localizedDescription ?: @"Failed to create report"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];
}

@end
