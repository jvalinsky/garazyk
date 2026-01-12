#import "PDSAccountService.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/Service/ServiceDatabases.h"
#import "Database/PDSDatabase.h"
#import "App/PDSConfiguration.h"
#import "Identity/ATProtoHandleValidator.h"
#import "Auth/JWT.h"
#import <os/log.h>
#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonKeyDerivation.h>

#ifndef kCCSuccess
#define kCCSuccess 0
#endif

@interface PDSAccountService ()

#if defined(GNUSTEP)
@property (nonatomic, assign) os_log_t log;
#else
@property (nonatomic, strong) os_log_t log;
#endif

@end

@implementation PDSAccountService

- (instancetype)initWithDatabasePool:(PDSDatabasePool *)databasePool {
    if (self = [super init]) {
        _databasePool = databasePool;
        PDSConfiguration *config = [PDSConfiguration sharedConfiguration];
        _serviceDatabases = [[PDSServiceDatabases alloc] initWithDirectory:config.dataDirectory
                                                           serviceMaxSize:1024*1024
                                                         didCacheMaxSize:1000
                                                       sequencerMaxSize:100];
        _log = os_log_create("com.atproto.pds", "account");
    }
    return self;
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
    if (did) {
        resolvedDid = did;
    } else if (debugMode) {
        resolvedDid = [self generatePlcIdentifier];
    } else {
        resolvedDid = [NSString stringWithFormat:@"did:web:%@", handle];
    }

    NSError *dbError = nil;
    PDSDatabaseAccount *existingAccount = [_serviceDatabases getAccountByDid:resolvedDid error:&dbError];

    if (existingAccount) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSController" code:1001
                                     userInfo:@{NSLocalizedDescriptionKey: @"Account already exists"}];
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
    if (![_serviceDatabases createAccount:account error:&createError]) {
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
    NSString *refreshToken = [[NSUUID UUID] UUIDString];

    account.accessJwt = [accessToken dataUsingEncoding:NSUTF8StringEncoding];
    account.refreshJwt = [refreshToken dataUsingEncoding:NSUTF8StringEncoding];
    [_serviceDatabases updateAccount:account error:nil];
    [_serviceDatabases storeRefreshToken:refreshToken forAccount:resolvedDid error:nil];

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

    NSError *dbError = nil;
    PDSDatabaseAccount *account = [_serviceDatabases getAccountByHandle:handle error:&dbError];

    if (!account) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSController" code:1000
                                     userInfo:@{NSLocalizedDescriptionKey: @"Account not found"}];
        }
        return nil;
    }

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
            os_log_info(self.log, "Account %@ using legacy password hash, will upgrade", account.did);
        }
    }

    if (!isPasswordCorrect) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSController" code:1002
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid password"}];
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
    [_serviceDatabases updateAccount:account error:nil];
    [_serviceDatabases storeRefreshToken:refreshToken forAccount:account.did error:nil];

    return @{
        @"did": account.did,
        @"handle": account.handle,
        @"email": account.email,
        @"accessJwt": accessToken,
        @"refreshJwt": refreshToken
    };
}

- (nullable NSDictionary *)getAccountForDid:(NSString *)did error:(NSError **)error {
    PDSDatabaseAccount *account = [_serviceDatabases getAccountByDid:did error:error];
    if (!account) return nil;
    
    return @{
        @"did": account.did ?: @"",
        @"handle": account.handle ?: @"",
        @"email": account.email ?: @""
    };
}

- (nullable NSArray *)getAllAccountsWithError:(NSError **)error {
    return [_serviceDatabases getAllAccountsWithError:error];
}

- (nullable NSDictionary *)refreshAccessToken:(NSString *)refreshToken
                                       error:(NSError **)error {

    NSError *dbError = nil;
    PDSDatabaseAccount *account = [_serviceDatabases getAccountByRefreshToken:refreshToken error:&dbError];

    if (!account) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSController" code:1002
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid refresh token"}];
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
    [_serviceDatabases updateAccount:account error:nil];

    return @{
        @"accessJwt": accessToken
    };
}

- (BOOL)deleteAccount:(NSString *)did password:(NSString *)password error:(NSError **)error {

    NSError *dbError = nil;
    PDSDatabaseAccount *account = [_serviceDatabases getAccountByDid:did error:&dbError];

    if (!account) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSController" code:1000
                                     userInfo:@{NSLocalizedDescriptionKey: @"Account not found"}];
        }
        return NO;
    }

    // Verify password
    NSData *passwordHash = [self hashPassword:password salt:account.passwordSalt];
    if (![passwordHash isEqualToData:account.passwordHash]) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSController" code:1007
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid password"}];
        }
        return NO;
    }

    return [_serviceDatabases deleteAccount:did error:error];
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

    unsigned char derivedKey[derivedKeyLength];

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
        os_log_error(self.log, "PBKDF2 derivation failed with error: %d", result);
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
            *error = [NSError errorWithDomain:@"PDSAccountService"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to rehash password"}];
        }
        return NO;
    }

    account.passwordHash = newHash;
    BOOL success = [_serviceDatabases updateAccount:account error:error];
    if (success) {
        os_log_info(self.log, "Upgraded password hash for account: %@", account.did);
    }
    return success;
}

@end