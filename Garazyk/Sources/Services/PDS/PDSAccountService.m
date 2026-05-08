#import "Network/PDSSafeHTTPClient.h"
#import "PDSAccountService.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/Service/ServiceDatabases.h"
#import "Database/PDSDatabase.h"
#import "Database/ActorStore/PDSActorStoreInternal.h"
#import "App/PDSConfiguration.h"
#import "Identity/ATProtoHandleValidator.h"
#import "Auth/JWT.h"
#import "Debug/PDSLogger.h"
#import "PLC/PLCOperation.h"
#import "PLC/PLCRotationKeyManager.h"
#import "Auth/Secp256k1.h"
#import "Auth/CryptoUtils.h"
#import "Core/CID.h"
#import "Core/ATProtoCBORSerialization.h"
#import <CommonCrypto/CommonKeyDerivation.h>
#import <Security/Security.h>
#import "Core/ATProtoError.h"
#import "Core/PDSAccountEvents.h"
#import "Core/Repositories/PDSAccountRepository.h"
#import "Core/Repositories/PDSSessionRepository.h"
#import "Database/PDSRepositoryFactory.h"
#import "Database/ActorStore/ActorStore.h"

#import "Email/PDSEmailProvider.h"

#ifndef kCCSuccess
#define kCCSuccess 0
#endif

static BOOL PDSConstantTimeEqualData(NSData *a, NSData *b) {
    if (!a || !b) {
        return a == b;
    }
    
    const uint8_t *aBytes = (const uint8_t *)a.bytes;
    const uint8_t *bBytes = (const uint8_t *)b.bytes;
    NSUInteger aLen = a.length;
    NSUInteger bLen = b.length;
    
    NSUInteger minLen = aLen < bLen ? aLen : bLen;
    uint8_t diff = (uint8_t)(aLen ^ bLen);
    
    for (NSUInteger i = 0; i < minLen; i++) {
        diff |= (uint8_t)(aBytes[i] ^ bBytes[i]);
    }
    return diff == 0;
}

@interface PDSAccountService ()
- (nullable NSString *)mintAccessTokenForDID:(NSString *)did
                                       handle:(NSString *)handle
                                        error:(NSError **)error;
@end

@implementation PDSAccountService

- (instancetype)initWithDatabasePool:(PDSDatabasePool *)databasePool {
    if (self = [super init]) {
        _databasePool = databasePool;
    }
    return self;
}

- (void)setServiceDatabases:(PDSServiceDatabases *)serviceDatabases {
    _serviceDatabases = serviceDatabases;
    if (serviceDatabases) {
        _accountRepository = [PDSRepositoryFactory accountRepositoryWithServiceDatabases:serviceDatabases];
        _sessionRepository = [PDSRepositoryFactory sessionRepositoryWithServiceDatabases:serviceDatabases];
    }
}

- (instancetype)initWithAccountRepository:(id<PDSAccountRepository>)accountRepository
                        sessionRepository:(id<PDSSessionRepository>)sessionRepository
                                   minter:(nullable JWTMinter *)minter
                            emailProvider:(nullable id<PDSEmailProvider>)emailProvider {
    if (self = [super init]) {
        _accountRepository = accountRepository;
        _sessionRepository = sessionRepository;
        _minter = minter;
        _emailProvider = emailProvider;
    }
    return self;
}

- (instancetype)initWithAccountRepository:(id<PDSAccountRepository>)accountRepository
                        sessionRepository:(id<PDSSessionRepository>)sessionRepository
                                   minter:(nullable JWTMinter *)minter {
    return [self initWithAccountRepository:accountRepository
                           sessionRepository:sessionRepository
                                      minter:minter
                               emailProvider:nil];
}

#pragma mark - Account Operations

- (nullable NSString *)mintAccessTokenForDID:(NSString *)did
                                       handle:(NSString *)handle
                                        error:(NSError **)error {
    NSError *primaryMintError = nil;
    if (self.minter) {
        JWT *jwt = [self.minter mintAccessTokenForDID:did
                                               handle:handle
                                               scopes:@[@"atproto"]
                                                error:&primaryMintError];
        NSString *encoded = [jwt encodedToken];
        if (encoded.length > 0) {
            return encoded;
        }
        if (primaryMintError) {
            PDS_LOG_ERROR(@"Primary JWT mint failed for DID %@: %@", did,
                          primaryMintError.localizedDescription ?: @"unknown");
        }
    }

    // Fallback for test/sandbox environments where keychain-backed signing can fail.
    NSError *fallbackKeyError = nil;
    Secp256k1KeyPair *fallbackKeyPair =
        [[Secp256k1 shared] generateKeyPairWithError:&fallbackKeyError];
    if (!fallbackKeyPair) {
        if (error) {
            *error = primaryMintError ?: fallbackKeyError
                ?: [NSError errorWithDomain:@"com.atproto.server"
                                       code:1
                                   userInfo:@{
                                     NSLocalizedDescriptionKey :
                                         @"JWT minter unavailable"
                                   }];
        }
        return nil;
    }

    JWTMinter *fallbackMinter = [[JWTMinter alloc] init];
    NSString *issuer = self.minter.issuer.length > 0 ? self.minter.issuer : @"http://localhost";
    fallbackMinter.issuer = issuer;
    fallbackMinter.audience = self.minter.audience.length > 0 ? self.minter.audience : issuer;
    fallbackMinter.signingAlgorithm = @"ES256K";
    fallbackMinter.keyManager = nil;
    fallbackMinter.privateKey = fallbackKeyPair.privateKey;
    fallbackMinter.publicKey = fallbackKeyPair.publicKey;

    NSError *fallbackMintError = nil;
    JWT *fallbackJWT = [fallbackMinter mintAccessTokenForDID:did
                                                      handle:handle
                                                      scopes:@[@"atproto"]
                                                       error:&fallbackMintError];
    NSString *fallbackToken = [fallbackJWT encodedToken];
    if (fallbackToken.length > 0) {
        return fallbackToken;
    }

    if (error) {
        *error = fallbackMintError ?: primaryMintError
            ?: [NSError errorWithDomain:@"com.atproto.server"
                                   code:1
                               userInfo:@{
                                 NSLocalizedDescriptionKey : @"JWT minter unavailable"
                               }];
    }
    return nil;
}

- (nullable NSDictionary *)createAccountForEmail:(NSString *)email
                                        password:(NSString *)password
                                         handle:(NSString *)handle
                                             did:(nullable NSString *)did
                                          error:(NSError **)error {

    // Validate Handle
    if (![ATProtoHandleValidator validateHandle:handle error:error]) {
        return nil;
    }
    handle = [ATProtoHandleValidator normalizeHandle:handle];

    if (self.databasePool && [PDSConfiguration sharedConfiguration].masterSecret.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.server"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"PDS_MASTER_SECRET not configured"}];
        }
        return nil;
    }

    NSString *resolvedDid;
    Secp256k1KeyPair *userKeyPair = [[Secp256k1 shared] generateKeyPairWithError:error];
    if (!userKeyPair) return nil;
    
    Secp256k1KeyPair *rotationKeyPair = [[Secp256k1 shared] generateKeyPairWithError:error];
    if (!rotationKeyPair) return nil;

    if (did) {
        resolvedDid = did;
    } else {
        resolvedDid = [self _registerDIDWithPLCWithHandle:handle
                                               signingKey:userKeyPair
                                              rotationKey:rotationKeyPair
                                                    error:error];
        if (!resolvedDid) return nil;
    }

    NSError *dbError = nil;
    PDSDatabaseAccount *existingAccount = [_accountRepository accountForDid:resolvedDid error:&dbError];

    if (existingAccount) {
        if (error) {
            *error = [ATProtoError errorWithCode:ATProtoErrorCodeAlreadyExists
                                       message:@"Account already exists"];
        }
        return nil;
    }

    // Generate password hash
    NSData *salt = [self generateSalt];
    NSData *passwordHash = [self hashPassword:password salt:salt];

    PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
    account.email = email;
    account.handle = handle;
    account.did = resolvedDid;
    account.passwordHash = passwordHash;
    account.passwordSalt = salt;
    account.createdAt = [[NSDate date] timeIntervalSince1970];
    account.updatedAt = [[NSDate date] timeIntervalSince1970];

    NSError *createError = nil;
    if (![_accountRepository saveAccount:account error:&createError]) {
        if (error) *error = createError;
        return nil;
    }

    // Generate tokens
    NSError *mintError = nil;
    NSString *accessToken = [self mintAccessTokenForDID:resolvedDid
                                                 handle:handle
                                                  error:&mintError];
    if (!accessToken) {
        if (error) {
            *error = mintError ?: [NSError errorWithDomain:@"com.atproto.server"
                                                       code:1
                                                   userInfo:@{
                                                     NSLocalizedDescriptionKey :
                                                         @"JWT minter unavailable"
                                                   }];
        }
        return nil;
    }

    // Import signing key into ActorStore (ensures it is available for signing commits)
    if (self.databasePool) {
        NSError *storeError = nil;
        PDSActorStore *store = [self.databasePool storeForDid:resolvedDid error:&storeError];
        if (store) {
            if (![store importSigningKey:userKeyPair.privateKey error:&storeError]) {
                PDS_LOG_ERROR(@"Failed to import signing key for DID %@: %@", resolvedDid, storeError);
            }
            if (![store storeRotationKeyPrivate:rotationKeyPair.privateKey
                                      publicKey:rotationKeyPair.compressedPublicKey
                                        error:&storeError]) {
                PDS_LOG_ERROR(@"Failed to store rotation key for DID %@: %@", resolvedDid, storeError);
            }
        } else {
             PDS_LOG_ERROR(@"Failed to get store for DID %@ to import key: %@", resolvedDid, storeError);
        }
    }
    NSString *refreshToken = [[NSUUID UUID] UUIDString];

    account.accessJwt = [accessToken dataUsingEncoding:NSUTF8StringEncoding];
    account.refreshJwt = [refreshToken dataUsingEncoding:NSUTF8StringEncoding];
    [_accountRepository saveAccount:account error:nil];
    [_sessionRepository storeRefreshToken:refreshToken forAccountDid:resolvedDid error:nil];

    if (self.serviceDatabases) {
        NSDictionary *details = @{
            @"handle": handle ?: @"",
            @"email": email ?: @""
        };
        [self.serviceDatabases logHostingEvent:resolvedDid
                                          type:@"account_created"
                                       details:details
                                     createdBy:resolvedDid
                                         error:nil];
    }

    // Notify firehose of new account (#identity + #account events)
    [[NSNotificationCenter defaultCenter]
        postNotificationName:PDSAccountCreatedNotification
                      object:self
                    userInfo:@{
                        PDSAccountEventDidKey: resolvedDid,
                        PDSAccountEventHandleKey: handle ?: @""
                    }];

    // Send Welcome Email
    if (self.emailProvider) {
        NSString *welcomeSubject = @"Welcome to the ATProto Network!";
        NSString *welcomeBody = [NSString stringWithFormat:@"Hello %@,\n\nWelcome to the ATProto network! Your account with handle %@ has been successfully created.", handle, handle];
        NSError *emailError = nil;
        if (![self.emailProvider sendEmailTo:email
                                     subject:welcomeSubject
                                        body:welcomeBody
                                       error:&emailError]) {
            PDS_LOG_ERROR(@"Failed to send welcome email to %@: %@", email, emailError);
        }
    }

    return @{
        @"did": resolvedDid,
        @"handle": handle,
        @"email": email,
        @"accessJwt": accessToken,
        @"refreshJwt": refreshToken
    };
}

- (nullable NSDictionary *)loginWithHandle:(NSString *)handle
                                 password:(NSString *)password
                                    error:(NSError **)error {
    return [self loginWithIdentifier:handle password:password error:error];
}

- (nullable NSDictionary *)loginWithIdentifier:(NSString *)identifier
                                      password:(NSString *)password
                                         error:(NSError **)error {
    if (!identifier) {
        if (error) {
            *error = [ATProtoError errorWithCode:ATProtoErrorCodeMissingParameter
                                       message:@"Missing identifier"];
        }
        return nil;
    }

    NSError *dbError = nil;
    PDSDatabaseAccount *account = nil;
    if ([identifier containsString:@"@"]) {
        account = [_accountRepository accountForEmail:identifier error:&dbError];
    } else {
        account = [_accountRepository accountForHandle:identifier error:&dbError];
    }

    if (dbError) {
        if (error) *error = dbError;
        return nil;
    }

    if (!account) {
        if (error) {
            *error = [ATProtoError errorWithCode:ATProtoErrorCodeNotFound
                                       message:@"Account not found"];
        }
        return nil;
    }

    return [self loginWithAccount:account password:password error:error];
}

- (nullable NSDictionary *)loginWithAccount:(PDSDatabaseAccount *)account
                                   password:(NSString *)password
                                      error:(NSError **)error {
    // Verify password using the current PBKDF2 policy only.
    NSData *passwordHash = [self hashPassword:password salt:account.passwordSalt];
    BOOL isPasswordCorrect = PDSConstantTimeEqualData(passwordHash, account.passwordHash);

    if (!isPasswordCorrect && self.serviceDatabases) {
        NSError *appPasswordError = nil;
        if ([self.serviceDatabases verifyAppPasswordForAccount:account.did password:password error:&appPasswordError]) {
            isPasswordCorrect = YES;
        }
    }

    if (!isPasswordCorrect) {
        if (error) {
            *error = [ATProtoError errorWithCode:ATProtoErrorCodeInvalidCredentials
                                       message:@"Invalid password"];
        }
        return nil;
    }

    // Generate new tokens
    NSError *mintError = nil;
    NSString *accessToken = [self mintAccessTokenForDID:account.did
                                                 handle:account.handle
                                                  error:&mintError];
    if (!accessToken) {
        if (error) {
            *error = mintError ?: [NSError errorWithDomain:@"com.atproto.server"
                                                       code:1
                                                   userInfo:@{
                                                     NSLocalizedDescriptionKey :
                                                         @"JWT minter unavailable"
                                                   }];
        }
        return nil;
    }
    NSString *refreshToken = [[NSUUID UUID] UUIDString];

    account.accessJwt = [accessToken dataUsingEncoding:NSUTF8StringEncoding];
    account.refreshJwt = [refreshToken dataUsingEncoding:NSUTF8StringEncoding];
    [_accountRepository saveAccount:account error:nil];
    [_sessionRepository storeRefreshToken:refreshToken forAccountDid:account.did error:nil];

    return @{
        @"did": account.did,
        @"handle": account.handle,
        @"email": account.email,
        @"accessJwt": accessToken,
        @"refreshJwt": refreshToken
    };
}

- (nullable NSDictionary *)getAccountForDid:(NSString *)did error:(NSError **)error {
    PDSDatabaseAccount *account = [_accountRepository accountForDid:did error:error];
    if (!account) return nil;
    
    return @{
        @"did": account.did ?: @"",
        @"handle": account.handle ?: @"",
        @"email": account.email ?: @""
    };
}

- (nullable NSDictionary *)usageForDid:(NSString *)did error:(NSError **)error {
    if (!self.databasePool) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.server"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Database pool unavailable"}];
        }
        return nil;
    }

    PDSActorStore *store = [self.databasePool storeForDid:did error:error];
    if (!store) {
        return nil;
    }

    __block NSDictionary *result = nil;
    [store readWithBlock:^(id<PDSActorStoreReader> reader, NSError **blockError) {
        PDSActorStore *actorStore = (PDSActorStore *)reader;
        NSString *sql = @"SELECT blob_bytes, blob_count, repo_bytes, record_count FROM account_usage WHERE did = ?";
        sqlite3_stmt *stmt = [actorStore prepareStatement:sql error:blockError];
        if (!stmt) {
            return;
        }
        sqlite3_bind_text(stmt, 1, [did UTF8String], -1, SQLITE_TRANSIENT);

        if (sqlite3_step(stmt) == SQLITE_ROW) {
            result = @{
                @"blobBytes": @(sqlite3_column_int64(stmt, 0)),
                @"blobCount": @(sqlite3_column_int(stmt, 1)),
                @"repoBytes": @(sqlite3_column_int64(stmt, 2)),
                @"recordCount": @(sqlite3_column_int(stmt, 3))
            };
        } else {
            result = @{
                @"blobBytes": @(0),
                @"blobCount": @(0),
                @"repoBytes": @(0),
                @"recordCount": @(0)
            };
        }
        [actorStore finalizeStatement:stmt];
    } error:error];

    return result;
}

- (nullable NSArray *)getAllAccountsWithError:(NSError **)error {
    return [_accountRepository listAccountsWithLimit:1000 cursor:nil error:error];
}

- (nullable NSDictionary *)refreshAccessToken:(NSString *)refreshToken
                                       error:(NSError **)error {

    NSError *dbError = nil;
    NSString *did = [_sessionRepository accountDidForRefreshToken:refreshToken error:&dbError];
    PDSDatabaseAccount *account = nil;
    if (did) {
        account = [_accountRepository accountForDid:did error:&dbError];
    }

    if (!account) {
        if (error) {
            *error = [ATProtoError errorWithCode:ATProtoErrorCodeInvalidCredentials
                                       message:@"Invalid refresh token"];
        }
        return nil;
    }

    // Revoke old refresh token (Rotation)
    [_sessionRepository revokeRefreshToken:refreshToken error:nil];

    // Generate new access token
    NSError *mintError = nil;
    NSString *accessToken = [self mintAccessTokenForDID:account.did
                                                 handle:account.handle
                                                  error:&mintError];
    if (!accessToken) {
        if (error) {
            *error = mintError ?: [NSError errorWithDomain:@"com.atproto.server"
                                                       code:1
                                                   userInfo:@{
                                                     NSLocalizedDescriptionKey :
                                                         @"JWT minter unavailable"
                                                   }];
        }
        return nil;
    }

    // Generate new refresh token
    NSString *newRefreshToken = [[NSUUID UUID] UUIDString];

    account.accessJwt = [accessToken dataUsingEncoding:NSUTF8StringEncoding];
    account.refreshJwt = [newRefreshToken dataUsingEncoding:NSUTF8StringEncoding];
    [_accountRepository saveAccount:account error:nil];
    [_sessionRepository storeRefreshToken:newRefreshToken forAccountDid:account.did error:nil];

    return @{
        @"accessJwt": accessToken,
        @"refreshJwt": newRefreshToken,
        @"handle": account.handle ?: @"",
        @"did": account.did ?: @""
    };
}

- (BOOL)deleteAccount:(NSString *)did password:(NSString *)password error:(NSError **)error {

    NSError *dbError = nil;
    PDSDatabaseAccount *account = [_accountRepository accountForDid:did error:&dbError];

    if (!account) {
        if (error) {
            *error = [ATProtoError errorWithCode:ATProtoErrorCodeNotFound
                                       message:@"Account not found"];
        }
        return NO;
    }

    // Verify password
    NSData *passwordHash = [self hashPassword:password salt:account.passwordSalt];
    if (!PDSConstantTimeEqualData(passwordHash, account.passwordHash)) {
        if (error) {
            *error = [ATProtoError errorWithCode:ATProtoErrorCodeUnauthorized
                                       message:@"Invalid password"];
        }
        return NO;
    }

    return [_accountRepository deleteAccount:did error:error];
}

#pragma mark - Private Helpers

- (NSData *)generateSalt {
    NSMutableData *salt = [NSMutableData dataWithLength:32];
    int randomStatus = SecRandomCopyBytes(kSecRandomDefault, salt.length, salt.mutableBytes);
    if (randomStatus != errSecSuccess) {
        arc4random_buf(salt.mutableBytes, salt.length);
    }
    return salt;
}

- (NSData *)hashPassword:(NSString *)password salt:(NSData *)salt {
    // OWASP 2023 recommendation: 600,000 iterations for PBKDF2-HMAC-SHA256
    const uint32_t iterations = 600000;
    const size_t derivedKeyLength = 32; // 256 bits
    unsigned char derivedKey[32];

    NSData *passwordData = [password dataUsingEncoding:NSUTF8StringEncoding];
    if (!passwordData) {
        PDS_LOG_AUTH_ERROR(@"Failed to encode password as UTF-8");
        return nil;
    }

    int result = CCKeyDerivationPBKDF(
        kCCPBKDF2,                          // algorithm
        (const char *)passwordData.bytes,    // password
        passwordData.length,                 // passwordLen
        salt.bytes,                          // salt
        salt.length,                         // saltLen
        kCCPRFHmacAlgSHA256,                // PRF (HMAC-SHA256)
        iterations,                          // rounds
        derivedKey,                          // derivedKey
        derivedKeyLength                     // derivedKeyLen
    );

    if (result != kCCSuccess) {
        PDS_LOG_AUTH_ERROR(@"PBKDF2 derivation failed with error: %d", result);
        return nil;
    }

    return [NSData dataWithBytes:derivedKey length:derivedKeyLength];
}

#pragma mark - PLC DID Generation (Sans-I/O)

/// Pure DID generation - no network I/O. Generates a valid did:plc from the
/// operation data without registering with a PLC server. This is the sans-IO
/// core that can be tested without mocks.
- (nullable NSString *)_generateDIDWithHandle:(NSString *)handle
                                    signingKey:(Secp256k1KeyPair *)signingKey
                                   rotationKey:(Secp256k1KeyPair *)rotationKey
                                         error:(NSError **)error {
    PDSConfiguration *config = [PDSConfiguration sharedConfiguration];
    NSString *pdsURL = config.canonicalIssuer;
    
    NSString *signingKeyMultibase = [signingKey didKeyString];
    NSString *rotationKeyMultibase = [rotationKey didKeyString];
    
    PLCRotationKeyManager *keyManager = [PLCRotationKeyManager sharedManager];
    NSError *keyLoadError = nil;
    if (![keyManager loadOrGenerateKeyWithError:&keyLoadError]) {
        if (error) {
            *error = keyLoadError;
        }
        return nil;
    }
    NSString *serverRotationKey = keyManager.rotationKeyDidKey;
    
    NSArray *rotationKeys = @[serverRotationKey, rotationKeyMultibase];
    
    // Create unsigned operation (no sig field)
    NSDictionary *unsignedData = @{
        @"type": @"plc_operation",
        @"rotationKeys": rotationKeys,
        @"verificationMethods": @{
            @"atproto": signingKeyMultibase
        },
        @"alsoKnownAs": @[[NSString stringWithFormat:@"at://%@", handle]],
        @"services": @{
            @"atproto_pds": @{
                @"type": @"AtprotoPersonalDataServer",
                @"endpoint": pdsURL
            }
        },
        @"prev": [NSNull null]
    };
    
    // Encode unsigned operation as DAG-CBOR and sign
    NSData *unsignedCBOR = [ATProtoCBORSerialization encodeDataWithJSONObject:unsignedData error:error];
    if (!unsignedCBOR) return nil;
    
    PDS_LOG_AUTH_DEBUG(@"[PDS ACCOUNT] Unsigned CBOR hex: %@", [CryptoUtils hexStringFromData:unsignedCBOR]);

    NSData *hash = [CID rawSha256:unsignedCBOR];
    PDS_LOG_AUTH_DEBUG(@"[PDS ACCOUNT] Unsigned operation hash (SHA-256): %@", [CryptoUtils hexStringFromData:hash]);
    
    NSData *sig = nil;
    if (![keyManager signHash:hash result:&sig error:error]) {
        return nil;
    }
    if (!sig) return nil;
    
    // Create signed operation (with sig field)
    NSMutableDictionary *signedData = [unsignedData mutableCopy];
    signedData[@"sig"] = [CryptoUtils base64URLEncode:sig];
    
    // Calculate DID from the UNSIGNED operation
    NSString *did = [PLCOperation calculateDIDForData:unsignedData];
    PDS_LOG_AUTH_DEBUG(@"[PDS ACCOUNT] Calculated DID %@ for unsigned data: %@", did, unsignedData);
    
    return did;
}

#pragma mark - PLC Registration (I/O Layer)

/// I/O adapter - generates DID then registers with PLC server.
/// For tests that don't need actual registration, use _generateDIDWithHandle: directly.
- (nullable NSString *)_registerDIDWithPLCWithHandle:(NSString *)handle
                                           signingKey:(Secp256k1KeyPair *)signingKey
                                          rotationKey:(Secp256k1KeyPair *)rotationKey
                                                error:(NSError **)error {
    PDSConfiguration *config = [PDSConfiguration sharedConfiguration];
    NSString *plcURLString = config.plcURL;
    
    // Check for "skip" or "mock" mode - generate DID without network registration (for tests)
    if ([plcURLString isEqualToString:@"skip"] || [plcURLString isEqualToString:@"mock"]) {
        return [self _generateDIDWithHandle:handle signingKey:signingKey rotationKey:rotationKey error:error];
    }
    
    if (plcURLString.length == 0) {
        plcURLString = @"http://127.0.0.1:2582";
    }
    
    // Generate the DID (pure, sans-IO)
    NSString *did = [self _generateDIDWithHandle:handle signingKey:signingKey rotationKey:rotationKey error:error];
    if (!did) return nil;
    
    // Build the operation for submission (I/O layer needs full operation)
    NSString *pdsURL = config.canonicalIssuer;
    NSString *signingKeyMultibase = [signingKey didKeyString];
    NSString *rotationKeyMultibase = [rotationKey didKeyString];
    
    PLCRotationKeyManager *keyManager = [PLCRotationKeyManager sharedManager];
    NSString *serverRotationKey = keyManager.rotationKeyDidKey;
    NSArray *rotationKeys = @[serverRotationKey, rotationKeyMultibase];
    
    // Rebuild unsigned data for the operation
    NSDictionary *unsignedData = @{
        @"type": @"plc_operation",
        @"rotationKeys": rotationKeys,
        @"verificationMethods": @{
            @"atproto": signingKeyMultibase
        },
        @"alsoKnownAs": @[[NSString stringWithFormat:@"at://%@", handle]],
        @"services": @{
            @"atproto_pds": @{
                @"type": @"AtprotoPersonalDataServer",
                @"endpoint": pdsURL
            }
        },
        @"prev": [NSNull null]
    };
    
    // Re-sign for the operation
    NSData *unsignedCBOR = [ATProtoCBORSerialization encodeDataWithJSONObject:unsignedData error:error];
    if (!unsignedCBOR) return nil;
    
    NSData *hash = [CID rawSha256:unsignedCBOR];
    NSData *sig = nil;
    if (![keyManager signHash:hash result:&sig error:error]) {
        return nil;
    }
    
    PLCOperation *op = [[PLCOperation alloc] init];
    op.did = did;
    op.data = [unsignedData copy];
    op.sig = [CryptoUtils base64URLEncode:sig];
    op.prev = nil;
    
    NSDictionary *opDict = [op toDictionary];
    PDS_LOG_AUTH_INFO(@"[PDS ACCOUNT] Registering DID %@ with PLC at %@", did, plcURLString);
    NSData *postData = [NSJSONSerialization dataWithJSONObject:opDict options:0 error:error];
    if (!postData) return nil;
    
    NSURL *plcURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@/%@", plcURLString, did]];
    NSMutableURLRequest *request = [NSURLRequest requestWithURL:plcURL].mutableCopy;
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    request.HTTPBody = postData;
    
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    __block NSString *resultDid = nil;
    __block NSError *innerError = nil;
    
    [[PDSSafeHTTPClient sharedClient] performSafeDataTaskWithRequest:request options:[PDSSafeHTTPClientOptions defaultOptions] completion:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (error) {
            innerError = error;
        } else if (httpResponse && (httpResponse.statusCode != 200 && httpResponse.statusCode != 202)) {
            NSNumber *bodyBytes = @((unsigned long long)(data.length));
            NSString *bodyString = nil;
            if (data.length > 0) {
                bodyString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                if (bodyString.length > 2048) {
                    bodyString = [[bodyString substringToIndex:2048] stringByAppendingString:@"..."];
                }
            }
            NSString *message = [NSString stringWithFormat:@"PLC registration failed with status %ld", (long)httpResponse.statusCode];
            NSMutableDictionary *userInfo = [@{
                NSLocalizedDescriptionKey: bodyString.length > 0 ? [message stringByAppendingFormat:@": %@", bodyString] : message,
                @"response_body_bytes": bodyBytes
            } mutableCopy];
            if (bodyString.length > 0) {
                userInfo[@"response_body"] = bodyString;
            }
            innerError = [NSError errorWithDomain:@"PLCRegistration" 
                                             code:httpResponse.statusCode 
                                         userInfo:userInfo];
        } else if (!httpResponse) {
            innerError = [NSError errorWithDomain:@"PLCRegistration" 
                                             code:-1 
                                         userInfo:@{NSLocalizedDescriptionKey: @"PLC registration failed: No response from server"}];
        } else {
            resultDid = did;
        }
        dispatch_semaphore_signal(sema);
            *error = [NSError errorWithDomain:@"PLCRegistration"
                                         code:NSURLErrorTimedOut
                                     userInfo:@{NSLocalizedDescriptionKey: @"PLC registration timed out after 10 seconds"}];
        }
        return nil;
    }
    
    if (innerError) {
        if (error) *error = innerError;
        return nil;
    }

    if (!resultDid) {
        if (error) {
            *error = [NSError errorWithDomain:@"PLCRegistration"
                                         code:-2
                                     userInfo:@{NSLocalizedDescriptionKey: @"PLC registration completed without returning a DID"}];
        }
        return nil;
    }
    
    return resultDid;
}

#pragma mark - Testing Utilities

- (NSString *)generatePlcIdentifier {
    // Generate a random 24-character base32 identifier for did:plc
    // Alphabet: 234567abcdefghijklmnopqrstuvwxyz (no 0, 1, 8, 9, no uppercase)
    static NSString * const alphabet = @"234567abcdefghijklmnopqrstuvwxyz";
    static const NSUInteger identifierLength = 24;

    NSMutableString *identifier = [NSMutableString stringWithCapacity:identifierLength];
    for (NSUInteger i = 0; i < identifierLength; i++) {
        NSUInteger idx = arc4random_uniform((uint32_t)alphabet.length);
        [identifier appendFormat:@"%C", [alphabet characterAtIndex:idx]];
    }

    return [NSString stringWithFormat:@"did:plc:%@", identifier];
}

@end
