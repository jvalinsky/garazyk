// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
//
//  XrpcAdminMethods.m
//  ATProtoPDS
//
//  Domain module for com.atproto.admin.* XRPC endpoints.
//

#import "Network/XrpcAdminMethods.h"
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
#import "Admin/PDSAdminController.h"
#import "Services/PDS/PDSRepositoryService.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Admin/Diagnostics/BlobAudit/PDSBlobAuditManager.h"
#import "Core/ATProtoValidator.h"
#import "Identity/ATProtoHandleValidator.h"
#import "Core/NSDateFormatter+ATProto.h"
#import "Debug/PDSLogger.h"
#import <CommonCrypto/CommonKeyDerivation.h>

// Forward declarations of helper functions
static NSDictionary *adminAccountViewFromAccount(PDSDatabaseAccount *account);
static NSString *iso8601StringFromUnixTimestamp(NSTimeInterval timestamp);
static NSArray<NSString *> *queryArrayValues(HttpRequest *request, NSString *key);
static NSDictionary *adminInviteCodeViewFromRow(NSDictionary *row);
static NSArray<NSDictionary *> *loadAdminInviteCodeViews(PDSServiceDatabases *serviceDatabases,
                                                         NSString *sort,
                                                         NSInteger limit,
                                                         NSInteger offset,
                                                         NSError **error);
static BOOL setInviteEnabledForAccount(PDSServiceDatabases *serviceDatabases,
                                       NSString *did,
                                       BOOL enabled,
                                       NSError **error);
static BOOL deleteAccountAsAdmin(PDSServiceDatabases *serviceDatabases,
                                 NSString *did,
                                 NSError **error);
static BOOL updateAccountEmail(PDSServiceDatabases *serviceDatabases,
                               NSString *did,
                               NSString *email,
                               NSError **error);
static BOOL updateAccountPassword(PDSServiceDatabases *serviceDatabases,
                                  NSString *did,
                                  NSString *password,
                                  NSError **error);
static BOOL updateAccountSigningKey(PDSServiceDatabases *serviceDatabases,
                                    NSString *did,
                                    NSString *signingKey,
                                    NSError **error);
static BOOL isLikelyEmail(NSString *email);
static BOOL parseStrictIntegerString(NSString *str, NSInteger *outValue);
static BOOL resolveAccountIdentifierToDid(PDSServiceDatabases *serviceDatabases,
                                          NSString *identifier,
                                          NSString **outDid,
                                          NSError **error);
static BOOL executeServiceUpdate(PDSDatabase *db,
                                 NSString *sql,
                                 NSArray *params,
                                 BOOL ignoreMissingTable,
                                 NSError **error);
static BOOL isNoSuchTableError(NSError *error);
static NSData *pbkdf2HashPassword(NSString *password, NSData *salt, NSError **error);
static NSData *generateAccountPasswordSalt(void);
static NSArray<NSString *> *validatedUniqueStringArrayFromJSONValue(id value,
                                                                     NSString *fieldName,
                                                                     NSError **error);

@implementation XrpcAdminMethods

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
              serviceDatabases:(PDSServiceDatabases *)serviceDatabases
                     jwtMinter:(JWTMinter *)jwtMinter
               adminController:(id<PDSAdminController>)adminController
             repositoryService:(PDSRepositoryService *)repositoryService
                  auditManager:(PDSBlobAuditManager *)auditManager {
    
    // Register com.atproto.admin.searchAccounts
    [dispatcher registerComAtprotoAdminSearchAccounts:^(HttpRequest *request, HttpResponse *response) {
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

        NSInteger limit = 50;
        NSString *limitParam = [request queryParamForKey:@"limit"];
        if (limitParam.length > 0 && (!parseStrictIntegerString(limitParam, &limit) || limit < 1 || limit > 100)) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"limit must be an integer between 1 and 100"}];
            return;
        }

        NSInteger offset = 0;
        NSString *cursorParam = [request queryParamForKey:@"cursor"];
        if (cursorParam.length > 0 && (!parseStrictIntegerString(cursorParam, &offset) || offset < 0)) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"cursor must be a non-negative integer"}];
            return;
        }

        NSString *emailQuery = [[request queryParamForKey:@"email"] lowercaseString];
        NSError *queryError = nil;
        NSArray<PDSDatabaseAccount *> *allAccounts = [serviceDatabases getAllAccountsWithError:&queryError];
        if (!allAccounts) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"QueryFailed", @"message": queryError.localizedDescription ?: @"Failed to query accounts"}];
            return;
        }

        NSMutableArray<PDSDatabaseAccount *> *filteredAccounts = [NSMutableArray arrayWithCapacity:allAccounts.count];
        for (PDSDatabaseAccount *account in allAccounts) {
            if (emailQuery.length > 0) {
                NSString *accountEmail = [account.email lowercaseString];
                if (accountEmail.length == 0 || [accountEmail rangeOfString:emailQuery].location == NSNotFound) {
                    continue;
                }
            }
            [filteredAccounts addObject:account];
        }

        NSUInteger startIndex = (NSUInteger)MIN(offset, (NSInteger)filteredAccounts.count);
        NSUInteger endIndex = MIN(startIndex + (NSUInteger)limit, filteredAccounts.count);
        NSMutableArray<NSDictionary *> *views = [NSMutableArray arrayWithCapacity:endIndex - startIndex];
        for (NSUInteger index = startIndex; index < endIndex; index += 1) {
            [views addObject:adminAccountViewFromAccount(filteredAccounts[index])];
        }

        NSMutableDictionary *result = [@{@"accounts": views} mutableCopy];
        if (endIndex < filteredAccounts.count) {
            result[@"cursor"] = [NSString stringWithFormat:@"%lu", (unsigned long)endIndex];
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    // Register com.atproto.admin.sendEmail
    [dispatcher registerComAtprotoAdminSendEmail:^(HttpRequest *request, HttpResponse *response) {
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
        NSString *recipientDid = body[@"recipientDid"];
        NSString *senderDid = body[@"senderDid"];
        NSString *content = body[@"content"];
        NSString *subject = body[@"subject"];

        NSError *didError = nil;
        if (![recipientDid isKindOfClass:[NSString class]]
            || ![senderDid isKindOfClass:[NSString class]]
            || ![content isKindOfClass:[NSString class]]
            || content.length == 0
            || ![ATProtoValidator validateDID:recipientDid error:&didError]
            || ![ATProtoValidator validateDID:senderDid error:&didError]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": didError.localizedDescription ?: @"Missing or invalid senderDid, recipientDid, or content"}];
            return;
        }

        if ([subject isKindOfClass:[NSString class]] && subject.length > 500) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"subject is too long"}];
            return;
        }

        NSError *lookupError = nil;
        PDSDatabaseAccount *recipientAccount = [serviceDatabases getAccountByDid:recipientDid error:&lookupError];
        if (!recipientAccount) {
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{@"error": @"AccountNotFound", @"message": lookupError.localizedDescription ?: @"Recipient account not found"}];
            return;
        }

        PDS_LOG_INFO(@"Admin sendEmail recipient=%@ sender=%@ subject=%@", recipientDid, senderDid, subject ?: @"");
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"sent": @YES}];
    }];

    // Register com.atproto.admin.updateAccountEmail
    [dispatcher registerComAtprotoAdminUpdateAccountEmail:^(HttpRequest *request, HttpResponse *response) {
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
        NSString *accountIdentifier = body[@"account"];
        NSString *email = body[@"email"];
        if (email.length == 0 || !isLikelyEmail(email)) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing or invalid email"}];
            return;
        }

        NSString *did = nil;
        NSError *resolveError = nil;
        if (!resolveAccountIdentifierToDid(serviceDatabases, accountIdentifier, &did, &resolveError)) {
            if (resolveError.code == 404) {
                response.statusCode = HttpStatusNotFound;
                [response setJsonBody:@{@"error": @"AccountNotFound", @"message": resolveError.localizedDescription ?: @"Account not found"}];
            } else {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"InvalidRequest", @"message": resolveError.localizedDescription ?: @"Invalid account identifier"}];
            }
            return;
        }

        NSError *existingError = nil;
        PDSDatabaseAccount *existingAccount = [serviceDatabases getAccountByEmail:email error:&existingError];
        if (existingAccount && ![existingAccount.did isEqualToString:did]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"EmailAlreadyInUse", @"message": @"Email is already used by another account"}];
            return;
        }

        NSError *updateError = nil;
        if (!updateAccountEmail(serviceDatabases, did, email, &updateError)) {
            if (updateError.code == 404) {
                response.statusCode = HttpStatusNotFound;
                [response setJsonBody:@{@"error": @"AccountNotFound", @"message": updateError.localizedDescription ?: @"Account not found"}];
            } else {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"EmailUpdateFailed", @"message": updateError.localizedDescription ?: @"Failed to update email"}];
            }
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    // Register com.atproto.admin.updateAccountHandle
    [dispatcher registerComAtprotoAdminUpdateAccountHandle:^(HttpRequest *request, HttpResponse *response) {
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
        NSString *handle = body[@"handle"];

        NSError *didError = nil;
        if (![did isKindOfClass:[NSString class]] || ![ATProtoValidator validateDID:did error:&didError]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidDid", @"message": didError.localizedDescription ?: @"Invalid DID"}];
            return;
        }

        NSError *handleError = nil;
        if (![ATProtoHandleValidator validateHandle:handle error:&handleError]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidHandle", @"message": handleError.localizedDescription ?: @"Invalid handle"}];
            return;
        }
        NSString *normalizedHandle = [ATProtoHandleValidator normalizeHandle:handle];

        NSError *existingError = nil;
        PDSDatabaseAccount *existingAccount = [serviceDatabases getAccountByHandle:normalizedHandle error:&existingError];
        if (existingAccount && ![existingAccount.did isEqualToString:did]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"HandleAlreadyInUse", @"message": @"Handle is already used by another account"}];
            return;
        }

        NSError *updateError = nil;
        if (![XrpcIdentityHelper updateAccountHandle:serviceDatabases
                                                 did:did
                                              handle:normalizedHandle
                                               error:&updateError]) {
            if (updateError.code == 404) {
                response.statusCode = HttpStatusNotFound;
                [response setJsonBody:@{@"error": @"AccountNotFound", @"message": updateError.localizedDescription ?: @"Account not found"}];
            } else {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"HandleUpdateFailed", @"message": updateError.localizedDescription ?: @"Failed to update handle"}];
            }
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    // Register com.atproto.admin.updateAccountPassword
    [dispatcher registerComAtprotoAdminUpdateAccountPassword:^(HttpRequest *request, HttpResponse *response) {
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
        NSString *password = body[@"password"];

        if (did.length == 0 || password.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"did and password are required"}];
            return;
        }

        NSError *error = nil;
        if (!updateAccountPassword(serviceDatabases, did, password, &error)) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"InternalError", @"message": error.localizedDescription ?: @"Failed to update password"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:adminAccountViewFromAccount([serviceDatabases getAccountByDid:did error:nil])];
    }];

    // com.atproto.admin.getServerStats
    [dispatcher registerMethod:@"com.atproto.admin.getServerStats"
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
    [dispatcher registerMethod:@"com.atproto.admin.queryAuditLog"
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
    [dispatcher registerMethod:@"com.atproto.admin.repairRepo"
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
    [dispatcher registerMethod:@"com.atproto.admin.runBlobAudit"
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
    [dispatcher registerMethod:@"com.atproto.admin.getBlobAuditStatus"
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

    // Register com.atproto.admin.getAccountUsage
    [dispatcher registerMethod:@"com.atproto.admin.getAccountUsage"
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
    [dispatcher registerComAtprotoAdminGetAccountInfo:^(HttpRequest *request, HttpResponse *response) {
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
    [dispatcher registerComAtprotoAdminGetAccountInfos:^(HttpRequest *request, HttpResponse *response) {
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
    [dispatcher registerComAtprotoAdminGetInviteCodes:^(HttpRequest *request, HttpResponse *response) {
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
    [dispatcher registerComAtprotoAdminDisableAccountInvites:^(HttpRequest *request, HttpResponse *response) {
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
    [dispatcher registerComAtprotoAdminEnableAccountInvites:^(HttpRequest *request, HttpResponse *response) {
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

    // Register com.atproto.admin.updateSubjectStatus
    [dispatcher registerComAtprotoAdminUpdateSubjectStatus:^(HttpRequest *request, HttpResponse *response) {
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

        NSString *did = body[@"subject"][@"did"];
        NSString *reason = body[@"reason"];

        if (!did) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing subject DID"}];
            return;
        }

        NSError *error = nil;
        BOOL success = [adminController takeDownAccount:did reason:reason error:&error];

        if (!success) {
            response.statusCode = 400;
            [response setJsonBody:@{@"error": @"UpdateFailed", @"message": error.localizedDescription ?: @"Failed to update status"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"success": @YES}];
    }];

    // Register com.atproto.admin.getSubjectStatus
    [dispatcher registerComAtprotoAdminGetSubjectStatus:^(HttpRequest *request, HttpResponse *response) {
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
    [dispatcher registerComAtprotoAdminGetAccountTakedown:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusGone;
        [response setJsonBody:@{
            @"error": @"MethodNotSupported",
            @"message": @"This method was removed. Moderation has moved to tools.ozone.* - please contact your moderation service administrator."
        }];
    }];

    // Register com.atproto.admin.deleteAccount
    [dispatcher registerComAtprotoAdminDeleteAccount:^(HttpRequest *request, HttpResponse *response) {
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
    [dispatcher registerComAtprotoAdminDisableInviteCodes:^(HttpRequest *request, HttpResponse *response) {
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
    [dispatcher registerComAtprotoAdminUpdateAccountSigningKey:^(HttpRequest *request, HttpResponse *response) {
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

    // Register com.atproto.admin.moderateAccount
    // DEPRECATED: This method was removed. Moderation has moved to tools.ozone.*
    [dispatcher registerComAtprotoAdminModerateAccount:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusGone;
        [response setJsonBody:@{
            @"error": @"MethodNotSupported",
            @"message": @"This method was removed. Moderation has moved to tools.ozone.* - please contact your moderation service administrator."
        }];
    }];

    // Register com.atproto.admin.moderateRecord
    // DEPRECATED: This method was removed. Moderation has moved to tools.ozone.*
    [dispatcher registerComAtprotoAdminModerateRecord:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusGone;
        [response setJsonBody:@{
            @"error": @"MethodNotSupported",
            @"message": @"This method was removed. Moderation has moved to tools.ozone.* - please contact your moderation service administrator."
        }];
    }];

    // Register com.atproto.admin.takeDownAccount
    // DEPRECATED: This method was removed. Moderation has moved to tools.ozone.*
    [dispatcher registerMethod:@"com.atproto.admin.takeDownAccount" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusGone;
        [response setJsonBody:@{
            @"error": @"MethodNotSupported",
            @"message": @"This method was removed. Moderation has moved to tools.ozone.* - please contact your moderation service administrator."
        }];
    }];

    // Register com.atproto.admin.getModerationReports
    // DEPRECATED: This method was removed. Moderation has moved to tools.ozone.*
    [dispatcher registerComAtprotoAdminGetModerationReports:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusGone;
        [response setJsonBody:@{
            @"error": @"MethodNotSupported",
            @"message": @"This method was removed. Moderation has moved to tools.ozone.* - please contact your moderation service administrator."
        }];
    }];

    // Register com.atproto.admin.resolveReport
    // DEPRECATED: This method was removed. Moderation has moved to tools.ozone.*
    [dispatcher registerComAtprotoAdminResolveReport:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = HttpStatusGone;
        [response setJsonBody:@{
            @"error": @"MethodNotSupported",
            @"message": @"This method was removed. Moderation has moved to tools.ozone.* - please contact your moderation service administrator."
        }];
    }];
}

@end


#pragma mark - Helper Functions

static NSArray<NSString *> *validatedUniqueStringArrayFromJSONValue(id value,
                                                                     NSString *fieldName,
                                                                     NSError **error) {
    if (!value) {
        return @[];
    }
    if (![value isKindOfClass:[NSArray class]]) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.admin"
                                         code:400
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"%@ must be an array of strings", fieldName ?: @"field"]}];
        }
        return nil;
    }

    NSMutableArray<NSString *> *values = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (id rawValue in (NSArray *)value) {
        if (![rawValue isKindOfClass:[NSString class]]) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.atproto.admin"
                                             code:400
                                         userInfo:@{NSLocalizedDescriptionKey:
                                                        [NSString stringWithFormat:@"%@ must contain only strings", fieldName ?: @"field"]}];
            }
            return nil;
        }
        NSString *trimmed = [(NSString *)rawValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length == 0) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.atproto.admin"
                                             code:400
                                         userInfo:@{NSLocalizedDescriptionKey:
                                                        [NSString stringWithFormat:@"%@ cannot contain empty strings", fieldName ?: @"field"]}];
            }
            return nil;
        }
        if (![seen containsObject:trimmed]) {
            [seen addObject:trimmed];
            [values addObject:trimmed];
        }
    }

    return values;
}

static BOOL updateAccountSigningKey(PDSServiceDatabases *serviceDatabases,
                                    NSString *did,
                                    NSString *signingKey,
                                    NSError **error) {
    if (![signingKey hasPrefix:@"did:key:"]) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.admin"
                                         code:400
                                     userInfo:@{NSLocalizedDescriptionKey: @"signingKey must be a did:key identifier"}];
        }
        return NO;
    }

    PDSDatabaseAccount *account = [serviceDatabases getAccountByDid:did error:error];
    if (!account) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"com.atproto.admin"
                                         code:404
                                     userInfo:@{NSLocalizedDescriptionKey: @"Account not found"}];
        }
        return NO;
    }

    PDS_LOG_WARN(@"updateAccountSigningKey accepted but no DID document persistence is configured for DID %@ (signingKey=%@)", did, signingKey);
    return YES;
}

static NSString *iso8601StringFromUnixTimestamp(NSTimeInterval timestamp) {
    NSDate *date = timestamp > 0 ? [NSDate dateWithTimeIntervalSince1970:timestamp] : [NSDate date];
    return [NSDateFormatter atproto_stringFromDate:date];
}

static NSDictionary *adminAccountViewFromAccount(PDSDatabaseAccount *account) {
    NSMutableDictionary *view = [@{
        @"did": account.did ?: @"",
        @"handle": account.handle ?: @"",
        @"indexedAt": iso8601StringFromUnixTimestamp(account.createdAt)
    } mutableCopy];

    if (account.email.length > 0) {
        view[@"email"] = account.email;
    }

    return view;
}

static NSArray<NSString *> *queryArrayValues(HttpRequest *request, NSString *key) {
    NSMutableArray<NSString *> *values = [NSMutableArray array];
    NSArray<NSString *> *pairs = [request.queryString componentsSeparatedByString:@"&"];
    for (NSString *pair in pairs) {
        if (pair.length == 0) {
            continue;
        }
        NSRange eqRange = [pair rangeOfString:@"="];
        NSString *rawKey = eqRange.location == NSNotFound ? pair : [pair substringToIndex:eqRange.location];
        NSString *rawValue = eqRange.location == NSNotFound ? @"" : [pair substringFromIndex:eqRange.location + 1];

        NSString *decodedKey = [[rawKey stringByReplacingOccurrencesOfString:@"+" withString:@" "] stringByRemovingPercentEncoding] ?: rawKey;
        if (![decodedKey isEqualToString:key]) {
            continue;
        }

        NSString *decodedValue = [[rawValue stringByReplacingOccurrencesOfString:@"+" withString:@" "] stringByRemovingPercentEncoding] ?: rawValue;
        for (NSString *component in [decodedValue componentsSeparatedByString:@","]) {
            NSString *trimmed = [component stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (trimmed.length > 0) {
                [values addObject:trimmed];
            }
        }
    }

    if (values.count == 0) {
        NSString *singleValue = [request queryParamForKey:key];
        for (NSString *component in [singleValue componentsSeparatedByString:@","]) {
            NSString *trimmed = [component stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (trimmed.length > 0) {
                [values addObject:trimmed];
            }
        }
    }

    return values;
}

static NSDictionary *adminInviteCodeViewFromRow(NSDictionary *row) {
    NSString *code = [row[@"code"] isKindOfClass:[NSString class]] ? row[@"code"] : @"";
    NSString *accountDid = [row[@"account_did"] isKindOfClass:[NSString class]] ? row[@"account_did"] : @"";
    NSInteger uses = [row[@"uses"] respondsToSelector:@selector(integerValue)] ? [row[@"uses"] integerValue] : 0;
    NSInteger maxUses = [row[@"max_uses"] respondsToSelector:@selector(integerValue)] ? [row[@"max_uses"] integerValue] : 1;
    if (maxUses < 0) {
        maxUses = 0;
    }
    NSInteger available = maxUses - uses;
    if (available < 0) {
        available = 0;
    }
    BOOL disabled = [row[@"disabled"] respondsToSelector:@selector(boolValue)] ? [row[@"disabled"] boolValue] : NO;
    NSTimeInterval createdAt = [row[@"created_at"] respondsToSelector:@selector(doubleValue)] ? [row[@"created_at"] doubleValue] : 0;

    return @{
        @"code": code,
        @"available": @(available),
        @"disabled": @(disabled),
        @"forAccount": accountDid,
        @"createdBy": accountDid,
        @"createdAt": iso8601StringFromUnixTimestamp(createdAt),
        @"uses": @[]
    };
}

static NSArray<NSDictionary *> *loadAdminInviteCodeViews(PDSServiceDatabases *serviceDatabases,
                                                          NSString *sort,
                                                          NSInteger limit,
                                                          NSInteger offset,
                                                          NSError **error) {
    PDSDatabase *db = [serviceDatabases serviceDatabaseWithError:error];
    if (!db) {
        return nil;
    }

    // Whitelist allowed sort values to prevent SQL injection
    NSString *orderBy = nil;
    if ([sort isEqualToString:@"usage"]) {
        orderBy = @"uses DESC, created_at DESC, code ASC";
    } else if ([sort isEqualToString:@"created_at"] || [sort isEqualToString:@"code"] || [sort isEqualToString:@"uses"]) {
        orderBy = [NSString stringWithFormat:@"%@ DESC", sort];
    } else {
        orderBy = @"created_at DESC, code ASC";
    }
    NSString *sql = [NSString stringWithFormat:
                     @"SELECT code, account_did, created_at, uses, max_uses, disabled "
                     @"FROM invite_codes ORDER BY %@ LIMIT ? OFFSET ?", orderBy];
    NSArray<NSDictionary *> *rows = [db executeParameterizedQuery:sql
                                                           params:@[@(limit), @(offset)]
                                                            error:error];
    [db close];
    if (!rows) {
        return nil;
    }

    NSMutableArray<NSDictionary *> *codes = [NSMutableArray arrayWithCapacity:rows.count];
    for (NSDictionary *row in rows) {
        [codes addObject:adminInviteCodeViewFromRow(row)];
    }
    return codes;
}

static BOOL isNoSuchTableError(NSError *error) {
    if (!error) {
        return NO;
    }
    NSString *message = [error.localizedDescription lowercaseString];
    return [message containsString:@"no such table"];
}

static BOOL executeServiceUpdate(PDSDatabase *db,
                                 NSString *sql,
                                 NSArray *params,
                                 BOOL ignoreMissingTable,
                                 NSError **error) {
    NSError *updateError = nil;
    BOOL success = [db executeParameterizedUpdate:sql params:params error:&updateError];
    if (success || (ignoreMissingTable && isNoSuchTableError(updateError))) {
        return YES;
    }
    if (error) {
        *error = updateError ?: [NSError errorWithDomain:@"com.atproto.admin"
                                                    code:500
                                                userInfo:@{NSLocalizedDescriptionKey: @"Database update failed"}];
    }
    return NO;
}

static BOOL setInviteEnabledForAccount(PDSServiceDatabases *serviceDatabases,
                                       NSString *did,
                                       BOOL enabled,
                                       NSError **error) {
    PDSDatabase *db = [serviceDatabases serviceDatabaseWithError:error];
    if (!db) {
        return NO;
    }

    PDSDatabaseAccount *account = [db getAccountByDid:did error:error];
    if (!account) {
        [db close];
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"com.atproto.admin"
                                         code:404
                                     userInfo:@{NSLocalizedDescriptionKey: @"Account not found"}];
        }
        return NO;
    }

    account.inviteEnabled = enabled;
    account.updatedAt = [[NSDate date] timeIntervalSince1970];
    BOOL updated = [db updateAccount:account error:error];
    [db close];
    return updated;
}

static BOOL deleteAccountAsAdmin(PDSServiceDatabases *serviceDatabases,
                                 NSString *did,
                                 NSError **error) {
    PDSDatabase *db = [serviceDatabases serviceDatabaseWithError:error];
    if (!db) {
        return NO;
    }

    PDSDatabaseAccount *account = [db getAccountByDid:did error:error];
    if (!account) {
        [db close];
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"com.atproto.admin"
                                         code:404
                                     userInfo:@{NSLocalizedDescriptionKey: @"Account not found"}];
        }
        return NO;
    }

    NSArray<NSString *> *cleanupSQL = @[
        @"DELETE FROM refresh_tokens WHERE account_did = ?",
        @"DELETE FROM app_passwords WHERE account_did = ?",
        @"DELETE FROM invite_codes WHERE account_did = ?",
        @"DELETE FROM passkeys WHERE account_did = ?"
    ];
    for (NSString *sql in cleanupSQL) {
        if (!executeServiceUpdate(db, sql, @[did], YES, error)) {
            [db close];
            return NO;
        }
    }

    BOOL deleted = [db deleteAccount:did error:error];
    [db close];
    return deleted;
}

static NSData *pbkdf2HashPassword(NSString *password, NSData *salt, NSError **error) {
    const uint32_t iterations = 600000;
    const size_t derivedKeyLength = 32;
    unsigned char derivedKey[32];

    int result = CCKeyDerivationPBKDF(kCCPBKDF2,
                                      password.UTF8String,
                                      (size_t)password.length,
                                      salt.bytes,
                                      (size_t)salt.length,
                                      kCCPRFHmacAlgSHA256,
                                      iterations,
                                      derivedKey,
                                      derivedKeyLength);
    if (result != 0) {  // kCCSuccess is 0
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.server"
                                         code:500
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to derive password hash"}];
        }
        return nil;
    }
    return [NSData dataWithBytes:derivedKey length:derivedKeyLength];
}

static NSData *generateAccountPasswordSalt(void) {
    NSMutableData *salt = [NSMutableData dataWithLength:32];
    uuid_t firstUUID;
    uuid_t secondUUID;
    [[NSUUID UUID] getUUIDBytes:firstUUID];
    [[NSUUID UUID] getUUIDBytes:secondUUID];
    [salt replaceBytesInRange:NSMakeRange(0, 16) withBytes:firstUUID];
    [salt replaceBytesInRange:NSMakeRange(16, 16) withBytes:secondUUID];
    return salt;
}

static BOOL updateAccountEmail(PDSServiceDatabases *serviceDatabases,
                               NSString *did,
                               NSString *email,
                               NSError **error) {
    PDSDatabaseAccount *account = [serviceDatabases getAccountByDid:did error:error];
    if (!account) {
        return NO;
    }
    account.email = email;
    account.updatedAt = [[NSDate date] timeIntervalSince1970];
    return [serviceDatabases updateAccount:account error:error];
}

static BOOL updateAccountPassword(PDSServiceDatabases *serviceDatabases,
                                  NSString *did,
                                  NSString *password,
                                  NSError **error) {
    PDSDatabaseAccount *account = [serviceDatabases getAccountByDid:did error:error];
    if (!account) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"com.atproto.admin"
                                         code:404
                                     userInfo:@{NSLocalizedDescriptionKey: @"Account not found"}];
        }
        return NO;
    }

    if (password.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.admin"
                                         code:400
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing password"}];
        }
        return NO;
    }

    NSData *salt = account.passwordSalt;
    if (salt.length == 0) {
        salt = generateAccountPasswordSalt();
    }

    NSError *hashError = nil;
    NSData *hash = pbkdf2HashPassword(password, salt, &hashError);
    if (!hash) {
        if (error) {
            *error = hashError ?: [NSError errorWithDomain:@"com.atproto.admin"
                                                      code:500
                                                  userInfo:@{NSLocalizedDescriptionKey: @"Failed to hash password"}];
        }
        return NO;
    }

    account.passwordSalt = salt;
    account.passwordHash = hash;
    account.updatedAt = [[NSDate date] timeIntervalSince1970];
    if (![serviceDatabases updateAccount:account error:error]) {
        return NO;
    }

    [serviceDatabases deleteRefreshTokensForAccount:did error:nil];
    return YES;
}

static BOOL isLikelyEmail(NSString *email) {
    if (![email isKindOfClass:[NSString class]]) {
        return NO;
    }
    NSRange atRange = [email rangeOfString:@"@"];
    if (atRange.location == NSNotFound || atRange.location == 0 || atRange.location == email.length - 1) {
        return NO;
    }
    NSString *domain = [email substringFromIndex:atRange.location + 1];
    return [domain containsString:@"."];
}

static BOOL parseStrictIntegerString(NSString *value, NSInteger *outValue) {
    if (![value isKindOfClass:[NSString class]] || value.length == 0) {
        return NO;
    }
    NSScanner *scanner = [NSScanner scannerWithString:value];
    NSInteger parsed = 0;
    if (![scanner scanInteger:&parsed] || !scanner.isAtEnd) {
        return NO;
    }
    if (outValue) {
        *outValue = parsed;
    }
    return YES;
}

static BOOL resolveAccountIdentifierToDid(PDSServiceDatabases *serviceDatabases,
                                          NSString *accountIdentifier,
                                          NSString **outDid,
                                          NSError **error) {
    return [XrpcIdentityHelper resolveAccountIdentifierToDid:accountIdentifier
                                            serviceDatabases:serviceDatabases
                                                      outDid:outDid
                                                       error:error];
}
