// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Network/XrpcServerPack+AccountLifecycle.h"
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

@implementation XrpcServerPack (AccountLifecycle)

+ (void)registerAccountLifecycleEndpoints:(XrpcDispatcher *)dispatcher
                                  services:(id<XrpcRoutePackServices>)services {
    ATProtoJWTMinter *jwtMinter = services.jwtMinter;
    id<PDSAdminController> adminController = services.adminController;
    id<PDSAccountService> accountService = services.accountService;
    PDSServiceDatabases *serviceDatabases = services.serviceDatabases;
#pragma mark - com.atproto.server.accountLifecycle.*
    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_server_getAccount handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader services:services request:request response:response];

        if (!did) {
            response.statusCode = HttpStatusUnauthorized;
            [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            return;
        }

        NSError *error = nil;
        NSDictionary *account = [accountService getAccountForDid:did error:&error];
        if (!account) {
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{@"error": @"AccountNotFound"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:account];
    }];

    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_server_deleteAccount handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *authenticatedDid = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader services:services request:request response:response];
        if (!authenticatedDid) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        NSDictionary *body = request.jsonBody ?: @{};
        BOOL typeMismatch = NO;
        NSString *token = AuthTypedValue(body, @"token", [NSString class], &typeMismatch);
        NSString *did = AuthTypedValue(body, @"did", [NSString class], &typeMismatch);
        NSString *password = AuthTypedValue(body, @"password", [NSString class], &typeMismatch);
        if (typeMismatch) {
            [XrpcErrorHelper setInvalidRequestError:response message:@"Request field has wrong type"];
            return;
        }
        if (did.length == 0 || password.length == 0 || token.length == 0) {
            [XrpcErrorHelper setInvalidRequestError:response message:@"did, password, and token are required"];
            return;
        }
        if (![ATProtoValidator validateDID:did error:nil]) {
            [XrpcErrorHelper setInvalidRequestError:response message:@"Invalid did"];
            return;
        }
        if (![authenticatedDid isEqualToString:did]) {
            response.statusCode = HttpStatusForbidden;
            [response setJsonBody:@{@"error": @"Forbidden", @"message": @"Authenticated account does not match did"}];
            return;
        }

        PDSDatabase *db = [serviceDatabases serviceDatabaseWithError:nil];
        if (!db) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"AccountDeletionFailed", @"message": @"Service unavailable"}];
            return;
        }

        // The conditional update validates the token's account, expiry, and
        // unused state while claiming it, so a concurrent replay cannot pass.
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        NSInteger claimedRows = 0;
        BOOL claimed = [db executeParameterizedUpdate:
            @"UPDATE password_reset_tokens SET used_at = ? WHERE token = ? AND did = ? AND used_at IS NULL AND expires_at >= ?"
                                               params:@[@((long long)now), token, did, @((long long)now)]
                                          changedRows:&claimedRows
                                                error:nil];
        if (!claimed) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"AccountDeletionFailed", @"message": @"Service unavailable"}];
            return;
        }
        if (claimedRows == 0) {
            NSError *lookupError = nil;
            NSArray<NSDictionary *> *tokenRows = [db executeParameterizedQuery:
                @"SELECT expires_at, used_at FROM password_reset_tokens WHERE token = ? AND did = ?"
                                                                        params:@[token, did]
                                                                         error:&lookupError];
            if (lookupError) {
                response.statusCode = HttpStatusInternalServerError;
                [response setJsonBody:@{@"error": @"AccountDeletionFailed", @"message": @"Service unavailable"}];
                return;
            }
            NSDictionary *tokenRow = tokenRows.firstObject;
            if (tokenRow && tokenRow[@"used_at"] == nil && [tokenRow[@"expires_at"] doubleValue] < now) {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"ExpiredToken", @"message": @"Confirmation token has expired"}];
                return;
            }
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidToken", @"message": @"Invalid confirmation token"}];
            return;
        }

        NSError *error = nil;
        BOOL success = [accountService deleteAccount:did password:password error:&error];

        if (!success) {
            response.statusCode = 400;
            [response setJsonBody:@{@"error": @"AccountDeletionFailed", @"message": error.localizedDescription ?: @"Failed to delete account"}];
            return;
        }

        [serviceDatabases logHostingEvent:did type:@"account_deleted" details:@{} createdBy:did error:nil];

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_server_checkAccountStatus handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader services:services request:request response:response];

        if (!did) {
            response.statusCode = HttpStatusUnauthorized;
            [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            return;
        }

        NSError *error = nil;
        NSDictionary *account = [accountService getAccountForDid:did error:&error];

        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        result[@"valid"] = @(account != nil && !error);

        if (account[@"takedown"]) {
            result[@"takedown"] = account[@"takedown"];
        }

        if (error) {
            result[@"error"] = error.localizedDescription;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_server_activateAccount handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader services:services request:request response:response];

        if (!did) {
            response.statusCode = HttpStatusUnauthorized;
            [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            return;
        }

        NSError *error = nil;
        BOOL success = [adminController reinstateAccount:did error:&error];

        if (!success) {
            response.statusCode = 400;
            [response setJsonBody:@{@"error": @"ActivationFailed", @"message": error.localizedDescription ?: @"Failed to activate account"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];

        // Notify firehose of account activation (#account event)
        [[NSNotificationCenter defaultCenter]
            postNotificationName:PDSAccountActivatedNotification
                          object:nil
                        userInfo:@{PDSAccountEventDidKey: did}];
    }];

    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_server_deactivateAccount handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader services:services request:request response:response];

        if (!did) {
            response.statusCode = HttpStatusUnauthorized;
            [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            return;
        }

        NSDictionary *body = request.jsonBody ?: @{};
        BOOL typeMismatch = NO;
        NSString *deleteAfter = AuthTypedValue(body, @"deleteAfter", [NSString class], &typeMismatch);
        if (typeMismatch) {
            [XrpcErrorHelper setInvalidRequestError:response message:@"Request field has wrong type"];
            return;
        }
        if (deleteAfter && ![ATProtoValidator validateDatetime:deleteAfter error:nil]) {
            [XrpcErrorHelper setInvalidRequestError:response message:@"Invalid deleteAfter datetime"];
            return;
        }

        // deleteAfter is a recommendation only. The current admin-service
        // boundary has no retention-deadline storage contract, so it is
        // validated here and intentionally not persisted or mapped to reason.
        NSError *error = nil;
        BOOL success = [adminController deactivateAccount:did reason:@"User deactivation" error:&error];

        if (!success) {
            response.statusCode = 400;
            [response setJsonBody:@{@"error": @"DeactivationFailed", @"message": error.localizedDescription ?: @"Failed to deactivate account"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];

        // Notify firehose of account deactivation (#account event)
        [[NSNotificationCenter defaultCenter]
            postNotificationName:PDSAccountDeactivatedNotification
                          object:nil
                        userInfo:@{
                            PDSAccountEventDidKey: did,
                            PDSAccountEventStatusKey: @"deactivated"
                        }];
    }];
}

@end
