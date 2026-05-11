// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
//
//  PDSOpenSSLES256KeyManager.m
//  ATProtoPDS
//
//  OpenSSL-based ES256 (ECDSA P-256) key manager for GNUstep/Linux.
//  This file is only compiled when GNUSTEP is defined or on non-Apple platforms.
//
//  Copyright (c) 2026 Jack Valinsky. All rights reserved.
//

#import "PDSOpenSSLES256KeyManager.h"

#if !defined(__APPLE__) || defined(GNUSTEP)

#import "Debug/PDSLogger.h"

#import <openssl/ec.h>
#import <openssl/ecdsa.h>
#import <openssl/err.h>
#import <openssl/sha.h>
#import <openssl/bn.h>
#import <openssl/pem.h>
#import <openssl/bio.h>

#pragma mark - Error Domain

NSString * const PDSOpenSSLES256KeyErrorDomain = @"com.atproto.pds.openssl.es256";

// Note: PDSKeyAlgorithmES256 and PDSKeyAlgorithmRS256 are defined in AuthCryptoJWK.m
// PDSKeyErrorDomain is also defined in AuthCryptoJWK.m

#pragma mark - Helper Functions

static NSString *base64URLEncode(NSData *data) {
    NSString *base64 = [data base64EncodedStringWithOptions:0];
    return [[[base64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"]
             stringByReplacingOccurrencesOfString:@"/" withString:@"_"]
            stringByReplacingOccurrencesOfString:@"=" withString:@""];
}

static NSData *base64URLDecode(NSString *string) {
    NSString *base64 = [string stringByReplacingOccurrencesOfString:@"-" withString:@"+"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    // Add padding
    while (base64.length % 4 != 0) {
        base64 = [base64 stringByAppendingString:@"="];
    }
    return [[NSData alloc] initWithBase64EncodedString:base64 options:0];
}

static NSData *dataFromBIGNUM(const BIGNUM *bn) {
    int len = BN_num_bytes(bn);
    if (len == 0) return [NSData data];
    NSMutableData *data = [NSMutableData dataWithLength:len];
    BN_bn2bin(bn, data.mutableBytes);
    return data;
}

static BIGNUM *bignumFromData(NSData *data) {
    if (data.length == 0) return BN_new();
    return BN_bin2bn(data.bytes, (int)data.length, NULL);
}

// Normalize signature to low-S (important for Bitcoin/ATProto compatibility)
static void normalizeLowS(ECDSA_SIG *sig, const EC_GROUP *group) {
    const BIGNUM *s;
    ECDSA_SIG_get0(sig, NULL, &s);

    BIGNUM *order = BN_new();
    EC_GROUP_get_order(group, order, NULL);

    // If s > order/2, s = order - s
    BN_CTX *ctx = BN_CTX_new();
    BIGNUM *halfOrder = BN_new();
    BN_rshift1(halfOrder, order);

    if (BN_cmp(s, halfOrder) > 0) {
        BIGNUM *newS = BN_new();
        BN_sub(newS, order, s);
        ECDSA_SIG_set0(sig, NULL, newS);
    }

    BN_free(order);
    BN_free(halfOrder);
    BN_CTX_free(ctx);
}

#pragma mark - PDSOpenSSLES256PrivateKey

@interface PDSOpenSSLES256PrivateKey ()
@property (nonatomic, assign) EC_KEY *ecKey;
@property (nonatomic, copy) NSString *keyID;
@end

@implementation PDSOpenSSLES256PrivateKey

- (void)dealloc {
    if (_ecKey) {
        EC_KEY_free(_ecKey);
        _ecKey = NULL;
    }
}

- (instancetype)init {
    return [self initWithECKey:NULL keyID:@"" error:nil];
}

- (instancetype)initWithECKey:(nullable void *)ecKey
                         keyID:(NSString *)keyID
                         error:(NSError **)error {
    self = [super init];
    if (self) {
        _ecKey = (EC_KEY *)ecKey;
        _keyID = [keyID copy] ?: [[NSUUID UUID] UUIDString];
        _isPrivateKey = YES;
        _algorithm = PDSKeyAlgorithmES256;

        if (!_ecKey) {
            if (error) {
                *error = [NSError errorWithDomain:PDSOpenSSLES256KeyErrorDomain
                                             code:PDSKeyErrorCodeInvalidKeyData
                                         userInfo:@{NSLocalizedDescriptionKey: @"Invalid or nil EC key"}];
            }
            return nil;
        }
    }
    return self;
}

+ (nullable instancetype)generateKeyWithKeyID:(NSString *)keyID
                                         error:(NSError **)error {
    // Create P-256 key
    EC_KEY *ecKey = EC_KEY_new_by_curve_name(NID_X9_62_prime256v1);
    if (!ecKey) {
        if (error) {
            *error = [NSError errorWithDomain:PDSOpenSSLES256KeyErrorDomain
                                         code:PDSKeyErrorCodeKeyGenerationFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to create P-256 key structure"}];
        }
        return nil;
    }

    // Generate key pair
    if (EC_KEY_generate_key(ecKey) != 1) {
        EC_KEY_free(ecKey);
        if (error) {
            *error = [NSError errorWithDomain:PDSOpenSSLES256KeyErrorDomain
                                         code:PDSKeyErrorCodeKeyGenerationFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to generate key pair"}];
        }
        return nil;
    }

    return [[PDSOpenSSLES256PrivateKey alloc] initWithECKey:ecKey
                                                     keyID:keyID ?: [[NSUUID UUID] UUIDString]
                                                     error:error];
}

- (nullable instancetype)initWithJWK:(NSDictionary *)jwk
                              keyID:(NSString *)keyID
                              error:(NSError **)error {
    // Validate JWK
    if (![jwk[@"kty"] isEqualToString:@"EC"]) {
        if (error) {
            *error = [NSError errorWithDomain:PDSOpenSSLES256KeyErrorDomain
                                         code:PDSKeyErrorCodeInvalidJWK
                                     userInfo:@{NSLocalizedDescriptionKey: @"JWK must be EC type"}];
        }
        return nil;
    }

    if (![jwk[@"crv"] isEqualToString:@"P-256"]) {
        if (error) {
            *error = [NSError errorWithDomain:PDSOpenSSLES256KeyErrorDomain
                                         code:PDSKeyErrorCodeInvalidJWK
                                     userInfo:@{NSLocalizedDescriptionKey: @"JWK must use P-256 curve"}];
        }
        return nil;
    }

    // Parse x, y coordinates
    NSData *xData = base64URLDecode(jwk[@"x"]);
    NSData *yData = base64URLDecode(jwk[@"y"]);

    if (!xData || !yData || xData.length != 32 || yData.length != 32) {
        if (error) {
            *error = [NSError errorWithDomain:PDSOpenSSLES256KeyErrorDomain
                                         code:PDSKeyErrorCodeInvalidJWK
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid x or y coordinates"}];
        }
        return nil;
    }

    // Create key
    EC_KEY *ecKey = EC_KEY_new_by_curve_name(NID_X9_62_prime256v1);
    if (!ecKey) {
        if (error) {
            *error = [NSError errorWithDomain:PDSOpenSSLES256KeyErrorDomain
                                         code:PDSKeyErrorCodeInvalidKeyData
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to create EC key"}];
        }
        return nil;
    }

    // Set public key
    BIGNUM *x = bignumFromData(xData);
    BIGNUM *y = bignumFromData(yData);
    EC_POINT *point = EC_POINT_new(EC_KEY_get0_group(ecKey));

    if (EC_POINT_set_affine_coordinates(EC_KEY_get0_group(ecKey), point, x, y, NULL) != 1) {
        EC_KEY_free(ecKey);
        BN_free(x); BN_free(y);
        if (error) {
            *error = [NSError errorWithDomain:PDSOpenSSLES256KeyErrorDomain
                                         code:PDSKeyErrorCodeInvalidKeyData
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to set public key coordinates"}];
        }
        return nil;
    }

    if (EC_KEY_set_public_key(ecKey, point) != 1) {
        EC_KEY_free(ecKey);
        EC_POINT_free(point);
        BN_free(x); BN_free(y);
        if (error) {
            *error = [NSError errorWithDomain:PDSOpenSSLES256KeyErrorDomain
                                         code:PDSKeyErrorCodeInvalidKeyData
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to set public key"}];
        }
        return nil;
    }

    // Set private key if present
    NSString *dStr = jwk[@"d"];
    if (dStr) {
        NSData *dData = base64URLDecode(dStr);
        if (!dData || dData.length != 32) {
            EC_KEY_free(ecKey);
            EC_POINT_free(point);
            BN_free(x); BN_free(y);
            if (error) {
                *error = [NSError errorWithDomain:PDSOpenSSLES256KeyErrorDomain
                                             code:PDSKeyErrorCodeInvalidJWK
                                         userInfo:@{NSLocalizedDescriptionKey: @"Invalid private key 'd'"}];
            }
            return nil;
        }

        BIGNUM *d = bignumFromData(dData);
        if (EC_KEY_set_private_key(ecKey, d) != 1) {
            EC_KEY_free(ecKey);
            EC_POINT_free(point);
            BN_free(x); BN_free(y); BN_free(d);
            if (error) {
                *error = [NSError errorWithDomain:PDSOpenSSLES256KeyErrorDomain
                                             code:PDSKeyErrorCodeInvalidKeyData
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to set private key"}];
            }
            return nil;
        }
        BN_free(d);
    }

    EC_POINT_free(point);
    BN_free(x); BN_free(y);

    return [[PDSOpenSSLES256PrivateKey alloc] initWithECKey:ecKey
                                                      keyID:keyID ?: jwk[@"kid"] ?: [[NSUUID UUID] UUIDString]
                                                      error:error];
}

- (nullable instancetype)initWithPrivateKeyData:(NSData *)data
                                           keyID:(NSString *)keyID
                                           error:(NSError **)error {
    // For now, assume JWK format or 32-byte scalar
    if (data.length == 32) {
        // Raw private key scalar
        EC_KEY *ecKey = EC_KEY_new_by_curve_name(NID_X9_62_prime256v1);
        if (!ecKey) {
            if (error) {
                *error = [NSError errorWithDomain:PDSOpenSSLES256KeyErrorDomain
                                             code:PDSKeyErrorCodeInvalidKeyData
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to create EC key"}];
            }
            return nil;
        }

        // Set private key
        BIGNUM *d = bignumFromData(data);
        if (EC_KEY_set_private_key(ecKey, d) != 1) {
            EC_KEY_free(ecKey);
            BN_free(d);
            if (error) {
                *error = [NSError errorWithDomain:PDSOpenSSLES256KeyErrorDomain
                                             code:PDSKeyErrorCodeInvalidKeyData
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to set private key"}];
            }
            return nil;
        }

        // Derive public key from private key
        const EC_GROUP *group = EC_KEY_get0_group(ecKey);
        EC_POINT *pubPoint = EC_POINT_new(group);
        if (EC_POINT_mul(group, pubPoint, EC_KEY_get0_private_key(ecKey), NULL, NULL, NULL) != 1) {
            EC_KEY_free(ecKey);
            EC_POINT_free(pubPoint);
            BN_free(d);
            if (error) {
                *error = [NSError errorWithDomain:PDSOpenSSLES256KeyErrorDomain
                                             code:PDSKeyErrorCodeInvalidKeyData
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to derive public key"}];
            }
            return nil;
        }

        EC_KEY_set_public_key(ecKey, pubPoint);
        EC_POINT_free(pubPoint);
        BN_free(d);

        return [[PDSOpenSSLES256PrivateKey alloc] initWithECKey:ecKey
                                                         keyID:keyID
                                                         error:error];
    }

    if (error) {
        *error = [NSError errorWithDomain:PDSOpenSSLES256KeyErrorDomain
                                     code:PDSKeyErrorCodeInvalidKeyData
                                 userInfo:@{NSLocalizedDescriptionKey: @"Unsupported key data format"}];
    }
    return nil;
}

- (void *)ecKey {
    return _ecKey;
}

- (id)copyWithZone:(NSZone *)zone {
    // Create a new EC_KEY copy
    EC_KEY *copiedKey = EC_KEY_dup(_ecKey);
    return [[PDSOpenSSLES256PrivateKey alloc] initWithECKey:copiedKey keyID:_keyID error:nil];
}

#pragma mark - PDSKeyProtocol

- (NSData *)publicKeyData {
    if (!_ecKey) return nil;

    const EC_GROUP *group = EC_KEY_get0_group(_ecKey);
    const EC_POINT *point = EC_KEY_get0_public_key(_ecKey);

    if (!group || !point) return nil;

    // Convert to uncompressed form (0x04 || x || y)
    size_t len = EC_POINT_point2oct(group, point, POINT_CONVERSION_UNCOMPRESSED, NULL, 0, NULL);
    if (len == 0) return nil;

    NSMutableData *data = [NSMutableData dataWithLength:len];
    EC_POINT_point2oct(group, point, POINT_CONVERSION_UNCOMPRESSED, data.mutableBytes, len, NULL);

    return data;
}

- (NSDictionary *)publicKeyJWK {
    NSData *pubData = self.publicKeyData;
    if (!pubData || pubData.length != 65) return nil;

    // Split into x and y (skip leading 0x04)
    NSData *xData = [pubData subdataWithRange:NSMakeRange(1, 32)];
    NSData *yData = [pubData subdataWithRange:NSMakeRange(33, 32)];

    NSString *kid = _keyID;
    NSString *jkt = self.thumbprint;
    if (jkt) {
        kid = jkt;  // Use thumbprint as kid if available
    }

    return @{
        @"kty": @"EC",
        @"crv": @"P-256",
        @"x": base64URLEncode(xData),
        @"y": base64URLEncode(yData),
        @"kid": kid
    };
}

- (NSString *)thumbprint {
    NSDictionary *jwk = self.publicKeyJWK;
    if (!jwk) return nil;

    // RFC 7638: Canonical JSON with required members only
    NSMutableDictionary *thumbprintJWK = [NSMutableDictionary dictionary];
    thumbprintJWK[@"crv"] = jwk[@"crv"];
    thumbprintJWK[@"kty"] = jwk[@"kty"];
    thumbprintJWK[@"x"] = jwk[@"x"];
    thumbprintJWK[@"y"] = jwk[@"y"];

    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:thumbprintJWK
                                                       options:NSJSONWritingSortedKeys
                                                         error:nil];
    if (!jsonData) return nil;

    unsigned char hash[32];
    SHA256(jsonData.bytes, jsonData.length, hash);

    NSData *hashData = [NSData dataWithBytes:hash length:32];
    return base64URLEncode(hashData);
}

- (id<PDSPublicKeyProtocol>)publicKey {
    NSData *pubData = self.publicKeyData;
    if (!pubData) return nil;

    // Create public key object
    return [[PDSOpenSSLES256PublicKey alloc] initWithPublicKeyData:pubData
                                                            keyID:_keyID
                                                            error:nil];
}

- (NSDictionary *)privateKeyJWK {
    NSMutableDictionary *jwk = [NSMutableDictionary dictionaryWithDictionary:self.publicKeyJWK];

    // Add private key
    const BIGNUM *d = EC_KEY_get0_private_key(_ecKey);
    if (!d) return nil;

    NSData *dData = dataFromBIGNUM(d);
    // Ensure 32 bytes
    if (dData.length < 32) {
        NSMutableData *padded = [NSMutableData dataWithLength:32];
        memcpy((char *)padded.mutableBytes + (32 - dData.length), dData.bytes, dData.length);
        dData = padded;
    }

    jwk[@"d"] = base64URLEncode(dData);
    return jwk;
}

#pragma mark - PDSPrivateKeyProtocol

- (NSData *)signData:(NSData *)data error:(NSError **)error {
    if (!_ecKey) {
        if (error) {
            *error = [NSError errorWithDomain:PDSOpenSSLES256KeyErrorDomain
                                         code:PDSKeyErrorCodeSigningFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"No key available"}];
        }
        return nil;
    }

    // Hash with SHA-256
    unsigned char hash[32];
    SHA256(data.bytes, data.length, hash);

    // Sign
    ECDSA_SIG *sig = ECDSA_do_sign(hash, 32, _ecKey);
    if (!sig) {
        if (error) {
            *error = [NSError errorWithDomain:PDSOpenSSLES256KeyErrorDomain
                                         code:PDSKeyErrorCodeSigningFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"ECDSA signing failed"}];
        }
        return nil;
    }

    // Normalize to low-S (ATProto requirement)
    normalizeLowS(sig, EC_KEY_get0_group(_ecKey));

    // Get r and s
    const BIGNUM *r, *s;
    ECDSA_SIG_get0(sig, &r, &s);

    // Convert to raw r||s format (64 bytes total)
    NSMutableData *result = [NSMutableData dataWithLength:64];
    unsigned char *bytes = result.mutableBytes;

    // Pad to 32 bytes each
    BN_bn2binpad(r, bytes, 32);
    BN_bn2binpad(s, bytes + 32, 32);

    ECDSA_SIG_free(sig);
    return result;
}

@end

#pragma mark - PDSOpenSSLES256PublicKey

@interface PDSOpenSSLES256PublicKey ()
@property (nonatomic, assign) EC_KEY *ecKey;
@property (nonatomic, copy) NSString *keyID;
@end

@implementation PDSOpenSSLES256PublicKey

- (void)dealloc {
    if (_ecKey) {
        EC_KEY_free(_ecKey);
        _ecKey = NULL;
    }
}

- (instancetype)initWithJWK:(NSDictionary *)jwk
                     keyID:(NSString *)keyID
                     error:(NSError **)error {
    // Validate JWK
    if (![jwk[@"kty"] isEqualToString:@"EC"]) {
        if (error) {
            *error = [NSError errorWithDomain:PDSOpenSSLES256KeyErrorDomain
                                         code:PDSKeyErrorCodeInvalidJWK
                                     userInfo:@{NSLocalizedDescriptionKey: @"JWK must be EC type"}];
        }
        return nil;
    }

    if (![jwk[@"crv"] isEqualToString:@"P-256"]) {
        if (error) {
            *error = [NSError errorWithDomain:PDSOpenSSLES256KeyErrorDomain
                                         code:PDSKeyErrorCodeInvalidJWK
                                     userInfo:@{NSLocalizedDescriptionKey: @"JWK must use P-256 curve"}];
        }
        return nil;
    }

    // Parse x, y coordinates
    NSData *xData = base64URLDecode(jwk[@"x"]);
    NSData *yData = base64URLDecode(jwk[@"y"]);

    if (!xData || !yData || xData.length != 32 || yData.length != 32) {
        if (error) {
            *error = [NSError errorWithDomain:PDSOpenSSLES256KeyErrorDomain
                                         code:PDSKeyErrorCodeInvalidJWK
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid x or y coordinates"}];
        }
        return nil;
    }

    // Create key
    EC_KEY *ecKey = EC_KEY_new_by_curve_name(NID_X9_62_prime256v1);
    if (!ecKey) {
        if (error) {
            *error = [NSError errorWithDomain:PDSOpenSSLES256KeyErrorDomain
                                         code:PDSKeyErrorCodeInvalidKeyData
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to create EC key"}];
        }
        return nil;
    }

    // Set public key
    BIGNUM *x = bignumFromData(xData);
    BIGNUM *y = bignumFromData(yData);
    EC_POINT *point = EC_POINT_new(EC_KEY_get0_group(ecKey));

    if (EC_POINT_set_affine_coordinates(EC_KEY_get0_group(ecKey), point, x, y, NULL) != 1) {
        EC_KEY_free(ecKey);
        EC_POINT_free(point);
        BN_free(x); BN_free(y);
        if (error) {
            *error = [NSError errorWithDomain:PDSOpenSSLES256KeyErrorDomain
                                         code:PDSKeyErrorCodeInvalidKeyData
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to set public key coordinates"}];
        }
        return nil;
    }

    if (EC_KEY_set_public_key(ecKey, point) != 1) {
        EC_KEY_free(ecKey);
        EC_POINT_free(point);
        BN_free(x); BN_free(y);
        if (error) {
            *error = [NSError errorWithDomain:PDSOpenSSLES256KeyErrorDomain
                                         code:PDSKeyErrorCodeInvalidKeyData
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to set public key"}];
        }
        return nil;
    }

    EC_POINT_free(point);
    BN_free(x); BN_free(y);

    self = [super init];
    if (self) {
        _ecKey = ecKey;
        _keyID = [keyID copy] ?: jwk[@"kid"] ?: [[NSUUID UUID] UUIDString];
        _isPrivateKey = NO;
        _algorithm = PDSKeyAlgorithmES256;
    }
    return self;
}

- (nullable instancetype)initWithPublicKeyData:(NSData *)data
                                          keyID:(NSString *)keyID
                                          error:(NSError **)error {
    // Expected: 65-byte uncompressed point (0x04 || x || y)
    if (!data || data.length != 65) {
        if (error) {
            *error = [NSError errorWithDomain:PDSOpenSSLES256KeyErrorDomain
                                         code:PDSKeyErrorCodeInvalidKeyData
                                     userInfo:@{NSLocalizedDescriptionKey: @"Public key must be 65 bytes (uncompressed)"}];
        }
        return nil;
    }

    const uint8_t *bytes = data.bytes;
    if (bytes[0] != 0x04) {
        if (error) {
            *error = [NSError errorWithDomain:PDSOpenSSLES256KeyErrorDomain
                                         code:PDSKeyErrorCodeInvalidKeyData
                                     userInfo:@{NSLocalizedDescriptionKey: @"Public key must start with 0x04"}];
        }
        return nil;
    }

    // Create JWK from data
    NSData *xData = [data subdataWithRange:NSMakeRange(1, 32)];
    NSData *yData = [data subdataWithRange:NSMakeRange(33, 32)];

    NSDictionary *jwk = @{
        @"kty": @"EC",
        @"crv": @"P-256",
        @"x": base64URLEncode(xData),
        @"y": base64URLEncode(yData)
    };

    return [self initWithJWK:jwk keyID:keyID error:error];
}

- (nullable instancetype)initWithCompressedPublicKeyData:(NSData *)data
                                                    keyID:(NSString *)keyID
                                                    error:(NSError **)error {
    // Expected: 33-byte compressed point (0x02 or 0x03 || x)
    if (!data || data.length != 33) {
        if (error) {
            *error = [NSError errorWithDomain:PDSOpenSSLES256KeyErrorDomain
                                         code:PDSKeyErrorCodeInvalidKeyData
                                     userInfo:@{NSLocalizedDescriptionKey: @"Compressed key must be 33 bytes"}];
        }
        return nil;
    }

    const uint8_t *bytes = data.bytes;
    if (bytes[0] != 0x02 && bytes[0] != 0x03) {
        if (error) {
            *error = [NSError errorWithDomain:PDSOpenSSLES256KeyErrorDomain
                                         code:PDSKeyErrorCodeInvalidKeyData
                                     userInfo:@{NSLocalizedDescriptionKey: @"Compressed key must start with 0x02 or 0x03"}];
        }
        return nil;
    }

    // Create EC_KEY and decompress
    EC_KEY *ecKey = EC_KEY_new_by_curve_name(NID_X9_62_prime256v1);
    if (!ecKey) {
        if (error) {
            *error = [NSError errorWithDomain:PDSOpenSSLES256KeyErrorDomain
                                         code:PDSKeyErrorCodeInvalidKeyData
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to create EC key"}];
        }
        return nil;
    }

    // Parse the compressed point
    EC_POINT *point = EC_POINT_new(EC_KEY_get0_group(ecKey));
    if (EC_POINT_oct2point(EC_KEY_get0_group(ecKey), point, data.bytes, data.length, NULL) != 1) {
        EC_KEY_free(ecKey);
        EC_POINT_free(point);
        if (error) {
            *error = [NSError errorWithDomain:PDSOpenSSLES256KeyErrorDomain
                                         code:PDSKeyErrorCodeInvalidKeyData
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to parse compressed point"}];
        }
        return nil;
    }

    EC_KEY_set_public_key(ecKey, point);
    EC_POINT_free(point);

    self = [super init];
    if (self) {
        _ecKey = ecKey;
        _keyID = [keyID copy] ?: [[NSUUID UUID] UUIDString];
        _isPrivateKey = NO;
        _algorithm = PDSKeyAlgorithmES256;
    }
    return self;
}

- (void *)ecKey {
    return _ecKey;
}

- (id)copyWithZone:(NSZone *)zone {
    EC_KEY *copiedKey = EC_KEY_dup(_ecKey);
    PDSOpenSSLES256PublicKey *copy = [[PDSOpenSSLES256PublicKey alloc] init];
    copy->_ecKey = copiedKey;
    copy->_keyID = [_keyID copy];
    return copy;
}

#pragma mark - PDSKeyProtocol

- (NSData *)publicKeyData {
    if (!_ecKey) return nil;

    const EC_GROUP *group = EC_KEY_get0_group(_ecKey);
    const EC_POINT *point = EC_KEY_get0_public_key(_ecKey);

    if (!group || !point) return nil;

    // Convert to uncompressed form (0x04 || x || y)
    size_t len = EC_POINT_point2oct(group, point, POINT_CONVERSION_UNCOMPRESSED, NULL, 0, NULL);
    if (len == 0) return nil;

    NSMutableData *data = [NSMutableData dataWithLength:len];
    EC_POINT_point2oct(group, point, POINT_CONVERSION_UNCOMPRESSED, data.mutableBytes, len, NULL);

    return data;
}

- (NSDictionary *)publicKeyJWK {
    NSData *pubData = self.publicKeyData;
    if (!pubData || pubData.length != 65) return nil;

    // Split into x and y (skip leading 0x04)
    NSData *xData = [pubData subdataWithRange:NSMakeRange(1, 32)];
    NSData *yData = [pubData subdataWithRange:NSMakeRange(33, 32)];

    NSString *kid = _keyID;
    NSString *jkt = self.thumbprint;
    if (jkt) {
        kid = jkt;
    }

    return @{
        @"kty": @"EC",
        @"crv": @"P-256",
        @"x": base64URLEncode(xData),
        @"y": base64URLEncode(yData),
        @"kid": kid
    };
}

- (NSString *)thumbprint {
    NSDictionary *jwk = self.publicKeyJWK;
    if (!jwk) return nil;

    // RFC 7638: Canonical JSON with required members only
    NSMutableDictionary *thumbprintJWK = [NSMutableDictionary dictionary];
    thumbprintJWK[@"crv"] = jwk[@"crv"];
    thumbprintJWK[@"kty"] = jwk[@"kty"];
    thumbprintJWK[@"x"] = jwk[@"x"];
    thumbprintJWK[@"y"] = jwk[@"y"];

    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:thumbprintJWK
                                                       options:NSJSONWritingSortedKeys
                                                         error:nil];
    if (!jsonData) return nil;

    unsigned char hash[32];
    SHA256(jsonData.bytes, jsonData.length, hash);

    NSData *hashData = [NSData dataWithBytes:hash length:32];
    return base64URLEncode(hashData);
}

#pragma mark - PDSPublicKeyProtocol

- (BOOL)verifySignature:(NSData *)signature
                forData:(NSData *)data
                  error:(NSError **)error {
    if (!_ecKey) {
        if (error) {
            *error = [NSError errorWithDomain:PDSOpenSSLES256KeyErrorDomain
                                         code:PDSKeyErrorCodeVerificationFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"No key available"}];
        }
        return NO;
    }

    // Signature must be 64 bytes (raw r||s)
    if (!signature || signature.length != 64) {
        if (error) {
            *error = [NSError errorWithDomain:PDSOpenSSLES256KeyErrorDomain
                                         code:PDSKeyErrorCodeInvalidSignature
                                     userInfo:@{NSLocalizedDescriptionKey: @"Signature must be 64 bytes"}];
        }
        return NO;
    }

    // Hash with SHA-256
    unsigned char hash[32];
    SHA256(data.bytes, data.length, hash);

    // Parse signature
    ECDSA_SIG *sig = ECDSA_SIG_new();
    BIGNUM *r = BN_bin2bn(signature.bytes, 32, NULL);
    BIGNUM *s = BN_bin2bn((const unsigned char *)signature.bytes + 32, 32, NULL);
    ECDSA_SIG_set0(sig, r, s);

    // Verify
    int result = ECDSA_do_verify(hash, 32, sig, _ecKey);
    ECDSA_SIG_free(sig);

    if (result == 1) {
        return YES;
    } else if (result == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PDSOpenSSLES256KeyErrorDomain
                                         code:PDSKeyErrorCodeVerificationFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Signature verification failed"}];
        }
        return NO;
    } else {
        if (error) {
            *error = [NSError errorWithDomain:PDSOpenSSLES256KeyErrorDomain
                                         code:PDSKeyErrorCodeVerificationFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Signature verification error"}];
        }
        return NO;
    }
}

- (BOOL)verifyDigestSignature:(NSData *)signature
                       forHash:(NSData *)digest
                         error:(NSError **)error {
    if (!_ecKey) {
        if (error) {
            *error = [NSError errorWithDomain:PDSOpenSSLES256KeyErrorDomain
                                         code:PDSKeyErrorCodeVerificationFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"No key available"}];
        }
        return NO;
    }

    // Digest must be 32 bytes (SHA-256)
    if (!digest || digest.length != 32) {
        if (error) {
            *error = [NSError errorWithDomain:PDSOpenSSLES256KeyErrorDomain
                                         code:PDSKeyErrorCodeInvalidSignature
                                     userInfo:@{NSLocalizedDescriptionKey: @"Digest must be 32 bytes (SHA-256)"}];
        }
        return NO;
    }

    // Signature must be 64 bytes (raw r||s)
    if (!signature || signature.length != 64) {
        if (error) {
            *error = [NSError errorWithDomain:PDSOpenSSLES256KeyErrorDomain
                                         code:PDSKeyErrorCodeInvalidSignature
                                     userInfo:@{NSLocalizedDescriptionKey: @"Signature must be 64 bytes"}];
        }
        return NO;
    }

    // Parse signature from raw r||s format
    ECDSA_SIG *sig = ECDSA_SIG_new();
    BIGNUM *r = BN_bin2bn(signature.bytes, 32, NULL);
    BIGNUM *s = BN_bin2bn((const unsigned char *)signature.bytes + 32, 32, NULL);
    ECDSA_SIG_set0(sig, r, s);

    // Verify against the pre-computed digest
    int result = ECDSA_do_verify(digest.bytes, (int)digest.length, sig, _ecKey);
    ECDSA_SIG_free(sig);

    if (result == 1) {
        return YES;
    } else if (result == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PDSOpenSSLES256KeyErrorDomain
                                         code:PDSKeyErrorCodeVerificationFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Digest signature verification failed"}];
        }
        return NO;
    } else {
        if (error) {
            *error = [NSError errorWithDomain:PDSOpenSSLES256KeyErrorDomain
                                         code:PDSKeyErrorCodeVerificationFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Signature verification error"}];
        }
        return NO;
    }
}

@end

#pragma mark - PDSOpenSSLES256KeyFactory

@implementation PDSOpenSSLES256KeyFactory

- (nullable id<PDSPrivateKeyProtocol>)generateKeyPairWithAlgorithm:(PDSKeyAlgorithm)algorithm
                                                              keyID:(nullable NSString *)keyID
                                                              error:(NSError **)error {
    if (![algorithm isEqualToString:PDSKeyAlgorithmES256]) {
        if (error) {
            *error = [NSError errorWithDomain:PDSOpenSSLES256KeyErrorDomain
                                         code:PDSKeyErrorCodeUnsupportedAlgorithm
                                     userInfo:@{NSLocalizedDescriptionKey: @"Only ES256 is supported"}];
        }
        return nil;
    }

    return [PDSOpenSSLES256PrivateKey generateKeyWithKeyID:keyID ?: [[NSUUID UUID] UUIDString]
                                                     error:error];
}

- (nullable id<PDSPrivateKeyProtocol>)importPrivateKeyFromJWK:(NSDictionary *)jwk
                                                         keyID:(nullable NSString *)keyID
                                                         error:(NSError **)error {
    return [[PDSOpenSSLES256PrivateKey alloc] initWithJWK:jwk
                                                    keyID:keyID ?: jwk[@"kid"]
                                                    error:error];
}

- (nullable id<PDSPublicKeyProtocol>)importPublicKeyFromJWK:(NSDictionary *)jwk
                                                       keyID:(nullable NSString *)keyID
                                                       error:(NSError **)error {
    return [[PDSOpenSSLES256PublicKey alloc] initWithJWK:jwk
                                                   keyID:keyID ?: jwk[@"kid"]
                                                   error:error];
}

- (nullable id<PDSPublicKeyProtocol>)importPublicKeyFromData:(NSData *)data
                                                   algorithm:(PDSKeyAlgorithm)algorithm
                                                        keyID:(nullable NSString *)keyID
                                                        error:(NSError **)error {
    if (![algorithm isEqualToString:PDSKeyAlgorithmES256]) {
        if (error) {
            *error = [NSError errorWithDomain:PDSOpenSSLES256KeyErrorDomain
                                         code:PDSKeyErrorCodeUnsupportedAlgorithm
                                     userInfo:@{NSLocalizedDescriptionKey: @"Only ES256 is supported"}];
        }
        return nil;
    }

    // Detect format: 65 bytes = uncompressed, 33 bytes = compressed
    if (data.length == 65) {
        return [[PDSOpenSSLES256PublicKey alloc] initWithPublicKeyData:data
                                                                keyID:keyID
                                                                error:error];
    } else if (data.length == 33) {
        return [[PDSOpenSSLES256PublicKey alloc] initWithCompressedPublicKeyData:data
                                                                           keyID:keyID
                                                                           error:error];
    } else {
        if (error) {
            *error = [NSError errorWithDomain:PDSOpenSSLES256KeyErrorDomain
                                         code:PDSKeyErrorCodeInvalidKeyData
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid public key data size"}];
        }
        return nil;
    }
}

@end

#endif // !__APPLE__ || GNUSTEP
