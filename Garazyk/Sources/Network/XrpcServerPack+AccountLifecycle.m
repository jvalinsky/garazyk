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
#import "App/ATProtoServiceConfiguration.h"
#import "Services/PDS/PDSAccountService.h"
#import "Services/PDS/PDSRepositoryService.h"
#import "Admin/PDSAdminController.h"
#import "Auth/PDSSecondFactorService.h"
#import "Auth/Secp256k1.h"
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
#import <sqlite3.h>

@implementation XrpcServerPack (AccountLifecycle)

+ (void)registerAccountLifecycleEndpoints:(XrpcDispatcher *)dispatcher
                                  services:(id<XrpcRoutePackServices>)services {
    JWTMinter *jwtMinter = services.jwtMinter;
    id<PDSAdminController> adminController = services.adminController;
    id<PDSAccountService> accountService = services.accountService;
    PDSServiceDatabases *serviceDatabases = services.serviceDatabases;
#pragma mark - com.atproto.server.accountLifecycle.*
    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_server_getAccount handler:^(HttpRequest *request, HttpResponse *response) {
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

    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_server_deleteAccount handler:^(HttpRequest *request, HttpResponse *response) {
        NSDictionary *body = request.jsonBody;
        NSString *token = body[@"token"];
        NSString *did = body[@"did"];
        NSString *password = body[@"password"];

        if (!did || !password) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing did or password"}];
            return;
        }

        // If a confirmation token is present, validate it before deleting.
        if (token.length > 0) {
            sqlite3 *db = (sqlite3 *)[serviceDatabases serviceDatabase];
            if (!db) {
                response.statusCode = HttpStatusInternalServerError;
                [response setJsonBody:@{@"error": @"AccountDeletionFailed", @"message": @"Service unavailable"}];
                return;
            }

            sqlite3_stmt *stmt = NULL;
            if (sqlite3_prepare_v2(db, "SELECT did, expires_at, used_at FROM password_reset_tokens WHERE token = ?", -1, &stmt, NULL) != SQLITE_OK) {
                response.statusCode = HttpStatusInternalServerError;
                [response setJsonBody:@{@"error": @"AccountDeletionFailed", @"message": @"Service unavailable"}];
                return;
            }
            sqlite3_bind_text(stmt, 1, token.UTF8String, -1, SQLITE_TRANSIENT);

            NSString *tokenDid = nil;
            NSTimeInterval expiresAt = 0;
            BOOL alreadyUsed = NO;

            if (sqlite3_step(stmt) == SQLITE_ROW) {
                const unsigned char *didText = sqlite3_column_text(stmt, 0);
                if (didText) tokenDid = [NSString stringWithUTF8String:(const char *)didText];
                expiresAt = (NSTimeInterval)sqlite3_column_int64(stmt, 1);
                alreadyUsed = (sqlite3_column_type(stmt, 2) != SQLITE_NULL);
            }
            sqlite3_finalize(stmt);

            if (!tokenDid || alreadyUsed) {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"InvalidToken", @"message": @"Invalid confirmation token"}];
                return;
            }
            if ([[NSDate date] timeIntervalSince1970] > expiresAt) {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"ExpiredToken", @"message": @"Confirmation token has expired"}];
                return;
            }
            if (![tokenDid isEqualToString:did]) {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"InvalidToken", @"message": @"Token does not match account"}];
                return;
            }

            // Atomically claim the token.
            NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
            sqlite3_stmt *claimStmt = NULL;
            if (sqlite3_prepare_v2(db,
                "UPDATE password_reset_tokens SET used_at = ? WHERE token = ? AND used_at IS NULL",
                -1, &claimStmt, NULL) != SQLITE_OK) {
                response.statusCode = HttpStatusInternalServerError;
                [response setJsonBody:@{@"error": @"AccountDeletionFailed", @"message": @"Service unavailable"}];
                return;
            }
            sqlite3_bind_int64(claimStmt, 1, (sqlite3_int64)now);
            sqlite3_bind_text(claimStmt, 2, token.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_step(claimStmt);
            if (sqlite3_changes(db) == 0) {
                sqlite3_finalize(claimStmt);
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"InvalidToken", @"message": @"Invalid confirmation token"}];
                return;
            }
            sqlite3_finalize(claimStmt);
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
        [response setJsonBody:@{@"success": @YES}];
    }];

    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_server_checkAccountStatus handler:^(HttpRequest *request, HttpResponse *response) {
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

    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_server_activateAccount handler:^(HttpRequest *request, HttpResponse *response) {
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
        [response setJsonBody:@{@"success": @YES}];

        // Notify firehose of account activation (#account event)
        [[NSNotificationCenter defaultCenter]
            postNotificationName:PDSAccountActivatedNotification
                          object:nil
                        userInfo:@{PDSAccountEventDidKey: did}];
    }];

    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_server_deactivateAccount handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader services:services request:request response:response];

        if (!did) {
            response.statusCode = HttpStatusUnauthorized;
            [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            return;
        }

        NSDictionary *body = request.jsonBody;
        NSString *reason = body[@"reason"];

        NSError *error = nil;
        BOOL success = [adminController deactivateAccount:did reason:reason ?: @"User deactivation" error:&error];

        if (!success) {
            response.statusCode = 400;
            [response setJsonBody:@{@"error": @"DeactivationFailed", @"message": error.localizedDescription ?: @"Failed to deactivate account"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"success": @YES}];

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
