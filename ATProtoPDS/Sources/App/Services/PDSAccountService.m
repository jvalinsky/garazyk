#import "PDSAccountService.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/Service/ServiceDatabases.h"
#import "Database/PDSDatabase.h"
#import "App/PDSConfiguration.h"
#import "Identity/ATProtoHandleValidator.h"
#import "Auth/JWT.h"
#import "Debug/PDSLogger.h"
#import "PLC/PLCOperation.h"
#import "Auth/Secp256k1.h"
#import "Auth/CryptoUtils.h"
#import "Core/CID.h"
#import "Core/ATProtoCBORSerialization.h"
#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonKeyDerivation.h>
#import "Core/ATProtoError.h"
#import "Core/Repositories/PDSAccountRepository.h"
#import "Core/Repositories/PDSSessionRepository.h"
#import "Database/PDSRepositoryFactory.h"
#import "Database/ActorStore/ActorStore.h"

#import "Email/PDSEmailProvider.h"

#ifndef kCCSuccess
#define kCCSuccess 0
#endif

@interface PDSAccountService ()
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

- (nullable NSDictionary *)createAccountForEmail:(NSString *)email
                                        password:(NSString *)password
                                         handle:(NSString *)handle
                                             did:(nullable NSString *)did
                                          error:(NSError **)error {

    PDSConfiguration *config = [PDSConfiguration sharedConfiguration];
    BOOL debugMode = config.debugSkipPlcOperations;

    // Validate Handle
    if (![ATProtoHandleValidator validateHandle:handle error:error]) {
        return nil;
    }
    handle = [ATProtoHandleValidator normalizeHandle:handle];

    NSString *resolvedDid;
    Secp256k1KeyPair *userKeyPair = [[Secp256k1 shared] generateKeyPairWithError:error];
    if (!userKeyPair) return nil;
    
    Secp256k1KeyPair *rotationKeyPair = [[Secp256k1 shared] generateKeyPairWithError:error];
    if (!rotationKeyPair) return nil;

    if (did) {
        resolvedDid = did;
    } else if (debugMode) {
        resolvedDid = [self generatePlcIdentifier];
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
    NSString *accessToken = nil;
    if (self.minter) {
        JWT *jwt = [self.minter mintAccessTokenForDID:resolvedDid handle:handle scopes:@[@"atproto"] error:nil];
        accessToken = [jwt encodedToken];
    } else {
        accessToken = [[NSUUID UUID] UUIDString];
    }

    // Import signing key into ActorStore (ensures it is available for signing commits)
    if (self.databasePool) {
        NSError *storeError = nil;
        PDSActorStore *store = [self.databasePool storeForDid:resolvedDid error:&storeError];
        if (store) {
            if (![store importSigningKey:userKeyPair.privateKey error:&storeError]) {
                PDS_LOG_ERROR(@"Failed to import signing key for DID %@: %@", resolvedDid, storeError);
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
    // Verify password - try PBKDF2 first (new method)
    NSData *passwordHash = [self hashPassword:password salt:account.passwordSalt];
    BOOL isPasswordCorrect = [passwordHash isEqualToData:account.passwordHash];
    BOOL usedLegacyHash = NO;

    if (!isPasswordCorrect) {
        // Fallback: try legacy SHA-256 method for migration support
        NSData *legacyHash = [self legacyHashPassword:password salt:account.passwordSalt];
        if ([legacyHash isEqualToData:account.passwordHash]) {
            isPasswordCorrect = YES;
            usedLegacyHash = YES;
            PDS_LOG_AUTH_INFO(@"Account %@ using legacy password hash, will upgrade", account.did);
        }
    }

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

    // Upgrade password hash if using legacy method
    if (usedLegacyHash) {
        [self upgradePasswordHashIfNeeded:password forAccount:account error:nil];
    }

    // Generate new tokens
    NSString *accessToken = nil;
    if (self.minter) {
        JWT *jwt = [self.minter mintAccessTokenForDID:account.did handle:account.handle scopes:@[@"atproto"] error:nil];
        accessToken = [jwt encodedToken];
    } else {
        accessToken = [[NSUUID UUID] UUIDString];
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

    // Generate new access token
    NSString *accessToken = nil;
    if (self.minter) {
        JWT *jwt = [self.minter mintAccessTokenForDID:account.did handle:account.handle scopes:@[@"atproto"] error:nil];
        accessToken = [jwt encodedToken];
    } else {
        accessToken = [[NSUUID UUID] UUIDString];
    }
    account.accessJwt = [accessToken dataUsingEncoding:NSUTF8StringEncoding];
    [_accountRepository saveAccount:account error:nil];

    return @{
        @"accessJwt": accessToken
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
    if (![passwordHash isEqualToData:account.passwordHash]) {
        if (error) {
            *error = [ATProtoError errorWithCode:ATProtoErrorCodeUnauthorized
                                       message:@"Invalid password"];
        }
        return NO;
    }

    return [_accountRepository deleteAccount:did error:error];
}

#pragma mark - Private Helpers

- (NSString *)generatePlcIdentifier {
    static NSString *const kBase32Chars = @"abcdefghijklmnopqrstuvwxyz234567";
    NSMutableString *str = [NSMutableString stringWithCapacity:24];
    for (int i = 0; i < 24; i++) {
        uint32_t idx = arc4random_uniform((uint32_t)kBase32Chars.length);
        [str appendFormat:@"%C", [kBase32Chars characterAtIndex:idx]];
    }
    return [NSString stringWithFormat:@"did:plc:%@", str];
}

- (NSData *)generateSalt {
    NSMutableData *salt = [NSMutableData dataWithLength:32];
    [[NSUUID UUID] getUUIDBytes:salt.mutableBytes];
    return salt;
}

- (NSData *)hashPassword:(NSString *)password salt:(NSData *)salt {
    // OWASP 2023 recommendation: 600,000 iterations for PBKDF2-HMAC-SHA256
    const uint32_t iterations = 600000;
    const size_t derivedKeyLength = 32; // 256 bits
    unsigned char derivedKey[32];

    int result = CCKeyDerivationPBKDF(
        kCCPBKDF2,                          // algorithm
        password.UTF8String,                 // password
        password.length,                     // passwordLen
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

- (NSData *)legacyHashPassword:(NSString *)password salt:(NSData *)salt {
    // Legacy SHA-256 method for migration support only
    // This will be removed after all passwords are migrated
    NSMutableData *input = [NSMutableData data];
    [input appendData:[password dataUsingEncoding:NSUTF8StringEncoding]];
    [input appendData:salt];

    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(input.bytes, (CC_LONG)input.length, hash);
    return [NSData dataWithBytes:hash length:CC_SHA256_DIGEST_LENGTH];
}

- (BOOL)upgradePasswordHashIfNeeded:(NSString *)password
                         forAccount:(PDSDatabaseAccount *)account
                              error:(NSError **)error {
    // Called after successful login with legacy hash
    // Re-hash with PBKDF2 and update database
    NSData *newHash = [self hashPassword:password salt:account.passwordSalt];
    if (!newHash) {
        if (error) {
            *error = [ATProtoError errorWithCode:ATProtoErrorCodeInternalServerError
                                       message:@"Failed to rehash password"];
        }
        return NO;
    }

    account.passwordHash = newHash;
    BOOL success = [_accountRepository saveAccount:account error:error];
    if (success) {
        PDS_LOG_AUTH_INFO(@"Upgraded password hash for account: %@", account.did);
    }
    return success;
}

#pragma mark - PLC Registration

- (nullable NSString *)_registerDIDWithPLCWithHandle:(NSString *)handle
                                          signingKey:(Secp256k1KeyPair *)signingKey
                                         rotationKey:(Secp256k1KeyPair *)rotationKey
                                               error:(NSError **)error {
    PDSConfiguration *config = [PDSConfiguration sharedConfiguration];
    NSString *plcURLString = config.plcURL;
    
    // Fallback to default if not configured or "mock"
    if ([plcURLString isEqualToString:@"mock"] || plcURLString.length == 0) {
        plcURLString = @"http://127.0.0.1:2582";
    }
    
    NSString *pdsURL = [NSString stringWithFormat:@"http://%@:%lu", config.serverHost, (unsigned long)config.serverPort];
    
    // Format keys as did:key multibase
    NSString *signingKeyMultibase = [signingKey didKeyString];
    NSString *rotationKeyMultibase = [rotationKey didKeyString];
    
    NSDictionary *plcData = @{
        @"type": @"plc_operation",
        @"rotationKeys": @[rotationKeyMultibase],
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
    
    NSString *did = [PLCOperation calculateDIDForData:plcData];
    
    // Sign the operation data (CBOR encoded)
    NSData *cborData = [ATProtoCBORSerialization encodeDataWithJSONObject:plcData error:error];
    if (!cborData) return nil;
    
    NSLog(@"[PDS ACCOUNT] CBOR Data (%lu bytes): %@", (unsigned long)cborData.length, [CryptoUtils hexStringFromData:cborData]);
    NSData *hash = [CID rawSha256:cborData];
    NSData *sig = [[Secp256k1 shared] signHash:hash withPrivateKey:rotationKey.privateKey error:error];
    if (!sig) return nil;
    
    PLCOperation *op = [[PLCOperation alloc] init];
    op.did = did;
    op.data = plcData;
    op.sig = [CryptoUtils base64URLEncode:sig];
    op.prev = nil;
    
    NSDictionary *opDict = [op toDictionary];
    NSLog(@"[PDS ACCOUNT] Registering DID %@ with PLC at %@. Payload: %@", did, plcURLString, opDict);
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
    
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (error) {
            innerError = error;
        } else if (httpResponse && (httpResponse.statusCode != 200 && httpResponse.statusCode != 202)) {
            NSString *body = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
            innerError = [NSError errorWithDomain:@"PLCRegistration" 
                                             code:httpResponse.statusCode 
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"PLC registration failed with status %ld: %@", (long)httpResponse.statusCode, body]}];
        } else if (!httpResponse) {
            innerError = [NSError errorWithDomain:@"PLCRegistration" 
                                             code:-1 
                                         userInfo:@{NSLocalizedDescriptionKey: @"PLC registration failed: No response from server"}];
        } else {
            resultDid = did;
        }
        dispatch_semaphore_signal(sema);
    }] resume];
    
    dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)));
    
    if (innerError) {
        if (error) *error = innerError;
        return nil;
    }
    
    return resultDid;
}

@end
