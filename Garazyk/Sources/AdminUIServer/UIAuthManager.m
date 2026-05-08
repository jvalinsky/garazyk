#import "AdminUIServer/UIAuthManager.h"
#import "Network/HttpRequest.h"
#import "Security/PDSSecurityCompare.h"
#import "Auth/CryptoUtils.h"
#import "Debug/PDSLogger.h"
#import "Compat/PDSTypes.h"

#if !TARGET_OS_LINUX
#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonKeyDerivation.h>
#import <Security/SecRandom.h>
#else
#import "Compat/PlatformShims/CommonCrypto/CommonDigest.h"
#import "Compat/PlatformShims/CommonCrypto/CommonKeyDerivation.h"
#import "Compat/PlatformShims/Security/SecRandom.h"
#endif

const NSTimeInterval kUIAuthDefaultSessionTTL = 28800.0; // 8 hours

static NSString *sha256Hex(NSString *input) {
    if (!input) return @"";
    NSData *data = [input dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (size_t i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [hex appendFormat:@"%02x", digest[i]];
    }
    return hex;
}

static NSData *pbkdf2DeriveKey(NSString *password, NSData *salt) {
    if (!password || !salt || salt.length == 0) return nil;
    NSData *passwordData = [password dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t derivedKey[32]; // 256-bit key
    int result = CCKeyDerivationPBKDF(kCCPBKDF2,
                                       passwordData.bytes, passwordData.length,
                                       salt.bytes, salt.length,
                                       kCCPRFHmacAlgSHA256,
                                       100000, // 100k iterations
                                       derivedKey, 32);
    if (result != kCCSuccess) return nil;
    return [NSData dataWithBytes:derivedKey length:32];
}

static NSString *generateCSPRNGToken(NSUInteger byteCount) {
    uint8_t bytes[32];
    if (byteCount > sizeof(bytes)) byteCount = sizeof(bytes);
    if (SecRandomCopyBytes(kSecRandomDefault, byteCount, bytes) != errSecSuccess) {
        PDS_LOG_ERROR(@"Failed to generate CSPRNG token");
        return nil;
    }
    NSMutableString *token = [NSMutableString stringWithCapacity:byteCount * 2];
    for (NSUInteger i = 0; i < byteCount; i++) {
        [token appendFormat:@"%02x", bytes[i]];
    }
    return token;
}

@interface UIAuthSessionEntry : NSObject
@property (nonatomic, copy) NSString *tokenHash;   // SHA-256 of the plaintext token
@property (nonatomic, assign) NSTimeInterval expiryTime; // timeIntervalSince1970
@end

@implementation UIAuthSessionEntry
@end

@interface UIAuthManager ()

/// PBKDF2 salt (random, generated at init)
@property (nonatomic, strong) NSData *passwordSalt;
/// PBKDF2-derived hash of the password (stored instead of plaintext)
@property (nonatomic, copy) NSString *passwordHash;
/// Active sessions: keyed by token hash, value is session entry with expiry
@property (nonatomic, strong) NSMutableDictionary<NSString *, UIAuthSessionEntry *> *activeSessions;
/// CSRF nonces: keyed by nonce hash, value is expiry time
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSTimeInterval> *csrfNonces;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t stateQueue;

@end

@implementation UIAuthManager

- (instancetype)initWithPassword:(NSString *)password {
    self = [super init];
    if (self) {
        _sessionTTL = kUIAuthDefaultSessionTTL;

        // Generate random salt for PBKDF2
        uint8_t saltBytes[16];
        if (SecRandomCopyBytes(kSecRandomDefault, 16, saltBytes) != errSecSuccess) {
            PDS_LOG_ERROR(@"Failed to generate password salt");
            _passwordSalt = [NSData data];
            _passwordHash = @"";
        } else {
            _passwordSalt = [NSData dataWithBytes:saltBytes length:16];
            // Derive key from password and store as hex hash
            NSData *derivedKey = pbkdf2DeriveKey(password, _passwordSalt);
            if (derivedKey) {
                NSMutableString *hex = [NSMutableString stringWithCapacity:64];
                const uint8_t *bytes = derivedKey.bytes;
                for (NSUInteger i = 0; i < derivedKey.length; i++) {
                    [hex appendFormat:@"%02x", bytes[i]];
                }
                _passwordHash = hex;
            } else {
                _passwordHash = @"";
            }
        }

        _activeSessions = [NSMutableDictionary dictionary];
        _csrfNonces = [NSMutableDictionary dictionary];
        _stateQueue = dispatch_queue_create("com.garazyk.ui.auth", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (BOOL)validatePassword:(NSString *)password {
    if (!password || password.length == 0) {
        return NO;
    }
    // Derive key from the provided password using the same salt
    NSData *derivedKey = pbkdf2DeriveKey(password, self.passwordSalt);
    if (!derivedKey) return NO;

    NSMutableString *hex = [NSMutableString stringWithCapacity:64];
    const uint8_t *bytes = derivedKey.bytes;
    for (NSUInteger i = 0; i < derivedKey.length; i++) {
        [hex appendFormat:@"%02x", bytes[i]];
    }
    return [PDSSecurityCompare constantTimeEqualString:self.passwordHash string:hex];
}

- (NSString *)createSessionToken {
    // Generate 32 bytes of CSPRNG data, hex-encoded = 64-char token
    NSString *token = generateCSPRNGToken(32);
    if (!token) {
        // Fallback to UUID (should never happen in practice)
        token = [[NSUUID UUID] UUIDString];
    }

    NSString *tokenHash = sha256Hex(token);
    NSTimeInterval expiry = [[NSDate date] timeIntervalSince1970] + self.sessionTTL;

    UIAuthSessionEntry *entry = [[UIAuthSessionEntry alloc] init];
    entry.tokenHash = tokenHash;
    entry.expiryTime = expiry;

    dispatch_sync(self.stateQueue, ^{
        self.activeSessions[tokenHash] = entry;
    });
    return token;
}

- (void)invalidateSessionToken:(NSString *)token {
    if (token.length == 0) return;
    NSString *tokenHash = sha256Hex(token);
    dispatch_sync(self.stateQueue, ^{
        [self.activeSessions removeObjectForKey:tokenHash];
    });
}

- (BOOL)isAuthorizedRequest:(HttpRequest *)request {
    NSString *token = [self extractTokenFromRequest:request];
    if (token.length == 0) return NO;

    NSString *tokenHash = sha256Hex(token);
    __block BOOL authorized = NO;
    dispatch_sync(self.stateQueue, ^{
        UIAuthSessionEntry *entry = self.activeSessions[tokenHash];
        if (entry) {
            NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
            if (now < entry.expiryTime) {
                authorized = YES;
            } else {
                // Expired — remove
                [self.activeSessions removeObjectForKey:tokenHash];
            }
        }
    });
    return authorized;
}

- (NSString *)extractTokenFromRequest:(HttpRequest *)request {
    NSString *authHeader = [request headerForKey:@"Authorization"];
    if ([authHeader.lowercaseString hasPrefix:@"bearer "]) {
        NSString *token = [authHeader substringFromIndex:7];
        token = [token stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (token.length > 0) {
            return token;
        }
    }

    NSString *cookieHeader = [request headerForKey:@"Cookie"];
    if (![cookieHeader isKindOfClass:[NSString class]] || cookieHeader.length == 0) {
        return nil;
    }

    for (NSString *cookie in [cookieHeader componentsSeparatedByString:@";"]) {
        NSString *trimmed = [cookie stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (![trimmed hasPrefix:@"ui_admin_token="]) {
            continue;
        }
        NSString *token = [trimmed substringFromIndex:@"ui_admin_token=".length];
        return token.length > 0 ? token : nil;
    }
    return nil;
}

- (NSString *)cookieHeaderValueForToken:(NSString *)token secure:(BOOL)secure {
    NSMutableString *cookie = [NSMutableString stringWithFormat:
        @"ui_admin_token=%@; Path=/; HttpOnly; SameSite=Strict", token];
    if (secure) {
        [cookie appendString:@"; Secure"];
    }
    return cookie;
}

#pragma mark - CSRF Protection

- (BOOL)validateCSRFForRequest:(HttpRequest *)request {
    // Only check CSRF for state-changing methods (POST, PUT, DELETE)
    NSString *method = request.methodString;
    if ([method isEqualToString:@"GET"] || [method isEqualToString:@"HEAD"] || [method isEqualToString:@"OPTIONS"]) {
        return YES;
    }

    NSString *nonceHeader = [request headerForKey:@"X-UI-Admin-Nonce"];
    if (nonceHeader.length == 0) return NO;

    // Find nonce in cookie
    NSString *cookieHeader = [request headerForKey:@"Cookie"];
    if (![cookieHeader isKindOfClass:[NSString class]] || cookieHeader.length == 0) return NO;

    NSString *nonceCookie = nil;
    for (NSString *cookie in [cookieHeader componentsSeparatedByString:@";"]) {
        NSString *trimmed = [cookie stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([trimmed hasPrefix:@"ui_admin_nonce="]) {
            nonceCookie = [trimmed substringFromIndex:@"ui_admin_nonce=".length];
            break;
        }
    }

    if (nonceCookie.length == 0) return NO;

    // Constant-time compare header vs cookie
    if (![PDSSecurityCompare constantTimeEqualString:nonceHeader string:nonceCookie]) {
        return NO;
    }

    // Check nonce hasn't expired
    NSString *nonceHash = sha256Hex(nonceHeader);
    __block BOOL valid = NO;
    dispatch_sync(self.stateQueue, ^{
        NSTimeInterval expiry = self.csrfNonces[nonceHash].doubleValue;
        if (expiry > 0 && [[NSDate date] timeIntervalSince1970] < expiry) {
            valid = YES;
            // Remove used nonce (one-time use)
            [self.csrfNonces removeObjectForKey:nonceHash];
        }
    });
    return valid;
}

- (NSString *)createCSRFNonceCookie:(BOOL)secure {
    NSString *nonce = generateCSPRNGToken(16);
    if (!nonce) nonce = [[NSUUID UUID] UUIDString];

    NSString *nonceHash = sha256Hex(nonce);
    NSTimeInterval expiry = [[NSDate date] timeIntervalSince1970] + self.sessionTTL;

    dispatch_sync(self.stateQueue, ^{
        self.csrfNonces[nonceHash] = @(expiry);
    });

    NSMutableString *cookie = [NSMutableString stringWithFormat:
        @"ui_admin_nonce=%@; Path=/; HttpOnly; SameSite=Strict", nonce];
    if (secure) {
        [cookie appendString:@"; Secure"];
    }
    return cookie;
}

@end
