/*!
 @file AuthCryptoJWK.m

 @abstract JWK key operations implementation.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "AuthCrypto/AuthCryptoJWK.h"
#import "AuthCrypto/AuthCryptoBase64URL.h"
#import <CommonCrypto/CommonDigest.h>

NSString * const AuthCryptoErrorDomain = @"com.atproto.auth.crypto";

@implementation AuthCryptoJWK

+ (nullable NSDictionary *)publicJWKFromKey:(SecKeyRef)key error:(NSError **)error {
    NSDictionary *jwk = [self jwkFromKey:key error:error];
    if (!jwk) return nil;
    return [self publicJWKFromJWK:jwk];
}

+ (nullable NSString *)thumbprintForKey:(SecKeyRef)key error:(NSError **)error {
    NSDictionary *jwk = [self jwkFromKey:key error:error];
    if (!jwk) return nil;
    return [self thumbprint:jwk error:error];
}

+ (nullable NSDictionary *)jwkFromKey:(SecKeyRef)key error:(NSError **)error {
    CFErrorRef cfError = NULL;
    NSData *keyData = CFBridgingRelease(SecKeyCopyExternalRepresentation(key, &cfError));
    if (!keyData) {
        if (error) *error = CFBridgingRelease(cfError);
        return nil;
    }

    // Determine key type and class without SecKeyCopyAttributes (not available on GNUstep)
    // Key type is determined by key data length:
    // - EC public: 65 bytes (0x04 || x(32) || y(32))
    // - EC private (full): 97 bytes (0x04 || x(32) || y(32) || d(32))
    // - EC private (raw d): 32 bytes
    BOOL isPrivateKey = NO;
    NSString *keyType = (__bridge NSString *)kSecAttrKeyTypeECSECPrimeRandom;
    NSString *keyClass = nil;

    if (keyData.length == 65 && ((const uint8_t *)keyData.bytes)[0] == 0x04) {
        // Public key format
        keyClass = (__bridge NSString *)kSecAttrKeyClassPublic;
    } else if (keyData.length == 97 && ((const uint8_t *)keyData.bytes)[0] == 0x04) {
        // Full private key format
        keyClass = (__bridge NSString *)kSecAttrKeyClassPrivate;
        isPrivateKey = YES;
    } else if (keyData.length == 32) {
        // Raw private key - try to get public key to confirm it's private
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

    if ([keyType isEqualToString:(__bridge NSString *)kSecAttrKeyTypeECSECPrimeRandom]) {
        // P-256
        NSMutableDictionary *jwk = [NSMutableDictionary dictionary];
        jwk[@"kty"] = @"EC";
        jwk[@"crv"] = @"P-256";

        if ([keyClass isEqualToString:(__bridge NSString *)kSecAttrKeyClassPublic]) {
            // Public key data is 0x04 || x || y (65 bytes)
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
        } else if ([keyClass isEqualToString:(__bridge NSString *)kSecAttrKeyClassPrivate]) {
            // macOS SecKeyCreateRandomKey returns ANSI X9.63 format: 0x04 || x || y || d (97 bytes)
            // Also handle raw d value (32 bytes) for compatibility
            if (keyData.length == 97 && ((const uint8_t *)keyData.bytes)[0] == 0x04) {
                // Full format: 0x04 || x (32) || y (32) || d (32)
                NSData *x = [keyData subdataWithRange:NSMakeRange(1, 32)];
                NSData *y = [keyData subdataWithRange:NSMakeRange(33, 32)];
                NSData *d = [keyData subdataWithRange:NSMakeRange(65, 32)];
                jwk[@"x"] = [AuthCryptoBase64URL encode:x];
                jwk[@"y"] = [AuthCryptoBase64URL encode:y];
                jwk[@"d"] = [AuthCryptoBase64URL encode:d];
                return jwk;
            } else if (keyData.length == 32) {
                // Raw d value - derive public key components
                SecKeyRef publicKey = SecKeyCopyPublicKey(key);
                if (publicKey) {
                    NSDictionary *publicJWK = [self jwkFromKey:publicKey error:error];
                    CFRelease(publicKey);
                    if (publicJWK) {
                        [jwk addEntriesFromDictionary:publicJWK];
                        jwk[@"d"] = [AuthCryptoBase64URL encode:keyData];
                        return jwk;
                    }
                }
            }
            if (error && !*error) {
                *error = [NSError errorWithDomain:AuthCryptoErrorDomain
                                             code:-3
                                         userInfo:@{NSLocalizedDescriptionKey: @"Unsupported EC private key format"}];
            }
            return nil;
        }
        return jwk;
    }

    if (error) {
        *error = [NSError errorWithDomain:AuthCryptoErrorDomain
                                     code:-3
                                 userInfo:@{NSLocalizedDescriptionKey: @"Unsupported key type for JWK conversion"}];
    }
    return nil;
}

+ (nullable NSString *)jsonStringForValue:(NSString *)value {
    NSData *data = [NSJSONSerialization dataWithJSONObject:@[value] options:0 error:nil];
    if (!data) return nil;
    NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (json.length < 2) return nil;
    return [json substringWithRange:NSMakeRange(1, json.length - 2)];
}

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

    NSArray<NSString *> *keys = [[thumbprintJWK allKeys] sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray<NSString *> *components = [NSMutableArray arrayWithCapacity:keys.count];
    for (NSString *key in keys) {
        NSString *keyJSON = [self jsonStringForValue:key];
        NSString *valueJSON = [self jsonStringForValue:thumbprintJWK[key]];
        if (!keyJSON || !valueJSON) {
            if (error) {
                *error = [NSError errorWithDomain:AuthCryptoErrorDomain
                                             code:-2
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

@end
