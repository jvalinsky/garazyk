/*!
 @file OAuth2.m

 @abstract OAuth 2.0 with DPoP implementation for ATProto.

 @discussion This file implements the OAuth 2.0 authorization server including
 authorization request handling, token issuance with DPoP proof binding,
 PKCE support, and token refresh. Follows ATProto OAuth 2.0 specification.

 @copyright Copyright (c) 2024 Jack Valinsky
 */

#import "Auth/OAuth2.h"
#import "Auth/Session.h"
#import "Auth/KeyManager.h"
#import "Auth/JWT.h"
#import "Auth/Secp256k1.h"
#import "Core/DID.h"
#import "Identity/HandleResolver.h"
#import "Database/PDSDatabase.h"
#import "Auth/TOTPService.h"
#import "Auth/Base32Utils.h"
#import "Debug/PDSLogger.h"
#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>

NSString * const OAuth2ScopeIdentify = @"atproto:identify";
NSString * const OAuth2ScopeSignIn = @"atproto:signin";
NSString * const OAuth2ScopeRepoWrite = @"atproto:repo_write";
NSString * const OAuth2ScopeRepoRead = @"atproto:repo_read";
NSString * const OAuth2ScopeAtprotoProfile = @"atproto:profile";

NSString * const OAuth2ErrorDomain = @"com.atproto.pds.oauth2";

static NSString * const kAuthorizationCodeKey = @"authorization_code";
static NSString * const kRefreshTokenKey = @"refresh_token";

@interface OAuth2Server ()
@end

@implementation OAuth2AuthorizationRequest

- (NSURL *)authorizationURL {
    NSURLComponents *components = [NSURLComponents componentsWithString:@"/oauth/authorize"];
    NSMutableArray<NSURLQueryItem *> *queryItems = [NSMutableArray array];
    if (self.clientID) [queryItems addObject:[NSURLQueryItem queryItemWithName:@"client_id" value:self.clientID]];
    if (self.redirectURI) [queryItems addObject:[NSURLQueryItem queryItemWithName:@"redirect_uri" value:self.redirectURI]];
    if (self.responseType) [queryItems addObject:[NSURLQueryItem queryItemWithName:@"response_type" value:self.responseType]];
    if (self.scope) [queryItems addObject:[NSURLQueryItem queryItemWithName:@"scope" value:self.scope]];
    if (self.state) [queryItems addObject:[NSURLQueryItem queryItemWithName:@"state" value:self.state]];
    if (self.codeChallenge) [queryItems addObject:[NSURLQueryItem queryItemWithName:@"code_challenge" value:self.codeChallenge]];
    if (self.codeChallengeMethod) [queryItems addObject:[NSURLQueryItem queryItemWithName:@"code_challenge_method" value:self.codeChallengeMethod]];
    if (self.nonce) [queryItems addObject:[NSURLQueryItem queryItemWithName:@"nonce" value:self.nonce]];
    components.queryItems = queryItems;
    return components.URL;
}

- (NSDictionary *)toDictionary {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"client_id"] = self.clientID;
    if (self.redirectURI) dict[@"redirect_uri"] = self.redirectURI;
    if (self.responseType) dict[@"response_type"] = self.responseType;
    if (self.scope) dict[@"scope"] = self.scope;
    if (self.state) dict[@"state"] = self.state;
    if (self.codeChallenge) dict[@"code_challenge"] = self.codeChallenge;
    if (self.codeChallengeMethod) dict[@"code_challenge_method"] = self.codeChallengeMethod;
    if (self.nonce) dict[@"nonce"] = self.nonce;
    if (self.dpopJWK) dict[@"dpop_jwk"] = self.dpopJWK;
    return dict;
}

@end

@implementation OAuth2AuthorizationResponse

+ (nullable instancetype)responseFromURL:(NSURL *)url expectedState:(nullable NSString *)state error:(NSError **)error {
    OAuth2AuthorizationResponse *response = [[OAuth2AuthorizationResponse alloc] init];
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    NSMutableDictionary<NSString *, NSString *> *params = [NSMutableDictionary dictionary];
    for (NSURLQueryItem *item in components.queryItems) {
        params[item.name] = item.value;
    }

    response.code = params[@"code"];
    response.state = params[@"state"];
    response.error = params[@"error"];
    response.errorDescription = params[@"error_description"];

    NSString *errorParam = params[@"error"];
    if (errorParam) {
        OAuth2Error errorCode = OAuth2ErrorInvalidRequest;
        if ([errorParam isEqualToString:@"invalid_request"]) errorCode = OAuth2ErrorInvalidRequest;
        else if ([errorParam isEqualToString:@"unauthorized_client"]) errorCode = OAuth2ErrorUnauthorizedClient;
        else if ([errorParam isEqualToString:@"access_denied"]) errorCode = OAuth2ErrorAccessDenied;
        else if ([errorParam isEqualToString:@"unsupported_response_type"]) errorCode = OAuth2ErrorUnsupportedResponseType;
        else if ([errorParam isEqualToString:@"invalid_scope"]) errorCode = OAuth2ErrorInvalidScope;
        else if ([errorParam isEqualToString:@"server_error"]) errorCode = OAuth2ErrorServerError;
        else if ([errorParam isEqualToString:@"temporarily_unavailable"]) errorCode = OAuth2ErrorTemporarilyUnavailable;
        else if ([errorParam isEqualToString:@"interaction_required"]) errorCode = OAuth2ErrorInteractionRequired;
        else if ([errorParam isEqualToString:@"consent_required"]) errorCode = OAuth2ErrorConsentRequired;

        if (error) {
            *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                         code:errorCode
                                     userInfo:@{
                NSLocalizedDescriptionKey: response.errorDescription ?: errorParam,
                @"error": errorParam
            }];
        }
        return nil;
    }

    if (!response.code) {
        if (error) {
            *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                         code:OAuth2ErrorInvalidGrant
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing authorization code"}];
        }
        return nil;
    }

    if (state && ![response.state isEqualToString:state]) {
        if (error) {
            *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                         code:OAuth2ErrorInvalidRequest
                                     userInfo:@{NSLocalizedDescriptionKey: @"State mismatch"}];
        }
        return nil;
    }

    return response;
}

@end

@implementation OAuth2TokenRequest

- (NSDictionary *)toFormData {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"grant_type"] = self.grantType;
    if (self.code) dict[@"code"] = self.code;
    if (self.redirectURI) dict[@"redirect_uri"] = self.redirectURI;
    if (self.clientID) dict[@"client_id"] = self.clientID;
    if (self.codeVerifier) dict[@"code_verifier"] = self.codeVerifier;
    if (self.refreshToken) dict[@"refresh_token"] = self.refreshToken;
    if (self.accessToken) dict[@"access_token"] = self.accessToken;
    if (self.dpopProof) dict[@"dpop"] = self.dpopProof;
    if (self.scope) dict[@"scope"] = self.scope;
    if (self.tfaCode) dict[@"tfa_code"] = self.tfaCode;
    return dict;
}

@end

@implementation OAuth2TokenResponse

+ (nullable instancetype)responseFromDictionary:(NSDictionary *)dictionary error:(NSError **)error {
    OAuth2TokenResponse *response = [[OAuth2TokenResponse alloc] init];
    response.accessToken = dictionary[@"access_token"];
    response.tokenType = dictionary[@"token_type"] ?: @"Bearer";
    response.refreshToken = dictionary[@"refresh_token"];
    response.scope = dictionary[@"scope"];

    id expiresIn = dictionary[@"expires_in"];
    if ([expiresIn isKindOfClass:[NSNumber class]]) {
        response.expiresIn = [expiresIn doubleValue];
    } else if ([expiresIn isKindOfClass:[NSString class]]) {
        response.expiresIn = [expiresIn doubleValue];
    } else {
        response.expiresIn = 3600;
    }

    response.dpopKeyThumbprint = dictionary[@"dpop_key_thumbprint"];

    if (!response.accessToken) {
        if (error) {
            *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                         code:OAuth2ErrorInvalidGrant
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing access token"}];
        }
        return nil;
    }

    return response;
}

@end

@implementation OAuth2DPoPProof

+ (nullable NSData *)decodeBase64URL:(NSString *)value error:(NSError **)error {
    return [JWT base64URLDecode:value error:error];
}

+ (nullable NSData *)decodeJWKComponent:(NSString *)value expectedLength:(NSUInteger)expectedLength error:(NSError **)error {
    NSData *decoded = [self decodeBase64URL:value error:error];
    if (!decoded) {
        return nil;
    }
    if (decoded.length != expectedLength) {
        if (error) {
            *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                         code:OAuth2ErrorInvalidRequest
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid JWK component length"}];
        }
        return nil;
    }
    return decoded;
}

+ (nullable SecKeyRef)createPrivateKeyFromJWK:(NSDictionary *)jwk error:(NSError **)error {
    NSString *kty = jwk[@"kty"];
    if (!kty) {
        if (error) {
            *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                         code:OAuth2ErrorInvalidRequest
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing JWK key type"}];
        }
        return nil;
    }

    if ([kty isEqualToString:@"EC"]) {
        NSString *crv = jwk[@"crv"];
        if (crv && ![crv isEqualToString:@"P-256"]) {
            if (error) {
                *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                             code:OAuth2ErrorInvalidRequest
                                         userInfo:@{NSLocalizedDescriptionKey: @"Unsupported EC curve"}];
            }
            return nil;
        }

        NSString *xValue = jwk[@"x"];
        NSString *yValue = jwk[@"y"];
        NSString *dValue = jwk[@"d"];
        if (!xValue || !yValue || !dValue) {
            if (error) {
                *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                             code:OAuth2ErrorInvalidRequest
                                         userInfo:@{NSLocalizedDescriptionKey: @"Missing EC key material"}];
            }
            return nil;
        }

        NSError *decodeError = nil;
        NSData *xData = [self decodeJWKComponent:xValue expectedLength:32 error:&decodeError];
        NSData *yData = [self decodeJWKComponent:yValue expectedLength:32 error:&decodeError];
        NSData *dData = [self decodeJWKComponent:dValue expectedLength:32 error:&decodeError];
        if (!xData || !yData || !dData) {
            if (error) *error = decodeError;
            return nil;
        }

        NSMutableData *privateKeyData = [NSMutableData dataWithCapacity:97];
        uint8_t prefix = 0x04;
        [privateKeyData appendBytes:&prefix length:1];
        [privateKeyData appendData:xData];
        [privateKeyData appendData:yData];
        [privateKeyData appendData:dData];

        NSDictionary *attrs = @{
            (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
            (__bridge id)kSecAttrKeyClass: (__bridge id)kSecAttrKeyClassPrivate,
            (__bridge id)kSecAttrKeySizeInBits: @256
        };

        CFErrorRef keyError = NULL;
        SecKeyRef privateKey = SecKeyCreateWithData((__bridge CFDataRef)privateKeyData,
                                                    (__bridge CFDictionaryRef)attrs,
                                                    &keyError);
        if (!privateKey) {
            if (error) {
                if (keyError) {
                    *error = CFBridgingRelease(keyError);
                } else {
                    *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                                 code:OAuth2ErrorServerError
                                             userInfo:@{NSLocalizedDescriptionKey: @"Failed to create EC private key"}];
                }
            } else if (keyError) {
                CFRelease(keyError);
            }
            return nil;
        }
        if (keyError) CFRelease(keyError);
        return privateKey;
    }

    if (error) {
        *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                     code:OAuth2ErrorInvalidRequest
                                 userInfo:@{NSLocalizedDescriptionKey: @"Unsupported JWK key type"}];
    }
    return nil;
}

+ (nullable SecKeyRef)createPublicKeyFromJWK:(NSDictionary *)jwk error:(NSError **)error {
    NSString *kty = jwk[@"kty"];
    if (![kty isEqualToString:@"EC"]) {
        if (error) {
            *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                         code:OAuth2ErrorInvalidRequest
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unsupported JWK key type"}];
        }
        return nil;
    }

    NSString *xValue = jwk[@"x"];
    NSString *yValue = jwk[@"y"];
    if (!xValue || !yValue) {
        if (error) {
            *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                         code:OAuth2ErrorInvalidRequest
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing EC public key material"}];
        }
        return nil;
    }

    NSError *decodeError = nil;
    NSData *xData = [self decodeJWKComponent:xValue expectedLength:32 error:&decodeError];
    NSData *yData = [self decodeJWKComponent:yValue expectedLength:32 error:&decodeError];
    if (!xData || !yData) {
        if (error) *error = decodeError;
        return nil;
    }

    NSMutableData *publicKeyData = [NSMutableData dataWithCapacity:65];
    uint8_t prefix = 0x04;
    [publicKeyData appendBytes:&prefix length:1];
    [publicKeyData appendData:xData];
    [publicKeyData appendData:yData];

    NSDictionary *attrs = @{
        (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
        (__bridge id)kSecAttrKeyClass: (__bridge id)kSecAttrKeyClassPublic,
        (__bridge id)kSecAttrKeySizeInBits: @256
    };

    CFErrorRef keyError = NULL;
    SecKeyRef publicKey = SecKeyCreateWithData((__bridge CFDataRef)publicKeyData,
                                               (__bridge CFDictionaryRef)attrs,
                                               &keyError);
    if (!publicKey) {
        if (error) {
            if (keyError) {
                *error = CFBridgingRelease(keyError);
            } else {
                *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                             code:OAuth2ErrorServerError
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to create EC public key"}];
            }
        } else if (keyError) {
            CFRelease(keyError);
        }
        return nil;
    }
    if (keyError) CFRelease(keyError);
    return publicKey;
}

+ (NSDictionary *)publicJWKFromJWK:(NSDictionary *)jwk {
    NSMutableDictionary *publicJWK = [jwk mutableCopy];
    [publicJWK removeObjectForKey:@"d"];
    [publicJWK removeObjectForKey:@"p"];
    [publicJWK removeObjectForKey:@"q"];
    [publicJWK removeObjectForKey:@"dp"];
    [publicJWK removeObjectForKey:@"dq"];
    [publicJWK removeObjectForKey:@"qi"];
    return publicJWK;
}

+ (nullable NSString *)jsonStringForValue:(NSString *)value {
    NSData *data = [NSJSONSerialization dataWithJSONObject:@[value] options:0 error:nil];
    if (!data) return nil;
    NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (json.length < 2) return nil;
    return [json substringWithRange:NSMakeRange(1, json.length - 2)];
}

+ (nullable NSString *)jwkThumbprint:(NSDictionary *)jwk error:(NSError **)error {
    NSString *kty = jwk[@"kty"];
    NSDictionary *thumbprintJWK = nil;
    if ([kty isEqualToString:@"EC"]) {
        NSString *crv = jwk[@"crv"];
        NSString *x = jwk[@"x"];
        NSString *y = jwk[@"y"];
        if (!crv || !x || !y) {
            if (error) {
                *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                             code:OAuth2ErrorInvalidRequest
                                         userInfo:@{NSLocalizedDescriptionKey: @"Missing EC JWK members for thumbprint"}];
            }
            return nil;
        }
        thumbprintJWK = @{@"crv": crv, @"kty": @"EC", @"x": x, @"y": y};
    } else if ([kty isEqualToString:@"RSA"]) {
        NSString *n = jwk[@"n"];
        NSString *e = jwk[@"e"];
        if (!n || !e) {
            if (error) {
                *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                             code:OAuth2ErrorInvalidRequest
                                         userInfo:@{NSLocalizedDescriptionKey: @"Missing RSA JWK members for thumbprint"}];
            }
            return nil;
        }
        thumbprintJWK = @{@"e": e, @"kty": @"RSA", @"n": n};
    } else {
        if (error) {
            *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                         code:OAuth2ErrorInvalidRequest
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unsupported JWK key type"}];
        }
        return nil;
    }

    NSArray<NSString *> *keys = [[thumbprintJWK allKeys] sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray<NSString *> *components = [NSMutableArray arrayWithCapacity:keys.count];
    for (NSString *key in keys) {
        NSString *keyJSON = [self jsonStringForValue:key];
        NSString *valueJSON = [self jsonStringForValue:thumbprintJWK[key]];
        if (!keyJSON || !valueJSON) {
            if (error) {
                *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                             code:OAuth2ErrorServerError
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to encode JWK thumbprint"}];
            }
            return nil;
        }
        [components addObject:[NSString stringWithFormat:@"%@:%@", keyJSON, valueJSON]];
    }

    NSString *canonicalJSON = [NSString stringWithFormat:@"{%@}", [components componentsJoinedByString:@","]];
    NSData *data = [canonicalJSON dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, hash);
    NSData *hashData = [NSData dataWithBytes:hash length:CC_SHA256_DIGEST_LENGTH];
    return [JWT base64URLEncodeData:hashData error:error];
}

+ (BOOL)readASN1Length:(const uint8_t *)bytes
                length:(size_t)length
                offset:(size_t *)offset
             outLength:(size_t *)outLength
                 error:(NSError **)error {
    if (*offset >= length) {
        if (error) {
            *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                         code:OAuth2ErrorInvalidRequest
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid ASN.1 length"}];
        }
        return NO;
    }
    uint8_t first = bytes[(*offset)++];
    if ((first & 0x80) == 0) {
        *outLength = first;
        return YES;
    }
    size_t byteCount = first & 0x7F;
    if (byteCount == 0 || byteCount > sizeof(size_t) || *offset + byteCount > length) {
        if (error) {
            *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                         code:OAuth2ErrorInvalidRequest
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid ASN.1 length"}];
        }
        return NO;
    }
    size_t value = 0;
    for (size_t i = 0; i < byteCount; i++) {
        value = (value << 8) | bytes[(*offset)++];
    }
    *outLength = value;
    return YES;
}

+ (nullable NSData *)ecdsaRawSignatureFromDER:(NSData *)der
                                expectedSize:(size_t)expectedSize
                                       error:(NSError **)error {
    const uint8_t *bytes = der.bytes;
    size_t length = der.length;
    size_t offset = 0;
    if (length < 8 || bytes[offset++] != 0x30) {
        if (error) {
            *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                         code:OAuth2ErrorInvalidRequest
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid ECDSA signature"}];
        }
        return nil;
    }
    size_t seqLen = 0;
    if (![self readASN1Length:bytes length:length offset:&offset outLength:&seqLen error:error]) {
        return nil;
    }
    if (offset + seqLen > length) {
        if (error) {
            *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                         code:OAuth2ErrorInvalidRequest
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid ECDSA signature length"}];
        }
        return nil;
    }
    if (bytes[offset++] != 0x02) {
        if (error) {
            *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                         code:OAuth2ErrorInvalidRequest
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid ECDSA signature"}];
        }
        return nil;
    }
    size_t rLen = 0;
    if (![self readASN1Length:bytes length:length offset:&offset outLength:&rLen error:error]) {
        return nil;
    }
    if (offset + rLen > length) {
        if (error) {
            *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                         code:OAuth2ErrorInvalidRequest
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid ECDSA signature"}];
        }
        return nil;
    }
    const uint8_t *rBytes = bytes + offset;
    offset += rLen;
    if (bytes[offset++] != 0x02) {
        if (error) {
            *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                         code:OAuth2ErrorInvalidRequest
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid ECDSA signature"}];
        }
        return nil;
    }
    size_t sLen = 0;
    if (![self readASN1Length:bytes length:length offset:&offset outLength:&sLen error:error]) {
        return nil;
    }
    if (offset + sLen > length) {
        if (error) {
            *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                         code:OAuth2ErrorInvalidRequest
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid ECDSA signature"}];
        }
        return nil;
    }
    const uint8_t *sBytes = bytes + offset;

    while (rLen > 0 && rBytes[0] == 0x00) {
        rBytes++;
        rLen--;
    }
    while (sLen > 0 && sBytes[0] == 0x00) {
        sBytes++;
        sLen--;
    }
    if (rLen > expectedSize || sLen > expectedSize) {
        if (error) {
            *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                         code:OAuth2ErrorInvalidRequest
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid ECDSA signature size"}];
        }
        return nil;
    }

    NSMutableData *raw = [NSMutableData dataWithLength:expectedSize * 2];
    uint8_t *rawBytes = raw.mutableBytes;
    memcpy(rawBytes + (expectedSize - rLen), rBytes, rLen);
    memcpy(rawBytes + expectedSize + (expectedSize - sLen), sBytes, sLen);
    return raw;
}

+ (nullable NSData *)ecdsaDERSignatureFromRaw:(NSData *)raw error:(NSError **)error {
    if (raw.length % 2 != 0) {
        if (error) {
            *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                         code:OAuth2ErrorInvalidRequest
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid ECDSA raw signature"}];
        }
        return nil;
    }

    NSUInteger half = raw.length / 2;
    NSData *rData = [raw subdataWithRange:NSMakeRange(0, half)];
    NSData *sData = [raw subdataWithRange:NSMakeRange(half, half)];

    NSMutableData *r = [rData mutableCopy];
    while (r.length > 0 && ((const uint8_t *)r.bytes)[0] == 0x00) {
        [r replaceBytesInRange:NSMakeRange(0, 1) withBytes:NULL length:0];
    }
    if (r.length == 0 || (((const uint8_t *)r.bytes)[0] & 0x80)) {
        uint8_t zero = 0x00;
        [r replaceBytesInRange:NSMakeRange(0, 0) withBytes:&zero length:1];
    }

    NSMutableData *s = [sData mutableCopy];
    while (s.length > 0 && ((const uint8_t *)s.bytes)[0] == 0x00) {
        [s replaceBytesInRange:NSMakeRange(0, 1) withBytes:NULL length:0];
    }
    if (s.length == 0 || (((const uint8_t *)s.bytes)[0] & 0x80)) {
        uint8_t zero = 0x00;
        [s replaceBytesInRange:NSMakeRange(0, 0) withBytes:&zero length:1];
    }

    NSMutableData *sequence = [NSMutableData data];
    uint8_t seqTag = 0x30;
    [sequence appendBytes:&seqTag length:1];

    NSMutableData *content = [NSMutableData data];
    uint8_t intTag = 0x02;
    [content appendBytes:&intTag length:1];
    uint8_t rLen = (uint8_t)r.length;
    [content appendBytes:&rLen length:1];
    [content appendData:r];
    [content appendBytes:&intTag length:1];
    uint8_t sLen = (uint8_t)s.length;
    [content appendBytes:&sLen length:1];
    [content appendData:s];

    uint8_t seqLen = (uint8_t)content.length;
    [sequence appendBytes:&seqLen length:1];
    [sequence appendData:content];
    return sequence;
}

+ (nullable NSString *)createProofForURL:(NSURL *)url
                                method:(NSString *)method
                                  key:(NSDictionary *)jwk
                                 error:(NSError **)error {
    NSString *kty = jwk[@"kty"];
    NSString *alg = jwk[@"alg"];
    if (!alg && [kty isEqualToString:@"EC"]) {
        alg = @"ES256";
    }
    if (![kty isEqualToString:@"EC"] || ![alg isEqualToString:@"ES256"]) {
        if (error) {
            *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                         code:OAuth2ErrorInvalidRequest
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unsupported DPoP key type"}];
        }
        return nil;
    }

    NSMutableDictionary *header = [NSMutableDictionary dictionary];
    header[@"typ"] = @"dpop+jwt";
    header[@"alg"] = alg;
    header[@"jwk"] = [self publicJWKFromJWK:jwk];
    if (jwk[@"kid"]) header[@"kid"] = jwk[@"kid"];

    NSData *headerData = [NSJSONSerialization dataWithJSONObject:header options:0 error:error];
    if (!headerData) return nil;

    NSString *headerEncoded = [JWT base64URLEncodeData:headerData error:error];
    if (!headerEncoded) return nil;

    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    components.fragment = nil;
    NSString *normalizedHTU = components.URL.absoluteString ?: url.absoluteString;
    NSString *normalizedMethod = [method uppercaseString];

    NSMutableDictionary *claims = [NSMutableDictionary dictionary];
    claims[@"jti"] = [[NSUUID UUID] UUIDString];
    claims[@"htm"] = normalizedMethod;
    claims[@"htu"] = normalizedHTU;
    claims[@"iat"] = @([[NSDate date] timeIntervalSince1970]);

    NSData *claimsData = [NSJSONSerialization dataWithJSONObject:claims options:0 error:error];
    if (!claimsData) return nil;

    NSString *claimsEncoded = [JWT base64URLEncodeData:claimsData error:error];
    if (!claimsEncoded) return nil;

    NSString *signingInput = [NSString stringWithFormat:@"%@.%@", headerEncoded, claimsEncoded];
    NSError *keyError = nil;
    SecKeyRef privateKey = [self createPrivateKeyFromJWK:jwk error:&keyError];
    if (!privateKey) {
        if (error) *error = keyError;
        return nil;
    }

    CFErrorRef signError = NULL;
    NSData *signatureData = CFBridgingRelease(SecKeyCreateSignature(privateKey,
                                                                    kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
                                                                    (__bridge CFDataRef)[signingInput dataUsingEncoding:NSUTF8StringEncoding],
                                                                    &signError));
    CFRelease(privateKey);

    if (signError || !signatureData) {
        if (error) {
            if (signError) {
                *error = CFBridgingRelease(signError);
            } else {
                *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                             code:OAuth2ErrorServerError
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to sign DPoP proof"}];
            }
        } else if (signError) {
            CFRelease(signError);
        }
        return nil;
    }

    NSData *rawSignature = [self ecdsaRawSignatureFromDER:signatureData expectedSize:32 error:error];
    if (!rawSignature) return nil;

    NSString *signatureEncoded = [JWT base64URLEncodeData:rawSignature error:error];
    if (!signatureEncoded) return nil;

    return [NSString stringWithFormat:@"%@.%@.%@", headerEncoded, claimsEncoded, signatureEncoded];
}

+ (BOOL)verifyProof:(NSString *)dpopJwt
             method:(NSString *)method
                url:(NSURL *)url
              nonce:(nullable NSString *)nonce
      outThumbprint:(NSString * _Nullable * _Nullable)thumbprint
              error:(NSError **)error {
    NSArray<NSString *> *parts = [dpopJwt componentsSeparatedByString:@"."];
    if (parts.count != 3) {
        if (error) {
            *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                         code:OAuth2ErrorInvalidDPoPProof
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid DPoP format"}];
        }
        return NO;
    }

    NSError *decodeError = nil;
    NSData *headerData = [self decodeBase64URL:parts[0] error:&decodeError];
    NSData *payloadData = [self decodeBase64URL:parts[1] error:&decodeError];
    NSData *signatureData = [self decodeBase64URL:parts[2] error:&decodeError];
    if (!headerData || !payloadData || !signatureData) {
        if (error) *error = decodeError;
        return NO;
    }

    NSDictionary *header = [NSJSONSerialization JSONObjectWithData:headerData options:0 error:&decodeError];
    NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:payloadData options:0 error:&decodeError];
    if (!header || !payload) {
        if (error) *error = decodeError;
        return NO;
    }

    NSString *typ = header[@"typ"];
    NSString *alg = header[@"alg"];
    NSDictionary *jwk = header[@"jwk"];
    if (![typ isEqualToString:@"dpop+jwt"] || ![alg isEqualToString:@"ES256"] || ![jwk isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                         code:OAuth2ErrorInvalidDPoPProof
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid DPoP header"}];
        }
        return NO;
    }

    NSString *htm = payload[@"htm"];
    NSString *htu = payload[@"htu"];
    NSString *jti = payload[@"jti"];
    NSNumber *iat = payload[@"iat"];
    if (!htm || !htu || !jti || !iat) {
        if (error) {
            *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                         code:OAuth2ErrorInvalidDPoPProof
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing DPoP claims"}];
        }
        return NO;
    }

    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    components.fragment = nil;
    NSString *expectedHTU = components.URL.absoluteString ?: url.absoluteString;

    NSString *normalizedMethod = [method uppercaseString];
    if (![htm isEqualToString:normalizedMethod]) {
        if (error) {
            *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                         code:OAuth2ErrorInvalidDPoPProof
                                     userInfo:@{NSLocalizedDescriptionKey: @"DPoP htm mismatch"}];
        }
        return NO;
    }

    if (![htu isEqualToString:expectedHTU]) {
        NSURLComponents *payloadComponents = [NSURLComponents componentsWithString:htu];
        if (!payloadComponents ||
            ![payloadComponents.scheme.lowercaseString isEqualToString:components.scheme.lowercaseString] ||
            ![payloadComponents.host.lowercaseString isEqualToString:components.host.lowercaseString] ||
            ![payloadComponents.path isEqualToString:components.path] ||
            ![(payloadComponents.query ?: @"") isEqualToString:(components.query ?: @"")]) {
            if (error) {
                *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                             code:OAuth2ErrorInvalidDPoPProof
                                         userInfo:@{NSLocalizedDescriptionKey: @"DPoP htu mismatch"}];
            }
            return NO;
        }
    }

    if (nonce && ![nonce isEqualToString:payload[@"nonce"]]) {
        if (error) {
            *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                         code:OAuth2ErrorInvalidDPoPProof
                                     userInfo:@{NSLocalizedDescriptionKey: @"DPoP nonce mismatch"}];
        }
        return NO;
    }

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (iat.doubleValue > now + 60) {
        if (error) {
            *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                         code:OAuth2ErrorInvalidDPoPProof
                                     userInfo:@{NSLocalizedDescriptionKey: @"DPoP iat in future"}];
        }
        return NO;
    }

    NSNumber *exp = payload[@"exp"];
    if (exp && exp.doubleValue < now) {
        if (error) {
            *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                         code:OAuth2ErrorInvalidDPoPProof
                                     userInfo:@{NSLocalizedDescriptionKey: @"DPoP proof expired"}];
        }
        return NO;
    }

    SecKeyRef publicKey = [self createPublicKeyFromJWK:jwk error:error];
    if (!publicKey) return NO;

    NSData *derSignature = [self ecdsaDERSignatureFromRaw:signatureData error:error];
    if (!derSignature) {
        CFRelease(publicKey);
        return NO;
    }

    NSString *signingInput = [NSString stringWithFormat:@"%@.%@", parts[0], parts[1]];
    NSData *signingData = [signingInput dataUsingEncoding:NSUTF8StringEncoding];
    BOOL verified = SecKeyVerifySignature(publicKey,
                                          kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
                                          (__bridge CFDataRef)signingData,
                                          (__bridge CFDataRef)derSignature,
                                          NULL);
    CFRelease(publicKey);
    if (!verified) {
        if (error) {
            *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                         code:OAuth2ErrorInvalidDPoPProof
                                     userInfo:@{NSLocalizedDescriptionKey: @"DPoP signature verification failed"}];
        }
        return NO;
    }

    if (thumbprint) {
        *thumbprint = [self jwkThumbprint:jwk error:error];
        if (!*thumbprint) {
            return NO;
        }
    }

    return YES;
}

@end

@implementation OAuth2Server

- (instancetype)initWithDatabase:(PDSDatabase *)database {
    self = [super init];
    if (self) {
        _authorizationCodes = [NSMutableDictionary dictionary];
        _activeSessions = [NSMutableDictionary dictionary];
        _authorizationQueue = dispatch_queue_create("com.atproto.oauth2.authorization", DISPATCH_QUEUE_SERIAL);
        _sessionQueue = dispatch_queue_create("com.atproto.oauth2.session", DISPATCH_QUEUE_SERIAL);
        _jwtMinter = [[JWTMinter alloc] init];
        _keyManager = [[KeyManager alloc] init];
        _didResolver = [[DIDResolver alloc] init];
        _handleResolver = [[HandleResolver alloc] init];
        _database = database;

        NSError *keyError;
        Secp256k1KeyPair *keyPair = [Secp256k1KeyPair generateKeyPair:&keyError];
        if (keyPair) {
            _jwtMinter.privateKey = keyPair.privateKey;
        } else {
            PDS_LOG_AUTH_ERROR(@"Failed to generate JWT signing key: %@", keyError);
        }
    }
    return self;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _authorizationCodes = [NSMutableDictionary dictionary];
        _activeSessions = [NSMutableDictionary dictionary];
        _authorizationQueue = dispatch_queue_create("com.atproto.oauth2.authorization", DISPATCH_QUEUE_SERIAL);
        _sessionQueue = dispatch_queue_create("com.atproto.oauth2.session", DISPATCH_QUEUE_SERIAL);
        _jwtMinter = [[JWTMinter alloc] init];
        _keyManager = [[KeyManager alloc] init];
        _didResolver = [[DIDResolver alloc] init];
        _handleResolver = [[HandleResolver alloc] init];
        NSURL *dbURL = [[NSURL fileURLWithPath:NSHomeDirectory()] URLByAppendingPathComponent:@".gemini/pds.db"];
        _database = [PDSDatabase databaseAtURL:dbURL];
        [_database openWithError:nil];

        NSError *keyError;
        Secp256k1KeyPair *keyPair = [Secp256k1KeyPair generateKeyPair:&keyError];
        if (keyPair) {
            _jwtMinter.privateKey = keyPair.privateKey;
        } else {
            PDS_LOG_AUTH_ERROR(@"Failed to generate JWT signing key: %@", keyError);
        }
    }
    return self;
}

#pragma mark - Thread-Safe Authorization Code Access

- (void)storeAuthorizationCode:(NSString *)code data:(NSDictionary *)codeData {
    dispatch_sync(self.authorizationQueue, ^{
        self.authorizationCodes[code] = codeData;
    });
}

- (nullable NSDictionary *)getAuthorizationCodeData:(NSString *)code {
    __block NSDictionary *result = nil;
    dispatch_sync(self.authorizationQueue, ^{
        result = [self.authorizationCodes[code] copy];
    });
    return result;
}

- (void)removeAuthorizationCode:(NSString *)code {
    dispatch_sync(self.authorizationQueue, ^{
        [self.authorizationCodes removeObjectForKey:code];
    });
}

- (void)handleAuthorizationRequest:(OAuth2AuthorizationRequest *)request
                        completion:(OAuth2AuthorizationCompletion)completion {
    if (!request.clientID || !request.redirectURI || !request.responseType) {
        NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                             code:OAuth2ErrorInvalidRequest
                                         userInfo:@{NSLocalizedDescriptionKey: @"Missing required parameters"}];
        completion(nil, nil, error);
        return;
    }

    if (![request.responseType isEqualToString:@"code"]) {
        NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                             code:OAuth2ErrorUnsupportedResponseType
                                         userInfo:@{NSLocalizedDescriptionKey: @"Only 'code' response type is supported"}];
        completion(nil, nil, error);
        return;
    }

    NSString *code = [[NSUUID UUID] UUIDString];
    NSMutableDictionary *codeData = [NSMutableDictionary dictionary];
    codeData[@"client_id"] = request.clientID;
    codeData[@"redirect_uri"] = request.redirectURI;
    if (request.scope) codeData[@"scope"] = request.scope;
    if (request.state) codeData[@"state"] = request.state;
    if (request.codeChallenge) codeData[@"code_challenge"] = request.codeChallenge;
    if (request.codeChallengeMethod) codeData[@"code_challenge_method"] = request.codeChallengeMethod;
    if (request.nonce) codeData[@"nonce"] = request.nonce;
    if (request.dpopJWK) codeData[@"dpop_jwk"] = request.dpopJWK;
    if (request.loginHint) {
        codeData[@"login_hint"] = request.loginHint;
        NSError *resolveError = nil;
        NSString *did = [self resolveIdentity:request.loginHint error:&resolveError];
        if (did) {
            codeData[@"login_hint_did"] = did;
        } else {
            PDS_LOG_AUTH_WARN(@"Failed to resolve login_hint for authorization request (client_id=%@): %@",
                              request.clientID ?: @"",
                              resolveError.localizedDescription ?: @"unknown error");
        }
    }
    codeData[@"created_at"] = @([[NSDate date] timeIntervalSince1970]);

    [self storeAuthorizationCode:code data:codeData];

    PDS_LOG_AUTH_DEBUG(@"Stored authorization code (client_id=%@, has_pkce=%@, has_dpop_jwk=%@, has_login_hint=%@)",
                       request.clientID ?: @"",
                       @(request.codeChallenge.length > 0),
                       @(request.dpopJWK != nil),
                       @(request.loginHint.length > 0));

    NSMutableString *authURL = [request.authorizationURL.absoluteString mutableCopy];
    NSString *separator = [authURL containsString:@"?"] ? @"&" : @"?";
    [authURL appendFormat:@"%@code=%@", separator, code];

    completion([NSURL URLWithString:authURL], code, nil);
}

- (void)handleTokenRequest:(OAuth2TokenRequest *)request
                completion:(OAuth2TokenCompletion)completion {
    if ([request.grantType isEqualToString:@"authorization_code"]) {
        [self processAuthorizationCodeGrant:request completion:completion];
    } else if ([request.grantType isEqualToString:@"refresh_token"]) {
        [self processRefreshTokenGrant:request completion:completion];
    } else if ([request.grantType isEqualToString:@"urn:ietf:params:oauth:grant-type:dpop"]) {
        [self processDPoPGrant:request completion:completion];
    } else {
        NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                             code:OAuth2ErrorUnsupportedGrantType
                                         userInfo:@{NSLocalizedDescriptionKey: @"Unsupported grant type"}];
        completion(nil, error);
    }
}

- (void)processAuthorizationCodeGrant:(OAuth2TokenRequest *)request
                          completion:(OAuth2TokenCompletion)completion {
    NSDictionary *codeData = [self getAuthorizationCodeData:request.code];
    if (!codeData) {
        PDS_LOG_AUTH_WARN(@"Authorization code not found or expired (client_id=%@)", request.clientID ?: @"");
        NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                             code:OAuth2ErrorInvalidGrant
                                         userInfo:@{NSLocalizedDescriptionKey: @"Invalid or expired authorization code"}];
        completion(nil, error);
        return;
    }

    PDS_LOG_AUTH_DEBUG(@"Processing token request (grant_type=%@, client_id=%@, has_code=%@, has_code_verifier=%@)",
                       request.grantType ?: @"",
                       request.clientID ?: @"",
                       @(request.code.length > 0),
                       @(request.codeVerifier.length > 0));

    NSTimeInterval codeAge = [[NSDate date] timeIntervalSince1970] - [codeData[@"created_at"] doubleValue];
    if (codeAge > 600) {
        [self removeAuthorizationCode:request.code];
        NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                             code:OAuth2ErrorInvalidGrant
                                         userInfo:@{NSLocalizedDescriptionKey: @"Authorization code expired"}];
        completion(nil, error);
        return;
    }

    if (![codeData[@"client_id"] isEqualToString:request.clientID]) {
        NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                             code:OAuth2ErrorInvalidGrant
                                         userInfo:@{NSLocalizedDescriptionKey: @"Client ID mismatch"}];
        completion(nil, error);
        return;
    }

    if (request.codeVerifier && codeData[@"code_challenge"]) {
        NSString *expectedChallenge = codeData[@"code_challenge"];
        NSString *method = codeData[@"code_challenge_method"] ?: @"plain";

        // URL-decode the code_verifier since browsers send it encoded
        NSString *codeVerifier = [request.codeVerifier stringByRemovingPercentEncoding];
        if (!codeVerifier) {
            codeVerifier = request.codeVerifier;
        }

        PDS_LOG_AUTH_DEBUG(@"Verifying PKCE (client_id=%@, method=%@, verifier_len=%lu, challenge_len=%lu)",
                           request.clientID ?: @"",
                           method ?: @"plain",
                           (unsigned long)codeVerifier.length,
                           (unsigned long)expectedChallenge.length);

        if (![self verifyCodeVerifier:codeVerifier challenge:expectedChallenge method:method]) {
            NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                                 code:OAuth2ErrorInvalidGrant
                                             userInfo:@{NSLocalizedDescriptionKey: @"Invalid code verifier"}];
            completion(nil, error);
            return;
        }
        PDS_LOG_AUTH_DEBUG(@"PKCE verification passed (client_id=%@)", request.clientID ?: @"");
    }

    [self removeAuthorizationCode:request.code];

    NSString *did = codeData[@"login_hint_did"];
    if (!did) {
        PDS_LOG_AUTH_ERROR(@"Authorization code missing login_hint_did (client_id=%@)", request.clientID ?: @"");
        NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                             code:OAuth2ErrorInvalidGrant
                                         userInfo:@{NSLocalizedDescriptionKey: @"Missing user identity in authorization code"}];
        completion(nil, error);
        return;
    }
    
    // Check 2FA Status
    NSError *dbError = nil;
    PDSDatabaseAccount *account = [self.database getAccountByDid:did error:&dbError];
    
    if (account && account.tfaEnabled) {
        if (!request.tfaCode) {
             NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                                  code:OAuth2ErrorInteractionRequired
                                              userInfo:@{NSLocalizedDescriptionKey: @"Two-factor authentication code required", @"error": @"mfa_required"}];
             completion(nil, error);
             return;
        }
        
        // Verify Code
        NSString *secret = [Base32Utils base32StringFromData:account.tfaSecret];
        BOOL valid = [TOTPService verifyCode:request.tfaCode secret:secret];
        if (!valid) {
            NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                                  code:OAuth2ErrorInvalidGrant
                                              userInfo:@{NSLocalizedDescriptionKey: @"Invalid 2FA code"}];
            completion(nil, error);
            return;
        }
    }

    NSString *handle = account.handle ?: @"handle.placeholder";
    NSString *scope = codeData[@"scope"] ?: OAuth2ScopeIdentify;

    if (!request.dpopKeyThumbprint || request.dpopKeyThumbprint.length == 0) {
        NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                             code:OAuth2ErrorInvalidDPoPProof
                                         userInfo:@{NSLocalizedDescriptionKey: @"Missing DPoP key thumbprint"}];
        completion(nil, error);
        return;
    }

    Session *session = [self createSessionForDID:did
                                          handle:handle
                                           scope:scope
                               dpopKeyThumbprint:request.dpopKeyThumbprint];

    completion(session, nil);
}

- (void)processRefreshTokenGrant:(OAuth2TokenRequest *)request
                      completion:(OAuth2TokenCompletion)completion {
    Session *existingSession = nil;
    for (Session *session in self.activeSessions.allValues) {
        if ([session.refreshToken isEqualToString:request.refreshToken]) {
            existingSession = session;
            break;
        }
    }

    if (!existingSession) {
        NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                             code:OAuth2ErrorInvalidGrant
                                         userInfo:@{NSLocalizedDescriptionKey: @"Invalid refresh token"}];
        completion(nil, error);
        return;
    }

    if ([existingSession.refreshTokenExpiresAt compare:[NSDate date]] == NSOrderedAscending) {
        [self.activeSessions removeObjectForKey:existingSession.sessionID];
        NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                             code:OAuth2ErrorTokenExpired
                                         userInfo:@{NSLocalizedDescriptionKey: @"Refresh token expired"}];
        completion(nil, error);
        return;
    }

    NSString *newScope = request.scope ?: existingSession.scope;
    Session *newSession = [self createSessionForDID:existingSession.did
                                             handle:existingSession.handle
                                              scope:newScope
                                  dpopKeyThumbprint:nil];

    [self.activeSessions removeObjectForKey:existingSession.sessionID];

    completion(newSession, nil);
}

- (void)processDPoPGrant:(OAuth2TokenRequest *)request
              completion:(OAuth2TokenCompletion)completion {
    Session *existingSession = [self getSessionByAccessToken:request.accessToken];
    if (!existingSession) {
        NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                             code:OAuth2ErrorInvalidGrant
                                         userInfo:@{NSLocalizedDescriptionKey: @"Invalid or expired access token"}];
        completion(nil, error);
        return;
    }

    NSString *newAccessToken = [existingSession refreshAccessToken];
    if (request.dpopKeyThumbprint) {
        existingSession.dpopKeyThumbprint = request.dpopKeyThumbprint;
    }

    completion(existingSession, nil);
}

- (nullable Session *)getSessionByAccessToken:(NSString *)accessToken {
    for (Session *session in self.activeSessions.allValues) {
        if ([session.accessToken isEqualToString:accessToken]) {
            return session;
        }
    }
    return nil;
}

- (Session *)createSessionForDID:(NSString *)did
                          handle:(NSString *)handle
                           scope:(NSString *)scope
               dpopKeyThumbprint:(nullable NSString *)dpopKeyThumbprint {
    Session *session = [[Session alloc] initWithDID:did
                                             handle:handle
                                              scope:scope
                                             minter:self.jwtMinter];

    if (dpopKeyThumbprint) {
        session.dpopKeyThumbprint = dpopKeyThumbprint;
    }

    self.activeSessions[session.sessionID] = session;

    return session;
}

- (BOOL)verifyCodeVerifier:(NSString *)verifier challenge:(NSString *)challenge method:(NSString *)method {
    if ([method isEqualToString:@"plain"]) {
        return [verifier isEqualToString:challenge];
    }
    if ([method isEqualToString:@"S256"]) {
        NSData *verifierData = [verifier dataUsingEncoding:NSUTF8StringEncoding];
        unsigned char hash[CC_SHA256_DIGEST_LENGTH];
        CC_SHA256(verifierData.bytes, (CC_LONG)verifierData.length, hash);
        NSData *hashData = [NSData dataWithBytes:hash length:CC_SHA256_DIGEST_LENGTH];
        NSString *base64Hash = [self base64URLEncodeData:hashData];
        return [base64Hash isEqualToString:challenge];
    }
    return NO;
}

- (NSString *)base64URLEncodeData:(NSData *)data {
    NSString *base64 = [data base64EncodedStringWithOptions:0];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"=" withString:@""];
    return base64;
}

- (void)refreshAccessToken:(NSString *)refreshToken
                     scope:(nullable NSString *)scope
                   dpopJWK:(nullable NSDictionary *)dpopJWK
                completion:(OAuth2RefreshCompletion)completion {
    // Find session with this refresh token
    Session *foundSession = nil;
    for (Session *session in self.activeSessions.allValues) {
        if ([session.refreshToken isEqualToString:refreshToken]) {
            foundSession = session;
            break;
        }
    }
    
    if (!foundSession) {
        NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                             code:OAuth2ErrorInvalidGrant
                                         userInfo:@{NSLocalizedDescriptionKey: @"Invalid refresh token"}];
        completion(nil, error);
        return;
    }
    
    // Check if refresh token is expired (assuming 30 days for now)
    if ([foundSession.createdAt timeIntervalSinceNow] < -30 * 24 * 60 * 60) {
        [self.activeSessions removeObjectForKey:foundSession.sessionID];
        NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                             code:OAuth2ErrorInvalidGrant
                                         userInfo:@{NSLocalizedDescriptionKey: @"Refresh token expired"}];
        completion(nil, error);
        return;
    }
    
    // Issue new access token and rotate refresh token
    NSString *newAccessToken = [foundSession refreshAccessToken];
    
    if (completion) {
        completion(newAccessToken, nil);
    }
}

#pragma mark - ATProto Identity Resolution

- (nullable NSString *)resolveIdentity:(NSString *)identity error:(NSError **)error {
    if (!identity || identity.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                         code:OAuth2ErrorInvalidRequest
                                     userInfo:@{NSLocalizedDescriptionKey: @"Empty identity"}];
        }
        return nil;
    }

    // Trim potential trailing '+' or spaces (common URL encoding artifacts)
    identity = [identity stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" +"]];
    BOOL isDID = [identity hasPrefix:@"did:"];
    BOOL looksLikeEmail = [identity containsString:@"@"];
    PDS_LOG_AUTH_DEBUG(@"Resolving identity (is_did=%@, looks_like_email=%@)", @(isDID), @(looksLikeEmail));

    // Check database is valid
    if (!self.database) {
        PDS_LOG_AUTH_ERROR(@"Database is nil during identity resolution");
        if (error) {
            *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                         code:OAuth2ErrorServerError
                                     userInfo:@{NSLocalizedDescriptionKey: @"Database not initialized"}];
        }
        return nil;
    }

    // Local optimization: check our own database for the handle first
    if (![identity hasPrefix:@"did:"]) {
        NSError *dbError = nil;
        PDSDatabaseAccount *account = [self.database getAccountByHandle:identity error:&dbError];
        if (dbError) {
            PDS_LOG_AUTH_ERROR(@"Database error looking up handle: %@", dbError.localizedDescription ?: @"unknown error");
        }
        if (account) {
            PDS_LOG_AUTH_DEBUG(@"Found local account for handle (did=%@)", account.did ?: @"");
            return account.did;
        }
        PDS_LOG_AUTH_DEBUG(@"Account not found for handle in local database");
    }

    // Check if it's already a DID
    if ([identity hasPrefix:@"did:"]) {
        // Validate DID format and resolve to ensure it exists
        DIDDocument *doc = [self.didResolver resolveDIDSync:identity error:error];
        return doc ? identity : nil;
    } else {
        // It's a handle - resolve to DID
        __block NSString *resolvedDID = nil;
        __block NSError *resolveError = nil;

        PDS_LOG_AUTH_DEBUG(@"Resolving handle via HandleResolver");
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

        [self.handleResolver resolveHandle:identity completion:^(NSString * _Nullable did, NSError * _Nullable err) {
            resolvedDID = did;
            resolveError = err;
            dispatch_semaphore_signal(semaphore);
        }];

        if (dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC)) != 0) {
            PDS_LOG_AUTH_ERROR(@"Handle resolution timeout");
            if (error) *error = [NSError errorWithDomain:OAuth2ErrorDomain code:OAuth2ErrorServerError userInfo:@{NSLocalizedDescriptionKey: @"Identity resolution timeout"}];
            return nil;
        }

        PDS_LOG_AUTH_DEBUG(@"Handle resolution completed (resolved_did_present=%@)", @(resolvedDID.length > 0));

        if (resolveError) {
            if (error) *error = resolveError;
            return nil;
        }

        // Verify bidirectional resolution (ATProto requirement)
        if (resolvedDID) {
            NSDictionary *atprotoData = [self.didResolver resolveAtprotoDataForDID:resolvedDID error:error];
            NSString *verifiedHandle = atprotoData[@"handle"];

            if (verifiedHandle && ![verifiedHandle isEqualToString:identity]) {
                PDS_LOG_AUTH_ERROR(@"Handle verification failed (mismatch)");
                if (error) {
                    *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                                 code:OAuth2ErrorInvalidRequest
                                             userInfo:@{NSLocalizedDescriptionKey: @"Handle verification failed"}];
                }
                return nil;
            }
        }

        return resolvedDID;
    }
}

@end
