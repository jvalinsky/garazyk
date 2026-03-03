#import <Foundation/Foundation.h>
#import "AccountService.h"
#import <CommonCrypto/CommonCrypto.h>

@interface AccountService ()
@property (nonatomic, strong) AccountRepository *repository;
@property (nonatomic, strong) SimpleJWTMinter *minter;
@end

@implementation AccountService

- (instancetype)initWithRepository:(AccountRepository *)repository
                            minter:(SimpleJWTMinter *)minter {
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
    // Validate inputs
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
    
    // Generate DID
    NSString *did = [NSString stringWithFormat:@"did:plc:%@", [[NSUUID UUID] UUIDString]];
    
    // Hash password
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
    
    // Generate tokens
    account.accessJwt = [self.minter mintAccessTokenForDID:did handle:handle];
    account.refreshJwt = [self.minter mintRefreshTokenForDID:did handle:handle];
    
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
    // Look up account
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
    
    // Generate new tokens
    NSString *accessJwt = [self.minter mintAccessTokenForDID:account.did handle:account.handle];
    NSString *refreshJwt = [self.minter mintRefreshTokenForDID:account.did handle:account.handle];
    
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

- (NSData *)generateSalt {
    unsigned char salt[16];
    arc4random_buf(salt, sizeof(salt));
    return [NSData dataWithBytes:salt length:sizeof(salt)];
}

- (NSData *)hashPassword:(NSString *)password salt:(NSData *)salt {
    NSData *passwordData = [password dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    
    CCHmac(kCCHmacAlgSHA256, salt.bytes, salt.length, passwordData.bytes, passwordData.length, digest);
    
    return [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
}

@end
