#import "Network/PDSSafeHTTPClient.h"
#import "ChatAuthManager.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Auth/JWT.h"
#import "Debug/PDSLogger.h"
#import "Compat/PDSTypes.h"

@interface ChatAuthManager ()
@property (nonatomic, strong, nullable) JWTVerifier *verifier;
@property (nonatomic, strong, nullable) NSData *cachedPublicKey;
@property (nonatomic, copy, nullable) NSString *cachedPdsUrl;
@property (nonatomic, assign) NSTimeInterval lastKeyFetchTime;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t keyCacheQueue;
@end

static const NSTimeInterval kKeyRefreshInterval = 3600.0; // Re-fetch JWKS every hour

@implementation ChatAuthManager

+ (instancetype)sharedManager {
    static ChatAuthManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[ChatAuthManager alloc] init];
        shared->_keyCacheQueue = dispatch_queue_create("com.atproto.chat.auth.keycache", DISPATCH_QUEUE_SERIAL);
    });
    return shared;
}

#pragma mark - JWKS Public Key Fetching

- (nullable NSDictionary *)fetchJWKSDictionaryFromURLString:(NSString *)jwksURL {
    NSURL *endpointURL = [NSURL URLWithString:jwksURL];
    if (!endpointURL) {
        return nil;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:endpointURL
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:10.0];

    __block NSData *data = nil;
    __block NSError *fetchError = nil;
    __block NSInteger statusCode = 0;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    [[PDSSafeHTTPClient sharedClient] performSafeDataTaskWithRequest:request options:[PDSSafeHTTPClientOptions defaultOptions] completion:
        completionHandler:^(NSData *_Nullable d, NSURLResponse *_Nullable r, NSError *_Nullable e) {
            data = d;
            fetchError = e;
            if ([r isKindOfClass:[NSHTTPURLResponse class]]) {
                statusCode = [(NSHTTPURLResponse *)r statusCode];
            }
            dispatch_semaphore_signal(semaphore);
        }];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

    if (!data || (statusCode != 0 && (statusCode < 200 || statusCode >= 300))) {
        PDS_LOG_ERROR(@"ChatAuthManager: failed to fetch JWKS from %@: status=%ld error=%@",
                      jwksURL, (long)statusCode, fetchError);
        return nil;
    }

    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![json isKindOfClass:[NSDictionary class]]) {
        PDS_LOG_ERROR(@"ChatAuthManager: JWKS from %@ was not a JSON object", jwksURL);
        return nil;
    }

    return json;
}

- (nullable NSDictionary *)firstJWKFromJWKSObject:(NSDictionary *)jwks {
    NSArray *keys = jwks[@"keys"];
    if ([keys isKindOfClass:[NSArray class]] && keys.count > 0) {
        NSDictionary *firstKey = keys[0];
        return [firstKey isKindOfClass:[NSDictionary class]] ? firstKey : nil;
    }

    return [jwks[@"kty"] isKindOfClass:[NSString class]] ? jwks : nil;
}

- (nullable NSData *)fetchPublicKeyFromPDS {
    NSString *url = self.pdsUrl;
    if (url.length == 0) {
        return nil;
    }

    // Check cache under queue protection
    __block NSData *cachedKey = nil;
    __block BOOL cacheHit = NO;
    dispatch_sync(self.keyCacheQueue, ^{
        if (self.cachedPublicKey && [url isEqualToString:self.cachedPdsUrl]
            && ([[NSDate date] timeIntervalSince1970] - self.lastKeyFetchTime) < kKeyRefreshInterval) {
            cachedKey = self.cachedPublicKey;
            cacheHit = YES;
        }
    });
    if (cacheHit) {
        return cachedKey;
    }

    NSArray<NSString *> *jwksURLs = @[
        [url stringByAppendingPathComponent:@"oauth/jwks"],
        [url stringByAppendingPathComponent:@".well-known/jwks.json"],
    ];

    NSDictionary *jwk = nil;
    for (NSString *jwksURL in jwksURLs) {
        NSDictionary *jwks = [self fetchJWKSDictionaryFromURLString:jwksURL];
        jwk = jwks ? [self firstJWKFromJWKSObject:jwks] : nil;
        if (jwk) {
            break;
        }
    }

    if (!jwk) {
        return cachedKey;
    }

    NSData *publicKey = [self publicKeyFromJWK:jwk];
    if (publicKey) {
        dispatch_sync(self.keyCacheQueue, ^{
            self.cachedPublicKey = publicKey;
            self.cachedPdsUrl = url;
            self.lastKeyFetchTime = [[NSDate date] timeIntervalSince1970];
        });
        PDS_LOG_INFO(@"ChatAuthManager: fetched public key from PDS JWKS");
    }
    return publicKey ?: cachedKey;
}

- (nullable NSData *)publicKeyFromJWK:(NSDictionary *)jwk {
    // Validate JWK type and curve
    NSString *kty = jwk[@"kty"];
    NSString *crv = jwk[@"crv"];
    if (![kty isEqualToString:@"EC"]) {
        PDS_LOG_ERROR(@"ChatAuthManager: JWK kty is not EC: %@", kty);
        return nil;
    }
    if (![crv isEqualToString:@"P-256"] && ![crv isEqualToString:@"secp256k1"]) {
        PDS_LOG_ERROR(@"ChatAuthManager: JWK crv not supported: %@ (expected P-256 or secp256k1)", crv);
        return nil;
    }

    // Extract x and y coordinates for EC public key
    NSString *x = jwk[@"x"];
    NSString *y = jwk[@"y"];
    if (!x || !y) {
        return nil;
    }

    // Decode base64url-encoded x and y coordinates
    NSData *xData = [[NSData alloc] initWithBase64EncodedString:[self base64URLToBase64:x] options:0];
    NSData *yData = [[NSData alloc] initWithBase64EncodedString:[self base64URLToBase64:y] options:0];
    if (!xData || !yData) {
        return nil;
    }

    // Construct uncompressed EC public key: 0x04 || x || y
    NSMutableData *keyData = [NSMutableData dataWithBytes:"\x04" length:1];
    [keyData appendData:xData];
    [keyData appendData:yData];
    return [keyData copy];
}

- (NSString *)base64URLToBase64:(NSString *)base64URL {
    NSString *s = [base64URL stringByReplacingOccurrencesOfString:@"-" withString:@"+"];
    s = [s stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    // Pad with = to make length a multiple of 4
    NSUInteger padding = (4 - (s.length % 4)) % 4;
    for (NSUInteger i = 0; i < padding; i++) {
        s = [s stringByAppendingString:@"="];
    }
    return s;
}

#pragma mark - Authentication

- (nullable NSString *)authenticateRequest:(HttpRequest *)request
                                  response:(nullable HttpResponse *)response {
    NSString *authHeader = [request headerForKey:@"Authorization"];
    if (!authHeader) {
        if (response) {
            response.statusCode = 401;
            [response setJsonBody:@{@"error": @"AuthenticationRequired", @"message": @"Authorization header missing"}];
        }
        return nil;
    }

    NSString *token = nil;
    if ([authHeader hasPrefix:@"Bearer "]) {
        token = [authHeader substringFromIndex:7];
    } else if ([authHeader hasPrefix:@"DPoP "]) {
        token = [authHeader substringFromIndex:5];
    } else {
        if (response) {
            response.statusCode = 401;
            [response setJsonBody:@{@"error": @"InvalidAuthentication", @"message": @"Invalid Authorization header format"}];
        }
        return nil;
    }

    NSError *error = nil;
    JWT *jwt = [JWT jwtWithToken:token error:&error];
    if (!jwt) {
        if (response) {
            response.statusCode = 401;
            [response setJsonBody:@{@"error": @"InvalidToken", @"message": @"Malformed JWT"}];
        }
        return nil;
    }

    NSString *did = jwt.payload.sub;
    if (!did) {
        if (response) {
            response.statusCode = 401;
            [response setJsonBody:@{@"error": @"InvalidToken", @"message": @"JWT subject missing"}];
        }
        return nil;
    }

    // Check expiration
    if (jwt.payload.exp && [jwt.payload.exp timeIntervalSinceNow] < 0) {
        if (response) {
            response.statusCode = 401;
            [response setJsonBody:@{@"error": @"ExpiredToken", @"message": @"JWT expired"}];
        }
        return nil;
    }

    // Verify JWT signature if PDS URL is configured
    NSData *publicKey = [self fetchPublicKeyFromPDS];
    if (publicKey) {
        JWTVerifier *verifier = [[JWTVerifier alloc] init];
        verifier.publicKey = publicKey;
        verifier.allowedAlgorithms = @[@"ES256", @"ES256K"];

        NSError *verifyError = nil;
        if (![verifier verifyJWT:jwt error:&verifyError]) {
            PDS_LOG_ERROR(@"ChatAuthManager: JWT signature verification failed: %@", verifyError.localizedDescription);
            if (response) {
                response.statusCode = 401;
                [response setJsonBody:@{@"error": @"InvalidToken", @"message": @"JWT signature verification failed"}];
            }
            return nil;
        }
    } else if (self.pdsUrl.length > 0) {
        // PDS URL is configured but we couldn't fetch the key — reject
        PDS_LOG_ERROR(@"ChatAuthManager: PDS URL configured but failed to fetch public key");
        if (response) {
            response.statusCode = 503;
            [response setJsonBody:@{@"error": @"KeyUnavailable", @"message": @"Cannot verify token: PDS public key unavailable"}];
        }
        return nil;
    }
    // If no pdsUrl is configured, we trust the PDS proxy (legacy behavior for proxied-only deployments)

    return did;
}

@end
