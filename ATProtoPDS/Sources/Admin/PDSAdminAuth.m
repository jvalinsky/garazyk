#import "Admin/PDSAdminAuth.h"
#import "Auth/JWT.h"
#import "App/PDSController.h"
#import "App/PDSConfiguration.h"
#import <CommonCrypto/CommonKeyDerivation.h>
#include <stdlib.h>

#ifndef kCCSuccess
#define kCCSuccess 0
#endif

static NSString *const PDSAdminAuthErrorDomain = @"PDSAdminAuth";
static const NSTimeInterval PDSAdminAuthDefaultTokenTTLSeconds = 3600.0;
static const NSTimeInterval PDSAdminAuthMinTokenTTLSeconds = 60.0;
static const NSTimeInterval PDSAdminAuthMaxTokenTTLSeconds = 86400.0;

static BOOL PDSConstantTimeEqualStrings(NSString *a, NSString *b) {
    if (a == nil || b == nil) {
        return NO;
    }

    NSData *aData = [a dataUsingEncoding:NSUTF8StringEncoding];
    NSData *bData = [b dataUsingEncoding:NSUTF8StringEncoding];
    if (aData == nil || bData == nil) {
        return NO;
    }

    if (aData.length != bData.length) {
        return NO;
    }

    const uint8_t *aBytes = aData.bytes;
    const uint8_t *bBytes = bData.bytes;
    uint8_t diff = 0;
    for (NSUInteger i = 0; i < aData.length; i++) {
        diff |= (uint8_t)(aBytes[i] ^ bBytes[i]);
    }
    return diff == 0;
}

static BOOL PDSScopesContainAdmin(NSString *scopeString) {
    if (scopeString.length == 0) {
        return NO;
    }
    NSArray<NSString *> *parts = [scopeString componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    for (NSString *part in parts) {
        if (part.length == 0) {
            continue;
        }
        if ([part isEqualToString:@"admin"]) {
            return YES;
        }
    }
    return NO;
}

static BOOL PDSAdminAuthEnvBool(NSString *value) {
    if (value.length == 0) {
        return NO;
    }
    NSString *normalized = [[value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    return [normalized isEqualToString:@"1"] ||
           [normalized isEqualToString:@"true"] ||
           [normalized isEqualToString:@"yes"] ||
           [normalized isEqualToString:@"on"];
}

static BOOL PDSAdminAuthIsIssuerRequired(NSDictionary *env) {
    if (PDSAdminAuthEnvBool(env[@"PDS_REQUIRE_ISSUER"])) {
        return YES;
    }
    NSString *environment = [env[@"PDS_ENV"] lowercaseString];
    return [environment isEqualToString:@"production"];
}

static BOOL PDSAdminAuthHostLooksLocal(NSString *host) {
    NSString *normalized = [[host ?: @"" lowercaseString]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return normalized.length == 0 ||
           [normalized isEqualToString:@"localhost"] ||
           [normalized isEqualToString:@"127.0.0.1"] ||
           [normalized isEqualToString:@"::1"] ||
           [normalized isEqualToString:@"0.0.0.0"];
}

static NSString *PDSAdminAuthCanonicalIssuerFromConfiguration(PDSConfiguration *configuration) {
    if (configuration.issuer.length > 0) {
        return configuration.issuer;
    }

    NSString *host = configuration.serverHost;
    if (PDSAdminAuthHostLooksLocal(host)) {
        host = @"localhost";
    }
    NSString *scheme = PDSAdminAuthHostLooksLocal(host) ? @"http" : @"https";
    NSUInteger port = configuration.serverPort > 0 ? configuration.serverPort : 2583;
    BOOL defaultPort = ([scheme isEqualToString:@"https"] && port == 443) ||
                       ([scheme isEqualToString:@"http"] && port == 80);
    if (defaultPort) {
        return [NSString stringWithFormat:@"%@://%@", scheme, host];
    }
    return [NSString stringWithFormat:@"%@://%@:%lu", scheme, host, (unsigned long)port];
}

static NSString *PDSAdminAuthResolvedIssuer(NSDictionary *env, BOOL *requiredButMissing) {
    // First check environment directly
    NSString *issuer = [env[@"PDS_ISSUER"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (issuer.length > 0) {
        if (requiredButMissing) *requiredButMissing = NO;
        return issuer;
    }
    
    // Fall back to canonical issuer from PDSConfiguration.
    NSString *configIssuer = PDSAdminAuthCanonicalIssuerFromConfiguration([PDSConfiguration sharedConfiguration]);
    if (configIssuer.length > 0) {
        if (requiredButMissing) *requiredButMissing = NO;
        return configIssuer;
    }
    
    if (PDSAdminAuthIsIssuerRequired(env)) {
        if (requiredButMissing) *requiredButMissing = YES;
        return nil;
    }
    if (requiredButMissing) *requiredButMissing = NO;
    return @"http://localhost:8080";
}

static NSInteger PDSAdminAuthParsePositiveInteger(NSString *value) {
    if (value.length == 0) {
        return NSNotFound;
    }
    NSString *trimmed = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        return NSNotFound;
    }

    NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    if ([trimmed rangeOfCharacterFromSet:nonDigits].location != NSNotFound) {
        return NSNotFound;
    }

    unsigned long long parsed = strtoull(trimmed.UTF8String, NULL, 10);
    if (parsed == 0 || parsed > NSIntegerMax) {
        return NSNotFound;
    }
    return (NSInteger)parsed;
}

static NSTimeInterval PDSAdminAuthResolvedTokenTTL(NSDictionary *env) {
    NSInteger parsed = PDSAdminAuthParsePositiveInteger(env[@"PDS_ADMIN_TOKEN_TTL_SECONDS"]);
    if (parsed == NSNotFound) {
        return PDSAdminAuthDefaultTokenTTLSeconds;
    }
    if (parsed < (NSInteger)PDSAdminAuthMinTokenTTLSeconds) {
        return PDSAdminAuthMinTokenTTLSeconds;
    }
    if (parsed > (NSInteger)PDSAdminAuthMaxTokenTTLSeconds) {
        return PDSAdminAuthMaxTokenTTLSeconds;
    }
    return (NSTimeInterval)parsed;
}

static BOOL PDSAdminAuthIsXAdminTokenHeaderDisabled(NSDictionary *env) {
    return PDSAdminAuthEnvBool(env[@"PDS_DISABLE_X_ADMIN_TOKEN_HEADER"]);
}

static NSArray<NSString *> *PDSAdminAuthAllowedAlgorithmsForMinter(JWTMinter *minter) {
    if (!minter) {
        return nil;
    }

    NSMutableOrderedSet<NSString *> *algorithms = [NSMutableOrderedSet orderedSet];
    NSString *configuredAlgorithm = [[minter.signingAlgorithm stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];
    if (configuredAlgorithm.length > 0) {
        [algorithms addObject:configuredAlgorithm];
    }

    if (algorithms.count == 0 && minter.publicKey) {
        [algorithms addObject:@"ES256K"];
    }
    if (algorithms.count == 0 && minter.keyRotationManager) {
        [algorithms addObjectsFromArray:@[@"ES256", @"RS256"]];
    }

    return algorithms.count > 0 ? algorithms.array : nil;
}

@interface PDSAdminAuth ()
@property (nonatomic, strong, nullable) NSDate *minimumTokenIssuedAt;
@end

static NSString *PDSAdminAuthMinIATFilePath(NSString *dataDirectory) {
    if (dataDirectory.length == 0) return nil;
    return [dataDirectory stringByAppendingPathComponent:@".admin_min_iat"];
}

static void PDSAdminAuthPersistMinIAT(NSString *dataDirectory, NSDate *date) {
    NSString *path = PDSAdminAuthMinIATFilePath(dataDirectory);
    if (!path) return;
    NSString *value = [NSString stringWithFormat:@"%.6f", date.timeIntervalSince1970];
    [value writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

static NSDate *PDSAdminAuthLoadMinIAT(NSString *dataDirectory) {
    NSString *path = PDSAdminAuthMinIATFilePath(dataDirectory);
    if (!path) return nil;
    NSString *value = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (value.length == 0) return nil;
    NSTimeInterval ts = value.doubleValue;
    if (ts <= 0) return nil;
    return [NSDate dateWithTimeIntervalSince1970:ts];
}

@implementation PDSAdminAuth

+ (instancetype)sharedAuth {
    static PDSAdminAuth *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[PDSAdminAuth alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _adminToken = nil;
        _minimumTokenIssuedAt = nil;
    }
    return self;
}

- (void)setDataDirectory:(NSString *)dataDirectory {
    _dataDirectory = [dataDirectory copy];
    // Load persisted minimum token issued-at on first assignment
    NSDate *persisted = PDSAdminAuthLoadMinIAT(_dataDirectory);
    if (persisted) {
        _minimumTokenIssuedAt = persisted;
    }
}

- (BOOL)isAuthenticatedWithRequest:(NSObject *)request {
    if (![request isKindOfClass:[NSDictionary class]]) {
        return NO;
    }

    NSDictionary *headers = (NSDictionary *)request;

    NSDictionary *env = [[NSProcessInfo processInfo] environment];

    NSString *authorization = headers[@"Authorization"] ?: headers[@"authorization"];
    NSString *token = nil;
    if ([authorization isKindOfClass:[NSString class]] && [authorization hasPrefix:@"Bearer "]) {
        token = [authorization substringFromIndex:@"Bearer ".length];
    }

    if (token.length == 0 && !PDSAdminAuthIsXAdminTokenHeaderDisabled(env)) {
        NSString *adminTokenHeader = headers[@"X-Admin-Token"] ?: headers[@"x-admin-token"];
        if ([adminTokenHeader isKindOfClass:[NSString class]]) {
            token = adminTokenHeader;
        }
    }

    if (token.length == 0) {
        return NO;
    }

    NSError *parseError = nil;
    JWT *jwt = [JWT jwtWithToken:token error:&parseError];
    if (!jwt || parseError) {
        return NO;
    }

    NSString *issuerClaim = [jwt.payload.iss stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *audienceClaim = [jwt.payload.aud stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (issuerClaim.length == 0 || audienceClaim.length == 0) {
        return NO;
    }

    if (!PDSScopesContainAdmin(jwt.payload.scope)) {
        return NO;
    }

    PDSController *controller = self.controller ?: [PDSController sharedController];
    if (![controller isKindOfClass:[PDSController class]] || !controller.jwtMinter) {
        return NO;
    }

    JWTVerifier *verifier = [[JWTVerifier alloc] init];
    verifier.keyRotationManager = controller.jwtMinter.keyRotationManager;
    verifier.publicKey = controller.jwtMinter.publicKey;

    BOOL issuerRequiredButMissing = NO;
    NSString *expectedIssuer = PDSAdminAuthResolvedIssuer(env, &issuerRequiredButMissing);
    if (issuerRequiredButMissing || expectedIssuer.length == 0) {
        return NO;
    }
    verifier.expectedIssuer = expectedIssuer;
    verifier.expectedAudience = expectedIssuer;
    verifier.allowedAlgorithms = PDSAdminAuthAllowedAlgorithmsForMinter(controller.jwtMinter);

    NSError *verifyError = nil;
    if (![verifier verifyJWT:jwt error:&verifyError]) {
        return NO;
    }

    if (self.minimumTokenIssuedAt && jwt.payload.iat && [jwt.payload.iat compare:self.minimumTokenIssuedAt] == NSOrderedAscending) {
        return NO;
    }

    return YES;
}

- (NSString *)resolveAdminPassword {
    NSDictionary *env = [[NSProcessInfo processInfo] environment];

    // Check PDS_ADMIN_PASSWORD_FILE first (production: secret from file)
    NSString *passwordFile = env[@"PDS_ADMIN_PASSWORD_FILE"];
    if (passwordFile.length > 0) {
        NSError *readError = nil;
        NSString *content = [NSString stringWithContentsOfFile:passwordFile
                                                     encoding:NSUTF8StringEncoding
                                                        error:&readError];
        if (content) {
            // Trim whitespace/newlines (common with Docker secrets)
            return [content stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }
    }

    // Fall back to PDS_ADMIN_PASSWORD environment variable
    return env[@"PDS_ADMIN_PASSWORD"];
}

- (BOOL)verifyPassword:(NSString *)password against:(NSString *)expected {
    // If expected starts with "$2" it's a bcrypt hash — use PBKDF2 comparison
    // For now, support plain-text comparison with constant-time check,
    // and PBKDF2-SHA256 hashed passwords (prefix "pbkdf2:")
    if ([expected hasPrefix:@"pbkdf2:"]) {
        // Format: pbkdf2:<iterations>:<base64salt>:<base64hash>
        NSArray *parts = [expected componentsSeparatedByString:@":"];
        if (parts.count != 4) return NO;

        NSInteger iterations = [parts[1] integerValue];
        NSData *salt = [[NSData alloc] initWithBase64EncodedString:parts[2] options:0];
        NSData *expectedHash = [[NSData alloc] initWithBase64EncodedString:parts[3] options:0];

        if (!salt || !expectedHash || iterations < 1) return NO;

        NSData *passwordData = [password dataUsingEncoding:NSUTF8StringEncoding];
        NSMutableData *derivedKey = [NSMutableData dataWithLength:expectedHash.length];

        int result = CCKeyDerivationPBKDF(kCCPBKDF2,
                                          passwordData.bytes, passwordData.length,
                                          salt.bytes, salt.length,
                                          kCCPRFHmacAlgSHA256,
                                          (uint)iterations,
                                          derivedKey.mutableBytes, derivedKey.length);

        if (result != kCCSuccess) return NO;

        // Constant-time comparison
        if (derivedKey.length != expectedHash.length) return NO;
        const uint8_t *a = derivedKey.bytes;
        const uint8_t *b = expectedHash.bytes;
        uint8_t diff = 0;
        for (NSUInteger i = 0; i < derivedKey.length; i++) {
            diff |= (uint8_t)(a[i] ^ b[i]);
        }
        return diff == 0;
    }

    // Plain-text comparison (dev/testing only)
    return PDSConstantTimeEqualStrings(password, expected);
}

- (BOOL)authenticateWithPassword:(NSString *)password error:(NSError **)error {
    NSDictionary *env = [[NSProcessInfo processInfo] environment];

    NSString *expectedPassword = [self resolveAdminPassword];
    if (expectedPassword.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PDSAdminAuthErrorDomain
                                         code:503
                                     userInfo:@{NSLocalizedDescriptionKey: @"Admin password not configured (set PDS_ADMIN_PASSWORD or PDS_ADMIN_PASSWORD_FILE)"}];
        }
        return NO;
    }

    if (![self verifyPassword:password against:expectedPassword]) {
        if (error) {
            *error = [NSError errorWithDomain:PDSAdminAuthErrorDomain
                                         code:401
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid admin password"}];
        }
        return NO;
    }

    PDSController *controller = self.controller ?: [PDSController sharedController];
    if (![controller isKindOfClass:[PDSController class]] || !controller.jwtMinter) {
        if (error) {
            *error = [NSError errorWithDomain:PDSAdminAuthErrorDomain
                                         code:500
                                     userInfo:@{NSLocalizedDescriptionKey: @"Server not initialized"}];
        }
        return NO;
    }

    BOOL issuerRequiredButMissing = NO;
    NSString *expectedIssuer = PDSAdminAuthResolvedIssuer(env, &issuerRequiredButMissing);
    if (issuerRequiredButMissing || expectedIssuer.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PDSAdminAuthErrorDomain
                                         code:503
                                     userInfo:@{NSLocalizedDescriptionKey: @"PDS_ISSUER is required in production mode"}];
        }
        return NO;
    }
    NSURLComponents *issuerComponents = [NSURLComponents componentsWithString:expectedIssuer];
    NSString *issuerHost = issuerComponents.host ?: expectedIssuer;
    NSString *adminDID = [NSString stringWithFormat:@"did:web:%@", issuerHost];

    NSTimeInterval tokenTTLSeconds = PDSAdminAuthResolvedTokenTTL(env);
    NSDate *issuedAt = [NSDate date];
    NSDate *expiresAt = [issuedAt dateByAddingTimeInterval:tokenTTLSeconds];

    NSMutableDictionary *claims = [NSMutableDictionary dictionary];
    claims[@"sub"] = adminDID;
    claims[@"scope"] = @"admin";
    claims[@"iss"] = expectedIssuer;
    claims[@"aud"] = expectedIssuer;
    claims[@"exp"] = @([expiresAt timeIntervalSince1970]);
    claims[@"iat"] = @([issuedAt timeIntervalSince1970]);

    NSError *signError = nil;
    NSString *token = [controller.jwtMinter signPayload:claims error:&signError];
    if (token) {
        self.adminToken = token;
        return YES;
    }

    if (error) {
        *error = signError ?: [NSError errorWithDomain:PDSAdminAuthErrorDomain
                                                  code:500
                                              userInfo:@{NSLocalizedDescriptionKey: @"Failed to generate admin token"}];
    }
    return NO;
}

- (void)logout {
    self.adminToken = nil;
    NSDate *now = [NSDate date];
    self.minimumTokenIssuedAt = now;
    PDSAdminAuthPersistMinIAT(self.dataDirectory, now);
}

@end
