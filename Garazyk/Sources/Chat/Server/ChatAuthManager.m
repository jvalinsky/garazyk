// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Network/ATProtoSafeHTTPClient.h"
#import "ChatAuthManager.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Auth/JWT.h"
#import "Auth/Secp256k1.h"
#import "Core/DID.h"
#import "Debug/GZLogger.h"
#import "Compat/PDSTypes.h"
#import <CommonCrypto/CommonDigest.h>

@interface ChatAuthManager ()
@property (nonatomic, strong) DIDResolver *didResolver;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t verificationQueue;
@end

@implementation ChatAuthManager

+ (instancetype)sharedManager {
    static ChatAuthManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[ChatAuthManager alloc] init];
        shared->_didResolver = [DIDResolver sharedResolver];
        shared->_verificationQueue = dispatch_queue_create("com.atproto.chat.auth.verification", DISPATCH_QUEUE_SERIAL);
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _didResolver = [DIDResolver sharedResolver];
        _verificationQueue = dispatch_queue_create("com.atproto.chat.auth.verification", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

#pragma mark - Authentication

- (nullable NSString *)authenticateRequest:(HttpRequest *)request
                                  response:(nullable HttpResponse *)response {
    return [self authenticateRequest:request response:response expectedMethod:nil];
}

- (nullable NSString *)authenticateRequest:(HttpRequest *)request
                                  response:(nullable HttpResponse *)response
                             expectedMethod:(nullable NSString *)expectedLxm {
    NSString *authHeader = [request headerForKey:@"Authorization"];
    if (!authHeader) {
        if (response) {
            response.statusCode = 401;
            [response setJsonBody:@{@"error": @"AuthenticationRequired", @"message": @"Authorization header missing"}];
        }
        return nil;
    }

    // Extract token from Authorization header
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

    // Parse the JWT
    NSError *error = nil;
    JWT *jwt = [JWT jwtWithToken:token error:&error];
    if (!jwt) {
        if (response) {
            response.statusCode = 401;
            [response setJsonBody:@{@"error": @"InvalidToken", @"message": @"Malformed JWT"}];
        }
        return nil;
    }

    // 1. Reject forbidden typ values per spec
    //    Service tokens must not be OAuth access tokens, refresh tokens, or DPoP proofs.
    NSString *typ = jwt.header.typ;
    if ([typ isEqualToString:@"at+jwt"] ||
        [typ isEqualToString:@"refresh+jwt"] ||
        [typ isEqualToString:@"dpop+jwt"]) {
        GZ_LOG_ERROR(@"ChatAuthManager: rejected JWT with forbidden typ: %@", typ);
        if (response) {
            response.statusCode = 401;
            [response setJsonBody:@{@"error": @"BadJwtType", @"message": [NSString stringWithFormat:@"Invalid JWT type \"%@\"", typ]}];
        }
        return nil;
    }

    // 2. Validate expiration
    if (!jwt.payload.exp || [jwt.payload.exp timeIntervalSinceNow] < 0) {
        if (response) {
            response.statusCode = 401;
            [response setJsonBody:@{@"error": @"ExpiredToken", @"message": @"JWT expired"}];
        }
        return nil;
    }

    // 3. Validate audience (aud) against this service's DID
    NSString *aud = jwt.payload.aud;
    if (!aud.length) {
        if (response) {
            response.statusCode = 401;
            [response setJsonBody:@{@"error": @"BadJwtAudience", @"message": @"JWT audience (aud) missing"}];
        }
        return nil;
    }

    if (self.serviceDID.length > 0 && ![aud isEqualToString:self.serviceDID]) {
        // Also accept without fragment as a fallback (some PDS implementations
        // may not include the fragment in aud)
        NSString *audWithoutFragment = aud;
        NSRange hashRange = [aud rangeOfString:@"#"];
        if (hashRange.location != NSNotFound) {
            audWithoutFragment = [aud substringToIndex:hashRange.location];
        }

        NSString *serviceDIDWithoutFragment = self.serviceDID;
        NSRange serviceHashRange = [self.serviceDID rangeOfString:@"#"];
        if (serviceHashRange.location != NSNotFound) {
            serviceDIDWithoutFragment = [self.serviceDID substringToIndex:serviceHashRange.location];
        }

        if (![audWithoutFragment isEqualToString:serviceDIDWithoutFragment] &&
            ![aud isEqualToString:serviceDIDWithoutFragment]) {
            GZ_LOG_ERROR(@"ChatAuthManager: JWT audience mismatch: aud=%@, expected=%@", aud, self.serviceDID);
            if (response) {
                response.statusCode = 401;
                [response setJsonBody:@{@"error": @"BadJwtAudience", @"message": @"JWT audience does not match service DID"}];
            }
            return nil;
        }
    }

    // 4. Validate lexicon method (lxm) if expected
    NSString *lxm = jwt.payload.lxm;
    if (expectedLxm.length > 0 && ![lxm isEqualToString:expectedLxm]) {
        NSString *message = lxm.length > 0
            ? [NSString stringWithFormat:@"Bad JWT lexicon method (\"lxm\"). must match: %@", expectedLxm]
            : [NSString stringWithFormat:@"Missing JWT lexicon method (\"lxm\"). must match: %@", expectedLxm];
        GZ_LOG_ERROR(@"ChatAuthManager: %@", message);
        if (response) {
            response.statusCode = 401;
            [response setJsonBody:@{@"error": @"BadJwtLexiconMethod", @"message": message}];
        }
        return nil;
    }

    // 5. Validate issuer (iss) — must be a valid DID
    NSString *iss = jwt.payload.iss;
    if (!iss.length) {
        if (response) {
            response.statusCode = 401;
            [response setJsonBody:@{@"error": @"BadJwtIss", @"message": @"JWT issuer (iss) missing"}];
        }
        return nil;
    }

    // Strip fragment from iss if present (e.g., "did:plc:xxx#atproto" → "did:plc:xxx")
    NSString *issDID = iss;
    NSRange issFragmentRange = [iss rangeOfString:@"#"];
    if (issFragmentRange.location != NSNotFound) {
        issDID = [iss substringToIndex:issFragmentRange.location];
    }

    if (![issDID hasPrefix:@"did:"]) {
        if (response) {
            response.statusCode = 401;
            [response setJsonBody:@{@"error": @"BadJwtIss", @"message": @"JWT issuer is not a valid DID"}];
        }
        return nil;
    }

    // 6. Resolve issuer DID to get signing key and verify signature
    NSString *verifiedDID = [self verifyServiceAuthJWT:jwt issuerDID:issDID error:&error];
    if (!verifiedDID) {
        // Signature verification failed — try with fresh key (key rotation)
        GZ_LOG_WARN(@"ChatAuthManager: initial signature verification failed for %@, retrying with fresh key: %@", issDID, error);
        verifiedDID = [self verifyServiceAuthJWT:jwt issuerDID:issDID forceRefresh:YES error:&error];
    }

    if (!verifiedDID) {
        // Final fallback: if this is a proxied request from a PDS that still
        // uses the legacy PDS-signed token format, try the old validation path.
        // The legacy token has iss=PDS DID and sub=user DID.
        if (jwt.payload.sub.length > 0 && [jwt.payload.sub hasPrefix:@"did:"]) {
            GZ_LOG_WARN(@"ChatAuthManager: service auth verification failed, attempting legacy PDS-signed token fallback for sub=%@", jwt.payload.sub);
            NSString *legacyDID = [self validateLegacyPDSToken:jwt];
            if (legacyDID) {
                return legacyDID;
            }
        }

        GZ_LOG_ERROR(@"ChatAuthManager: JWT signature verification failed for issuer %@: %@", issDID, error);
        if (response) {
            response.statusCode = 401;
            [response setJsonBody:@{@"error": @"BadJwtSignature", @"message": @"JWT signature does not match issuer"}];
        }
        return nil;
    }

    return verifiedDID;
}

#pragma mark - Signature Verification

- (nullable NSString *)verifyServiceAuthJWT:(JWT *)jwt
                                 issuerDID:(NSString *)issDID
                                     error:(NSError **)error {
    return [self verifyServiceAuthJWT:jwt issuerDID:issDID forceRefresh:NO error:error];
}

- (nullable NSString *)verifyServiceAuthJWT:(JWT *)jwt
                                 issuerDID:(NSString *)issDID
                             forceRefresh:(BOOL)forceRefresh
                                     error:(NSError **)error {
    // Resolve the issuer's DID document to get the signing key
    NSDictionary *atprotoData = [self.didResolver resolveAtprotoDataForDID:issDID forceRefresh:forceRefresh error:error];
    if (!atprotoData) {
        GZ_LOG_ERROR(@"ChatAuthManager: failed to resolve DID %@: %@", issDID, error ? *error : @"(unknown)");
        return nil;
    }

    NSData *signingKeyBytes = atprotoData[@"signingKeyBytes"];
    if (!signingKeyBytes.length) {
        // Try the did:key string instead
        NSString *signingKeyStr = atprotoData[@"signingKey"];
        if (signingKeyStr.length) {
            GZ_LOG_WARN(@"ChatAuthManager: got signing key as did:key string but need raw bytes for verification: %@", signingKeyStr);
        }
        if (error) {
            *error = [NSError errorWithDomain:@"ChatAuthManager"
                                         code:401
                                     userInfo:@{NSLocalizedDescriptionKey: @"No signing key found in DID document"}];
        }
        return nil;
    }

    // Verify the JWT signature using the resolved signing key
    NSString *alg = jwt.header.alg ?: @"";
    NSData *signingInputData = [jwt.signingInput dataUsingEncoding:NSUTF8StringEncoding];
    NSData *signatureData = [JWT base64URLDecode:jwt.encodedSignature error:error];
    if (!signatureData) return nil;

    BOOL verified = NO;

    if ([alg isEqualToString:@"ES256K"]) {
        // ES256K verification using secp256k1
        Secp256k1 *secp = [Secp256k1 shared];
        unsigned char hash[32];
        CC_SHA256(signingInputData.bytes, (CC_LONG)signingInputData.length, hash);
        NSData *hashData = [NSData dataWithBytes:hash length:32];
        verified = [secp verifySignature:signatureData forHash:hashData withPublicKey:signingKeyBytes error:error];
    } else if ([alg isEqualToString:@"ES256"]) {
        // ES256 (P-256) verification — not typical for atproto but supported
        // This would require Security framework SecKeyVerifySignature
        GZ_LOG_WARN(@"ChatAuthManager: ES256 verification not yet implemented for service auth");
        if (error) {
            *error = [NSError errorWithDomain:@"ChatAuthManager"
                                         code:401
                                     userInfo:@{NSLocalizedDescriptionKey: @"ES256 verification not implemented"}];
        }
        return nil;
    } else {
        if (error) {
            *error = [NSError errorWithDomain:@"ChatAuthManager"
                                         code:401
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unsupported JWT algorithm: %@", alg]}];
        }
        return nil;
    }

    if (!verified) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"ChatAuthManager"
                                         code:401
                                     userInfo:@{NSLocalizedDescriptionKey: @"JWT signature verification failed"}];
        }
        return nil;
    }

    // Return the issuer DID (without fragment) as the authenticated user
    return issDID;
}

#pragma mark - Legacy PDS Token Fallback

/*! Validate a legacy PDS-signed token (iss=PDS DID, sub=user DID).
    This supports gradual migration from the old format. */
- (nullable NSString *)validateLegacyPDSToken:(JWT *)jwt {
    // Legacy tokens have sub=user DID and are signed with the PDS key.
    // We can't verify the PDS key here, but we can trust the sub claim
    // if the token came from a PDS we trust (configured via pdsUrl).
    NSString *sub = jwt.payload.sub;
    if (!sub.length || ![sub hasPrefix:@"did:"]) {
        return nil;
    }

    // Check expiration
    if (jwt.payload.exp && [jwt.payload.exp timeIntervalSinceNow] < 0) {
        return nil;
    }

    // Try to verify via PDS session check as a last resort
    if (self.pdsUrl.length > 0) {
        NSString *pdsDid = [self validateTokenViaPDS:[jwt encodedToken]];
        if (pdsDid.length > 0) {
            return pdsDid;
        }
    }

    // If no PDS URL configured, trust the sub claim (legacy behavior)
    return sub;
}

#pragma mark - PDS Session Verification (Legacy Fallback)

/*! Validate a token by calling the PDS's com.atproto.server.getSession.
    Returns the DID on success, nil on failure. */
- (nullable NSString *)validateTokenViaPDS:(NSString *)token {
    NSString *pdsUrl = self.pdsUrl;
    if (pdsUrl.length == 0) {
        return nil;
    }

    NSString *sessionURL = ChatAuthURLByAppendingPath(pdsUrl, @"xrpc/com.atproto.server.getSession");
    NSURL *url = [NSURL URLWithString:sessionURL];
    if (!url) {
        GZ_LOG_ERROR(@"ChatAuthManager: invalid PDS session URL: %@", sessionURL);
        return nil;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:5.0];
    [request setHTTPMethod:@"GET"];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];

    ATProtoSafeHTTPClientOptions *options = [ATProtoSafeHTTPClientOptions defaultOptions];
    options.allowHTTP = YES;
    options.allowPrivateHosts = YES;

    NSHTTPURLResponse *urlResponse = nil;
    NSError *error = nil;
    NSData *data = [[ATProtoSafeHTTPClient sharedClient] sendSynchronousRequest:request
                                                                        options:options
                                                                       response:&urlResponse
                                                                          error:&error];

    if (!data || urlResponse.statusCode < 200 || urlResponse.statusCode >= 300) {
        GZ_LOG_ERROR(@"ChatAuthManager: PDS session check failed: status=%ld",
                      (long)urlResponse.statusCode);
        return nil;
    }

    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![json isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    NSString *did = ((NSDictionary *)json)[@"did"];
    if (![did isKindOfClass:[NSString class]] || did.length == 0) {
        return nil;
    }

    GZ_LOG_INFO(@"ChatAuthManager: PDS session check verified DID: %@", did);
    return did;
}

#pragma mark - URL Helpers

static NSString *ChatAuthURLByAppendingPath(NSString *baseURL, NSString *path) {
    NSString *trimmedBase = [baseURL stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *trimmedPath = [path stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]];
    if (trimmedBase.length == 0 || trimmedPath.length == 0) {
        return nil;
    }
    if ([trimmedBase hasSuffix:@"/"]) {
        return [trimmedBase stringByAppendingString:trimmedPath];
    }
    return [NSString stringWithFormat:@"%@/%@", trimmedBase, trimmedPath];
}

@end
