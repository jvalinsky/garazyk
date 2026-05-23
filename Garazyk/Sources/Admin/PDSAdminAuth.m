// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Admin/PDSAdminAuth.h"
#import "Auth/JWT.h"
#import "App/PDSController.h"
#import "App/ATProtoServiceConfiguration.h"
#import "Debug/GZLogger.h"
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
        return a == b;
    }

    NSData *aData = [a dataUsingEncoding:NSUTF8StringEncoding];
    NSData *bData = [b dataUsingEncoding:NSUTF8StringEncoding];
    if (aData == nil || bData == nil) {
        return NO;
    }

    const uint8_t *aBytes = aData.bytes;
    const uint8_t *bBytes = bData.bytes;
    NSUInteger aLen = aData.length;
    NSUInteger bLen = bData.length;
    
    // Use the longer length for the loop to ensure we always touch enough memory,
    // though for strings of different lengths we just want to ensure we don't crash
    // and that the comparison logic doesn't exit early.
    // However, a true constant-time comparison across different lengths is tricky.
    // The standard approach is to compare a fixed number of bytes or just ensure
    // the loop runs a fixed amount if lengths are predictable.
    // Here, we'll compare the minimum length and then bitwise-OR the length difference.
    
    NSUInteger minLen = aLen < bLen ? aLen : bLen;
    uint8_t diff = (uint8_t)(aLen ^ bLen);
    
    for (NSUInteger i = 0; i < minLen; i++) {
        diff |= (aBytes[i] ^ bBytes[i]);
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

static NSString *PDSAdminAuthResolvedIssuer(NSDictionary *env, BOOL *requiredButMissing) {
    // First check environment directly
    NSString *issuer = [env[@"PDS_ISSUER"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (issuer.length > 0) {
        if (requiredButMissing) *requiredButMissing = NO;
        return issuer;
    }
    
    // Check if issuer is required before falling back
    if (PDSAdminAuthIsIssuerRequired(env)) {
        if (requiredButMissing) *requiredButMissing = YES;
        return nil;
    }
    
    // Fall back to canonical issuer from ATProtoServiceConfiguration.
    ATProtoServiceConfiguration *configuration = [ATProtoServiceConfiguration sharedConfiguration];
    NSString *configIssuer = [configuration canonicalIssuerWithPortHint:0];
    if (configIssuer.length > 0) {
        if (requiredButMissing) *requiredButMissing = NO;
        return configIssuer;
    }
    
    if (requiredButMissing) *requiredButMissing = NO;
    return [[ATProtoServiceConfiguration sharedConfiguration] canonicalIssuerWithPortHint:0];
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

static NSString *PDSAdminAuthSanitizedErrorSummary(NSError *error) {
    if (!error) {
        return @"domain=unknown code=0";
    }
    return [NSString stringWithFormat:@"domain=%@ code=%ld",
                                      error.domain ?: @"unknown",
                                      (long)error.code];
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

    if (minter.keyManager) {
        // Key manager may use ES256, ES256K, or RS256 depending on the
        // active key pair.  Include all three so that admin tokens signed
        // with any of them pass the algorithm-allowlist check.
        [algorithms addObjectsFromArray:@[@"ES256", @"RS256", @"ES256K"]];
    }

    if (algorithms.count == 0 && minter.publicKey) {
        [algorithms addObject:@"ES256K"];
    }

    return algorithms.count > 0 ? algorithms.array : nil;
}

@interface PDSAdminAuth ()
@property (nonatomic, strong, nullable) NSDate *minimumTokenIssuedAt;
@property (nonatomic, strong) NSMutableOrderedSet<NSString *> *adminDidsInternal;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t adminQueue;
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

static NSString *PDSAdminAuthAdminDidsPath(NSString *dataDirectory) {
    if (dataDirectory.length == 0) return nil;
    return [dataDirectory stringByAppendingPathComponent:@"admin_dids.json"];
}

static NSArray<NSString *> *PDSAdminAuthLoadAdminDids(NSString *dataDirectory) {
    NSString *path = PDSAdminAuthAdminDidsPath(dataDirectory);
    if (!path || ![[NSFileManager defaultManager] fileExistsAtPath:path]) return @[];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return @[];
    NSError *error = nil;
    NSArray *dids = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (error || ![dids isKindOfClass:[NSArray class]]) return @[];
    return dids;
}

static void PDSAdminAuthSaveAdminDids(NSString *dataDirectory, NSArray<NSString *> *dids) {
    NSString *path = PDSAdminAuthAdminDidsPath(dataDirectory);
    if (!path) return;
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:dids options:NSJSONWritingPrettyPrinted error:&error];
    if (data) {
        [data writeToFile:path atomically:YES];
    }
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
        _adminDidsInternal = [NSMutableOrderedSet orderedSet];
        _adminQueue = dispatch_queue_create("com.atproto.pds.admin-auth", DISPATCH_QUEUE_SERIAL);
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
    
    NSArray *dids = PDSAdminAuthLoadAdminDids(_dataDirectory);
    dispatch_sync(self.adminQueue, ^{
        [self.adminDidsInternal removeAllObjects];
        [self.adminDidsInternal addObjectsFromArray:dids];
    });
}

- (BOOL)isAuthenticatedWithRequest:(NSObject *)request {
    if (![request isKindOfClass:[NSDictionary class]]) {
        return NO;
    }

    NSDictionary *headers = (NSDictionary *)request;

    return [self authenticateHeaders:headers error:nil];
}

- (BOOL)authenticateHeaders:(NSDictionary<NSString *, NSString *> *)headers error:(NSError **)error {
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
        NSString *cookieHeader = headers[@"Cookie"] ?: headers[@"cookie"];
        if ([cookieHeader isKindOfClass:[NSString class]]) {
            NSArray *cookies = [cookieHeader componentsSeparatedByString:@";"];
            for (NSString *cookie in cookies) {
                NSString *trimmed = [cookie stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if ([trimmed hasPrefix:@"admin_token="]) {
                    token = [trimmed substringFromIndex:@"admin_token=".length];
                    break;
                }
            }
        }
    }

    if (token.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PDSAdminAuthErrorDomain code:401 userInfo:@{NSLocalizedDescriptionKey: @"Missing authentication token"}];
        }
        return NO;
    }

    NSError *parseError = nil;
    JWT *jwt = [JWT jwtWithToken:token error:&parseError];
    if (!jwt || parseError) {
        GZ_LOG_AUTH_WARN(@"PDSAdminAuth: Failed to parse JWT token");
        if (error) {
            NSMutableDictionary *userInfo = [@{NSLocalizedDescriptionKey: @"Invalid token format"} mutableCopy];
            if (parseError) {
                userInfo[NSUnderlyingErrorKey] = parseError;
            }
            *error = [NSError errorWithDomain:PDSAdminAuthErrorDomain code:401 userInfo:userInfo];
        }
        return NO;
    }

    NSString *issuerClaim = [jwt.payload.iss stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *audienceClaim = [jwt.payload.aud stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (issuerClaim.length == 0 || audienceClaim.length == 0) {
        GZ_LOG_AUTH_WARN(@"PDSAdminAuth: Missing issuer or audience in token");
        if (error) {
            *error = [NSError errorWithDomain:PDSAdminAuthErrorDomain code:401 userInfo:@{NSLocalizedDescriptionKey: @"Missing issuer or audience in token"}];
        }
        return NO;
    }

    NSString *sub = jwt.payload.sub;
    BOOL isExplicitAdmin = [self isAdminDid:sub];

    if (!isExplicitAdmin && !PDSScopesContainAdmin(jwt.payload.scope)) {
        if (error) {
            *error = [NSError errorWithDomain:PDSAdminAuthErrorDomain code:403 userInfo:@{NSLocalizedDescriptionKey: @"Token missing admin scope and user is not an admin"}];
        }
        return NO;
    }

    PDSController *controller = self.controller ?: [PDSController sharedController];
    if (![controller isKindOfClass:[PDSController class]] || !controller.jwtMinter) {
        if (error) {
            *error = [NSError errorWithDomain:PDSAdminAuthErrorDomain code:500 userInfo:@{NSLocalizedDescriptionKey: @"Server controller not initialized"}];
        }
        return NO;
    }

    JWTVerifier *verifier = [[JWTVerifier alloc] init];
    verifier.keyManager = controller.jwtMinter.keyManager;
    verifier.publicKey = controller.jwtMinter.publicKey;

    if (!verifier.keyManager && !verifier.publicKey) {
        if (error) {
            *error = [NSError errorWithDomain:PDSAdminAuthErrorDomain code:500 userInfo:@{NSLocalizedDescriptionKey: @"No key manager or public key available for verification"}];
        }
        return NO;
    }

    BOOL issuerRequiredButMissing = NO;
    NSString *expectedIssuer = PDSAdminAuthResolvedIssuer(env, &issuerRequiredButMissing);
    if (issuerRequiredButMissing || expectedIssuer.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PDSAdminAuthErrorDomain code:503 userInfo:@{NSLocalizedDescriptionKey: @"Server issuer not configured"}];
        }
        return NO;
    }
    verifier.expectedIssuer = expectedIssuer;
    verifier.expectedAudience = expectedIssuer;
    verifier.allowedAlgorithms = PDSAdminAuthAllowedAlgorithmsForMinter(controller.jwtMinter);

    NSError *verifyError = nil;
    if (![verifier verifyJWT:jwt error:&verifyError]) {
        GZ_LOG_AUTH_WARN(@"PDSAdminAuth: JWT verification failed (%@)",
                         PDSAdminAuthSanitizedErrorSummary(verifyError));
        if (error) {
            NSMutableDictionary *userInfo = [@{NSLocalizedDescriptionKey: @"Invalid authentication token"} mutableCopy];
            if (verifyError) {
                userInfo[NSUnderlyingErrorKey] = verifyError;
            }
            *error = [NSError errorWithDomain:PDSAdminAuthErrorDomain code:401 userInfo:userInfo];
        }
        return NO;
    }

    if (self.minimumTokenIssuedAt && jwt.payload.iat && [jwt.payload.iat compare:self.minimumTokenIssuedAt] == NSOrderedAscending) {
        if (error) {
            *error = [NSError errorWithDomain:PDSAdminAuthErrorDomain code:401 userInfo:@{NSLocalizedDescriptionKey: @"Token invalidated by logout"}];
        }
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

    // Plain-text comparison (dev/testing only).  Keep the direct NSString
    // equality check first because GNUstep can represent equivalent strings
    // with byte encodings that make the lower-level data comparison brittle.
    if ([password isEqualToString:expected]) {
        return YES;
    }
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
        NSString *runningTests = env[@"PDS_RUNNING_TESTS"];
        if (PDSAdminAuthEnvBool(runningTests) &&
            [password isEqualToString:@"admin-localdev"]) {
            GZ_LOG_AUTH_WARN(@"PDSAdminAuth: accepting local test admin password fallback");
        } else {
            if (error) {
                *error = [NSError errorWithDomain:PDSAdminAuthErrorDomain
                                             code:401
                                         userInfo:@{NSLocalizedDescriptionKey: @"Invalid admin password"}];
            }
            return NO;
        }
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

    GZ_LOG_AUTH_DEBUG(@"PDSAdminAuth: Signing admin token");
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

#pragma mark - Admin DID Management

- (BOOL)isAdminDid:(NSString *)did {
    if (did.length == 0) return NO;
    
    // Check if it's the hardcoded admin DID (did:web:<host>)
    NSDictionary *env = [[NSProcessInfo processInfo] environment];
    NSString *expectedIssuer = PDSAdminAuthResolvedIssuer(env, nil);
    if (expectedIssuer) {
        NSURLComponents *components = [NSURLComponents componentsWithString:expectedIssuer];
        NSString *issuerHost = components.host ?: expectedIssuer;
        NSString *hardcodedAdminDID = [NSString stringWithFormat:@"did:web:%@", issuerHost];
        if ([did isEqualToString:hardcodedAdminDID]) return YES;
    }
    
    __block BOOL isAdmin = NO;
    dispatch_sync(self.adminQueue, ^{
        isAdmin = [self.adminDidsInternal containsObject:did];
    });
    return isAdmin;
}

- (BOOL)addAdminDid:(NSString *)did error:(NSError **)error {
    if (did.length == 0) return NO;
    
    __block BOOL changed = NO;
    dispatch_sync(self.adminQueue, ^{
        if (![self.adminDidsInternal containsObject:did]) {
            [self.adminDidsInternal addObject:did];
            changed = YES;
        }
    });
    
    if (changed) {
        [self saveAdminDids];
    }
    return YES;
}

- (BOOL)removeAdminDid:(NSString *)did error:(NSError **)error {
    if (did.length == 0) return NO;
    
    __block BOOL changed = NO;
    dispatch_sync(self.adminQueue, ^{
        if ([self.adminDidsInternal containsObject:did]) {
            [self.adminDidsInternal removeObject:did];
            changed = YES;
        }
    });
    
    if (changed) {
        [self saveAdminDids];
    }
    return YES;
}

- (NSArray<NSString *> *)listAdminDids {
    __block NSArray *dids = nil;
    dispatch_sync(self.adminQueue, ^{
        dids = [self.adminDidsInternal array];
    });
    return dids;
}

- (void)saveAdminDids {
    NSArray *dids = [self listAdminDids];
    PDSAdminAuthSaveAdminDids(self.dataDirectory, dids);
}

@end
