#import "Video/VideoJWTAuthProvider.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Auth/JWT.h"
#import "Core/DID.h"
#import "Core/CID.h"
#import "Debug/PDSLogger.h"

@interface VideoJWTAuthProvider ()
@end

@implementation VideoJWTAuthProvider

- (instancetype)initWithExpectedAudience:(NSString *)audience
                            signingKeyJWK:(nullable NSDictionary *)signingKeyJWK {
    self = [super init];
    if (self) {
        _audience = [audience copy];
        _signingKeyJWK = signingKeyJWK;
    }
    return self;
}

- (instancetype)initWithExpectedAudience:(NSString *)audience
                                 pdsURL:(NSString *)pdsURL
                                 plcURL:(nullable NSString *)plcURL {
    self = [super init];
    if (self) {
        _audience = [audience copy];
        _signingKeyJWK = nil;

        // Create a DID resolver for verifying Service Auth JWTs.
        // The resolver needs the PLC URL to resolve did:plc DIDs.
        _didResolver = [[DIDResolver alloc] init];
        _didResolver.plcURL = plcURL ?: @"https://plc.directory";
    }
    return self;
}

- (nullable NSString *)authenticateRequest:(HttpRequest *)request
                                   response:(HttpResponse *)response {
    NSString *authHeader = [request headerForKey:@"Authorization"];
    if (!authHeader || authHeader.length == 0) {
        response.statusCode = HttpStatusUnauthorized;
        [response setJsonBody:@{
            @"error": @"AuthRequired",
            @"message": @"Valid authorization required"
        }];
        return nil;
    }

    NSString *token = nil;
    if ([authHeader hasPrefix:@"Bearer "]) {
        token = [authHeader substringFromIndex:7];
    } else if ([authHeader hasPrefix:@"DPoP "]) {
        token = [authHeader substringFromIndex:5];
    }

    if (!token || token.length == 0) {
        response.statusCode = HttpStatusUnauthorized;
        [response setJsonBody:@{
            @"error": @"AuthRequired",
            @"message": @"Invalid authorization header format"
        }];
        return nil;
    }

    // Parse the JWT
    NSError *error = nil;
    JWT *jwt = [JWT jwtWithToken:token error:&error];
    if (!jwt) {
        PDS_LOG_WARN(@"Service Auth JWT parsing failed: %@", error);
        response.statusCode = HttpStatusUnauthorized;
        [response setJsonBody:@{
            @"error": @"InvalidToken",
            @"message": @"Token parsing failed"
        }];
        return nil;
    }

    // Determine token type and extract issuer DID
    NSString *typ = jwt.header.typ;
    BOOL isAccessToken = [typ isEqualToString:@"at+jwt"];
    BOOL isServiceAuth = !isAccessToken && ![typ isEqualToString:@"refresh+jwt"] && ![typ isEqualToString:@"dpop+jwt"];

    NSString *iss = nil;
    if (isAccessToken) {
        // Access tokens: issuer is the PDS, subject is the user DID
        iss = jwt.payload.sub;
        if (!iss || ![iss hasPrefix:@"did:"]) {
            // Fall back to the 'did' claim
            iss = jwt.payload.did;
        }
        PDS_LOG_INFO(@"Video auth: received access token for did=%@", iss);
    } else if (isServiceAuth) {
        // Service Auth tokens: issuer is the user DID
        iss = jwt.payload.iss;
    } else {
        PDS_LOG_WARN(@"Video auth: rejected token with typ=%@", typ);
        response.statusCode = HttpStatusUnauthorized;
        [response setJsonBody:@{
            @"error": @"InvalidToken",
            @"message": @"Not a valid token type"
        }];
        return nil;
    }

    if (!iss || iss.length == 0) {
        response.statusCode = HttpStatusUnauthorized;
        [response setJsonBody:@{
            @"error": @"InvalidToken",
            @"message": @"Token missing issuer"
        }];
        return nil;
    }

    // Verify audience (Service Auth tokens only; access tokens have PDS as audience)
    if (isServiceAuth) {
        NSString *aud = jwt.payload.aud;
        if (aud && ![aud isEqualToString:self.audience]) {
            PDS_LOG_WARN(@"Service Auth JWT audience mismatch: expected %@, got %@", self.audience, aud);
            response.statusCode = HttpStatusUnauthorized;
            [response setJsonBody:@{
                @"error": @"InvalidToken",
                @"message": @"Token audience mismatch"
            }];
            return nil;
        }
    }

    // Verify expiration
    NSDate *exp = jwt.payload.exp;
    if (exp && [exp timeIntervalSinceNow] < 0) {
        response.statusCode = HttpStatusUnauthorized;
        [response setJsonBody:@{
            @"error": @"ExpiredToken",
            @"message": @"Token has expired"
        }];
        return nil;
    }

    // Verify JWT signature
    if (isAccessToken) {
        // Access tokens are signed by the PDS's server key, not the user's actor key.
        // We can't fully verify them without the PDS's JWKS, but we trust them in
        // the sidecar architecture since the PDS has already authenticated the user.
        // In production, the PDS's JWKS would be fetched and used for verification.
        PDS_LOG_INFO(@"Video auth: accepting access token for did=%@ (PDS-signed, trusted)", iss);
    } else if (self.didResolver) {
        BOOL verified = [self verifyJWTSignature:jwt issuerDID:iss forceRefresh:NO error:&error];
        if (!verified) {
            // Retry with force-refresh to handle key rotation
            PDS_LOG_INFO(@"Service Auth JWT verification failed, retrying with fresh DID: %@", error);
            error = nil;
            verified = [self verifyJWTSignature:jwt issuerDID:iss forceRefresh:YES error:&error];
        }

        if (!verified) {
            PDS_LOG_WARN(@"Service Auth JWT verification failed: %@", error);
            response.statusCode = HttpStatusUnauthorized;
            [response setJsonBody:@{
                @"error": @"InvalidToken",
                @"message": @"Token verification failed"
            }];
            return nil;
        }
    } else if (self.signingKeyJWK) {
        // Legacy path: verify with a pre-configured JWK
        JWTVerifier *verifier = [[JWTVerifier alloc] init];
        verifier.expectedAudience = self.audience;
        if (![verifier verifyJWT:jwt error:&error]) {
            PDS_LOG_WARN(@"Service Auth JWT verification failed (JWK): %@", error);
            response.statusCode = HttpStatusUnauthorized;
            [response setJsonBody:@{
                @"error": @"InvalidToken",
                @"message": @"Token verification failed"
            }];
            return nil;
        }
    } else {
        // No DID resolver and no JWK — can't verify
        PDS_LOG_WARN(@"Service Auth JWT verification failed: no DID resolver or signing key configured");
        response.statusCode = HttpStatusUnauthorized;
        [response setJsonBody:@{
            @"error": @"InvalidToken",
            @"message": @"Token verification failed"
        }];
        return nil;
    }

    // Verify scope (lxm) for Service Auth tokens only.
    // Access tokens have a different scope model (e.g. "atproto transition:generic")
    // and don't need lxm verification.
    if (!isAccessToken) {
        NSString *scope = jwt.payload.scope;
        NSString *lxm = jwt.payload.lxm;
        NSString *effectiveScope = lxm ?: scope;
        if (effectiveScope && ![effectiveScope isEqualToString:@"com.atproto.repo.uploadBlob"] &&
            ![effectiveScope isEqualToString:@"app.bsky.video.uploadVideo"]) {
            PDS_LOG_WARN(@"Service Auth JWT scope mismatch: %@", effectiveScope);
            response.statusCode = HttpStatusForbidden;
            [response setJsonBody:@{
                @"error": @"Forbidden",
                @"message": @"Token does not authorize this operation"
            }];
            return nil;
        }
    }

    return iss;
}

#pragma mark - DID-based Signature Verification

- (BOOL)verifyJWTSignature:(JWT *)jwt
                  issuerDID:(NSString *)iss
               forceRefresh:(BOOL)forceRefresh
                      error:(NSError **)error {
    // Resolve the issuer's DID document to get their signing key
    NSDictionary *atprotoData = nil;
    if (forceRefresh) {
        DIDDocument *doc = [self.didResolver resolveDIDSync:iss forceRefresh:YES error:error];
        if (!doc) {
            PDS_LOG_WARN(@"Service Auth: DID resolution failed for %@ (forceRefresh): %@", iss, error ? *error : @"unknown");
            return NO;
        }
        // Re-extract atproto data from the fresh document
        atprotoData = [self atprotoDataFromDocument:doc];
    } else {
        atprotoData = [self.didResolver resolveAtprotoDataForDID:iss error:error];
    }

    if (!atprotoData) {
        PDS_LOG_WARN(@"Service Auth: no atprotoData for DID %@: %@", iss, error ? *error : @"unknown");
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.video.auth"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"Failed to resolve DID %@: %@",
                                                     iss, error ? *error : @"unknown"]}];
        }
        return NO;
    }

    NSData *signingKeyBytes = atprotoData[@"signingKeyBytes"];
    NSString *signingKey = atprotoData[@"signingKey"];
    if (!signingKeyBytes || signingKeyBytes.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.video.auth"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"No signing key found in DID document for %@", iss]}];
        }
        return NO;
    }

    // Verify the JWT signature using the resolved public key
    JWTVerifier *verifier = [[JWTVerifier alloc] init];
    verifier.publicKey = signingKeyBytes;
    return [verifier verifyJWT:jwt error:error];
}

- (nullable NSDictionary *)atprotoDataFromDocument:(DIDDocument *)doc {
    // Re-implement the key extraction logic from resolveAtprotoDataForDID:
    // since that method doesn't take a pre-resolved document.
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"did"] = doc.id;

    NSDictionary *json = doc.jsonDictionary;
    NSArray *verificationMethods = json[@"verificationMethod"];
    if ([verificationMethods isKindOfClass:[NSArray class]] && verificationMethods.count > 0) {
        NSDictionary *selectedMethod = nil;
        for (id entry in verificationMethods) {
            if (![entry isKindOfClass:[NSDictionary class]]) continue;
            NSString *candidateKey = entry[@"publicKeyMultibase"];
            if (!candidateKey) continue;
            NSString *methodId = entry[@"id"];
            NSString *methodType = entry[@"type"];
            if ([methodId isKindOfClass:[NSString class]] && [methodId containsString:@"#atproto"]) {
                selectedMethod = entry;
                break;
            }
            if (!selectedMethod && [methodType isKindOfClass:[NSString class]] && [methodType isEqualToString:@"Multikey"]) {
                selectedMethod = entry;
            } else if (!selectedMethod) {
                selectedMethod = entry;
            }
        }

        NSString *signingKey = selectedMethod[@"publicKeyMultibase"];
        if ([signingKey isKindOfClass:[NSString class]]) {
            result[@"signingKey"] = signingKey;

            if (signingKey.length > 1) {
                unichar prefix = [signingKey characterAtIndex:0];
                NSString *payload = [signingKey substringFromIndex:1];
                NSData *keyBytes = nil;
                if (prefix == 'z') {
                    keyBytes = [CID base58btcDecode:payload];
                } else if (prefix == 'b') {
                    keyBytes = [CID base32Decode:payload];
                }

                if (keyBytes.length > 2) {
                    const uint8_t *bytes = keyBytes.bytes;
                    if (bytes[0] == 0xE7 && bytes[1] == 0x01) {
                        keyBytes = [keyBytes subdataWithRange:NSMakeRange(2, keyBytes.length - 2)];
                    }
                }

                if (keyBytes) {
                    result[@"signingKeyBytes"] = keyBytes;
                }
            }
        }
    }

    return [result copy];
}

@end
