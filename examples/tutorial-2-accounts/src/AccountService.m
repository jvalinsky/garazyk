#import <Foundation/Foundation.h>
#import "AccountService.h"
#import "AccountRepository.h"
#import "Account.h"
#import "TutorialJWTMinter.h"

#if defined(__APPLE__) && !defined(GNUSTEP)
#import <CommonCrypto/CommonCrypto.h>
#else
#import <openssl/sha.h>
#import <openssl/hmac.h>
#endif

@interface AccountService ()
@property (nonatomic, strong) AccountRepository *repository;
@property (nonatomic, strong) TutorialJWTMinter *minter;
@end

@implementation AccountService

- (instancetype)initWithRepository:(AccountRepository *)repository
                            minter:(TutorialJWTMinter *)minter {
    self = [super init];
    if (!self) return nil;
    self.repository = repository;
    self.minter = minter;
    return self;
}

- (nullable NSDictionary *)createAccountForEmail:(NSString *)email
                                        password:(NSString *)password
                                         handle:(NSString *)handle
                                          error:(NSError **)error {
    if (!email || !password || !handle) {
        if (error) {
            *error = [NSError errorWithDomain:@"Account" code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing required fields"}];
        }
        return nil;
    }

    // Check if handle already exists
    NSError *dbError = nil;
    Account *existing = [self.repository accountForHandle:handle error:&dbError];
    if (existing) {
        if (error) {
            *error = [NSError errorWithDomain:@"Account" code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Handle already taken"}];
        }
        return nil;
    }

    // Check if email already exists
    Account *existingEmail = [self.repository accountForEmail:email error:&dbError];
    if (existingEmail) {
        if (error) {
            *error = [NSError errorWithDomain:@"Account" code:5
                                     userInfo:@{NSLocalizedDescriptionKey: @"Email already registered"}];
        }
        return nil;
    }

    // Generate DID (using did:web format for tutorial — production uses did:plc)
    NSString *did = [NSString stringWithFormat:@"did:web:localhost:~%@", handle];

    // Hash password with salt
    NSData *salt = [self generateSalt];
    NSData *passwordHash = [self hashPassword:password salt:salt];

    // Create account
    Account *account = [[Account alloc] init];
    account.did = did;
    account.handle = handle;
    account.email = email;
    account.passwordHash = passwordHash;
    account.passwordSalt = salt;
    account.createdAt = [[NSDate date] timeIntervalSince1970];

    // Generate ES256-signed tokens
    NSError *mintError = nil;
    account.accessJwt = [self.minter mintAccessTokenForDID:did
                                                    handle:handle
                                                    scopes:@[@"atproto_repo"]
                                                     error:&mintError];
    if (!account.accessJwt) {
        if (error) *error = mintError;
        return nil;
    }

    account.refreshJwt = [self.minter mintRefreshTokenForDID:did
                                                       handle:handle
                                                       scopes:@[@"atproto_refresh"]
                                                        error:&mintError];
    if (!account.refreshJwt) {
        if (error) *error = mintError;
        return nil;
    }

    // Save account
    if (![self.repository saveAccount:account error:&dbError]) {
        if (error) *error = dbError;
        return nil;
    }

    return @{
        @"did": did,
        @"handle": handle,
        @"email": email,
        @"accessJwt": account.accessJwt,
        @"refreshJwt": account.refreshJwt
    };
}

- (nullable NSDictionary *)loginWithHandle:(NSString *)handle
                                  password:(NSString *)password
                                     error:(NSError **)error {
    NSError *dbError = nil;
    Account *account = [self.repository accountForHandle:handle error:&dbError];

    if (!account) {
        if (error) {
            *error = [NSError errorWithDomain:@"Account" code:3
                                     userInfo:@{NSLocalizedDescriptionKey: @"Account not found"}];
        }
        return nil;
    }

    // Verify password
    NSData *passwordHash = [self hashPassword:password salt:account.passwordSalt];
    if (![passwordHash isEqualToData:account.passwordHash]) {
        if (error) {
            *error = [NSError errorWithDomain:@"Account" code:4
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid password"}];
        }
        return nil;
    }

    // Generate new ES256-signed tokens
    NSError *mintError = nil;
    NSString *accessJwt = [self.minter mintAccessTokenForDID:account.did
                                                      handle:account.handle
                                                      scopes:@[@"atproto_repo"]
                                                       error:&mintError];
    if (!accessJwt) {
        if (error) *error = mintError;
        return nil;
    }

    NSString *refreshJwt = [self.minter mintRefreshTokenForDID:account.did
                                                         handle:account.handle
                                                         scopes:@[@"atproto_refresh"]
                                                          error:&mintError];
    if (!refreshJwt) {
        if (error) *error = mintError;
        return nil;
    }

    // Update account with new tokens
    account.accessJwt = accessJwt;
    account.refreshJwt = refreshJwt;
    [self.repository saveAccount:account error:nil];

    return @{
        @"did": account.did,
        @"handle": account.handle,
        @"email": account.email,
        @"accessJwt": accessJwt,
        @"refreshJwt": refreshJwt
    };
}

#pragma mark - Password Hashing

- (NSData *)generateSalt {
    unsigned char salt[16];
    arc4random_buf(salt, sizeof(salt));
    return [NSData dataWithBytes:salt length:sizeof(salt)];
}

- (NSData *)hashPassword:(NSString *)password salt:(NSData *)salt {
    NSData *passwordData = [password dataUsingEncoding:NSUTF8StringEncoding];

#if defined(__APPLE__) && !defined(GNUSTEP)
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, salt.bytes, (size_t)salt.length,
           passwordData.bytes, (size_t)passwordData.length, digest);
    return [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
#else
    unsigned char digest[EVP_MAX_MD_SIZE];
    unsigned int digestLen = 0;
    HMAC(EVP_sha256(), salt.bytes, (int)salt.length,
         passwordData.bytes, (int)passwordData.length, digest, &digestLen);
    return [NSData dataWithBytes:digest length:digestLen];
#endif
}

@end
