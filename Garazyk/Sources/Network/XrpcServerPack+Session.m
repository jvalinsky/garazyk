// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Network/XrpcServerPack+Session.h"
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

@implementation ATProtoXrpcServerPack (PDSSession)

+ (void)registerAccountCreationAndSessionEndpoints:(ATProtoXrpcDispatcher *)dispatcher
                                          services:(id<XrpcRoutePackServices>)services
                                 registrationGate:(nullable id<PDSRegistrationGate>)registrationGate {
    ATProtoJWTMinter *jwtMinter = services.jwtMinter;
    id<PDSAdminController> adminController = services.adminController;
    id<PDSAccountService> accountService = services.accountService;
    PDSRepositoryService *repositoryService = services.repositoryService;
    PDSServiceDatabases *serviceDatabases = services.serviceDatabases;
    ATProtoServiceConfiguration *config = services.configuration;
#pragma mark - com.atproto.server.session.*
    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_server_createAccount handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        NSString *email = [request stringBodyForKey:@"email"];
        NSString *handle = [request stringBodyForKey:@"handle"];
        NSString *password = [request stringBodyForKey:@"password"];
        NSString *did = [request stringBodyForKey:@"did"];

        if (!email || !password || !handle) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing email, handle, or password"}];
            return;
        }

        // Bring-your-own-DID migration path (ADR 0035): when a DID is supplied,
        // the caller must prove control of it with a service-auth JWT signed by
        // the DID's current signing key (verified against the resolved DID
        // document). The account is created deactivated, no PLC operation is
        // minted, and registration gates do not apply — the service-auth proof
        // is the authorization for a migration, not a registration.
        BOOL hasDid = did.length > 0;
        if (hasDid) {
            if (![ATProtoValidator validateDID:did error:nil]) {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Invalid did"}];
                return;
            }
            if (!validateDidServiceAuthForAccountCreation(request, response, did, config)) {
                return;
            }
        } else if (registrationGate) {
            // Registration gate validation
            NSError *gateError = nil;
            // Dispatch to the remoteAddress-aware variant when the gate
            // implements it (e.g. CAPTCHA siteverify's remoteip field);
            // fall back to the two-parameter method otherwise.
            BOOL passed = NO;
            if ([registrationGate respondsToSelector:@selector(validateRegistrationRequest:configuration:remoteAddress:error:)]) {
                passed = [registrationGate validateRegistrationRequest:request.jsonBody
                                                          configuration:config
                                                          remoteAddress:request.remoteAddress
                                                                  error:&gateError];
            } else {
                passed = [registrationGate validateRegistrationRequest:request.jsonBody
                                                          configuration:config
                                                                  error:&gateError];
            }
            if (!passed) {
                // A gate error with httpStatus=503 indicates a service
                // availability failure (e.g. CAPTCHA siteverify unreachable).
                // Map to 503 so the client retries rather than believing
                // the signup was rejected on its merits.
                NSInteger httpStatusOverride = 0;
                if ([gateError.domain isEqualToString:PDSRegistrationGateErrorDomain]) {
                    id statusVal = gateError.userInfo[@"httpStatus"];
                    if ([statusVal isKindOfClass:[NSNumber class]]) {
                        httpStatusOverride = [(NSNumber *)statusVal integerValue];
                    }
                }
                response.statusCode = (httpStatusOverride == 503) ? 503 : HttpStatusBadRequest;
                NSString *errorCode = @"InvalidRequest";
                NSString *errorMessage = gateError.localizedDescription ?: @"Registration rejected";
                if ([gateError.domain isEqualToString:PDSRegistrationGateErrorDomain]) {
                    switch (gateError.code) {
                        case PDSRegistrationGateErrorInviteCodeRequired:
                        case PDSRegistrationGateErrorInvalidInviteCode:
                            errorCode = @"InvalidInviteCode";
                            break;
                        case PDSRegistrationGateErrorPhoneVerificationRequired:
                        case PDSRegistrationGateErrorInvalidPhoneVerification:
                            errorCode = @"PhoneVerificationRequired";
                            break;
                        case PDSRegistrationGateErrorCaptchaRequired:
                        case PDSRegistrationGateErrorInvalidCaptcha:
                            errorCode = @"InvalidCaptcha";
                            break;
                        case PDSRegistrationGateErrorOAuthOnlyRegistration:
                            errorCode = @"OAuthOnlyRegistration";
                            break;
                        default:
                            break;
                    }
                }
                [response setJsonBody:@{@"error": errorCode, @"message": errorMessage}];
                return;
            }
        }

        NSError *error = nil;
        NSDictionary *result = [accountService createAccountForEmail:email
                                                             password:password
                                                               handle:handle
                                                                  did:hasDid ? did : nil
                                                                error:&error];

        if (error || !result) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"AccountCreationFailed",
                                    @"message": error.localizedDescription ?: @"Account creation failed without a result"}];
            return;
        }

        NSString *createdDid = result[@"did"];
        if (createdDid && repositoryService) {
            NSError *initError = nil;
            if (![repositoryService initializeRepoForDid:createdDid error:&initError]) {
                GZ_LOG_ERROR(@"Failed to initialize repo for DID %@: %@", createdDid, initError);
            }
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_server_createSession handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        NSString *identifier = [request stringBodyForKey:@"identifier"];
        NSString *password = [request stringBodyForKey:@"password"];
        NSString *authFactorToken = [request stringBodyForKey:@"authFactorToken"];

        if (!identifier || !password) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing identifier or password"}];
            return;
        }

        NSError *error = nil;
        NSDictionary *session = [accountService loginWithIdentifier:identifier
                                                            password:password
                                                     authFactorToken:authFactorToken
                                                               error:&error];

        if (error) {
            if ([error.domain isEqualToString:PDSSecondFactorErrorDomain] &&
                [error.userInfo[PDSSecondFactorATProtoErrorKey] isEqualToString:@"AuthFactorTokenRequired"]) {
                response.statusCode = HttpStatusUnauthorized;
                [response setHeader:@"no-store" forKey:@"Cache-Control"];
                [response setHeader:@"no-cache" forKey:@"Pragma"];
                [response setJsonBody:@{@"error": @"AuthFactorTokenRequired",
                                        @"message": error.localizedDescription ?: @"Two-factor authentication required"}];
                return;
            }
            // Deactivated accounts cannot create sessions (ADR 0035); surface
            // the stable AccountDeactivated error code carried by the service.
            NSString *atprotoError = [error.userInfo[@"atprotoError"] isKindOfClass:[NSString class]]
                ? error.userInfo[@"atprotoError"] : nil;
            if (atprotoError.length > 0) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": atprotoError, @"message": error.localizedDescription}];
                return;
            }
            response.statusCode = HttpStatusUnauthorized;
            [response setJsonBody:@{@"error": @"AuthenticationFailed", @"message": error.localizedDescription}];
            return;
        }

        [response setHeader:@"no-store" forKey:@"Cache-Control"];
        [response setHeader:@"no-cache" forKey:@"Pragma"];
        response.statusCode = HttpStatusOK;
        
        NSMutableDictionary *lexiconSession = [NSMutableDictionary dictionary];
        if (session[@"accessJwt"]) lexiconSession[@"accessJwt"] = session[@"accessJwt"];
        if (session[@"refreshJwt"]) lexiconSession[@"refreshJwt"] = session[@"refreshJwt"];
        if (session[@"handle"]) lexiconSession[@"handle"] = [ATProtoHandleValidator normalizeHandle:session[@"handle"]];
        if (session[@"did"]) lexiconSession[@"did"] = session[@"did"];
        if (session[@"email"]) lexiconSession[@"email"] = session[@"email"];
        lexiconSession[@"emailConfirmed"] = session[@"emailConfirmed"] ?: @YES;
        lexiconSession[@"active"] = session[@"active"] ?: @YES;
        if (session[@"didDoc"]) lexiconSession[@"didDoc"] = session[@"didDoc"];

        [response setJsonBody:lexiconSession];
    }];

    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_server_getSession handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
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
        NSDictionary *account = [accountService getAccountForDid:did error:&error];
        if (error || !account) {
            response.statusCode = HttpStatusUnauthorized;
            [response setJsonBody:@{@"error": @"AccountNotFound", @"message": @"Account not found for session"}];
            return;
        }

        if (!account[@"handle"]) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"InvalidAccount", @"message": @"Account handle is missing"}];
            return;
        }

        NSMutableDictionary *lexiconSession = [NSMutableDictionary dictionary];
        lexiconSession[@"handle"] = [ATProtoHandleValidator normalizeHandle:account[@"handle"]];
        lexiconSession[@"did"] = did;
        if (account[@"email"]) lexiconSession[@"email"] = account[@"email"];
        lexiconSession[@"emailConfirmed"] = account[@"emailConfirmed"] ?: @YES;
        lexiconSession[@"active"] = account[@"active"] ?: @YES;
        if (account[@"didDoc"]) lexiconSession[@"didDoc"] = account[@"didDoc"];

        [response setHeader:@"no-store" forKey:@"Cache-Control"];
        [response setHeader:@"no-cache" forKey:@"Pragma"];
        response.statusCode = HttpStatusOK;
        [response setJsonBody:lexiconSession];
    }];

    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_server_refreshSession handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *refreshToken = nil;
        
        if ([authHeader hasPrefix:@"Bearer "]) {
            refreshToken = [authHeader substringFromIndex:7];
        } else if ([authHeader hasPrefix:@"DPoP "]) {
            refreshToken = [authHeader substringFromIndex:5];
        }

        if (!refreshToken) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing refresh token in Authorization header"}];
            return;
        }

        NSError *error = nil;
        NSDictionary *session = [accountService refreshAccessToken:refreshToken error:&error];

        if (error) {
            response.statusCode = HttpStatusUnauthorized;
            [response setJsonBody:@{@"error": @"AuthenticationFailed", @"message": error.localizedDescription}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:session];
    }];

    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_server_deleteSession handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
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
        NSString *sessionID = nil;
        if ([authHeader hasPrefix:@"Bearer "]) {
            NSString *token = [authHeader substringFromIndex:7];
            ATProtoJWT *jwt = [ATProtoJWT jwtWithToken:token error:nil];
            NSDictionary *payload = jwt ? payloadDictionaryFromJWT(jwt, nil) : nil;
            sessionID = [payload[@"sid"] isKindOfClass:[NSString class]] ? payload[@"sid"] : nil;
        }
        BOOL success = sessionID.length > 0
            ? [serviceDatabases revokeSession:sessionID error:&error]
            : [serviceDatabases deleteRefreshTokensForAccount:did error:&error];
        if (!success) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"SessionDeletionFailed", @"message": error.localizedDescription ?: @"Failed to delete session"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];
}

@end
