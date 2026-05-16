// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Auth/PDSSecondFactorService.h"

#import "Auth/Base32Utils.h"
#import "Auth/CryptoUtils.h"
#import "Auth/TOTPService.h"
#import "Auth/WebAuthnVerifier.h"
#import "Core/ATProtoError.h"
#import "Database/PDSDatabase+WebAuthn.h"
#import "Database/PDSDatabase.h"
#import "Database/Service/ServiceDatabases.h"
#import "Security/PDSSecurityCompare.h"

NSString * const PDSSecondFactorErrorDomain = @"com.atproto.pds.second_factor";
NSString * const PDSSecondFactorATProtoErrorKey = @"atproto.error";

static NSTimeInterval const PDSSecondFactorChallengeTTL = 300.0;
static NSTimeInterval const PDSSecondFactorProofTTL = 300.0;

@interface PDSSecondFactorService ()
@property (nonatomic, strong) PDSServiceDatabases *serviceDatabases;
@property (nonatomic, copy) NSString *origin;
@end

@implementation PDSSecondFactorService

- (instancetype)initWithServiceDatabases:(PDSServiceDatabases *)serviceDatabases
                                  origin:(NSString *)origin {
    self = [super init];
    if (self) {
        _serviceDatabases = serviceDatabases;
        _origin = [origin copy] ?: @"";
        [self ensureSchema:nil];
    }
    return self;
}

- (BOOL)accountRequiresSecondFactor:(PDSDatabaseAccount *)account {
    return account.tfaEnabled || account.webauthnEnabled;
}

- (BOOL)verifyAuthFactorToken:(NSString *)authFactorToken
                    forAccount:(PDSDatabaseAccount *)account
                         error:(NSError **)error {
    if (![self accountRequiresSecondFactor:account]) {
        return YES;
    }

    if (authFactorToken.length == 0) {
        if (error) *error = [self requiredError];
        return NO;
    }

    if (account.tfaEnabled && [self isSixDigitCode:authFactorToken]) {
        NSString *secret = [self totpSecretStringForAccount:account];
        if (secret.length > 0 && [TOTPService verifyCode:authFactorToken secret:secret]) {
            return YES;
        }
    }

    if ([self consumeFactorToken:authFactorToken
                          forDid:account.did
                          method:@"webauthn"
                           error:error]) {
        return YES;
    }

    if (error && !*error) {
        *error = [self invalidTokenError];
    }
    return NO;
}

- (NSDictionary *)beginWebAuthnLoginForAccount:(PDSDatabaseAccount *)account
                                         error:(NSError **)error {
    if (!account.webauthnEnabled) {
        if (error) *error = [self unavailableError:@"WebAuthn is not enabled for this account"];
        return nil;
    }

    PDSDatabase *db = [self.serviceDatabases serviceDatabaseWithError:error];
    if (!db) return nil;

    NSArray<NSDictionary *> *credentials = [db getWebAuthnCredentialsForDid:account.did error:error];
    if (credentials.count == 0) {
        if (error) *error = [self unavailableError:@"No WebAuthn credentials are registered for this account"];
        return nil;
    }

    NSData *challenge = [CryptoUtils randomBytes:32];
    NSString *sessionID = [CryptoUtils base64URLEncode:[CryptoUtils randomBytes:32]];
    if (challenge.length == 0 || sessionID.length == 0) {
        if (error) *error = [self unavailableError:@"Failed to create WebAuthn challenge"];
        return nil;
    }

    if (![self storeTokenOrChallenge:sessionID
                              forDid:account.did
                              method:@"webauthn_challenge"
                           challenge:challenge
                                 ttl:PDSSecondFactorChallengeTTL
                               error:error]) {
        return nil;
    }

    NSMutableArray *allowCredentials = [NSMutableArray arrayWithCapacity:credentials.count];
    for (NSDictionary *credential in credentials) {
        NSData *credentialID = credential[@"credentialId"];
        if ([credentialID isKindOfClass:[NSData class]]) {
            [allowCredentials addObject:@{
                @"type": @"public-key",
                @"id": [CryptoUtils base64URLEncode:credentialID]
            }];
        }
    }

    return @{
        @"sessionId": sessionID,
        @"publicKey": @{
            @"challenge": [CryptoUtils base64URLEncode:challenge],
            @"timeout": @(PDSSecondFactorChallengeTTL * 1000),
            @"rpId": [self rpID],
            @"allowCredentials": allowCredentials,
            @"userVerification": @"preferred"
        }
    };
}

- (NSString *)completeWebAuthnLoginWithSessionID:(NSString *)sessionID
                                      assertion:(NSDictionary *)assertion
                                      forAccount:(PDSDatabaseAccount *)account
                                           error:(NSError **)error {
    if (!account.webauthnEnabled) {
        if (error) *error = [self unavailableError:@"WebAuthn is not enabled for this account"];
        return nil;
    }

    NSDictionary *challengeRow = [self consumeRowForToken:sessionID
                                                   forDid:account.did
                                                   method:@"webauthn_challenge"
                                                    error:error];
    NSData *challenge = challengeRow[@"challenge"];
    if (![challenge isKindOfClass:[NSData class]] || challenge.length == 0) {
        if (error && !*error) *error = [self invalidTokenError];
        return nil;
    }

    PDSDatabase *db = [self.serviceDatabases serviceDatabaseWithError:error];
    if (!db) return nil;

    NSArray<NSDictionary *> *credentials = [db getWebAuthnCredentialsForDid:account.did error:error];
    BOOL verified = NO;
    uint32_t newSignCount = 0;
    NSDictionary *matchedCredential = nil;
    NSError *verifyError = nil;

    for (NSDictionary *credential in credentials) {
        NSData *publicKey = credential[@"publicKey"];
        if (![publicKey isKindOfClass:[NSData class]]) continue;

        uint32_t storedSignCount = [credential[@"signCount"] unsignedIntValue];
        uint32_t candidateSignCount = 0;
        verified = [WebAuthnVerifier verifyAssertionResponse:assertion
                                                   challenge:challenge
                                                      origin:self.origin
                                                   publicKey:publicKey
                                                   signCount:storedSignCount
                                                newSignCount:&candidateSignCount
                                                       error:&verifyError];
        if (verified) {
            matchedCredential = credential;
            newSignCount = candidateSignCount;
            break;
        }
    }

    if (!verified) {
        if (error) *error = verifyError ?: [self invalidTokenError];
        return nil;
    }

    NSData *credentialID = matchedCredential[@"credentialId"];
    if ([credentialID isKindOfClass:[NSData class]] && newSignCount > 0) {
        [db updateWebAuthnCredentialSignCount:credentialID
                                       forDid:account.did
                                    signCount:newSignCount
                                        error:nil];
    }

    NSString *authFactorToken = [CryptoUtils base64URLEncode:[CryptoUtils randomBytes:32]];
    if (authFactorToken.length == 0) {
        if (error) *error = [self unavailableError:@"Failed to create auth factor token"];
        return nil;
    }

    if (![self storeTokenOrChallenge:authFactorToken
                              forDid:account.did
                              method:@"webauthn"
                           challenge:challenge
                                 ttl:PDSSecondFactorProofTTL
                               error:error]) {
        return nil;
    }

    return authFactorToken;
}

#pragma mark - Storage

- (BOOL)ensureSchema:(NSError **)error {
    PDSDatabase *db = [self.serviceDatabases serviceDatabaseWithError:error];
    if (!db) return NO;

    NSString *sql =
        @"CREATE TABLE IF NOT EXISTS pending_factor_tokens ("
        @"id TEXT PRIMARY KEY,"
        @"token_hash BLOB NOT NULL UNIQUE,"
        @"account_did TEXT NOT NULL,"
        @"method TEXT NOT NULL,"
        @"challenge BLOB,"
        @"expires_at REAL NOT NULL,"
        @"consumed_at REAL,"
        @"created_at REAL NOT NULL"
        @");"
        @"CREATE INDEX IF NOT EXISTS idx_pending_factor_tokens_account ON pending_factor_tokens(account_did, method, expires_at);";
    return [db executeUnsafeRawSQL:sql error:error];
}

- (BOOL)storeTokenOrChallenge:(NSString *)token
                       forDid:(NSString *)did
                       method:(NSString *)method
                    challenge:(NSData *)challenge
                          ttl:(NSTimeInterval)ttl
                        error:(NSError **)error {
    if (![self ensureSchema:error]) return NO;

    NSData *tokenHash = [self hashToken:token];
    if (!tokenHash) return NO;

    PDSDatabase *db = [self.serviceDatabases serviceDatabaseWithError:error];
    if (!db) return NO;

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSString *sql = @"INSERT INTO pending_factor_tokens (id, token_hash, account_did, method, challenge, expires_at, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)";
    return [db executeParameterizedUpdate:sql
                                   params:@[[[NSUUID UUID] UUIDString],
                                            tokenHash,
                                            did ?: @"",
                                            method ?: @"",
                                            challenge ?: [NSNull null],
                                            @(now + ttl),
                                            @(now)]
                                    error:error];
}

- (BOOL)consumeFactorToken:(NSString *)token
                    forDid:(NSString *)did
                    method:(NSString *)method
                     error:(NSError **)error {
    return [self consumeRowForToken:token forDid:did method:method error:error] != nil;
}

- (NSDictionary *)consumeRowForToken:(NSString *)token
                               forDid:(NSString *)did
                               method:(NSString *)method
                                error:(NSError **)error {
    if (![self ensureSchema:error]) return nil;

    NSData *tokenHash = [self hashToken:token];
    if (!tokenHash) return nil;

    PDSDatabase *db = [self.serviceDatabases serviceDatabaseWithError:error];
    if (!db) return nil;

    NSArray *rows = [db executeParameterizedQuery:@"SELECT id, token_hash, challenge, expires_at, consumed_at FROM pending_factor_tokens WHERE account_did = ? AND method = ? AND consumed_at IS NULL"
                                          params:@[did ?: @"", method ?: @""]
                                           error:error];
    NSDictionary *matched = nil;
    for (NSDictionary *row in rows) {
        NSData *storedHash = row[@"token_hash"];
        if ([storedHash isKindOfClass:[NSData class]] &&
            [PDSSecurityCompare constantTimeEqualData:storedHash data:tokenHash]) {
            matched = row;
            break;
        }
    }

    if (!matched) {
        if (error && !*error) *error = [self invalidTokenError];
        return nil;
    }

    NSTimeInterval expiresAt = [matched[@"expires_at"] doubleValue];
    if ([[NSDate date] timeIntervalSince1970] > expiresAt) {
        if (error) *error = [self expiredTokenError];
        return nil;
    }

    BOOL consumed = [db executeParameterizedUpdate:@"UPDATE pending_factor_tokens SET consumed_at = ? WHERE id = ? AND consumed_at IS NULL"
                                           params:@[@([[NSDate date] timeIntervalSince1970]), matched[@"id"] ?: @""]
                                            error:error];
    return consumed ? matched : nil;
}

#pragma mark - Helpers

- (NSData *)hashToken:(NSString *)token {
    NSData *data = [token dataUsingEncoding:NSUTF8StringEncoding];
    return data ? [CryptoUtils sha256:data] : nil;
}

- (BOOL)isSixDigitCode:(NSString *)code {
    if (code.length != 6) return NO;
    NSCharacterSet *notDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    return [code rangeOfCharacterFromSet:notDigits].location == NSNotFound;
}

- (NSString *)totpSecretStringForAccount:(PDSDatabaseAccount *)account {
    if (account.tfaSecret.length == 0) return nil;

    NSString *stored = [[NSString alloc] initWithData:account.tfaSecret encoding:NSUTF8StringEncoding];
    if (stored.length > 0 && [Base32Utils dataFromBase32String:stored]) {
        return stored;
    }
    return [Base32Utils base32StringFromData:account.tfaSecret];
}

- (NSString *)rpID {
    NSURL *url = [NSURL URLWithString:self.origin];
    return url.host ?: self.origin ?: @"localhost";
}

- (NSError *)requiredError {
    return [NSError errorWithDomain:PDSSecondFactorErrorDomain
                               code:PDSSecondFactorErrorRequired
                           userInfo:@{
        NSLocalizedDescriptionKey: @"Two-factor authentication required",
        PDSSecondFactorATProtoErrorKey: @"AuthFactorTokenRequired"
    }];
}

- (NSError *)invalidTokenError {
    return [NSError errorWithDomain:PDSSecondFactorErrorDomain
                               code:PDSSecondFactorErrorInvalidToken
                           userInfo:@{NSLocalizedDescriptionKey: @"Invalid auth factor token"}];
}

- (NSError *)expiredTokenError {
    return [NSError errorWithDomain:PDSSecondFactorErrorDomain
                               code:PDSSecondFactorErrorExpiredToken
                           userInfo:@{NSLocalizedDescriptionKey: @"Expired auth factor token"}];
}

- (NSError *)unavailableError:(NSString *)message {
    return [NSError errorWithDomain:PDSSecondFactorErrorDomain
                               code:PDSSecondFactorErrorUnavailable
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"Second factor unavailable"}];
}

@end
