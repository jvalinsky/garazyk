// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0


#import "Network/XrpcAdminPack+AccountLookup.h"
#import "Network/XrpcAdminPack_Internal.h"
#import "Network/XrpcServerPack_Internal.h"
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

@implementation XrpcAdminPack (AccountLookup)

+ (void)registerAccountLookupEndpoints:(XrpcDispatcher *)dispatcher
                services:(id<XrpcRoutePackServices>)services {
    PDSServiceDatabases *serviceDatabases = services.serviceDatabases;
    JWTMinter *jwtMinter = services.jwtMinter;
    id<PDSAdminController> adminController = services.adminController;

    #pragma mark - com.atproto.admin.* Account Lookup, Search & Email

    // Register com.atproto.admin.searchAccounts
    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_admin_searchAccounts handler:^(HttpRequest *request, HttpResponse *response) {
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
    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_admin_sendEmail handler:^(HttpRequest *request, HttpResponse *response) {
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

        GZ_LOG_INFO(@"Admin sendEmail recipient=%@ sender=%@ subject=%@", recipientDid, senderDid, subject ?: @"");
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"sent": @YES}];
    }];

    // Register com.atproto.admin.updateAccountEmail
    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_admin_updateAccountEmail handler:^(HttpRequest *request, HttpResponse *response) {
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
    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_admin_updateAccountHandle handler:^(HttpRequest *request, HttpResponse *response) {
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
    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_admin_updateAccountPassword handler:^(HttpRequest *request, HttpResponse *response) {
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

}

@end
