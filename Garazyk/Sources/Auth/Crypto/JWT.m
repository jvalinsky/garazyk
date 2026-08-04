// SPDX-FileCopyrightText: 2024-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file JWT.m

 @abstract JWT (JSON Web Token) implementation for ATProto authentication.

 @discussion This file provides concrete implementations for JWT token parsing,
 encoding, verification, and minting. It includes ATProtoJWTHeader, ATProtoJWTPayload, JWT,
 ATProtoJWTVerifier, and JWTMinter classes.

 @copyright Copyright (c) 2024-2026 Jack Valinsky
 */

#import "Auth/Crypto/JWT.h"
#import "Auth/AuthClaimTypeCheck.h"
#import "Auth/Crypto/Secp256k1.h"
#import "Auth/PDSKeyManagerProtocol.h"
#import "Auth/PDSActorKeyManagerProtocol.h"
#import <CommonCrypto/CommonDigest.h>
#import <Security/SecRandom.h>
#import "Security/PDSSecurityCompare.h"

NSString * const JWTErrorDomain = @"com.atproto.pds.jwt";

/*! Base64URL character set for JWT encoding. */
static NSCharacterSet *Base64URLCharacterSet(void) {
    static NSCharacterSet *set = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableCharacterSet *mutableSet = [NSMutableCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"];
        set = [mutableSet copy];
    });
    return set;
}

@implementation ATProtoJWTHeader

+ (nullable instancetype)headerFromDictionary:(NSDictionary *)dictionary error:(NSError **)error {
    ATProtoJWTHeader *header = [[ATProtoJWTHeader alloc] init];
    BOOL typeMismatch = NO;
    header.alg = AuthTypedValue(dictionary, @"alg", [NSString class], &typeMismatch);
    header.typ = AuthTypedValue(dictionary, @"typ", [NSString class], &typeMismatch);
    header.kid = AuthTypedValue(dictionary, @"kid", [NSString class], &typeMismatch);
    header.cty = AuthTypedValue(dictionary, @"cty", [NSString class], &typeMismatch);
    if (typeMismatch) {
        if (error) {
            *error = [NSError errorWithDomain:JWTErrorDomain
                                         code:JWTErrorInvalidHeader
                                     userInfo:@{NSLocalizedDescriptionKey: @"JWT header claim has unexpected type"}];
        }
        return nil;
    }
    return header;
}

- (NSDictionary *)toDictionary {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    if (self.alg) dict[@"alg"] = self.alg;
    if (self.typ) dict[@"typ"] = self.typ;
    if (self.kid) dict[@"kid"] = self.kid;
    if (self.cty) dict[@"cty"] = self.cty;
    return [dict copy];
}

@end

@implementation ATProtoJWTPayload

+ (nullable instancetype)payloadFromDictionary:(NSDictionary *)dictionary error:(NSError **)error {
    ATProtoJWTPayload *payload = [[ATProtoJWTPayload alloc] init];
    BOOL typeMismatch = NO;
    payload.iss = AuthTypedValue(dictionary, @"iss", [NSString class], &typeMismatch);
    payload.sub = AuthTypedValue(dictionary, @"sub", [NSString class], &typeMismatch);
    payload.jti = AuthTypedValue(dictionary, @"jti", [NSString class], &typeMismatch);
    payload.sid = AuthTypedValue(dictionary, @"sid", [NSString class], &typeMismatch);
    payload.did = AuthTypedValue(dictionary, @"did", [NSString class], &typeMismatch);
    payload.handle = AuthTypedValue(dictionary, @"handle", [NSString class], &typeMismatch);
    payload.scope = AuthTypedValue(dictionary, @"scope", [NSString class], &typeMismatch);
    payload.lxm = AuthTypedValue(dictionary, @"lxm", [NSString class], &typeMismatch);
    payload.token_use = AuthTypedValue(dictionary, @"token_use", [NSString class], &typeMismatch);
    payload.cnf = AuthTypedValue(dictionary, @"cnf", [NSDictionary class], &typeMismatch);

    // RFC 7519 §4.1.3: 'aud' is a single StringOrURI, or an array of them.
    // Normalize to an array; keep 'aud' as the first element for existing
    // single-value consumers.
    id audValue = dictionary[@"aud"];
    if (audValue != nil) {
        if ([audValue isKindOfClass:[NSString class]]) {
            payload.aud = audValue;
            payload.audiences = @[audValue];
        } else if ([audValue isKindOfClass:[NSArray class]]) {
            BOOL allStrings = YES;
            for (id element in (NSArray *)audValue) {
                if (![element isKindOfClass:[NSString class]]) {
                    allStrings = NO;
                    break;
                }
            }
            if (allStrings) {
                NSArray<NSString *> *audArray = [(NSArray *)audValue copy];
                payload.audiences = audArray;
                payload.aud = audArray.firstObject;
            } else {
                typeMismatch = YES;
            }
        } else {
            typeMismatch = YES;
        }
    }

    if (typeMismatch) {
        if (error) {
            *error = [NSError errorWithDomain:JWTErrorDomain
                                         code:JWTErrorInvalidPayload
                                     userInfo:@{NSLocalizedDescriptionKey: @"JWT payload claim has unexpected type"}];
        }
        return nil;
    }

    id expValue = dictionary[@"exp"];
    if (expValue != nil) {
        if (![expValue isKindOfClass:[NSNumber class]]) {
            if (error) {
                *error = [NSError errorWithDomain:JWTErrorDomain
                                             code:JWTErrorInvalidPayload
                                         userInfo:@{NSLocalizedDescriptionKey: @"JWT 'exp' claim must be a number"}];
            }
            return nil;
        }
        payload.exp = [NSDate dateWithTimeIntervalSince1970:[expValue doubleValue]];
    }

    id iatValue = dictionary[@"iat"];
    if (iatValue != nil) {
        if (![iatValue isKindOfClass:[NSNumber class]]) {
            if (error) {
                *error = [NSError errorWithDomain:JWTErrorDomain
                                             code:JWTErrorInvalidPayload
                                         userInfo:@{NSLocalizedDescriptionKey: @"JWT 'iat' claim must be a number"}];
            }
            return nil;
        }
        payload.iat = [NSDate dateWithTimeIntervalSince1970:[iatValue doubleValue]];
    }

    id nbfValue = dictionary[@"nbf"];
    if (nbfValue != nil) {
        if (![nbfValue isKindOfClass:[NSNumber class]]) {
            if (error) {
                *error = [NSError errorWithDomain:JWTErrorDomain
                                             code:JWTErrorInvalidPayload
                                         userInfo:@{NSLocalizedDescriptionKey: @"JWT 'nbf' claim must be a number"}];
            }
            return nil;
        }
        payload.nbf = [NSDate dateWithTimeIntervalSince1970:[nbfValue doubleValue]];
    }

    return payload;
}

- (NSDictionary *)toDictionary {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    if (self.iss) dict[@"iss"] = self.iss;
    if (self.sub) dict[@"sub"] = self.sub;
    if (self.aud) dict[@"aud"] = self.aud;
    if (self.jti) dict[@"jti"] = self.jti;
    if (self.sid) dict[@"sid"] = self.sid;
    if (self.did) dict[@"did"] = self.did;
    if (self.handle) dict[@"handle"] = self.handle;
    if (self.scope) dict[@"scope"] = self.scope;
    if (self.lxm) dict[@"lxm"] = self.lxm;
    if (self.token_use) dict[@"token_use"] = self.token_use;
    if (self.cnf) dict[@"cnf"] = self.cnf;
    if (self.exp) dict[@"exp"] = @([self.exp timeIntervalSince1970]);
    if (self.iat) dict[@"iat"] = @([self.iat timeIntervalSince1970]);
    if (self.nbf) dict[@"nbf"] = @([self.nbf timeIntervalSince1970]);
    return [dict copy];
}

@end

@interface JWT ()
@property (nonatomic, strong) ATProtoJWTHeader *header;
@property (nonatomic, strong) ATProtoJWTPayload *payload;
@property (nonatomic, copy) NSString *rawHeader;
@property (nonatomic, copy) NSString *rawPayload;
@property (nonatomic, copy) NSString *signature;
@property (nonatomic, copy) NSString *encodedSignature;
@end

@implementation JWT

+ (nullable instancetype)jwtWithToken:(NSString *)token error:(NSError **)error {
    NSArray<NSString *> *parts = [token componentsSeparatedByString:@"."];
    if (parts.count != 3) {
        if (error) {
            *error = [NSError errorWithDomain:JWTErrorDomain
                                         code:JWTErrorInvalidFormat
                                     userInfo:@{NSLocalizedDescriptionKey: @"JWT must have exactly 3 parts"}];
        }
        return nil;
    }

    NSString *headerPart = parts[0];
    NSString *payloadPart = parts[1];
    NSString *signaturePart = parts[2];

    NSData *headerData = [self base64URLDecode:headerPart error:error];
    if (!headerData) return nil;

    NSData *payloadData = [self base64URLDecode:payloadPart error:error];
    if (!payloadData) return nil;

    NSDictionary *headerDict = [NSJSONSerialization JSONObjectWithData:headerData options:0 error:error];
    if (!headerDict || ![headerDict isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [NSError errorWithDomain:JWTErrorDomain
                                         code:JWTErrorInvalidHeader
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid JWT header JSON"}];
        }
        return nil;
    }

    NSDictionary *payloadDict = [NSJSONSerialization JSONObjectWithData:payloadData options:0 error:error];
    if (!payloadDict || ![payloadDict isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [NSError errorWithDomain:JWTErrorDomain
                                         code:JWTErrorInvalidPayload
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid JWT payload JSON"}];
        }
        return nil;
    }

    ATProtoJWTHeader *header = [ATProtoJWTHeader headerFromDictionary:headerDict error:error];
    if (!header) return nil;

    ATProtoJWTPayload *payload = [ATProtoJWTPayload payloadFromDictionary:payloadDict error:error];
    if (!payload) return nil;

    JWT *jwt = [[JWT alloc] init];
    jwt.header = header;
    jwt.payload = payload;
    jwt.rawHeader = headerPart;
    jwt.rawPayload = payloadPart;
    jwt.signature = @"";
    jwt.encodedSignature = signaturePart;

    return jwt;
}

+ (nullable instancetype)jwtWithHeader:(ATProtoJWTHeader *)header
                               payload:(ATProtoJWTPayload *)payload
                             signature:(NSString *)signature
                                  error:(NSError **)error {
    JWT *jwt = [[JWT alloc] init];
    jwt.header = header;
    jwt.payload = payload;
    jwt.rawHeader = [self base64URLEncodeData:[NSJSONSerialization dataWithJSONObject:[header toDictionary] options:0 error:error] error:error];
    if (!jwt.rawHeader) return nil;
    jwt.rawPayload = [self base64URLEncodeData:[NSJSONSerialization dataWithJSONObject:[payload toDictionary] options:0 error:error] error:error];
    if (!jwt.rawPayload) return nil;
    jwt.signature = @"";
    jwt.encodedSignature = signature;
    return jwt;
}

- (NSString *)encodedToken {
    return [NSString stringWithFormat:@"%@.%@.%@", self.rawHeader, self.rawPayload, self.encodedSignature];
}

- (NSString *)signingInput {
    return [NSString stringWithFormat:@"%@.%@", self.rawHeader, self.rawPayload];
}

+ (NSString *)base64URLEncodeData:(NSData *)data error:(NSError **)error {
    NSString *base64 = [data base64EncodedStringWithOptions:0];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    base64 = [base64 stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    while ([base64 hasSuffix:@"="]) {
        base64 = [base64 substringToIndex:base64.length - 1];
    }
    return base64;
}

+ (nullable NSData *)base64URLDecode:(NSString *)string error:(NSError **)error {
    if (!string || string.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:JWTErrorDomain
                                         code:JWTErrorDecodingFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Empty Base64URL string"}];
        }
        return nil;
    }

    if ([string hasSuffix:@"="]) {
        if (error) {
            *error = [NSError errorWithDomain:JWTErrorDomain
                                         code:JWTErrorDecodingFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Base64URL must not contain padding characters ('=')"}];
        }
        return nil;
    }

    NSMutableString *base64 = [string mutableCopy];
    NSUInteger remainder = base64.length % 4;
    if (remainder > 0) {
        [base64 appendString:[@"====" substringToIndex:(4 - remainder)]];
    }
    base64 = [[base64 stringByReplacingOccurrencesOfString:@"-" withString:@"+"] mutableCopy];
    base64 = [[base64 stringByReplacingOccurrencesOfString:@"_" withString:@"/"] mutableCopy];
    NSData *data = [[NSData alloc] initWithBase64EncodedData:[base64 dataUsingEncoding:NSUTF8StringEncoding] options:0];
    if (!data && error) {
        *error = [NSError errorWithDomain:JWTErrorDomain
                                     code:JWTErrorDecodingFailed
                                 userInfo:@{NSLocalizedDescriptionKey: @"Base64URL decoding failed"}];
    }
    return data;
}

@end

@implementation ATProtoJWTVerifier

- (instancetype)init {
    self = [super init];
    return self;
}

- (BOOL)verifyJWT:(JWT *)jwt error:(NSError **)error {
    // Fail closed: allowedAlgorithms must be set by the caller. An unset
    // list means no algorithm is accepted, preventing alg-confusion where
    // an attacker-controlled header alg selects the verification path.
    if (!self.allowedAlgorithms) {
        if (error) {
            *error = [NSError errorWithDomain:JWTErrorDomain
                                         code:JWTErrorInvalidAlgorithm
                                     userInfo:@{NSLocalizedDescriptionKey: @"No allowed algorithms configured"}];
        }
        return NO;
    }

    NSString *alg = jwt.header.alg ?: @"";
    if (![self.allowedAlgorithms containsObject:alg]) {
        if (error) {
            *error = [NSError errorWithDomain:JWTErrorDomain
                                         code:JWTErrorInvalidAlgorithm
                                     userInfo:@{NSLocalizedDescriptionKey: @"Algorithm not allowed"}];
        }
        return NO;
    }

    NSData *signingInputData = [jwt.signingInput dataUsingEncoding:NSUTF8StringEncoding];
    NSData *signatureData = [JWT base64URLDecode:jwt.encodedSignature error:error];
    if (!signatureData) return NO;

    BOOL verified = NO;

    // Derive the verification path from the key material, not from the
    // attacker-controlled header alg. The allowedAlgorithms check above
    // validates the declared alg; the actual crypto path is selected by
    // which key is configured.
    if (self.publicKey) {
        // self.publicKey is always a secp256k1 public key.
        ATProtoSecp256k1 *secp = [ATProtoSecp256k1 shared];
        unsigned char hash[32];
        CC_SHA256(signingInputData.bytes, (CC_LONG)signingInputData.length, hash);
        NSData *hashData = [NSData dataWithBytes:hash length:32];
        verified = [secp verifySignature:signatureData forHash:hashData withPublicKey:self.publicKey error:error];
    } else if (self.keyManager) {
        NSString *kid = jwt.header.kid;
        if (kid) {
            verified = [self.keyManager verifySignature:signatureData forData:signingInputData withKeyID:kid error:error];
        } else {
            // Legacy path for ES256K without kid (standard for actor keys)
            // Use the first available key if no kid is present
            id<PDSKeyPair> active = [self.keyManager getActiveKeyPair:error];
            if (active) {
                verified = [self.keyManager verifySignature:signatureData forData:signingInputData withKeyID:active.keyID error:error];
            }
        }
    } else {
        if (error) {
            *error = [NSError errorWithDomain:JWTErrorDomain
                                         code:JWTErrorNoPublicKey
                                     userInfo:@{NSLocalizedDescriptionKey: @"No public key or key manager configured for signature verification"}];
        }
        return NO;
    }

    if (!verified) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:JWTErrorDomain
                                         code:JWTErrorInvalidSignature
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid JWT signature"}];
        }
        return NO;
    }

    if (![self validateClaims:jwt.payload ofJWT:jwt error:error]) {
        return NO;
    }
    if (error && *error) {
        return NO;
    }
    return YES;
}

- (BOOL)validateClaims:(ATProtoJWTPayload *)payload ofJWT:(JWT *)jwt error:(NSError **)error {
    // Use clockOffset as the reference time if set; otherwise use the live
    // clock. Tests can set clockOffset for deterministic expiry/nbf checks.
    NSDate *now = self.clockOffset ?: [NSDate date];

    // exp is mandatory: a token without an expiration must never be
    // accepted. All self-issued tokens (mintAccessTokenForDID:,
    // mintRefreshTokenForDID:, mintServiceAuthJWTForDID:) always set exp.
    if (!payload.exp) {
        if (error) {
            *error = [NSError errorWithDomain:JWTErrorDomain
                                         code:JWTErrorMissingRequiredClaim
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing required 'exp' claim"}];
        }
        return NO;
    }

    if ([payload.exp compare:now] == NSOrderedAscending) {
        if (error) {
            *error = [NSError errorWithDomain:JWTErrorDomain
                                         code:JWTErrorTokenExpired
                                     userInfo:@{NSLocalizedDescriptionKey: @"Token has expired"}];
        }
        return NO;
    }

    if (payload.nbf && [payload.nbf compare:now] == NSOrderedDescending) {
        if (error) {
            *error = [NSError errorWithDomain:JWTErrorDomain
                                         code:JWTErrorTokenNotYetValid
                                     userInfo:@{NSLocalizedDescriptionKey: @"Token is not yet valid"}];
        }
        return NO;
    }

    // iss mandatory when expectedIssuer is set: a nil iss must not
    // silently bypass the issuer check.
    if (self.expectedIssuer) {
        if (!payload.iss) {
            if (error) {
                *error = [NSError errorWithDomain:JWTErrorDomain
                                             code:JWTErrorMissingRequiredClaim
                                         userInfo:@{NSLocalizedDescriptionKey: @"Missing required 'iss' claim"}];
            }
            return NO;
        }
        if (![PDSSecurityCompare constantTimeEqualString:payload.iss string:self.expectedIssuer]) {
            if (error) {
                *error = [NSError errorWithDomain:JWTErrorDomain
                                             code:JWTErrorInvalidIssuer
                                         userInfo:@{NSLocalizedDescriptionKey: @"Invalid issuer"}];
            }
            return NO;
        }
    }

    // aud mandatory when expectedAudience is set: a nil aud must not
    // silently bypass the audience check. Per RFC 7519 §4.1.3, match
    // if any element of the normalized audiences array equals the
    // expected audience.
    if (self.expectedAudience) {
        if (!payload.audiences || payload.audiences.count == 0) {
            if (error) {
                *error = [NSError errorWithDomain:JWTErrorDomain
                                             code:JWTErrorMissingRequiredClaim
                                         userInfo:@{NSLocalizedDescriptionKey: @"Missing required 'aud' claim"}];
            }
            return NO;
        }
        BOOL matched = NO;
        for (NSString *audience in payload.audiences) {
            if ([PDSSecurityCompare constantTimeEqualString:audience string:self.expectedAudience]) {
                matched = YES;
                break;
            }
        }
        if (!matched) {
            if (error) {
                *error = [NSError errorWithDomain:JWTErrorDomain
                                             code:JWTErrorInvalidAudience
                                         userInfo:@{NSLocalizedDescriptionKey: @"Invalid audience"}];
            }
            return NO;
        }
    }

    // §4.1: token_use enforcement prevents refresh tokens from being
    // accepted as access tokens and vice versa. Access tokens are minted
    // with token_use="access" (typ="at+jwt"), refresh tokens with
    // token_use="refresh" (typ="refresh+jwt"). The verifier caller sets
    // expectedTokenUse to the value they expect; nil means skip this check.
    if (self.expectedTokenUse) {
        if (!payload.token_use) {
            if (error) {
                *error = [NSError errorWithDomain:JWTErrorDomain
                                             code:JWTErrorMissingRequiredClaim
                                         userInfo:@{NSLocalizedDescriptionKey: @"Missing required 'token_use' claim"}];
            }
            return NO;
        }
        if (![payload.token_use isEqualToString:self.expectedTokenUse]) {
            if (error) {
                *error = [NSError errorWithDomain:JWTErrorDomain
                                             code:JWTErrorInvalidPayload
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Invalid token_use: expected '%@', got '%@'", self.expectedTokenUse, payload.token_use]}];
            }
            return NO;
        }
        // When expectedTokenUse is set, also check the header typ for
        // defense-in-depth. Access tokens carry typ="at+jwt", refresh
        // tokens carry typ="refresh+jwt".
        if (self.expectedTyp) {
            NSString *typ = jwt.header.typ;
            if (!typ || ![typ isEqualToString:self.expectedTyp]) {
                if (error) {
                    *error = [NSError errorWithDomain:JWTErrorDomain
                                                 code:JWTErrorInvalidHeader
                                             userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Invalid typ: expected '%@', got '%@'", self.expectedTyp, typ ?: @"(nil)"]}];
                }
                return NO;
            }
        }
    }

    if (!payload.sub && !payload.did && !self.allowMissingSubject) {
        if (error) {
            *error = [NSError errorWithDomain:JWTErrorDomain
                                         code:JWTErrorMissingRequiredClaim
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing subject claim"}];
        }
        return NO;
    }

    return YES;
}

@end

@implementation JWTMinter

- (instancetype)init {
    self = [super init];
    if (self) {
        _signingAlgorithm = @"ES256";
        _defaultExpiration = 3600;
    }
    return self;
}

- (NSString *)signPayload:(NSDictionary *)payload keyManager:(id<PDSKeyManager>)keyManager error:(NSError **)error {
    id<PDSKeyPair> activeKey = [keyManager getActiveKeyPair:error];
    if (!activeKey) return nil;

    NSData *payloadData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:error];
    if (!payloadData) return nil;

    NSString *payloadEncoded = [JWT base64URLEncodeData:payloadData error:error];
    if (!payloadEncoded) return nil;

    NSMutableDictionary *header = [NSMutableDictionary dictionary];
    header[@"alg"] = activeKey.algorithm;
    header[@"typ"] = @"JWT";
    header[@"kid"] = activeKey.keyID;

    NSData *headerData = [NSJSONSerialization dataWithJSONObject:header options:0 error:error];
    if (!headerData) return nil;

    NSString *headerEncoded = [JWT base64URLEncodeData:headerData error:error];
    if (!headerEncoded) return nil;

    NSString *signingInput = [NSString stringWithFormat:@"%@.%@", headerEncoded, payloadEncoded];
    NSData *dataToSign = [signingInput dataUsingEncoding:NSUTF8StringEncoding];

    NSData *signatureData = [keyManager signData:dataToSign withKeyID:activeKey.keyID error:error];
    if (!signatureData) return nil;

    NSString *signatureEncoded = [JWT base64URLEncodeData:signatureData error:error];
    if (!signatureEncoded) return nil;

    return [NSString stringWithFormat:@"%@.%@.%@", headerEncoded, payloadEncoded, signatureEncoded];
}

- (NSString *)signPayload:(NSDictionary *)payload actorKeyManager:(id<PDSActorKeyManager>)keyManager error:(NSError **)error {
    NSData *payloadData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:error];
    if (!payloadData) return nil;

    NSString *payloadEncoded = [JWT base64URLEncodeData:payloadData error:error];
    if (!payloadEncoded) return nil;

    NSMutableDictionary *header = [NSMutableDictionary dictionary];
    header[@"alg"] = @"ES256K"; // Actor keys are ES256K
    header[@"typ"] = @"JWT";

    NSData *headerData = [NSJSONSerialization dataWithJSONObject:header options:0 error:error];
    if (!headerData) return nil;

    NSString *headerEncoded = [JWT base64URLEncodeData:headerData error:error];
    if (!headerEncoded) return nil;

    NSString *signingInput = [NSString stringWithFormat:@"%@.%@", headerEncoded, payloadEncoded];
    NSData *dataToSign = [signingInput dataUsingEncoding:NSUTF8StringEncoding];

    NSData *signatureData = [keyManager signData:dataToSign error:error];
    if (!signatureData) return nil;

    NSString *signatureEncoded = [JWT base64URLEncodeData:signatureData error:error];
    if (!signatureEncoded) return nil;

    return [NSString stringWithFormat:@"%@.%@.%@", headerEncoded, payloadEncoded, signatureEncoded];
}

- (NSString *)mintServiceAuthJWTForDID:(NSString *)userDID
                                   aud:(NSString *)audienceDID
                                   lxm:(NSString *)methodNSID
                       actorKeyManager:(id<PDSActorKeyManager>)actorKeyManager
                                  error:(NSError **)error {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];

    // Generate 128-bit random nonce (16 hex characters)
    NSMutableData *nonceData = [NSMutableData dataWithLength:16];
    int result = SecRandomCopyBytes(kSecRandomDefault, 16, nonceData.mutableBytes);
    if (result != errSecSuccess) {
        if (error) {
            *error = [NSError errorWithDomain:JWTErrorDomain
                                         code:JWTErrorSigningFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to generate jti nonce"}];
        }
        return nil;
    }
    NSMutableString *jti = [NSMutableString stringWithCapacity:32];
    const unsigned char *bytes = (const unsigned char *)nonceData.bytes;
    for (NSUInteger i = 0; i < 16; i++) {
        [jti appendFormat:@"%02x", bytes[i]];
    }

    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    payload[@"iss"] = userDID;
    payload[@"aud"] = audienceDID;
    payload[@"lxm"] = methodNSID;
    payload[@"iat"] = @((NSInteger)now);
    payload[@"exp"] = @((NSInteger)(now + 60)); // 60 seconds per spec
    payload[@"jti"] = jti;

    return [self signPayload:payload actorKeyManager:actorKeyManager error:error];
}


- (NSString *)signPayload:(NSDictionary *)payload error:(NSError **)error {
    if (self.keyManager) {
        return [self signPayload:payload keyManager:self.keyManager error:error];
    }

    NSData *payloadData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:error];
    if (!payloadData) return nil;

    NSString *payloadEncoded = [JWT base64URLEncodeData:payloadData error:error];
    if (!payloadEncoded) return nil;

    NSMutableDictionary *header = [NSMutableDictionary dictionary];
    header[@"alg"] = self.signingAlgorithm;
    header[@"typ"] = @"JWT";

    NSData *headerData = [NSJSONSerialization dataWithJSONObject:header options:0 error:error];
    if (!headerData) return nil;

    NSString *headerEncoded = [JWT base64URLEncodeData:headerData error:error];
    if (!headerEncoded) return nil;

    NSString *signingInput = [NSString stringWithFormat:@"%@.%@", headerEncoded, payloadEncoded];

    NSData *signatureData = [self signData:signingInput error:error];
    if (!signatureData) return nil;

    NSString *signatureEncoded = [JWT base64URLEncodeData:signatureData error:error];
    if (!signatureEncoded) return nil;

    return [NSString stringWithFormat:@"%@.%@.%@", headerEncoded, payloadEncoded, signatureEncoded];
}

- (NSData *)signData:(NSString *)data error:(NSError **)error {
    NSData *dataBytes = [data dataUsingEncoding:NSUTF8StringEncoding];
    
    if (self.keyManager) {
        // Use active key ID if available, or generate/get one
        id<PDSKeyPair> active = [self.keyManager getActiveKeyPair:error];
        if (!active) return nil;
        return [self.keyManager signData:dataBytes withKeyID:active.keyID error:error];
    }
    
    if (self.privateKey) {
        // Use ATProtoSecp256k1 signing
        unsigned char hash[32];
        CC_SHA256(dataBytes.bytes, (CC_LONG)dataBytes.length, hash);
        NSData *hashData = [NSData dataWithBytes:hash length:32];
        
        ATProtoSecp256k1KeyPair *keyPair = [ATProtoSecp256k1KeyPair keyPairWithPrivateKey:self.privateKey error:error];
        if (!keyPair) return nil;
        
        return [keyPair signHash:hashData error:error];
    } else {
        // No private key configured for signing
        if (error) {
            *error = [NSError errorWithDomain:JWTErrorDomain
                                         code:JWTErrorSigningFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"No private key configured for signing"}];
        }
        return nil;
    }
}

- (JWT *)mintAccessTokenForDID:(NSString *)did
                        handle:(NSString *)handle
                        scopes:(NSArray<NSString *> *)scopes
                     sessionID:(nullable NSString *)sid
             dpopKeyThumbprint:(nullable NSString *)jkt
                           error:(NSError **)error {
    ATProtoJWTPayload *payload = [[ATProtoJWTPayload alloc] init];
    payload.iss = self.issuer;
    payload.sub = did;
    payload.aud = self.audience;
    payload.did = did;
    payload.handle = handle;
    payload.scope = [scopes componentsJoinedByString:@" "];
    payload.token_use = @"access";
    payload.iat = [NSDate date];
    payload.exp = [NSDate dateWithTimeIntervalSinceNow:self.defaultExpiration];
    payload.jti = [[NSUUID UUID] UUIDString];
    payload.sid = sid;
    
    if (jkt) {
        payload.cnf = @{@"jkt": jkt};
    }

    ATProtoJWTHeader *header = [[ATProtoJWTHeader alloc] init];
    header.alg = self.signingAlgorithm;
    header.typ = @"at+jwt";

    NSData *headerData = [NSJSONSerialization dataWithJSONObject:[header toDictionary] options:0 error:error];
    if (!headerData) return nil;

    NSString *headerEncoded = [JWT base64URLEncodeData:headerData error:error];
    if (!headerEncoded) return nil;

    NSData *payloadData = [NSJSONSerialization dataWithJSONObject:[payload toDictionary] options:0 error:error];
    if (!payloadData) return nil;

    NSString *payloadEncoded = [JWT base64URLEncodeData:payloadData error:error];
    if (!payloadEncoded) return nil;

    NSData *signatureData = [self signData:[NSString stringWithFormat:@"%@.%@", headerEncoded, payloadEncoded] error:error];
    if (!signatureData) return nil;

    NSString *signature = [JWT base64URLEncodeData:signatureData error:error];
    if (!signature) return nil;

    return [JWT jwtWithHeader:header payload:payload signature:signature error:error];
}

- (JWT *)mintAccessTokenForDID:(NSString *)did
                        handle:(NSString *)handle
                        scopes:(NSArray<NSString *> *)scopes
             dpopKeyThumbprint:(nullable NSString *)jkt
                           error:(NSError **)error {
    return [self mintAccessTokenForDID:did handle:handle scopes:scopes sessionID:nil dpopKeyThumbprint:jkt error:error];
}

- (JWT *)mintAccessTokenForDID:(NSString *)did
                        handle:(NSString *)handle
                        scopes:(NSArray<NSString *> *)scopes
                           error:(NSError **)error {
    return [self mintAccessTokenForDID:did handle:handle scopes:scopes sessionID:nil dpopKeyThumbprint:nil error:error];
}

- (JWT *)mintRefreshTokenForDID:(NSString *)did
                         handle:(NSString *)handle
                         scopes:(NSArray<NSString *> *)scopes
                           error:(NSError **)error {
    ATProtoJWTPayload *payload = [[ATProtoJWTPayload alloc] init];
    payload.iss = self.issuer;
    payload.sub = did;
    payload.aud = self.audience;
    payload.did = did;
    payload.handle = handle;
    payload.scope = [scopes componentsJoinedByString:@" "];
    payload.token_use = @"refresh";
    payload.iat = [NSDate date];
    payload.exp = [NSDate dateWithTimeIntervalSinceNow:86400 * 30];
    payload.jti = [[NSUUID UUID] UUIDString];

    ATProtoJWTHeader *header = [[ATProtoJWTHeader alloc] init];
    header.alg = self.signingAlgorithm;
    header.typ = @"refresh+jwt";

    NSData *headerData = [NSJSONSerialization dataWithJSONObject:[header toDictionary] options:0 error:error];
    if (!headerData) return nil;

    NSString *headerEncoded = [JWT base64URLEncodeData:headerData error:error];
    if (!headerEncoded) return nil;

    NSData *payloadData = [NSJSONSerialization dataWithJSONObject:[payload toDictionary] options:0 error:error];
    if (!payloadData) return nil;

    NSString *payloadEncoded = [JWT base64URLEncodeData:payloadData error:error];
    if (!payloadEncoded) return nil;

    NSData *signatureData = [self signData:[NSString stringWithFormat:@"%@.%@", headerEncoded, payloadEncoded] error:error];
    if (!signatureData) return nil;

    NSString *signature = [JWT base64URLEncodeData:signatureData error:error];
    if (!signature) return nil;

    return [JWT jwtWithHeader:header payload:payload signature:signature error:error];
}

- (NSDictionary *)toJWKS {
    if (self.keyManager) {
        return [self.keyManager toJWKS];
    }
    
    if (self.publicKey) {
        // Construct JWK for static ES256K key
        // Uncompressed public key is 65 bytes: 0x04 + X (32) + Y (32)
        if (self.publicKey.length == 65) {
            NSData *xData = [self.publicKey subdataWithRange:NSMakeRange(1, 32)];
            NSData *yData = [self.publicKey subdataWithRange:NSMakeRange(33, 32)];
            
            NSString *xStr = [JWT base64URLEncodeData:xData error:nil];
            NSString *yStr = [JWT base64URLEncodeData:yData error:nil];
            
            NSDictionary *jwk = @{
                @"kty": @"EC",
                @"crv": @"secp256k1",
                @"alg": @"ES256K",
                @"use": @"sig",
                @"kid": @"server-key", // Static kid for now
                @"x": xStr ?: @"",
                @"y": yStr ?: @""
            };
            
            return @{ @"keys": @[jwk] };
        }
    }
    
    return @{ @"keys": @[] };
}

@end
