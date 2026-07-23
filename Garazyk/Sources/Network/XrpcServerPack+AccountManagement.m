// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Network/XrpcServerPack+AccountManagement.h"
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

@implementation XrpcServerPack (AccountManagement)

+ (void)registerEmailAndAccountEndpoints:(XrpcDispatcher *)dispatcher
                                 services:(id<XrpcRoutePackServices>)services {
    JWTMinter *jwtMinter = services.jwtMinter;
    id<PDSAdminController> adminController = services.adminController;
    id<PDSAccountService> accountService = services.accountService;
    PDSServiceDatabases *serviceDatabases = services.serviceDatabases;
    PDSDatabasePool *userDatabasePool = services.userDatabasePool;

#pragma mark - com.atproto.server.accountManagement.*
    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_server_requestEmailConfirmation handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader services:services request:request response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_server_requestEmailUpdate handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader services:services request:request response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"tokenRequired": @NO}];
    }];

    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_server_confirmEmail handler:^(HttpRequest *request, HttpResponse *response) {
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
        NSString *email = body[@"email"];
        NSString *token = body[@"token"];
        if (email.length == 0 || token.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing email or token"}];
            return;
        }

        NSError *accountError = nil;
        PDSDatabaseAccount *account = [serviceDatabases getAccountByDid:did error:&accountError];
        if (!account) {
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{@"error": @"AccountNotFound", @"message": accountError.localizedDescription ?: @"Account not found"}];
            return;
        }

        if (!isLikelyEmail(email) || (account.email.length > 0 && ![[account.email lowercaseString] isEqualToString:[email lowercaseString]])) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidEmail", @"message": @"Provided email does not match account"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_server_updateEmail handler:^(HttpRequest *request, HttpResponse *response) {
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
        NSString *email = body[@"email"];
        if (email.length == 0 || !isLikelyEmail(email)) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing or invalid email"}];
            return;
        }

        NSError *error = nil;
        if (!updateAccountEmail(serviceDatabases, did, email, &error)) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"EmailUpdateFailed", @"message": error.localizedDescription ?: @"Failed to update email"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_server_requestAccountDelete handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader services:services request:request response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_server_requestPasswordReset handler:^(HttpRequest *request, HttpResponse *response) {
        NSDictionary *body = request.jsonBody ?: @{};
        NSString *email = body[@"email"];
        if (email.length == 0 || !isLikelyEmail(email)) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing or invalid email"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_server_resetPassword handler:^(HttpRequest *request, HttpResponse *response) {
        NSDictionary *body = request.jsonBody ?: @{};
        NSString *token = body[@"token"];
        NSString *password = body[@"password"];
        if (token.length == 0 || password.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing token or password"}];
            return;
        }
        if (password.length < 8) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Password must be at least 8 characters"}];
            return;
        }

        NSError *didError = nil;
        if (![ATProtoValidator validateDID:token error:&didError]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidToken", @"message": @"Invalid reset token"}];
            return;
        }

        NSError *accountError = nil;
        PDSDatabaseAccount *account = [serviceDatabases getAccountByDid:token error:&accountError];
        if (!account) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidToken", @"message": @"Invalid reset token"}];
            return;
        }

        NSError *hashError = nil;
        NSData *newHash = pbkdf2HashPassword(password, account.passwordSalt, &hashError);
        if (!newHash) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"PasswordResetFailed", @"message": hashError.localizedDescription ?: @"Failed to reset password"}];
            return;
        }

        account.passwordHash = newHash;
        account.updatedAt = [[NSDate date] timeIntervalSince1970];
        NSError *updateError = nil;
        if (![serviceDatabases updateAccount:account error:&updateError]) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"PasswordResetFailed", @"message": updateError.localizedDescription ?: @"Failed to persist new password"}];
            return;
        }

        [serviceDatabases logHostingEvent:token type:@"password_updated" details:@{} createdBy:token error:nil];

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_server_reserveSigningKey handler:^(HttpRequest *request, HttpResponse *response) {
        NSDictionary *body = request.jsonBody ?: @{};
        NSString *did = body[@"did"];
        NSString *signingKey = nil;
        NSError *error = nil;

        if (did.length > 0) {
            NSError *didError = nil;
            if (![ATProtoValidator validateDID:did error:&didError]) {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"InvalidRequest", @"message": didError.localizedDescription ?: @"Invalid DID"}];
                return;
            }

            PDSDatabaseAccount *account = [serviceDatabases getAccountByDid:did error:&error];
            if (!account) {
                response.statusCode = HttpStatusNotFound;
                [response setJsonBody:@{@"error": @"AccountNotFound", @"message": error.localizedDescription ?: @"Account not found"}];
                return;
            }

            NSError *storeError = nil;
            PDSActorStore *store = [userDatabasePool storeForDid:did error:&storeError];
            if (!store) {
                response.statusCode = HttpStatusInternalServerError;
                [response setJsonBody:@{@"error": @"StoreUnavailable", @"message": storeError.localizedDescription ?: @"Failed to open account store"}];
                return;
            }

            NSError *keyError = nil;
            NSString *storedKey = [store didKeyStringWithError:&keyError];
            if (!storedKey) {
                response.statusCode = HttpStatusInternalServerError;
                [response setJsonBody:@{@"error": @"SigningKeyUnavailable", @"message": keyError.localizedDescription ?: @"Signing key unavailable"}];
                return;
            }
            signingKey = storedKey;
        } else {
            Secp256k1KeyPair *keyPair = [[Secp256k1 shared] generateKeyPairWithError:&error];
            if (keyPair) {
                signingKey = keyPair.didKeyString;
            }
        }

        if (!signingKey) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"SigningKeyUnavailable", @"message": error.localizedDescription ?: @"Failed to reserve signing key"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"signingKey": signingKey}];
    }];

    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_server_getServiceAuth handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *aud = [request queryParamForKey:@"aud"];
        if (!aud) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing aud parameter"}];
            return;
        }

        NSString *lxm = [request queryParamForKey:@"lxm"];
        if (lxm.length > 0) {
            NSError *lxmError = nil;
            if (![ATProtoValidator validateNSID:lxm error:&lxmError]) {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"InvalidRequest", @"message": lxmError.localizedDescription ?: @"Invalid lxm parameter"}];
                return;
            }
        }

        NSString *expParam = [request queryParamForKey:@"exp"];
        long long requestedExp = 0;
        BOOL hasRequestedExp = expParam.length > 0;
        if (hasRequestedExp) {
            NSScanner *scanner = [NSScanner scannerWithString:expParam];
            if (![scanner scanLongLong:&requestedExp] || !scanner.isAtEnd) {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"BadExpiration", @"message": @"Invalid exp parameter"}];
                return;
            }
        }

        NSString *audDid = aud;
        NSRange hashRange = [aud rangeOfString:@"#"];
        if (hashRange.location != NSNotFound) {
            audDid = [aud substringToIndex:hashRange.location];
        }

        NSError *audError = nil;
        if (![ATProtoValidator validateDID:audDid error:&audError]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": audError.localizedDescription ?: @"Invalid aud DID"}];
            return;
        }

        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader services:services request:request response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"InvalidToken", @"message": @"Missing or invalid authorization token"}];
            }
            return;
        }

        NSError *accountError = nil;
        if (![serviceDatabases getAccountByDid:did error:&accountError]) {
            response.statusCode = HttpStatusUnauthorized;
            [response setJsonBody:@{@"error": @"AccountNotFound", @"message": @"Account not found for token"}];
            return;
        }

        NSError *storeError = nil;
        PDSActorStore *store = [userDatabasePool storeForDid:did error:&storeError];
        if (!store) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"StoreUnavailable", @"message": storeError.localizedDescription ?: @"Failed to load signing key"}];
            return;
        }

        long long nowSeconds = (long long)[[NSDate date] timeIntervalSince1970];
        if (hasRequestedExp && requestedExp <= nowSeconds) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"BadExpiration", @"message": @"exp must be in the future"}];
            return;
        }

        NSMutableDictionary *payload = [NSMutableDictionary dictionary];
        payload[@"iss"] = did;
        payload[@"sub"] = did;
        payload[@"did"] = did;
        payload[@"aud"] = aud;
        payload[@"iat"] = @((long long)nowSeconds);
        payload[@"exp"] = @(hasRequestedExp ? requestedExp : (long long)(nowSeconds + 60));
        payload[@"jti"] = [[NSUUID UUID] UUIDString];
        if (lxm.length > 0) {
            payload[@"lxm"] = lxm;
        }

        JWTMinter *minter = [[JWTMinter alloc] init];
        minter.issuer = did;
        minter.signingAlgorithm = @"ES256K";

        NSError *mintError = nil;
        NSString *token = [minter signPayload:payload actorKeyManager:store.keyManager error:&mintError];
        if (!token) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"TokenMintFailed", @"message": mintError.localizedDescription ?: @"Failed to mint service auth token"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"token": token}];
    }];
}

@end
