// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Network/XrpcServerPack+InviteCodes.h"
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

@implementation XrpcServerPack (InviteCodes)

+ (void)registerInviteCodeEndpoints:(XrpcDispatcher *)dispatcher
                           services:(id<XrpcRoutePackServices>)services {
    JWTMinter *jwtMinter = services.jwtMinter;
    id<PDSAdminController> adminController = services.adminController;
    PDSServiceDatabases *serviceDatabases = services.serviceDatabases;
#pragma mark - com.atproto.server.inviteCodes.*
    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_server_createInviteCode handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader services:services request:request response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        NSDictionary *body = request.jsonBody ?: @{};
        NSNumber *useCountNumber = body[@"useCount"];
        NSInteger useCount = useCountNumber.integerValue;
        NSString *forAccount = body[@"forAccount"];
        NSString *targetDid = forAccount.length > 0 ? forAccount : did;

        if (![targetDid isEqualToString:did]) {
            response.statusCode = HttpStatusForbidden;
            [response setJsonBody:@{@"error": @"Forbidden", @"message": @"Cannot create invite codes for other accounts"}];
            return;
        }

        NSError *error = nil;
        NSString *code = nil;
        if (!createInviteCodeInDatabase(serviceDatabases, targetDid, useCount, &code, &error)) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InviteCodeCreateFailed", @"message": error.localizedDescription ?: @"Failed to create invite code"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"code": code ?: @""}];
    }];

    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_server_createInviteCodes handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader services:services request:request response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        NSDictionary *body = request.jsonBody ?: @{};
        NSNumber *codeCountNumber = body[@"codeCount"] ?: @1;
        NSNumber *useCountNumber = body[@"useCount"];
        NSInteger codeCount = codeCountNumber.integerValue;
        NSInteger useCount = useCountNumber.integerValue;
        NSArray<NSString *> *forAccounts = body[@"forAccounts"];
        if (![forAccounts isKindOfClass:[NSArray class]] || forAccounts.count == 0) {
            forAccounts = @[did];
        }

        if (codeCount <= 0 || codeCount > 100) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"codeCount must be between 1 and 100"}];
            return;
        }

        for (NSString *accountDid in forAccounts) {
            if (![accountDid isKindOfClass:[NSString class]] || ![accountDid isEqualToString:did]) {
                response.statusCode = HttpStatusForbidden;
                [response setJsonBody:@{@"error": @"Forbidden", @"message": @"Cannot create invite codes for other accounts"}];
                return;
            }
        }

        NSMutableArray *codesByAccount = [NSMutableArray array];
        for (NSString *accountDid in forAccounts) {
            NSMutableArray<NSString *> *codes = [NSMutableArray arrayWithCapacity:(NSUInteger)codeCount];
            for (NSInteger i = 0; i < codeCount; i++) {
                NSError *error = nil;
                NSString *code = nil;
                if (!createInviteCodeInDatabase(serviceDatabases, accountDid, useCount, &code, &error)) {
                    response.statusCode = HttpStatusBadRequest;
                    [response setJsonBody:@{@"error": @"InviteCodeCreateFailed", @"message": error.localizedDescription ?: @"Failed to create invite code"}];
                    return;
                }
                if (code.length > 0) {
                    [codes addObject:code];
                }
            }
            [codesByAccount addObject:@{@"account": accountDid, @"codes": codes}];
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"codes": codesByAccount}];
    }];

    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_server_getAccountInviteCodes handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader services:services request:request response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        NSError *error = nil;
        NSString *code = [serviceDatabases getInviteCodeForAccount:did error:&error];
        if (error) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"InviteCodeLookupFailed", @"message": error.localizedDescription ?: @"Failed to load invite codes"}];
            return;
        }

        NSMutableArray<NSDictionary *> *codes = [NSMutableArray array];
        if (code.length > 0) {
            [codes addObject:@{
                @"code": code,
                @"available": @1,
                @"disabled": @NO,
                @"forAccount": did,
                @"createdBy": did,
                @"createdAt": [XrpcIdentityHelper currentISO8601String],
                @"uses": @[]
            }];
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"codes": codes}];
    }];
}

@end
