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
#import "Auth/AuthClaimTypeCheck.h"
#import "App/ATProtoServiceConfiguration.h"
#import "Services/PDS/PDSAccountService.h"
#import "Services/PDS/PDSRepositoryService.h"
#import "Admin/PDSAdminController.h"
#import "Auth/PDSSecondFactorService.h"
#import "Auth/Crypto/Secp256k1.h"
#import "Core/ATProtoValidator.h"
#import "Security/ATProtoPermissionScopeEvaluator.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/Monitoring/PDSHealthCheck.h"
#import "Identity/ATProtoHandleValidator.h"
#import "Core/DID.h"
#import "Core/PDSAccountEvents.h"
#import "Debug/GZLogger.h"
#import "Core/NSDateFormatter+ATProto.h"
#import "Network/Generated/GZXrpcNSID.h"
#import "Email/PDSEmailProvider.h"

static BOOL XrpcAccountAllowsEmailManagement(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
    if ([ATProtoPermissionScopeEvaluator evaluateAccountScopes:request.permissionScopes ?: @[]
                                                  forAttribute:@"email"
                                                        action:@"manage"]) {
        return YES;
    }
    response.statusCode = HttpStatusForbidden;
    [response setJsonBody:@{ @"error": @"InsufficientScope",
                             @"message": @"account:email?action=manage scope is required" }];
    return NO;
}

@implementation XrpcServerPack (AccountManagement)

+ (void)registerEmailAndAccountEndpoints:(XrpcDispatcher *)dispatcher
                                 services:(id<XrpcRoutePackServices>)services {
    ATProtoJWTMinter *jwtMinter = services.jwtMinter;
    id<PDSAdminController> adminController = services.adminController;
    id<PDSAccountService> accountService = services.accountService;
    PDSServiceDatabases *serviceDatabases = services.serviceDatabases;
    PDSDatabasePool *userDatabasePool = services.userDatabasePool;

#pragma mark - com.atproto.server.accountManagement.*
    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_server_requestEmailConfirmation handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader services:services request:request response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }
        if (!XrpcAccountAllowsEmailManagement(request, response)) return;

        // Look up the account to get the email address.
        NSError *accountError = nil;
        PDSDatabaseAccount *account = [serviceDatabases getAccountByDid:did error:&accountError];
        if (!account || account.email.length == 0) {
            // No-leak: return 200 even if no email is on file.
            response.statusCode = HttpStatusOK;
            [response setJsonBody:@{}];
            return;
        }

        // Mint a 32-byte opaque token (phase-23 slice 3b, ADR 0022).
        uint8_t tokenBytes[32];
        if (SecRandomCopyBytes(kSecRandomDefault, 32, tokenBytes) != errSecSuccess) {
            GZ_LOG_ERROR(@"requestEmailConfirmation: SecRandomCopyBytes failed");
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"InternalServerError", @"message": @"Failed to generate token"}];
            return;
        }
        NSMutableString *token = [NSMutableString stringWithCapacity:64];
        for (NSUInteger i = 0; i < 32; i++) {
            [token appendFormat:@"%02x", tokenBytes[i]];
        }

        // Store in email_confirmation_tokens (V17). TTL: 30 minutes.
        NSTimeInterval expiresAt = [[NSDate date] timeIntervalSince1970] + 1800.0;
        PDSDatabase *db = [serviceDatabases serviceDatabaseWithError:nil];
        NSError *insertError = nil;
        if (![db executeParameterizedUpdate:
                @"INSERT INTO email_confirmation_tokens (token, did, email, expires_at) VALUES (?, ?, ?, ?)"
                                     params:@[token, did, account.email, @((long long)expiresAt)]
                                      error:&insertError]) {
            GZ_LOG_ERROR(@"requestEmailConfirmation: failed to store token: %@", insertError.localizedDescription);
        }

        // Send the token via email.
        id<PDSEmailProvider> emailProvider = services.emailProvider;
        if (emailProvider) {
            NSString *subject = @"Confirm your email address";
            NSString *bodyText = [NSString stringWithFormat:
                @"Use this token to confirm your email address:\n\n%@\n\nThis token expires in 30 minutes.", token];
            NSError *emailError = nil;
            if (![emailProvider sendEmailTo:account.email subject:subject body:bodyText error:&emailError]) {
                GZ_LOG_ERROR(@"requestEmailConfirmation: failed to send email to %@: %@", account.email, emailError.localizedDescription);
            }
        } else {
            GZ_LOG_WARN(@"requestEmailConfirmation: no emailProvider configured, token not sent");
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_server_requestEmailUpdate handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader services:services request:request response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }
        if (!XrpcAccountAllowsEmailManagement(request, response)) return;

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"tokenRequired": @NO}];
    }];

    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_server_confirmEmail handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader services:services request:request response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }
        if (!XrpcAccountAllowsEmailManagement(request, response)) return;

        NSDictionary *body = request.jsonBody ?: @{};
        BOOL typeMismatch = NO;
        NSString *email = AuthTypedValue(body, @"email", [NSString class], &typeMismatch);
        NSString *token = AuthTypedValue(body, @"token", [NSString class], &typeMismatch);
        if (typeMismatch) {
            [XrpcErrorHelper setInvalidRequestError:response message:@"Request field has wrong type"];
            return;
        }
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

        // Validate the opaque confirmation token (phase-23 slice 3b, V17).
        PDSDatabase *db = [serviceDatabases serviceDatabaseWithError:nil];
        NSArray<NSDictionary *> *tokenRows = [db executeParameterizedQuery:
            @"SELECT did, email, expires_at, used_at FROM email_confirmation_tokens WHERE token = ?"
                                                                    params:@[token]
                                                                     error:nil];
        BOOL tokenValid = NO;
        NSDictionary *tokenRow = tokenRows.firstObject;
        if (tokenRow) {
            // A NULL column is absent from the row dictionary, so a present
            // used_at means the token was already claimed.
            BOOL alreadyUsed = (tokenRow[@"used_at"] != nil);
            NSTimeInterval expiresAt = [tokenRow[@"expires_at"] doubleValue];
            NSString *storedDid = tokenRow[@"did"] ?: @"";
            NSString *storedEmail = tokenRow[@"email"] ?: @"";

            if (!alreadyUsed && [[NSDate date] timeIntervalSince1970] <= expiresAt &&
                [storedDid isEqualToString:did] &&
                [[storedEmail lowercaseString] isEqualToString:[email lowercaseString]]) {
                tokenValid = YES;
            }
        }

        if (!tokenValid) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidToken", @"message": @"Invalid, expired, or already used confirmation token"}];
            return;
        }

        // Atomically claim the token — guards concurrent replays.
        NSTimeInterval claimTime = [[NSDate date] timeIntervalSince1970];
        NSInteger claimedRows = 0;
        BOOL claimed = [db executeParameterizedUpdate:
            @"UPDATE email_confirmation_tokens SET used_at = ? WHERE token = ? AND used_at IS NULL"
                                               params:@[@((long long)claimTime), token]
                                          changedRows:&claimedRows
                                                error:nil];
        if (claimed && claimedRows == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidToken", @"message": @"Invalid, expired, or already used confirmation token"}];
            return;
        }

        // Persist emailConfirmed flag on the account.
        NSString *nowStr = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]];
        NSError *flagError = nil;
        if (![db executeParameterizedUpdate:@"UPDATE accounts SET email_confirmed_at = ? WHERE did = ?"
                                     params:@[nowStr, did]
                                      error:&flagError]) {
            GZ_LOG_ERROR(@"confirmEmail: failed to set email_confirmed_at for %@: %@", did, flagError.localizedDescription);
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_server_updateEmail handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader services:services request:request response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }
        if (!XrpcAccountAllowsEmailManagement(request, response)) return;

        NSDictionary *body = request.jsonBody ?: @{};
        BOOL typeMismatch = NO;
        NSString *email = AuthTypedValue(body, @"email", [NSString class], &typeMismatch);
        if (typeMismatch) {
            [XrpcErrorHelper setInvalidRequestError:response message:@"Request field has wrong type"];
            return;
        }
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

    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_server_requestAccountDelete handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader services:services request:request response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        // The lexicon has no input schema. Any body is ignored: this endpoint
        // only initiates the authenticated email flow; token exchange belongs
        // exclusively to com.atproto.server.deleteAccount.

        // Fail closed if no email provider is configured — this is a global
        // config check, not a per-account check, so it doesn't leak.
        id<PDSEmailProvider> emailProvider = services.emailProvider;
        if (!emailProvider) {
            response.statusCode = HttpStatusServiceUnavailable;
            [response setJsonBody:@{@"error": @"AccountDeleteUnavailable",
                                     @"message": @"Account deletion is not available"}];
            return;
        }

        // No-leak: always return 200 before doing any per-account work.
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];

        // Look up account to get the email.
        NSError *accountError = nil;
        PDSDatabaseAccount *account = [serviceDatabases getAccountByDid:did error:&accountError];
        if (!account || account.email.length == 0) return;

        // Mint a 32-byte opaque token (64 hex characters).
        uint8_t tokenBytes[32];
        if (SecRandomCopyBytes(kSecRandomDefault, 32, tokenBytes) != errSecSuccess) {
            GZ_LOG_ERROR(@"requestAccountDelete: SecRandomCopyBytes failed");
            return;
        }
        NSMutableString *token = [NSMutableString stringWithCapacity:64];
        for (NSUInteger i = 0; i < 32; i++) {
            [token appendFormat:@"%02x", tokenBytes[i]];
        }

        // TTL: 15 minutes.
        NSTimeInterval expiresAt = [[NSDate date] timeIntervalSince1970] + 900.0;

        // Store token in service database.
        PDSDatabase *db = [serviceDatabases serviceDatabaseWithError:nil];
        if (!db) {
            GZ_LOG_ERROR(@"requestAccountDelete: service database unavailable");
            return;
        }

        NSError *insertError = nil;
        if (![db executeParameterizedUpdate:
                @"INSERT INTO password_reset_tokens (token, did, expires_at) VALUES (?, ?, ?)"
                                     params:@[token, did, @((long long)expiresAt)]
                                      error:&insertError]) {
            GZ_LOG_ERROR(@"requestAccountDelete: INSERT failed: %@", insertError.localizedDescription);
            return;
        }

        // Send confirmation email (provider already validated above).
        NSString *subject = @"Account deletion request";
        NSString *bodyText = [NSString stringWithFormat:
            @"Use this token to confirm account deletion:\n\n%@\n\nThis token expires in 15 minutes.", token];
        NSError *emailError = nil;
        if (![emailProvider sendEmailTo:account.email subject:subject body:bodyText error:&emailError]) {
            GZ_LOG_ERROR(@"requestAccountDelete: failed to send email to %@: %@", account.email, emailError.localizedDescription);
        }
    }];

    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_server_requestPasswordReset handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        NSDictionary *body = request.jsonBody ?: @{};
        BOOL typeMismatch = NO;
        NSString *email = AuthTypedValue(body, @"email", [NSString class], &typeMismatch);
        if (typeMismatch) {
            [XrpcErrorHelper setInvalidRequestError:response message:@"Request field has wrong type"];
            return;
        }
        if (email.length == 0 || !isLikelyEmail(email)) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing or invalid email"}];
            return;
        }

        // Fail closed if no email provider is configured — this is a global
        // config check, not a per-account check, so it doesn't leak.
        id<PDSEmailProvider> emailProvider = services.emailProvider;
        if (!emailProvider) {
            response.statusCode = HttpStatusServiceUnavailable;
            [response setJsonBody:@{@"error": @"PasswordResetUnavailable",
                                     @"message": @"Password reset is not available"}];
            return;
        }

        // No-leak: always return 200 regardless of whether the email exists.
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];

        // Look up account — silently return if no match (no-leak).
        NSError *accountError = nil;
        PDSDatabaseAccount *account = [serviceDatabases getAccountByEmail:email error:&accountError];
        if (!account) return;

        // Mint a 32-byte opaque token (64 hex characters).
        uint8_t tokenBytes[32];
        if (SecRandomCopyBytes(kSecRandomDefault, 32, tokenBytes) != errSecSuccess) {
            GZ_LOG_ERROR(@"requestPasswordReset: SecRandomCopyBytes failed");
            return;
        }
        NSMutableString *token = [NSMutableString stringWithCapacity:64];
        for (NSUInteger i = 0; i < 32; i++) {
            [token appendFormat:@"%02x", tokenBytes[i]];
        }

        // TTL: 15 minutes.
        NSTimeInterval expiresAt = [[NSDate date] timeIntervalSince1970] + 900.0;

        // Store token in service database.
        PDSDatabase *db = [serviceDatabases serviceDatabaseWithError:nil];
        if (!db) {
            GZ_LOG_ERROR(@"requestPasswordReset: service database unavailable");
            return;
        }

        NSError *insertError = nil;
        if (![db executeParameterizedUpdate:
                @"INSERT INTO password_reset_tokens (token, did, expires_at) VALUES (?, ?, ?)"
                                     params:@[token, account.did, @((long long)expiresAt)]
                                      error:&insertError]) {
            GZ_LOG_ERROR(@"requestPasswordReset: INSERT failed: %@", insertError.localizedDescription);
            return;
        }

        // Send reset email (provider already validated above).
        NSString *subject = @"Password reset";
        NSString *bodyText = [NSString stringWithFormat:
            @"Use this token to reset your password:\n\n%@\n\nThis token expires in 15 minutes.", token];
        NSError *emailError = nil;
        if (![emailProvider sendEmailTo:email subject:subject body:bodyText error:&emailError]) {
            GZ_LOG_ERROR(@"requestPasswordReset: failed to send email to %@: %@", email, emailError.localizedDescription);
        }
    }];

    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_server_resetPassword handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        NSDictionary *body = request.jsonBody ?: @{};
        BOOL typeMismatch = NO;
        NSString *token = AuthTypedValue(body, @"token", [NSString class], &typeMismatch);
        NSString *password = AuthTypedValue(body, @"password", [NSString class], &typeMismatch);
        if (typeMismatch) {
            [XrpcErrorHelper setInvalidRequestError:response message:@"Request field has wrong type"];
            return;
        }
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

        // Previous versions of this handler accepted the account DID as the
        // token — a security hole that allowed password reset by anyone who
        // knows a victim's public DID. That path was removed in phase 23 slice 4
        // in favor of the opaque single-use token in password_reset_tokens.
        // Clients that previously sent DIDs must migrate to the token received
        // via email from requestPasswordReset.

        // Look up the opaque token in password_reset_tokens.
        PDSDatabase *db = [serviceDatabases serviceDatabaseWithError:nil];
        if (!db) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"PasswordResetFailed", @"message": @"Service unavailable"}];
            return;
        }

        // SELECT token metadata to validate expiry and resolve the DID.
        NSError *lookupError = nil;
        NSArray<NSDictionary *> *tokenRows = [db executeParameterizedQuery:
            @"SELECT did, expires_at, used_at FROM password_reset_tokens WHERE token = ?"
                                                                    params:@[token]
                                                                     error:&lookupError];
        if (lookupError) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"PasswordResetFailed", @"message": @"Service unavailable"}];
            return;
        }

        NSDictionary *tokenRow = tokenRows.firstObject;
        NSString *did = tokenRow[@"did"];
        NSTimeInterval expiresAt = [tokenRow[@"expires_at"] doubleValue];
        BOOL alreadyUsed = (tokenRow[@"used_at"] != nil);

        // Use a single error message for all invalid-token cases — no leak.
        if (!did || alreadyUsed) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidToken", @"message": @"Invalid reset token"}];
            return;
        }
        if ([[NSDate date] timeIntervalSince1970] > expiresAt) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"ExpiredToken", @"message": @"Reset token has expired"}];
            return;
        }

        // Atomically claim the token. The WHERE used_at IS NULL guards against
        // concurrent replays even across connections.
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        NSInteger claimedRows = 0;
        if (![db executeParameterizedUpdate:
                @"UPDATE password_reset_tokens SET used_at = ? WHERE token = ? AND used_at IS NULL"
                                     params:@[@((long long)now), token]
                                changedRows:&claimedRows
                                      error:nil]) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"PasswordResetFailed", @"message": @"Service unavailable"}];
            return;
        }
        if (claimedRows == 0) {
            // Another request already claimed this token.
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidToken", @"message": @"Invalid reset token"}];
            return;
        }

        // Get account and update password.
        NSError *accountError = nil;
        PDSDatabaseAccount *account = [serviceDatabases getAccountByDid:did error:&accountError];
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

        // Log the event — use the account DID, not the token.
        [serviceDatabases logHostingEvent:did type:@"password_updated" details:@{} createdBy:did error:nil];

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_server_reserveSigningKey handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        NSDictionary *body = request.jsonBody ?: @{};
        BOOL typeMismatch = NO;
        NSString *did = AuthTypedValue(body, @"did", [NSString class], &typeMismatch);
        if (typeMismatch) {
            [XrpcErrorHelper setInvalidRequestError:response message:@"Request field has wrong type"];
            return;
        }
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
            ATProtoSecp256k1KeyPair *keyPair = [[ATProtoSecp256k1 shared] generateKeyPairWithError:&error];
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

    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_server_getServiceAuth handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
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

        if (![ATProtoPermissionScopeEvaluator evaluateRPCScopes:request.permissionScopes ?: @[]
                                                       forMethod:lxm
                                                        audience:aud]) {
            response.statusCode = HttpStatusForbidden;
            [response setJsonBody:@{
                @"error": @"InsufficientScope",
                @"message": @"Token scope does not permit the requested service authentication"
            }];
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

        ATProtoJWTMinter *minter = [[ATProtoJWTMinter alloc] init];
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
