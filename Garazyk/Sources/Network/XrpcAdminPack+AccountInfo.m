// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0


#import "Network/XrpcAdminPack+AccountInfo.h"
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

@implementation XrpcAdminPack (AccountInfo)

+ (void)registerAccountInfoEndpoints:(XrpcDispatcher *)dispatcher
                services:(id<XrpcRoutePackServices>)services {
    PDSServiceDatabases *serviceDatabases = services.serviceDatabases;
    JWTMinter *jwtMinter = services.jwtMinter;
    id<PDSAdminController> adminController = services.adminController;
    PDSRepositoryService *repositoryService = services.repositoryService;

    #pragma mark - com.atproto.admin.* Account Info, Invites & Subject Status

    // Register com.atproto.admin.getAccountUsage
    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_admin_getAccountUsage
                       handler:^(HttpRequest *request, HttpResponse *response) {
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
            [response setJsonBody:@{@"error": @"MethodNotAllowed",
                                    @"message": @"Expected GET"}];
            return;
        }

        NSString *did = [request queryParamForKey:@"did"];
        if (did.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest",
                                    @"message": @"Missing did parameter"}];
            return;
        }

        NSError *didError = nil;
        if (![ATProtoValidator validateDID:did error:&didError]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidDid",
                                    @"message": didError.localizedDescription ?: @"Invalid DID"}];
            return;
        }

        // Verify account exists
        NSError *accountError = nil;
        PDSDatabaseAccount *account = [serviceDatabases getAccountByDid:did error:&accountError];
        if (!account) {
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{@"error": @"AccountNotFound",
                                    @"message": accountError.localizedDescription ?: @"Account not found"}];
            return;
        }

        // Query account_usage from actor store
        PDSActorStore *store = [repositoryService.databasePool storeForDid:did error:nil];
        NSDictionary *usage;
        if (store) {
            __block NSDictionary *usageResult = nil;
            [store readWithBlock:^(id<PDSActorStoreReader> reader, NSError **blockError) {
                PDSActorStore *actorStore = (PDSActorStore *)reader;
                NSString *sql = @"SELECT blob_bytes, blob_count, repo_bytes, record_count "
                                 @"FROM account_usage WHERE did = ?";
                sqlite3_stmt *stmt = [actorStore prepareStatement:sql error:blockError];
                if (!stmt) return;
                sqlite3_bind_text(stmt, 1, [did UTF8String], -1, SQLITE_TRANSIENT);
                if (sqlite3_step(stmt) == SQLITE_ROW) {
                    usageResult = @{
                        @"blobBytes": @(sqlite3_column_int64(stmt, 0)),
                        @"blobCount": @(sqlite3_column_int(stmt, 1)),
                        @"repoBytes": @(sqlite3_column_int64(stmt, 2)),
                        @"recordCount": @(sqlite3_column_int(stmt, 3))
                    };
                }
                [actorStore finalizeStatement:stmt];
            } error:nil];
            usage = usageResult ?: @{
                @"did": did,
                @"blobBytes": @(0),
                @"blobCount": @(0),
                @"repoBytes": @(0),
                @"recordCount": @(0)
            };
            if (usageResult) {
                NSMutableDictionary *mutable = [usage mutableCopy];
                mutable[@"did"] = did;
                usage = [mutable copy];
            }
        } else {
            usage = @{
                @"did": did,
                @"blobBytes": @(0),
                @"blobCount": @(0),
                @"repoBytes": @(0),
                @"recordCount": @(0)
            };
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:usage];
    }];

    // Register com.atproto.admin.getAccountInfo
    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_admin_getAccountInfo handler:^(HttpRequest *request, HttpResponse *response) {
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
        if (did.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing did parameter"}];
            return;
        }

        NSError *didError = nil;
        if (![ATProtoValidator validateDID:did error:&didError]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidDid", @"message": didError.localizedDescription ?: @"Invalid DID"}];
            return;
        }

        NSError *error = nil;
        PDSDatabaseAccount *account = [serviceDatabases getAccountByDid:did error:&error];
        if (!account) {
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{@"error": @"AccountNotFound", @"message": error.localizedDescription ?: @"Account not found"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:adminAccountViewFromAccount(account)];
    }];

    // Register com.atproto.admin.getAccountInfos
    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_admin_getAccountInfos handler:^(HttpRequest *request, HttpResponse *response) {
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

        NSArray<NSString *> *dids = queryArrayValues(request, @"dids");
        if (dids.count == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing dids parameter"}];
            return;
        }

        NSMutableArray<NSDictionary *> *infos = [NSMutableArray arrayWithCapacity:dids.count];
        for (NSString *did in dids) {
            NSError *didError = nil;
            if (![ATProtoValidator validateDID:did error:&didError]) {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"InvalidDid", @"message": didError.localizedDescription ?: @"Invalid DID"}];
                return;
            }

            PDSDatabaseAccount *account = [serviceDatabases getAccountByDid:did error:nil];
            if (account) {
                [infos addObject:adminAccountViewFromAccount(account)];
            }
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"infos": infos}];
    }];

    // Register com.atproto.admin.getInviteCodes
    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_admin_getInviteCodes handler:^(HttpRequest *request, HttpResponse *response) {
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

        NSString *sort = [request queryParamForKey:@"sort"] ?: @"recent";
        if (![sort isEqualToString:@"recent"] && ![sort isEqualToString:@"usage"]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"sort must be one of: recent, usage"}];
            return;
        }

        NSInteger limit = 100;
        NSString *limitParam = [request queryParamForKey:@"limit"];
        if (limitParam.length > 0 && (!parseStrictIntegerString(limitParam, &limit) || limit < 1 || limit > 500)) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"limit must be an integer between 1 and 500"}];
            return;
        }

        NSInteger offset = 0;
        NSString *cursorParam = [request queryParamForKey:@"cursor"];
        if (cursorParam.length > 0 && (!parseStrictIntegerString(cursorParam, &offset) || offset < 0)) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"cursor must be a non-negative integer"}];
            return;
        }

        NSError *error = nil;
        NSArray<NSDictionary *> *codes = loadAdminInviteCodeViews(serviceDatabases, sort, limit, offset, &error);
        if (!codes) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"QueryFailed", @"message": error.localizedDescription ?: @"Failed to query invite codes"}];
            return;
        }

        NSMutableDictionary *result = [@{@"codes": codes} mutableCopy];
        if (codes.count == (NSUInteger)limit) {
            result[@"cursor"] = [NSString stringWithFormat:@"%ld", (long)(offset + (NSInteger)codes.count)];
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    // Register com.atproto.admin.disableAccountInvites
    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_admin_disableAccountInvites handler:^(HttpRequest *request, HttpResponse *response) {
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
        NSString *accountDid = body[@"account"];
        if (![accountDid isKindOfClass:[NSString class]] || accountDid.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing account"}];
            return;
        }

        NSError *didError = nil;
        if (![ATProtoValidator validateDID:accountDid error:&didError]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidDid", @"message": didError.localizedDescription ?: @"Invalid DID"}];
            return;
        }

        NSError *updateError = nil;
        if (!setInviteEnabledForAccount(serviceDatabases, accountDid, NO, &updateError)) {
            if (updateError.code == 404) {
                response.statusCode = HttpStatusNotFound;
                [response setJsonBody:@{@"error": @"AccountNotFound", @"message": updateError.localizedDescription ?: @"Account not found"}];
            } else {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"InviteUpdateFailed", @"message": updateError.localizedDescription ?: @"Failed to disable account invites"}];
            }
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    // Register com.atproto.admin.enableAccountInvites
    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_admin_enableAccountInvites handler:^(HttpRequest *request, HttpResponse *response) {
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
        NSString *accountDid = body[@"account"];
        if (![accountDid isKindOfClass:[NSString class]] || accountDid.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing account"}];
            return;
        }

        NSError *didError = nil;
        if (![ATProtoValidator validateDID:accountDid error:&didError]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidDid", @"message": didError.localizedDescription ?: @"Invalid DID"}];
            return;
        }

        NSError *updateError = nil;
        if (!setInviteEnabledForAccount(serviceDatabases, accountDid, YES, &updateError)) {
            if (updateError.code == 404) {
                response.statusCode = HttpStatusNotFound;
                [response setJsonBody:@{@"error": @"AccountNotFound", @"message": updateError.localizedDescription ?: @"Account not found"}];
            } else {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"InviteUpdateFailed", @"message": updateError.localizedDescription ?: @"Failed to enable account invites"}];
            }
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

}

@end
