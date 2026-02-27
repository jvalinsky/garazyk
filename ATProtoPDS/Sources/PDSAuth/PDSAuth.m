/*!
 @file PDSAuth.m

 @abstract PDS-specific adapters implementation.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "PDSAuth/PDSAuth.h"
#import "Database/PDSDatabase.h"
#import "Auth/JWT.h"
#import "Auth/OAuth2.h"
#import "App/PDSController.h"
#import "Admin/PDSAdminController.h"
#import "Debug/PDSLogger.h"

NSString * const PDSAuthErrorDomain = @"com.atproto.pds.auth";

#pragma mark - PDSAuthStorage

@interface PDSAuthStorage ()
@property (nonatomic, strong) PDSDatabase *database;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *inMemoryPARs;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *inMemoryCodes;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *inMemoryRefreshTokens;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *inMemoryConsents;
@property (nonatomic, strong) dispatch_queue_t queue;
@end

@implementation PDSAuthStorage

- (instancetype)initWithDatabase:(PDSDatabase *)database {
    self = [super init];
    if (self) {
        _database = database;
        _queue = dispatch_queue_create("com.atproto.pdsauth.storage", DISPATCH_QUEUE_SERIAL);
        _inMemoryPARs = [NSMutableDictionary dictionary];
        _inMemoryCodes = [NSMutableDictionary dictionary];
        _inMemoryRefreshTokens = [NSMutableDictionary dictionary];
        _inMemoryConsents = [NSMutableDictionary dictionary];
    }
    return self;
}

#pragma mark - OAuthProviderStorage

- (BOOL)storePAR:(NSDictionary *)par
    forRequestURI:(NSString *)requestURI
        expiresAt:(NSDate *)expiresAt
            error:(NSError **)error {
    dispatch_sync(self.queue, ^{
        self.inMemoryPARs[requestURI] = @{@"data": par, @"expires": expiresAt};
    });
    return YES;
}

- (nullable NSDictionary *)loadPARForRequestURI:(NSString *)requestURI
                                         error:(NSError **)error {
    __block NSDictionary *result = nil;
    dispatch_sync(self.queue, ^{
        NSDictionary *stored = self.inMemoryPARs[requestURI];
        if (stored) {
            NSDate *expires = stored[@"expires"];
            if ([expires compare:[NSDate date]] == NSOrderedDescending) {
                result = stored[@"data"];
            }
        }
    });
    return result;
}

- (BOOL)deletePARForRequestURI:(NSString *)requestURI
                         error:(NSError **)error {
    dispatch_sync(self.queue, ^{
        [self.inMemoryPARs removeObjectForKey:requestURI];
    });
    return YES;
}

- (BOOL)storeAuthCode:(NSString *)code
                 data:(NSDictionary *)data
            expiresAt:(NSDate *)expiresAt
                error:(NSError **)error {
    dispatch_sync(self.queue, ^{
        self.inMemoryCodes[code] = @{@"data": data, @"expires": expiresAt};
    });
    return YES;
}

- (nullable NSDictionary *)consumeAuthCode:(NSString *)code
                                     error:(NSError **)error {
    __block NSDictionary *result = nil;
    dispatch_sync(self.queue, ^{
        NSDictionary *stored = self.inMemoryCodes[code];
        if (stored) {
            NSDate *expires = stored[@"expires"];
            if ([expires compare:[NSDate date]] == NSOrderedDescending) {
                result = stored[@"data"];
            }
            [self.inMemoryCodes removeObjectForKey:code];
        }
    });
    return result;
}

- (BOOL)storeRefreshToken:(NSString *)tokenID
                     data:(NSDictionary *)data
                    error:(NSError **)error {
    dispatch_sync(self.queue, ^{
        self.inMemoryRefreshTokens[tokenID] = data;
    });
    return YES;
}

- (nullable NSDictionary *)loadRefreshToken:(NSString *)tokenID
                                     error:(NSError **)error {
    __block NSDictionary *result = nil;
    dispatch_sync(self.queue, ^{
        result = self.inMemoryRefreshTokens[tokenID];
    });
    return result;
}

- (BOOL)rotateRefreshToken:(NSString *)oldTokenID
                toNewToken:(NSString *)newTokenID
                   withData:(NSDictionary *)newData
                      error:(NSError **)error {
    dispatch_sync(self.queue, ^{
        [self.inMemoryRefreshTokens removeObjectForKey:oldTokenID];
        self.inMemoryRefreshTokens[newTokenID] = newData;
    });
    return YES;
}

- (BOOL)revokeRefreshToken:(NSString *)tokenID
                      error:(NSError **)error {
    dispatch_sync(self.queue, ^{
        [self.inMemoryRefreshTokens removeObjectForKey:tokenID];
    });
    return YES;
}

- (BOOL)hasConsentForAccountDID:(NSString *)accountDID
                       clientID:(NSString *)clientID
                          scope:(NSString *)scope
                          error:(NSError **)error {
    NSString *key = [NSString stringWithFormat:@"%@:%@:%@", accountDID, clientID, scope];
    __block BOOL hasConsent = NO;
    dispatch_sync(self.queue, ^{
        hasConsent = (self.inMemoryConsents[key] != nil);
    });
    return hasConsent;
}

- (BOOL)recordConsentForAccountDID:(NSString *)accountDID
                          clientID:(NSString *)clientID
                             scope:(NSString *)scope
                             error:(NSError **)error {
    NSString *key = [NSString stringWithFormat:@"%@:%@:%@", accountDID, clientID, scope];
    dispatch_sync(self.queue, ^{
        self.inMemoryConsents[key] = @"granted";
    });
    return YES;
}

@end


#pragma mark - PDSAuthClientRegistry

@interface PDSAuthClientRegistry ()
@property (nonatomic, strong) PDSDatabase *database;
@end

@implementation PDSAuthClientRegistry

- (instancetype)initWithDatabase:(PDSDatabase *)database {
    self = [super init];
    if (self) {
        _database = database;
    }
    return self;
}

- (nullable NSDictionary *)getClientByID:(NSString *)clientID
                                  error:(NSError **)error {
    if ([clientID hasPrefix:@"https://"] || [clientID hasPrefix:@"http://"]) {
        return @{
            @"client_id": clientID,
            @"redirect_uris": @[clientID],
            @"token_endpoint_auth_method": @"none",
            @"grant_types": @[@"authorization_code"],
            @"response_types": @[@"code"]
        };
    }
    return @{
        @"client_id": clientID,
        @"redirect_uris": @[[NSString stringWithFormat:@"https://%@/oauth/callback", clientID]],
        @"token_endpoint_auth_method": @"none"
    };
}

- (BOOL)validateRedirectURI:(NSString *)redirectURI
                  forClient:(NSDictionary *)client
                      error:(NSError **)error {
    NSArray *allowed = client[@"redirect_uris"];
    for (NSString *allowedURI in allowed) {
        if ([redirectURI isEqualToString:allowedURI]) {
            return YES;
        }
    }
    return NO;
}

@end


#pragma mark - PDSAuthTokenSigner

@interface PDSAuthTokenSigner ()
@property (nonatomic, strong) JWTMinter *minter;
@property (nonatomic, copy) NSString *issuer;
@end

@implementation PDSAuthTokenSigner

- (instancetype)initWithJWTMinter:(JWTMinter *)minter issuer:(NSString *)issuer {
    self = [super init];
    if (self) {
        _minter = minter;
        _issuer = issuer;
    }
    return self;
}

- (NSString *)issuer {
    return _issuer;
}

- (NSDictionary *)jwks {
    if (self.minter.publicKey) {
        NSData *publicKeyData = self.minter.publicKey;
        if (publicKeyData.length == 65 && ((const uint8_t *)publicKeyData.bytes)[0] == 0x04) {
            NSData *x = [publicKeyData subdataWithRange:NSMakeRange(1, 32)];
            NSData *y = [publicKeyData subdataWithRange:NSMakeRange(33, 32)];
            NSMutableDictionary *jwk = [NSMutableDictionary dictionary];
            jwk[@"kty"] = @"EC";
            jwk[@"crv"] = @"P-256";
            jwk[@"x"] = [self base64URLEncode:x];
            jwk[@"y"] = [self base64URLEncode:y];
            return @{@"keys": @[jwk]};
        }
    }
    return @{@"keys": @[]};
}

- (NSString *)base64URLEncode:(NSData *)data {
    NSString *base64 = [data base64EncodedStringWithOptions:0];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    while ([base64 hasSuffix:@"="]) {
        base64 = [base64 substringToIndex:base64.length - 1];
    }
    return base64;
}

- (nullable NSString *)mintAccessTokenWithClaims:(NSDictionary *)claims
                                         error:(NSError **)error {
    NSMutableDictionary *payload = [claims mutableCopy];
    payload[@"iss"] = self.issuer;
    payload[@"iat"] = @([[NSDate date] timeIntervalSince1970]);
    if (!payload[@"exp"]) {
        payload[@"exp"] = @([[NSDate date] timeIntervalSince1970] + 3600);
    }
    return [self.minter signPayload:payload error:error];
}

- (nullable NSString *)mintRefreshTokenWithClaims:(NSDictionary *)claims
                                            error:(NSError **)error {
    NSMutableDictionary *payload = [claims mutableCopy];
    payload[@"iss"] = self.issuer;
    payload[@"iat"] = @([[NSDate date] timeIntervalSince1970]);
    return [self.minter signPayload:payload error:error];
}

- (nullable NSDictionary *)verifyAccessToken:(NSString *)token
                                 forAudience:(NSString *)audience
                                     error:(NSError **)error {
    JWTVerifier *verifier = [[JWTVerifier alloc] init];
    verifier.keyManager = self.minter.keyManager;
    verifier.publicKey = self.minter.publicKey;
    verifier.expectedIssuer = self.issuer;
    verifier.expectedAudience = audience;
    verifier.allowedAlgorithms = @[@"ES256K", @"ES256"];

    JWT *jwt = [JWT jwtWithToken:token error:error];
    if (!jwt) return nil;

    BOOL valid = [verifier verifyJWT:jwt error:error];
    if (!valid) return nil;

    return [jwt.payload toDictionary];
}

- (nullable NSDictionary *)verifyRefreshToken:(NSString *)token
                                     error:(NSError **)error {
    return [self verifyAccessToken:token forAudience:self.issuer error:error];
}

@end


#pragma mark - PDSAuthUserAuthenticator

@interface PDSAuthUserAuthenticator ()
@property (nonatomic, strong) PDSAccountService *accountService;
@end

@implementation PDSAuthUserAuthenticator

- (instancetype)initWithAccountService:(PDSAccountService *)accountService {
    self = [super init];
    if (self) {
        _accountService = accountService;
    }
    return self;
}

- (nullable NSString *)authenticateLogin:(NSString *)login
                               password:(NSString *)password
                                tfaCode:(nullable NSString *)tfaCode
                                  error:(NSError **)error {
    return nil;
}

- (nullable NSString *)handleForDID:(NSString *)did
                              error:(NSError **)error {
    return nil;
}

@end


#pragma mark - PDSAccountPolicy

@interface PDSAccountPolicy ()
@property (nonatomic, strong) PDSDatabase *database;
@property (nonatomic, weak) id adminController;
@end

@implementation PDSAccountPolicy

- (instancetype)initWithDatabase:(PDSDatabase *)database {
    self = [super init];
    if (self) {
        _database = database;
    }
    return self;
}

- (void)setAdminController:(id)adminController {
    self.adminController = adminController;
}

- (BOOL)isAccountAllowed:(NSString *)did
                   error:(NSError **)error {
    if ([self.adminController respondsToSelector:@selector(isAccountTakedownActive:error:)]) {
        NSError *takedownError = nil;
        BOOL isTakedown = [self.adminController isAccountTakedownActive:did error:&takedownError];
        return !isTakedown;
    }
    return YES;
}

- (BOOL)isAdmin:(NSString *)did
           error:(NSError **)error {
    if ([self.adminController respondsToSelector:@selector(isAdmin:error:)]) {
        return [self.adminController isAdmin:did error:error];
    }
    return NO;
}

@end
