#import "Admin/PDSAdminAuth.h"
#import "Auth/JWT.h"
#import "App/PDSController.h"
#import <CommonCrypto/CommonKeyDerivation.h>

#ifndef kCCSuccess
#define kCCSuccess 0
#endif

static NSString *const PDSAdminAuthErrorDomain = @"PDSAdminAuth";

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

@interface PDSAdminAuth ()
@property (nonatomic, strong, nullable) NSDate *minimumTokenIssuedAt;
@end

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

- (BOOL)isAuthenticatedWithRequest:(NSObject *)request {
    if (![request isKindOfClass:[NSDictionary class]]) {
        return NO;
    }

    NSDictionary *headers = (NSDictionary *)request;

    NSString *authorization = headers[@"Authorization"] ?: headers[@"authorization"];
    NSString *token = nil;
    if ([authorization isKindOfClass:[NSString class]] && [authorization hasPrefix:@"Bearer "]) {
        token = [authorization substringFromIndex:@"Bearer ".length];
    }

    if (token.length == 0) {
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

    if (!PDSScopesContainAdmin(jwt.payload.scope)) {
        return NO;
    }

    PDSController *controller = [PDSController sharedController];
    if (!controller || !controller.jwtMinter) {
        return NO;
    }

    JWTVerifier *verifier = [[JWTVerifier alloc] init];
    verifier.keyRotationManager = controller.jwtMinter.keyRotationManager;
    verifier.publicKey = controller.jwtMinter.publicKey;

    NSString *expectedIssuer = [[NSProcessInfo processInfo] environment][@"PDS_ISSUER"] ?: @"https://pds.local:8443";
    verifier.expectedIssuer = expectedIssuer;
    verifier.expectedAudience = expectedIssuer;
    NSMutableArray<NSString *> *allowedAlgorithms = [NSMutableArray array];
    if (verifier.publicKey) {
        [allowedAlgorithms addObject:@"ES256K"];
    }
    if (verifier.keyRotationManager) {
        [allowedAlgorithms addObjectsFromArray:@[@"ES256", @"RS256"]];
    }
    verifier.allowedAlgorithms = allowedAlgorithms.count > 0 ? allowedAlgorithms : nil;

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

    PDSController *controller = [PDSController sharedController];
    if (!controller || !controller.jwtMinter) {
        if (error) {
            *error = [NSError errorWithDomain:PDSAdminAuthErrorDomain
                                         code:500
                                     userInfo:@{NSLocalizedDescriptionKey: @"Server not initialized"}];
        }
        return NO;
    }

    NSString *expectedIssuer = [[NSProcessInfo processInfo] environment][@"PDS_ISSUER"] ?: @"https://pds.local:8443";
    NSURLComponents *issuerComponents = [NSURLComponents componentsWithString:expectedIssuer];
    NSString *issuerHost = issuerComponents.host ?: expectedIssuer;
    NSString *adminDID = [NSString stringWithFormat:@"did:web:%@", issuerHost];

    NSMutableDictionary *claims = [NSMutableDictionary dictionary];
    claims[@"sub"] = adminDID;
    claims[@"scope"] = @"admin";
    claims[@"iss"] = expectedIssuer;
    claims[@"aud"] = expectedIssuer;
    claims[@"exp"] = @([[NSDate dateWithTimeIntervalSinceNow:3600] timeIntervalSince1970]);
    claims[@"iat"] = @([[NSDate date] timeIntervalSince1970]);

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
    self.minimumTokenIssuedAt = [NSDate date];
}

@end
