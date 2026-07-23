// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0


#import "Network/XrpcAdminPack+Moderation.h"
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

@implementation XrpcAdminPack (Moderation)

+ (void)registerModerationEndpoints:(XrpcDispatcher *)dispatcher
                services:(id<XrpcRoutePackServices>)services {
    PDSServiceDatabases *serviceDatabases = services.serviceDatabases;
    JWTMinter *jwtMinter = services.jwtMinter;
    id<PDSAdminController> adminController = services.adminController;

    #pragma mark - com.atproto.admin.* Moderation (deprecated → tools.ozone.*)

    // Register com.atproto.admin.moderateAccount
    // DEPRECATED: This method was removed. Moderation has moved to tools.ozone.*
    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_admin_moderateAccount handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusGone;
        [response setJsonBody:@{
            @"error": @"MethodNotSupported",
            @"message": @"This method was removed. Moderation has moved to tools.ozone.* - please contact your moderation service administrator."
        }];
    }];

    // Register com.atproto.admin.moderateRecord
    // DEPRECATED: This method was removed. Moderation has moved to tools.ozone.*
    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_admin_moderateRecord handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusGone;
        [response setJsonBody:@{
            @"error": @"MethodNotSupported",
            @"message": @"This method was removed. Moderation has moved to tools.ozone.* - please contact your moderation service administrator."
        }];
    }];

    // Register com.atproto.admin.takeDownAccount
    // DEPRECATED: This method was removed. Moderation has moved to tools.ozone.*
    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_admin_takeDownAccount handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusGone;
        [response setJsonBody:@{
            @"error": @"MethodNotSupported",
            @"message": @"This method was removed. Moderation has moved to tools.ozone.* - please contact your moderation service administrator."
        }];
    }];

    // Register com.atproto.admin.getModerationReports
    // DEPRECATED: This method was removed. Moderation has moved to tools.ozone.*
    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_admin_getModerationReports handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusGone;
        [response setJsonBody:@{
            @"error": @"MethodNotSupported",
            @"message": @"This method was removed. Moderation has moved to tools.ozone.* - please contact your moderation service administrator."
        }];
    }];

    // Register com.atproto.admin.resolveReport
    // DEPRECATED: This method was removed. Moderation has moved to tools.ozone.*
    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_admin_resolveReport handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusGone;
        [response setJsonBody:@{
            @"error": @"MethodNotSupported",
            @"message": @"This method was removed. Moderation has moved to tools.ozone.* - please contact your moderation service administrator."
        }];
    }];
}

@end
