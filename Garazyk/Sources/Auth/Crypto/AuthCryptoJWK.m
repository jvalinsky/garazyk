/*!
 @file AuthCryptoJWK.m

 @abstract JWK key operations implementation.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "Auth/Crypto/AuthCryptoJWK.h"
#import "Auth/Crypto/AuthCryptoBase64URL.h"
#import "Auth/Crypto/AuthCryptoECDSA.h"
#import "Auth/PDSKeyProtocol.h"

#if defined(__APPLE__) && !defined(GNUSTEP)
#import <Security/Security.h>
#import <CommonCrypto/CommonDigest.h>
#else
#import <openssl/sha.h>
#endif

#if !defined(__APPLE__) || defined(GNUSTEP)
#import "Auth/PDSOpenSSLES256KeyManager.h"
#endif

NSString * const AuthCryptoErrorDomain = @"com.atproto.auth.crypto";

// Protocol constants (needed for cross-platform)
PDSKeyAlgorithm const PDSKeyAlgorithmES256 = @"ES256";
PDSKeyAlgorithm const PDSKeyAlgorithmRS256 = @"RS256";

NSString * const PDSKeyErrorDomain = @"com.atproto.pds.key";

#pragma mark - SecKey Adapter Class (macOS only)

#if defined(__APPLE__) && !defined(GNUSTEP)

/**
 * Adapter class wrapping SecKeyRef to conform to PDSKeyProtocol.
 * Must be defined OUTSIDE AuthCryptoJWK implementation.
 */
@interface PDSSecKeyAdapter : NSObject <PDSPrivateKeyProtocol>
@property (nonatomic, assign) SecKeyRef secKey;
@property (nonatomic, assign) BOOL isPrivateKey;
@property (nonatomic, copy) NSString *keyID;
- (instancetype)initWithSecKey:(SecKeyRef)secKey isPrivateKey:(BOOL)isPrivateKey;
@end

@implementation PDSSecKeyAdapter

- (instancetype)initWithSecKey:(SecKeyRef)secKey isPrivateKey:(BOOL)isPrivateKey {
    self = [super init];
    if (self) {
        CFRetain(secKey);
        _secKey = secKey;
        _isPrivateKey = isPrivateKey;
        _keyID = [[NSUUID UUID] UUIDString];
    }
    return self;
}

- (void)dealloc {
    if (_secKey) {
        CFRelease(_secKey);
        _secKey = NULL;
    }
}

- (id)copyWithZone:(NSZone *)zone {
    PDSSecKeyAdapter *copy = [[PDSSecKeyAdapter alloc] initWithSecKey:_secKey isPrivateKey:_isPrivateKey];
    copy->_keyID = [_keyID copy];
    return copy;
}

- (PDSKeyAlgorithm)algorithm {
    return PDSKeyAlgorithmES256;
}

- (NSData *)publicKeyData {
    if (!_secKey) return nil;

    SecKeyRef pubKey = _isPrivateKey ? SecKeyCopyPublicKey(_secKey) : _secKey;
    if (!pubKey) return nil;

    CFErrorRef error = NULL;
    NSData *data = CFBridgingRelease(SecKeyCopyExternalRepresentation(pubKey, &error));
    if (_isPrivateKey && pubKey != _secKey) {
        CFRelease(pubKey);
    }
    return data;
}

- (NSDictionary *)publicKeyJWK {
    NSData *pubData = self.publicKeyData;
    if (!pubData || pubData.length != 65) return nil;

    NSData *xData = [pubData subdataWithRange:NSMakeRange(1, 32)];
    NSData *yData = [pubData subdataWithRange:NSMakeRange(33, 32)];

    NSString *kid = self.thumbprint ?: _keyID;
    return @{
        @"kty": @"EC",
        @"crv": @"P-256",
        @"x": [AuthCryptoBase64URL encode:xData],
        @"y": [AuthCryptoBase64URL encode:yData],
        @"kid": kid
    };
}

- (NSString *)thumbprint {
    NSDictionary *jwk = self.publicKeyJWK;
    NSDictionary *thumbprintJWK = @{
        @"crv": jwk[@"crv"],
        @"kty": jwk[@"kty"],
        @"x": jwk[@"x"],
        @"y": jwk[@"y"]
    };

    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:thumbprintJWK
                                                       options:NSJSONWritingSortedKeys
                                                         error:nil];
    if (!jsonData) return nil;

    unsigned char hash[32];
    CC_SHA256(jsonData.bytes, (CC_LONG)jsonData.length, hash);
    NSData *hashData = [NSData dataWithBytes:hash length:32];
    return [AuthCryptoBase64URL encode:hashData];
}

- (NSData *)signData:(NSData *)data error:(NSError **)error {
    if (!_secKey || !_isPrivateKey) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoErrorDomain
                                         code:PDSKeyErrorCodeSigningFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"No private key available"}];
        }
        return nil;
    }

    unsigned char hash[32];
    CC_SHA256(data.bytes, (CC_LONG)data.length, hash);
    NSData *hashData = [NSData dataWithBytes:hash length:32];

    CFErrorRef cfError = NULL;
    CFDataRef signature = SecKeyCreateSignature(_secKey,
                                                 kSecKeyAlgorithmECDSASignatureDigestX962SHA256,
                                                 (__bridge CFDataRef)hashData,
                                                 &cfError);
    if (!signature) {
        if (error) {
            *error = cfError ? CFBridgingRelease(cfError)
                : [NSError errorWithDomain:AuthCryptoErrorDomain
                                     code:PDSKeyErrorCodeSigningFailed
                                 userInfo:@{NSLocalizedDescriptionKey: @"Signing failed"}];
        } else if (cfError) {
            CFRelease(cfError);
        }
        return nil;
    }

    NSData *sigData = CFBridgingRelease(signature);

    // Convert DER to raw r||s format
    const uint8_t *der = sigData.bytes;
    if (der[0] != 0x30 || sigData.length < 8) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoErrorDomain
                                         code:PDSKeyErrorCodeSigningFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid DER signature format"}];
        }
        return nil;
    }

    int rLen = der[3];
    const uint8_t *rStart = &der[4];
    int sLen = der[4 + rLen + 1];
    const uint8_t *sStart = &der[4 + rLen + 2];

    NSMutableData *rawSig = [NSMutableData dataWithLength:64];
    uint8_t *raw = (uint8_t *)rawSig.mutableBytes;

    int rOffset = (rLen > 32) ? (rLen - 32) : 0;
    int rPad = (rLen < 32) ? (32 - rLen) : 0;
    memset(raw, 0, rPad);
    memcpy(raw + rPad, rStart + rOffset, MIN(32, rLen));

    int sOffset = (sLen > 32) ? (sLen - 32) : 0;
    int sPad = (sLen < 32) ? (32 - sLen) : 0;
    memset(raw + 32, 0, sPad);
    memcpy(raw + 32 + sPad, sStart + sOffset, MIN(32, sLen));

    return rawSig;
}

- (BOOL)verifySignature:(NSData *)signature
                forData:(NSData *)data
                  error:(NSError **)error {
    if (!_secKey) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoErrorDomain
                                         code:PDSKeyErrorCodeVerificationFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"No key available"}];
        }
    return NO;
    }

    unsigned char hash[32];
    CC_SHA256(data.bytes, (CC_LONG)data.length, hash);
    NSData *hashData = [NSData dataWithBytes:hash length:32];

    if (signature.length != 64) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoErrorDomain
                                         code:PDSKeyErrorCodeInvalidSignature
                                     userInfo:@{NSLocalizedDescriptionKey: @"Signature must be 64 bytes"}];
        }
        return NO;
    }

    // ATProto requires low-S signatures
    if (![AuthCryptoECDSA isLowS:signature error:error]) {
        return NO;
    }

    NSError *derError = nil;
    NSData *derSig = [AuthCryptoECDSA derSignatureFromRaw:signature error:&derError];
    if (!derSig) {
        if (error) {
            *error = derError ?: [NSError errorWithDomain:AuthCryptoErrorDomain
                                                     code:PDSKeyErrorCodeInvalidSignature
                                                 userInfo:@{NSLocalizedDescriptionKey: @"Invalid raw ECDSA signature"}];
        }
        return NO;
    }

    SecKeyRef pubKey = _isPrivateKey ? SecKeyCopyPublicKey(_secKey) : _secKey;
    if (!pubKey) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoErrorDomain
                                         code:PDSKeyErrorCodeVerificationFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"No public key available"}];
        }
        return NO;
    }

    CFErrorRef cfError = NULL;
    BOOL valid = SecKeyVerifySignature(pubKey,
                                       kSecKeyAlgorithmECDSASignatureDigestX962SHA256,
                                       (__bridge CFDataRef)hashData,
                                       (__bridge CFDataRef)derSig,
                                       &cfError);

    if (_isPrivateKey && pubKey != _secKey) {
        CFRelease(pubKey);
    }

    if (cfError) CFRelease(cfError);

    if (!valid && error) {
        *error = [NSError errorWithDomain:AuthCryptoErrorDomain
                                     code:PDSKeyErrorCodeVerificationFailed
                                 userInfo:@{NSLocalizedDescriptionKey: @"Signature verification failed"}];
    }

    return valid;
}

- (BOOL)verifyDigestSignature:(NSData *)signature
                       forHash:(NSData *)digest
                         error:(NSError **)error {
    if (!_secKey) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoErrorDomain
                                         code:PDSKeyErrorCodeVerificationFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"No key available"}];
        }
        return NO;
    }

    if (digest.length != 32) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoErrorDomain
                                         code:PDSKeyErrorCodeInvalidSignature
                                     userInfo:@{NSLocalizedDescriptionKey: @"Digest must be 32 bytes (SHA-256)"}];
        }
        return NO;
    }

    if (signature.length != 64) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoErrorDomain
                                         code:PDSKeyErrorCodeInvalidSignature
                                     userInfo:@{NSLocalizedDescriptionKey: @"Signature must be 64 bytes"}];
        }
        return NO;
    }

    // ATProto requires low-S signatures
    if (![AuthCryptoECDSA isLowS:signature error:error]) {
        return NO;
    }

    NSError *derError = nil;
    NSData *derSig = [AuthCryptoECDSA derSignatureFromRaw:signature error:&derError];
    if (!derSig) {
        if (error) {
            *error = derError ?: [NSError errorWithDomain:AuthCryptoErrorDomain
                                                     code:PDSKeyErrorCodeInvalidSignature
                                                 userInfo:@{NSLocalizedDescriptionKey: @"Invalid raw ECDSA signature"}];
        }
        return NO;
    }

    SecKeyRef pubKey = _isPrivateKey ? SecKeyCopyPublicKey(_secKey) : _secKey;
    if (!pubKey) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoErrorDomain
                                         code:PDSKeyErrorCodeVerificationFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"No public key available"}];
        }
        return NO;
    }

    CFErrorRef cfError = NULL;
    // Note: kSecKeyAlgorithmECDSASignatureDigestX962SHA256 expects the digest (not the message)
    BOOL valid = SecKeyVerifySignature(pubKey,
                                       kSecKeyAlgorithmECDSASignatureDigestX962SHA256,
                                       (__bridge CFDataRef)digest,
                                       (__bridge CFDataRef)derSig,
                                       &cfError);

    if (_isPrivateKey && pubKey != _secKey) {
        CFRelease(pubKey);
    }

    if (cfError) CFRelease(cfError);

    if (!valid && error) {
        *error = [NSError errorWithDomain:AuthCryptoErrorDomain
                                     code:PDSKeyErrorCodeVerificationFailed
                                 userInfo:@{NSLocalizedDescriptionKey: @"Digest signature verification failed"}];
    }

    return valid;
}

- (id<PDSPublicKeyProtocol>)publicKey {
    if (!_secKey) return nil;

    SecKeyRef pubKey = _isPrivateKey ? SecKeyCopyPublicKey(_secKey) : _secKey;
    if (!pubKey) return nil;

    PDSSecKeyAdapter *adapter = [[PDSSecKeyAdapter alloc] initWithSecKey:pubKey isPrivateKey:NO];
    if (_isPrivateKey) CFRelease(pubKey);
    return adapter;
}

- (NSDictionary *)privateKeyJWK {
    if (!_secKey || !_isPrivateKey) return nil;

    CFErrorRef error = NULL;
    NSData *keyData = CFBridgingRelease(SecKeyCopyExternalRepresentation(_secKey, &error));
    if (!keyData) {
        if (error) CFRelease(error);
        return nil;
    }

    NSMutableDictionary *jwk = [NSMutableDictionary dictionaryWithDictionary:self.publicKeyJWK];

    if (keyData.length == 97) {
        NSData *d = [keyData subdataWithRange:NSMakeRange(65, 32)];
        jwk[@"d"] = [AuthCryptoBase64URL encode:d];
    } else if (keyData.length == 32) {
        jwk[@"d"] = [AuthCryptoBase64URL encode:keyData];
    }

    return jwk;
}

@end

#endif // __APPLE__ && !GNUSTEP

#pragma mark - AuthCryptoJWK Implementation

@implementation AuthCryptoJWK

#pragma mark - JWK Thumbprint Operations

+ (nullable NSString *)thumbprint:(NSDictionary *)jwk error:(NSError **)error {
    NSString *kty = jwk[@"kty"];
    NSDictionary *thumbprintJWK = nil;

    if ([kty isEqualToString:@"EC"]) {
        NSString *crv = jwk[@"crv"];
        NSString *x = jwk[@"x"];
        NSString *y = jwk[@"y"];
        if (!crv || !x || !y) {
            if (error) {
                *error = [NSError errorWithDomain:AuthCryptoErrorDomain
                                             code:-1
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
                *error = [NSError errorWithDomain:AuthCryptoErrorDomain
                                             code:-1
                                         userInfo:@{NSLocalizedDescriptionKey: @"Missing RSA JWK members for thumbprint"}];
            }
            return nil;
        }
        thumbprintJWK = @{@"e": e, @"kty": @"RSA", @"n": n};
    } else {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoErrorDomain
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unsupported JWK key type for thumbprint"}];
        }
        return nil;
    }

    // Use NSJSONWritingSortedKeys for canonical JSON
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:thumbprintJWK
                                                       options:NSJSONWritingSortedKeys
                                                         error:nil];
    if (!jsonData) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoErrorDomain
                                         code:-2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to encode JWK thumbprint"}];
        }
        return nil;
    }

    unsigned char hash[32];
#if defined(__APPLE__) && !defined(GNUSTEP)
    CC_SHA256(jsonData.bytes, (CC_LONG)jsonData.length, hash);
#else
    SHA256(jsonData.bytes, jsonData.length, hash);
#endif

    NSData *hashData = [NSData dataWithBytes:hash length:32];
    return [AuthCryptoBase64URL encode:hashData];
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

#pragma mark - Protocol-based Key Operations (Cross-platform)

+ (nullable id<PDSPublicKeyProtocol>)publicKeyFromJWK:(NSDictionary *)jwk
                                                error:(NSError **)error {
    NSString *kty = jwk[@"kty"];
    if (![kty isEqualToString:@"EC"]) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoErrorDomain
                                         code:-3
                                     userInfo:@{NSLocalizedDescriptionKey: @"Only EC keys are supported"}];
        }
        return nil;
    }

#if defined(__APPLE__) && !defined(GNUSTEP)
    // macOS: Use Apple Security framework
    NSError *secError = nil;
    SecKeyRef secKey = [self createPublicKeyFromJWK:jwk error:&secError];
    if (!secKey) {
        if (error) *error = secError;
        return nil;
    }

    // Wrap in protocol adapter
    PDSSecKeyAdapter *adapter = [[PDSSecKeyAdapter alloc] initWithSecKey:secKey isPrivateKey:NO];
    CFRelease(secKey);
    return adapter;
#else
    // GNUstep: Use OpenSSL
    NSString *keyID = jwk[@"kid"] ?: [[NSUUID UUID] UUIDString];
    return [[PDSOpenSSLES256PublicKey alloc] initWithJWK:jwk keyID:keyID error:error];
#endif
}

+ (nullable id<PDSPrivateKeyProtocol>)privateKeyFromJWK:(NSDictionary *)jwk
                                                  error:(NSError **)error {
    NSString *kty = jwk[@"kty"];
    if (![kty isEqualToString:@"EC"]) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoErrorDomain
                                         code:-3
                                     userInfo:@{NSLocalizedDescriptionKey: @"Only EC keys are supported"}];
        }
        return nil;
    }

#if defined(__APPLE__) && !defined(GNUSTEP)
    // macOS: Use Apple Security framework
    NSError *secError = nil;
    SecKeyRef secKey = [self createPrivateKeyFromJWK:jwk error:&secError];
    if (!secKey) {
        if (error) *error = secError;
        return nil;
    }

    // Wrap in protocol adapter
    PDSSecKeyAdapter *adapter = [[PDSSecKeyAdapter alloc] initWithSecKey:secKey isPrivateKey:YES];
    CFRelease(secKey);
    return adapter;
#else
    // GNUstep: Use OpenSSL
    NSString *keyID = jwk[@"kid"] ?: [[NSUUID UUID] UUIDString];
    return [[PDSOpenSSLES256PrivateKey alloc] initWithJWK:jwk keyID:keyID error:error];
#endif
}

+ (nullable NSDictionary *)publicJWKFromKey:(id<PDSKeyProtocol>)key
                                      error:(NSError **)error {
    NSDictionary *jwk = [key publicKeyJWK];
    if (!jwk && error) {
        *error = [NSError errorWithDomain:AuthCryptoErrorDomain
                                     code:-3
                                 userInfo:@{NSLocalizedDescriptionKey: @"Failed to get public JWK from key"}];
    }
    return jwk;
}

+ (nullable NSDictionary *)jwkFromKey:(id<PDSKeyProtocol>)key
                                error:(NSError **)error {
    // If it's a private key, return private JWK
    if ([key conformsToProtocol:@protocol(PDSPrivateKeyProtocol)]) {
        id<PDSPrivateKeyProtocol> privateKey = (id<PDSPrivateKeyProtocol>)key;
        NSDictionary *jwk = [privateKey privateKeyJWK];
        if (!jwk && error) {
            *error = [NSError errorWithDomain:AuthCryptoErrorDomain
                                         code:-3
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to get private JWK from key"}];
        }
        return jwk;
    }

    // Otherwise return public JWK
    return [self publicJWKFromKey:key error:error];
}

+ (nullable NSString *)thumbprintForKey:(id<PDSKeyProtocol>)key
                                  error:(NSError **)error {
    NSString *thumbprint = [key thumbprint];
    if (!thumbprint && error) {
        *error = [NSError errorWithDomain:AuthCryptoErrorDomain
                                     code:-3
                                 userInfo:@{NSLocalizedDescriptionKey: @"Failed to compute thumbprint"}];
    }
    return thumbprint;
}

#pragma mark - SecKeyRef Operations (macOS only)

#if defined(__APPLE__) && !defined(GNUSTEP)

+ (nullable SecKeyRef)createPublicKeyFromJWK:(NSDictionary *)jwk error:(NSError **)error {
    NSString *kty = jwk[@"kty"];
    if (![kty isEqualToString:@"EC"]) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoErrorDomain
                                         code:-3
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unsupported JWK key type"}];
        }
        return nil;
    }

    NSString *xValue = jwk[@"x"];
    NSString *yValue = jwk[@"y"];
    if (!xValue || !yValue) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoErrorDomain
                                         code:-3
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing EC public key material"}];
        }
        return nil;
    }

    NSData *xData = [AuthCryptoBase64URL decode:xValue];
    NSData *yData = [AuthCryptoBase64URL decode:yValue];
    if (!xData || xData.length != 32 || !yData || yData.length != 32) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoErrorDomain
                                         code:-3
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid EC key component length"}];
        }
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
            *error = keyError ? CFBridgingRelease(keyError)
                : [NSError errorWithDomain:AuthCryptoErrorDomain code:-4
                    userInfo:@{NSLocalizedDescriptionKey: @"Failed to create EC public key"}];
        } else if (keyError) {
            CFRelease(keyError);
        }
        return nil;
    }
    if (keyError) CFRelease(keyError);
    return publicKey;
}

+ (nullable SecKeyRef)createPrivateKeyFromJWK:(NSDictionary *)jwk error:(NSError **)error {
    NSString *kty = jwk[@"kty"];
    if (!kty) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoErrorDomain
                                         code:-3
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing JWK key type"}];
        }
        return nil;
    }

    if (![kty isEqualToString:@"EC"]) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoErrorDomain
                                         code:-3
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unsupported JWK key type"}];
        }
        return nil;
    }

    NSString *crv = jwk[@"crv"];
    if (crv && ![crv isEqualToString:@"P-256"]) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoErrorDomain
                                         code:-3
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unsupported EC curve"}];
        }
        return nil;
    }

    NSString *xValue = jwk[@"x"];
    NSString *yValue = jwk[@"y"];
    NSString *dValue = jwk[@"d"];
    if (!xValue || !yValue || !dValue) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoErrorDomain
                                         code:-3
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing EC key material"}];
        }
        return nil;
    }

    NSData *xData = [AuthCryptoBase64URL decode:xValue];
    NSData *yData = [AuthCryptoBase64URL decode:yValue];
    NSData *dData = [AuthCryptoBase64URL decode:dValue];
    if (!xData || xData.length != 32 || !yData || yData.length != 32 || !dData || dData.length != 32) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoErrorDomain
                                         code:-3
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid EC key component length"}];
        }
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
            *error = keyError ? CFBridgingRelease(keyError)
                : [NSError errorWithDomain:AuthCryptoErrorDomain code:-4
                    userInfo:@{NSLocalizedDescriptionKey: @"Failed to create EC private key"}];
        } else if (keyError) {
            CFRelease(keyError);
        }
        return nil;
    }
    if (keyError) CFRelease(keyError);
    return privateKey;
}

+ (nullable NSDictionary *)publicJWKFromSecKey:(SecKeyRef)key error:(NSError **)error {
    NSDictionary *jwk = [self jwkFromSecKey:key error:error];
    if (!jwk) return nil;
    return [self publicJWKFromJWK:jwk];
}

+ (nullable NSDictionary *)jwkFromSecKey:(SecKeyRef)key error:(NSError **)error {
    CFErrorRef cfError = NULL;
    NSData *keyData = CFBridgingRelease(SecKeyCopyExternalRepresentation(key, &cfError));
    if (!keyData) {
        if (error) *error = CFBridgingRelease(cfError);
        return nil;
    }

    // Determine key type and class by data length
    BOOL isPrivateKey = NO;
    NSString *keyClass = nil;

    if (keyData.length == 65 && ((const uint8_t *)keyData.bytes)[0] == 0x04) {
        keyClass = (__bridge NSString *)kSecAttrKeyClassPublic;
    } else if (keyData.length == 97 && ((const uint8_t *)keyData.bytes)[0] == 0x04) {
        keyClass = (__bridge NSString *)kSecAttrKeyClassPrivate;
        isPrivateKey = YES;
    } else if (keyData.length == 32) {
        SecKeyRef publicKey = SecKeyCopyPublicKey(key);
        if (publicKey) {
            CFRelease(publicKey);
            keyClass = (__bridge NSString *)kSecAttrKeyClassPrivate;
            isPrivateKey = YES;
        } else {
            keyClass = (__bridge NSString *)kSecAttrKeyClassPublic;
        }
    } else {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoErrorDomain
                                         code:-3
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unknown key format"}];
        }
        return nil;
    }

    // Build JWK (EC P-256 assumed)
    NSMutableDictionary *jwk = [NSMutableDictionary dictionary];
    jwk[@"kty"] = @"EC";
    jwk[@"crv"] = @"P-256";

    if ([keyClass isEqualToString:(__bridge NSString *)kSecAttrKeyClassPublic]) {
        if (keyData.length != 65 || ((const uint8_t *)keyData.bytes)[0] != 0x04) {
            if (error) {
                *error = [NSError errorWithDomain:AuthCryptoErrorDomain
                                             code:-3
                                         userInfo:@{NSLocalizedDescriptionKey: @"Unexpected EC public key format"}];
            }
            return nil;
        }
        NSData *x = [keyData subdataWithRange:NSMakeRange(1, 32)];
        NSData *y = [keyData subdataWithRange:NSMakeRange(33, 32)];
        jwk[@"x"] = [AuthCryptoBase64URL encode:x];
        jwk[@"y"] = [AuthCryptoBase64URL encode:y];
    } else {
        // Private key
        if (keyData.length == 97) {
            NSData *x = [keyData subdataWithRange:NSMakeRange(1, 32)];
            NSData *y = [keyData subdataWithRange:NSMakeRange(33, 32)];
            NSData *d = [keyData subdataWithRange:NSMakeRange(65, 32)];
            jwk[@"x"] = [AuthCryptoBase64URL encode:x];
            jwk[@"y"] = [AuthCryptoBase64URL encode:y];
            jwk[@"d"] = [AuthCryptoBase64URL encode:d];
        } else if (keyData.length == 32) {
            // Raw d value - derive public key components
            SecKeyRef publicKey = SecKeyCopyPublicKey(key);
            if (publicKey) {
                NSDictionary *publicJWK = [self jwkFromSecKey:publicKey error:error];
                CFRelease(publicKey);
                if (publicJWK) {
                    [jwk addEntriesFromDictionary:publicJWK];
                    jwk[@"d"] = [AuthCryptoBase64URL encode:keyData];
                }
            }
        }
    }

    return jwk;
}

+ (nullable NSString *)thumbprintForSecKey:(SecKeyRef)key error:(NSError **)error {
    NSDictionary *jwk = [self jwkFromSecKey:key error:error];
    if (!jwk) return nil;
    return [self thumbprint:jwk error:error];
}

#endif // __APPLE__ && !GNUSTEP

@end
