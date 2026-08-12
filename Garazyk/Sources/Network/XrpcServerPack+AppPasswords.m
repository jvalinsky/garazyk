// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Network/XrpcServerPack+AppPasswords.h"
#import "Network/XrpcServerPack_Internal.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcAuthHelper.h"
#import "Network/XrpcIdentityHelper.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/XrpcMethodRegistry.h"
#import "Network/XrpcServiceAuthHelper.h"
#import "Auth/AuthClaimTypeCheck.h"
#import "App/ATProtoServiceConfiguration.h"
#import "Services/PDS/PDSAccountService.h"
#import "Services/PDS/PDSRepositoryService.h"
#import "Admin/PDSAdminController.h"
#import "Auth/PDSSecondFactorService.h"
#import "Auth/Crypto/Secp256k1.h"
#import "Core/ATProtoValidator.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/Monitoring/PDSHealthCheck.h"
#import "Identity/ATProtoHandleValidator.h"
#import "Core/DID.h"
#import "Core/PDSAccountEvents.h"
#import "Debug/GZLogger.h"
#import "Core/NSDateFormatter+ATProto.h"
#import "Network/Generated/GZXrpcNSID.h"

@implementation ATProtoXrpcServerPack (AppPasswords)

+ (void)registerAppPasswordEndpoints:(ATProtoXrpcDispatcher *)dispatcher
                             services:(id<XrpcRoutePackServices>)services {
    ATProtoJWTMinter *jwtMinter = services.jwtMinter;
    id<PDSAdminController> adminController = services.adminController;
    PDSServiceDatabases *serviceDatabases = services.serviceDatabases;

#pragma mark - com.atproto.server.appPasswords.*
    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_server_createAppPassword handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        if (request.method != HttpMethodPOST) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"POST" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed", @"message": @"Expected POST"}];
            return;
        }

        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [ATProtoXrpcAuthHelper extractDIDFromAuthHeader:authHeader services:services request:request response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        NSDictionary *body = request.jsonBody ?: @{};
        BOOL typeMismatch = NO;
        NSString *name = AuthTypedValue(body, @"name", [NSString class], &typeMismatch);
        NSNumber *privilegedNumber = AuthTypedValue(body, @"privileged", [NSNumber class], &typeMismatch);
        if (typeMismatch) {
            [ATProtoXrpcErrorHelper setInvalidRequestError:response message:@"Request field has wrong type"];
            return;
        }
        BOOL privileged = privilegedNumber.boolValue;

        if (name.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing name"}];
            return;
        }

        NSError *error = nil;
        NSDictionary *result = [serviceDatabases createAppPasswordForAccount:did
                                                                         name:name
                                                                   privileged:privileged
                                                                        error:&error];
        if (!result) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"AppPasswordCreateFailed", @"message": error.localizedDescription ?: @"Failed to create app password"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_server_listAppPasswords handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        if (request.method != HttpMethodGET) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"GET" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed", @"message": @"Expected GET"}];
            return;
        }

        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [ATProtoXrpcAuthHelper extractDIDFromAuthHeader:authHeader services:services request:request response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        NSError *error = nil;
        NSArray<NSDictionary *> *passwords = [serviceDatabases listAppPasswordsForAccount:did error:&error];
        if (error) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"AppPasswordListFailed", @"message": error.localizedDescription ?: @"Failed to list app passwords"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"passwords": passwords ?: @[]}];
    }];

    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_server_revokeAppPassword handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        if (request.method != HttpMethodPOST) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"POST" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed", @"message": @"Expected POST"}];
            return;
        }

        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [ATProtoXrpcAuthHelper extractDIDFromAuthHeader:authHeader services:services request:request response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        NSDictionary *body = request.jsonBody ?: @{};
        BOOL typeMismatch = NO;
        NSString *name = AuthTypedValue(body, @"name", [NSString class], &typeMismatch);
        if (typeMismatch) {
            [ATProtoXrpcErrorHelper setInvalidRequestError:response message:@"Request field has wrong type"];
            return;
        }
        if (name.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing name"}];
            return;
        }

        NSError *error = nil;
        BOOL success = [serviceDatabases revokeAppPasswordForAccount:did name:name error:&error];
        if (!success) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"AppPasswordRevokeFailed", @"message": error.localizedDescription ?: @"Failed to revoke app password"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];
}

@end
