//
//  PDSOpenSSLKeyManager.m
//  ATProtoPDS
//
//  Created by Jack Valinsky on 2/18/26.
//  Copyright (c) 2026 Jack Valinsky. All rights reserved.
//

#import "PDSOpenSSLKeyManager.h"
#import "Core/ATProtoError.h"

#if defined(GNUSTEP)
// #import <openssl/evp.h>
// #import <openssl/pem.h>
// #import <openssl/err.h>
#endif

@implementation PDSOpenSSLKeyManager

@synthesize keyManagerId = _keyManagerId;

- (instancetype)initWithDid:(NSString *)did keystorePath:(NSString *)keystorePath {
    self = [super init];
    if (self) {
        _did = [did copy];
        _keystorePath = [keystorePath copy];
        _keyManagerId = [NSString stringWithFormat:@"openssl-%@", did];
    }
    return self;
}

#pragma mark - PDSKeyManager Protocol

- (nullable NSString *)generateKeyPairWithAlgorithm:(NSString *)algorithm 
                                           keySize:(NSUInteger)keySize 
                                             error:(NSError **)error {
#if defined(GNUSTEP)
    // TODO: Implement OpenSSL key generation
    // 1. Generate EC key (secp256k1)
    // 2. Write private key to _keystorePath/did.pem (encrypted?)
    // 3. Return public key DID string (did:key:zQ3s...)
    if (error) {
        *error = [NSError errorWithDomain:@"PDSOpenSSLKeyManager" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Not implemented"}];
    }
    return nil;
#else
    if (error) {
        *error = [NSError errorWithDomain:@"PDSOpenSSLKeyManager" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"OpenSSL not available on this platform"}];
    }
    return nil;
#endif
}

- (nullable NSData *)signData:(NSData *)data error:(NSError **)error {
#if defined(GNUSTEP)
    // TODO: Implement OpenSSL signing
    // 1. Load private key from _keystorePath
    // 2. Sign SHA256 of data using ECDSA
    if (error) {
        *error = [NSError errorWithDomain:@"PDSOpenSSLKeyManager" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Not implemented"}];
    }
    return nil;
#else
    if (error) {
        *error = [NSError errorWithDomain:@"PDSOpenSSLKeyManager" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"OpenSSL not available on this platform"}];
    }
    return nil;
#endif
}

- (nullable NSString *)publicSigningKeyWithError:(NSError **)error {
#if defined(GNUSTEP)
    // TODO: Return stored public key as DID key string
    if (error) {
        *error = [NSError errorWithDomain:@"PDSOpenSSLKeyManager" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Not implemented"}];
    }
    return nil;
#else
    if (error) {
        *error = [NSError errorWithDomain:@"PDSOpenSSLKeyManager" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"OpenSSL not available on this platform"}];
    }
    return nil;
#endif
}

- (nullable NSString *)didKeyStringWithError:(NSError **)error {
    return [self publicSigningKeyWithError:error];
}

- (BOOL)importKey:(NSData *)privateKeyData error:(NSError **)error {
#if defined(GNUSTEP)
    // TODO: Save imported raw private key to storage
    if (error) {
        *error = [NSError errorWithDomain:@"PDSOpenSSLKeyManager" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Not implemented"}];
    }
    return NO;
#else
    if (error) {
        *error = [NSError errorWithDomain:@"PDSOpenSSLKeyManager" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"OpenSSL not available on this platform"}];
    }
    return NO;
#endif
}

- (BOOL)deleteKeyWithError:(NSError **)error {
    // TODO: Delete key file
    return YES;
}

@end
