// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0


#import "Network/XrpcAdminPack+Lifecycle.h"
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

@implementation XrpcAdminPack (Lifecycle)

+ (void)registerLifecycleEndpoints:(XrpcDispatcher *)dispatcher
                services:(id<XrpcRoutePackServices>)services {
    PDSServiceDatabases *serviceDatabases = services.serviceDatabases;
    JWTMinter *jwtMinter = services.jwtMinter;
    id<PDSAdminController> adminController = services.adminController;
    PDSRecordService *recordService = services.recordService;

    #pragma mark - com.atproto.admin.* Account Lifecycle, Records & Takedown

    // Register com.atproto.admin.updateSubjectStatus
    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_admin_updateSubjectStatus handler:^(HttpRequest *request, HttpResponse *response) {
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
        if (!body) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing request body"}];
            return;
        }

        NSDictionary *subject = subjectStatusSubjectFromRequestBody(body);
        NSString *did = subject[@"did"];
        NSString *uri = subject[@"uri"];
        NSString *reason = body[@"reason"];

        if (did.length == 0 && uri.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing subject DID or record URI"}];
            return;
        }

        NSError *error = nil;
        BOOL success = NO;
        if (did.length > 0) {
            success = [adminController takeDownAccount:did reason:reason error:&error];
        } else {
            NSDictionary *result = [adminController moderateRecord:@{
                @"uri": uri,
                @"action": @"takedown",
                @"reason": reason ?: @""
            } error:&error];
            success = [result[@"status"] isEqualToString:@"success"];
        }

        if (!success) {
            response.statusCode = 400;
            [response setJsonBody:@{@"error": @"UpdateFailed", @"message": error.localizedDescription ?: @"Failed to update status"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"success": @YES}];
    }];

    // Compatibility policy: This endpoint tracks the upstream com.atproto.admin.getRecord
    // lexicon exactly. Output shape matches {uri, cid?, value}. If the upstream lexicon
    // adds new required fields, this handler must be updated to provide them. Custom
    // extensions (e.g., additional output fields) should use the tools.garazyk.* namespace
    // rather than extending this endpoint.
    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_admin_getRecord handler:^(HttpRequest *request, HttpResponse *response) {
        if (![XrpcAuthHelper authorizeAdminRequest:request
                                           response:response
                                   serviceDatabases:serviceDatabases
                                          jwtMinter:jwtMinter
                                    adminController:adminController]) {
            return;
        }
        if (request.method != HttpMethodGET) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"GET" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed", @"message": @"Expected GET"}];
            return;
        }

        NSString *uriString = [request queryParamForKey:@"uri"];
        if (uriString.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing required parameter: uri"}];
            return;
        }

        NSError *uriError = nil;
        ATURI *parsedUri = [ATURI uriWithString:uriString error:&uriError];
        if (!parsedUri) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Invalid AT-URI format"}];
            return;
        }

        NSString *did = parsedUri.did;
        NSError *error = nil;
        NSDictionary *record = [recordService getRecord:uriString forDid:did error:&error];
        if (!record) {
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{@"error": @"RecordNotFound", @"message": error.localizedDescription ?: @"Record not found"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:record];
    }];

    // Register com.atproto.admin.getSubjectStatus
    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_admin_getSubjectStatus handler:^(HttpRequest *request, HttpResponse *response) {
        if (![XrpcAuthHelper authorizeAdminRequest:request
                                           response:response
                                   serviceDatabases:serviceDatabases
                                          jwtMinter:jwtMinter
                                    adminController:adminController]) {
            return;
        }
        if (request.method != HttpMethodGET) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"GET" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed", @"message": @"Expected GET"}];
            return;
        }

        NSString *did = [request queryParamForKey:@"did"];
        if (!did) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing did parameter"}];
            return;
        }

        NSError *error = nil;
        BOOL isTakedown = [adminController isAccountTakedownActive:did error:&error];

        if (error) {
            response.statusCode = 500;
            [response setJsonBody:@{@"error": @"QueryFailed", @"message": error.localizedDescription}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{
            @"subject": @{@"did": did},
            @"takedown": @(isTakedown)
        }];
    }];

    // Register com.atproto.admin.getAccountTakedown
    // DEPRECATED: This method was removed. Moderation has moved to tools.ozone.*
    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_admin_getAccountTakedown handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusGone;
        [response setJsonBody:@{
            @"error": @"MethodNotSupported",
            @"message": @"This method was removed. Moderation has moved to tools.ozone.* - please contact your moderation service administrator."
        }];
    }];

    // Register com.atproto.admin.deleteAccount
    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_admin_deleteAccount handler:^(HttpRequest *request, HttpResponse *response) {
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

        NSDictionary *body = request.jsonBody ?: @{};
        NSString *did = body[@"did"];
        if (![did isKindOfClass:[NSString class]] || did.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing did"}];
            return;
        }

        NSError *didError = nil;
        if (![ATProtoValidator validateDID:did error:&didError]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidDid", @"message": didError.localizedDescription ?: @"Invalid DID"}];
            return;
        }

        NSError *deleteError = nil;
        if (!deleteAccountAsAdmin(serviceDatabases, did, &deleteError)) {
            if (deleteError.code == 404) {
                response.statusCode = HttpStatusNotFound;
                [response setJsonBody:@{@"error": @"AccountNotFound", @"message": deleteError.localizedDescription ?: @"Account not found"}];
            } else {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"AccountDeletionFailed", @"message": deleteError.localizedDescription ?: @"Failed to delete account"}];
            }
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    // Register com.atproto.admin.disableInviteCodes
    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_admin_disableInviteCodes handler:^(HttpRequest *request, HttpResponse *response) {
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

        NSDictionary *body = request.jsonBody ?: @{};
        NSError *validationError = nil;
        NSArray<NSString *> *codes = validatedUniqueStringArrayFromJSONValue(body[@"codes"], @"codes", &validationError);
        if (!codes) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": validationError.localizedDescription ?: @"Invalid codes"}];
            return;
        }
        NSArray<NSString *> *accounts = validatedUniqueStringArrayFromJSONValue(body[@"accounts"], @"accounts", &validationError);
        if (!accounts) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": validationError.localizedDescription ?: @"Invalid accounts"}];
            return;
        }

        NSError *disableError = nil;
        if (![adminController disableInviteCodesWithCodes:codes accounts:accounts error:&disableError]) {
            if (disableError.code == 404) {
                response.statusCode = HttpStatusNotFound;
                [response setJsonBody:@{@"error": @"AccountNotFound", @"message": disableError.localizedDescription ?: @"Account not found"}];
            } else {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"InviteUpdateFailed", @"message": disableError.localizedDescription ?: @"Failed to disable invite codes"}];
            }
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    // Register com.atproto.admin.updateAccountSigningKey
    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_admin_updateAccountSigningKey handler:^(HttpRequest *request, HttpResponse *response) {
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

        NSDictionary *body = request.jsonBody ?: @{};
        NSString *did = body[@"did"];
        NSString *signingKey = body[@"signingKey"];

        NSError *didError = nil;
        if (![did isKindOfClass:[NSString class]] || ![ATProtoValidator validateDID:did error:&didError]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidDid", @"message": didError.localizedDescription ?: @"Invalid DID"}];
            return;
        }

        if (![signingKey isKindOfClass:[NSString class]]
            || ![signingKey hasPrefix:@"did:key:"]
            || signingKey.length <= @"did:key:".length) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"signingKey must be a did:key identifier"}];
            return;
        }

        NSError *updateError = nil;
        if (!updateAccountSigningKey(serviceDatabases, did, signingKey, &updateError)) {
            if (updateError.code == 404) {
                response.statusCode = HttpStatusNotFound;
                [response setJsonBody:@{@"error": @"AccountNotFound", @"message": updateError.localizedDescription ?: @"Account not found"}];
            } else {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"SigningKeyUpdateFailed", @"message": updateError.localizedDescription ?: @"Failed to update signing key"}];
            }
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

}

@end
