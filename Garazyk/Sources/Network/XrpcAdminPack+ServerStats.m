// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0


#import "Network/XrpcAdminPack+ServerStats.h"
#import "Network/XrpcAdminPack_Internal.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcAuthHelper.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/XrpcIdentityHelper.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Auth/JWT.h"
#import "Database/ActorStore/PDSActorStoreInternal.h"
#import "Database/Service/ServiceDatabases.h"
#import "Database/PDSDatabase.h"
#import "Database/PDSDatabase+Moderation.h"
#import "Admin/PDSAdminController.h"
#import "Services/PDS/PDSRecordService.h"
#import "Services/PDS/PDSRepositoryService.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Admin/Diagnostics/BlobAudit/PDSBlobAuditManager.h"
#import "Core/ATProtoValidator.h"
#import "Core/ATURI.h"
#import "Identity/ATProtoHandleValidator.h"
#import "Core/NSDateFormatter+ATProto.h"
#import "Debug/GZLogger.h"
#import "Network/Generated/GZXrpcNSID.h"

@implementation XrpcAdminPack (ServerStats)

+ (void)registerServerStatsEndpoints:(XrpcDispatcher *)dispatcher
                services:(id<XrpcRoutePackServices>)services {
    PDSServiceDatabases *serviceDatabases = services.serviceDatabases;
    JWTMinter *jwtMinter = services.jwtMinter;
    id<PDSAdminController> adminController = services.adminController;
    PDSRepositoryService *repositoryService = services.repositoryService;
    PDSBlobAuditManager *auditManager = services.blobAuditManager;

    #pragma mark - com.atproto.admin.* Server Stats, Audit & Repair

    // com.atproto.admin.getServerStats
    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_admin_getServerStats
                       handler:^(HttpRequest *request, HttpResponse *response) {
        if (![XrpcAuthHelper authorizeAdminRequest:request
                                           response:response
                                   serviceDatabases:serviceDatabases
                                          jwtMinter:jwtMinter
                                    adminController:adminController]) {
            return;
        }
        
        NSError *error = nil;
        NSDictionary *stats = [adminController getServerStatsWithError:&error];
        if (!stats) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"InternalError", @"message": error.localizedDescription ?: @"Failed to get stats"}];
            return;
        }
        
        response.statusCode = HttpStatusOK;
        [response setJsonBody:stats];
    }];
    
    // com.atproto.admin.queryAuditLog
    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_admin_queryAuditLog
                       handler:^(HttpRequest *request, HttpResponse *response) {
        if (![XrpcAuthHelper authorizeAdminRequest:request
                                           response:response
                                   serviceDatabases:serviceDatabases
                                          jwtMinter:jwtMinter
                                    adminController:adminController]) {
            return;
        }
        
        NSString *limitStr = [request queryParamForKey:@"limit"];
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSInteger limit = limitStr ? [limitStr integerValue] : 50;
        if (limit <= 0) limit = 50;
        
        NSMutableDictionary *filters = [NSMutableDictionary dictionary];
        NSString *adminDid = [request queryParamForKey:@"adminDid"];
        if (adminDid) filters[@"admin_did"] = adminDid;
        
        NSError *error = nil;
        NSDictionary *result = [adminController queryAuditLog:filters limit:limit cursor:cursor error:&error];
        if (!result) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"InternalError", @"message": error.localizedDescription ?: @"Failed to query audit log"}];
            return;
        }
        
        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    // com.atproto.admin.repairRepo
    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_admin_repairRepo
                       handler:^(HttpRequest *request, HttpResponse *response) {
        if (![XrpcAuthHelper authorizeAdminRequest:request
                                           response:response
                                   serviceDatabases:serviceDatabases
                                          jwtMinter:jwtMinter
                                    adminController:adminController]) {
            return;
        }
        
        if (request.method != HttpMethodPOST) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"POST" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed", @"message": @"Expected POST"}];
            return;
        }

        NSDictionary *body = request.jsonBody;
        NSString *did = body[@"did"];
        
        if (did.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"did is required"}];
            return;
        }

        NSError *error = nil;
        if (![repositoryService forceReinitializeRepoForDid:did error:&error]) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"InternalError", @"message": error.localizedDescription ?: @"Failed to repair repository"}];
            return;
        }
        
        // Log the action
        [adminController logAdminAction:@"REPAIR_REPO"
                             subjectType:@"account"
                               subjectId:did
                                 details:@{@"action": @"force_reinitialize"}
                               ipAddress:nil
                                adminDid:@"" // Extract from JWT if needed
                                   error:nil];

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"success": @YES, @"did": did}];
    }];

    // com.atproto.admin.runBlobAudit
    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_admin_runBlobAudit
                       handler:^(HttpRequest *request, HttpResponse *response) {
        if (![XrpcAuthHelper authorizeAdminRequest:request
                                           response:response
                                   serviceDatabases:serviceDatabases
                                          jwtMinter:jwtMinter
                                    adminController:adminController]) {
            return;
        }

        if (request.method != HttpMethodPOST) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"POST" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed", @"message": @"Expected POST"}];
            return;
        }

        NSDictionary *body = request.jsonBody;
        NSString *type = body[@"type"] ?: @"consistency";
        BOOL dryRun = [body[@"dryRun"] boolValue];

        NSString *jobId = [auditManager startAuditWithType:type dryRun:dryRun];
        if (!jobId) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"InternalError", @"message": @"Failed to start audit job"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"jobId": jobId, @"type": type, @"status": @"queued"}];
    }];

    // com.atproto.admin.getBlobAuditStatus
    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_admin_getBlobAuditStatus
                       handler:^(HttpRequest *request, HttpResponse *response) {
        if (![XrpcAuthHelper authorizeAdminRequest:request
                                           response:response
                                   serviceDatabases:serviceDatabases
                                          jwtMinter:jwtMinter
                                    adminController:adminController]) {
            return;
        }

        NSString *jobId = [request queryParamForKey:@"jobId"];
        if (jobId.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"jobId is required"}];
            return;
        }

        NSDictionary *status = [auditManager jobStatusForId:jobId];
        if (!status) {
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{@"error": @"NotFound", @"message": @"Job not found"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:status];
    }];

}

@end
