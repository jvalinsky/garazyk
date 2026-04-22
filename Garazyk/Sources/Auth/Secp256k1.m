#import "Auth/Secp256k1.h"
#import "Core/CID.h"
#import <CommonCrypto/CommonDigest.h>

NSString * const Secp256k1ErrorDomain = @"com.atproto.pds.secp256k1";

@implementation Secp256k1KeyPair

+ (nullable instancetype)generateKeyPair:(NSError **)error {
    Secp256k1PrivateKey privKey;
    Secp256k1PublicKey pubKey;

    Secp256k1Error result = secp256k1_wrapper_generate_key_pair(&privKey, &pubKey);
    if (result != Secp256k1ErrorNone) {
        if (error) {
            *error = [NSError errorWithDomain:Secp256k1ErrorDomain
                                         code:result
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:secp256k1_error_string(result)]}];
        }
        return nil;
    }

    Secp256k1KeyPair *keyPair = [[Secp256k1KeyPair alloc] init];
    keyPair->_privateKey = [NSData dataWithBytes:privKey.data length:32];
    keyPair->_publicKey = [NSData dataWithBytes:pubKey.data length:65];

    uint8_t compressed[33];
    secp256k1_wrapper_public_key_serialize_compressed(&pubKey, compressed);
    keyPair->_compressedPublicKey = [NSData dataWithBytes:compressed length:33];

    return keyPair;
}

+ (nullable instancetype)keyPairWithPrivateKey:(NSData *)privateKey error:(NSError **)error {
    if (privateKey.length != 32) {
        if (error) {
            *error = [NSError errorWithDomain:Secp256k1ErrorDomain
                                         code:Secp256k1ErrorInvalidPrivateKey
                                     userInfo:@{NSLocalizedDescriptionKey: @"Private key must be 32 bytes"}];
        }
        return nil;
    }

    Secp256k1PrivateKey privKey;
    Secp256k1Error parseResult = secp256k1_wrapper_private_key_parse(privateKey.bytes, &privKey);
    if (parseResult != Secp256k1ErrorNone) {
        if (error) {
            *error = [NSError errorWithDomain:Secp256k1ErrorDomain
                                         code:parseResult
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:secp256k1_error_string(parseResult)]}];
        }
        return nil;
    }

    Secp256k1PublicKey pubKey;
    Secp256k1Error result = secp256k1_wrapper_public_key_from_private_key(&privKey, &pubKey);
    if (result != Secp256k1ErrorNone) {
        if (error) {
            *error = [NSError errorWithDomain:Secp256k1ErrorDomain
                                         code:result
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:secp256k1_error_string(result)]}];
        }
        return nil;
    }

    Secp256k1KeyPair *keyPair = [[Secp256k1KeyPair alloc] init];
    keyPair->_privateKey = privateKey;
    keyPair->_publicKey = [NSData dataWithBytes:pubKey.data length:65];

    uint8_t compressed[33];
    secp256k1_wrapper_public_key_serialize_compressed(&pubKey, compressed);
    keyPair->_compressedPublicKey = [NSData dataWithBytes:compressed length:33];

    return keyPair;
}

- (nullable NSData *)signHash:(NSData *)hash error:(NSError **)error {
    if (hash.length != 32) {
        if (error) {
            *error = [NSError errorWithDomain:Secp256k1ErrorDomain
                                         code:Secp256k1ErrorSigningFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Hash must be 32 bytes"}];
        }
        return nil;
    }

    Secp256k1PrivateKey privKey;
    memcpy(privKey.data, self.privateKey.bytes, 32);

    Secp256k1Signature sig;
    Secp256k1Error result = secp256k1_wrapper_sign(&privKey, hash.bytes, &sig);
    if (result != Secp256k1ErrorNone) {
        if (error) {
            *error = [NSError errorWithDomain:Secp256k1ErrorDomain
                                         code:result
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:secp256k1_error_string(result)]}];
        }
        return nil;
    }

    return [NSData dataWithBytes:sig.data length:64];
}

- (NSString *)didKeyString {
    NSMutableData *data = [NSMutableData data];
    // Multicodec for secp256k1-pub: 0xe7 0x01
    uint8_t codec[] = {0xe7, 0x01};
    [data appendBytes:codec length:2];
    [data appendData:self.compressedPublicKey];
    
    NSString *base58 = [CID base58btcEncode:data];
    return [NSString stringWithFormat:@"did:key:z%@", base58];
}

- (BOOL)verifySignature:(NSData *)signature forHash:(NSData *)hash error:(NSError **)error {
    if (signature.length != 64) {
        if (error) {
            *error = [NSError errorWithDomain:Secp256k1ErrorDomain
                                         code:Secp256k1ErrorInvalidSignature
                                     userInfo:@{NSLocalizedDescriptionKey: @"Signature must be 64 bytes"}];
        }
        return NO;
    }

    if (hash.length != 32) {
        if (error) {
            *error = [NSError errorWithDomain:Secp256k1ErrorDomain
                                         code:Secp256k1ErrorVerificationFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Hash must be 32 bytes"}];
        }
        return NO;
    }

    Secp256k1PublicKey pubKey;
    memcpy(pubKey.data, self.publicKey.bytes, 65);

    Secp256k1Signature sig;
    memcpy(sig.data, signature.bytes, 64);

    Secp256k1Error result = secp256k1_wrapper_verify(&pubKey, hash.bytes, &sig);
    if (result != Secp256k1ErrorNone) {
        if (error) {
            *error = [NSError errorWithDomain:Secp256k1ErrorDomain
                                         code:result
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:secp256k1_error_string(result)]}];
        }
        return NO;
    }

    return YES;
}

@end

@implementation Secp256k1

+ (instancetype)shared {
    static Secp256k1 *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (nullable Secp256k1KeyPair *)generateKeyPairWithError:(NSError **)error {
    return [Secp256k1KeyPair generateKeyPair:error];
}

- (nullable Secp256k1KeyPair *)keyPairFromPrivateKey:(NSData *)privateKey error:(NSError **)error {
    return [Secp256k1KeyPair keyPairWithPrivateKey:privateKey error:error];
}

- (nullable NSData *)signHash:(NSData *)hash withPrivateKey:(NSData *)privateKey error:(NSError **)error {
    if (privateKey.length != 32) {
        if (error) {
            *error = [NSError errorWithDomain:Secp256k1ErrorDomain
                                         code:Secp256k1ErrorInvalidPrivateKey
                                     userInfo:@{NSLocalizedDescriptionKey: @"Private key must be 32 bytes"}];
        }
        return nil;
    }

    if (hash.length != 32) {
        if (error) {
            *error = [NSError errorWithDomain:Secp256k1ErrorDomain
                                         code:Secp256k1ErrorSigningFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Hash must be 32 bytes"}];
        }
        return nil;
    }

    Secp256k1PrivateKey privKey;
    memcpy(privKey.data, privateKey.bytes, 32);

    Secp256k1Signature sig;
    Secp256k1Error result = secp256k1_wrapper_sign(&privKey, hash.bytes, &sig);
    if (result != Secp256k1ErrorNone) {
        if (error) {
            *error = [NSError errorWithDomain:Secp256k1ErrorDomain
                                         code:result
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:secp256k1_error_string(result)]}];
        }
        return nil;
    }

    return [NSData dataWithBytes:sig.data length:64];
}

- (BOOL)verifySignature:(NSData *)signature forHash:(NSData *)hash withPublicKey:(NSData *)publicKey error:(NSError **)error {
    if (publicKey.length != 33 && publicKey.length != 65) {
        if (error) {
            *error = [NSError errorWithDomain:Secp256k1ErrorDomain
                                         code:Secp256k1ErrorInvalidPublicKey
                                     userInfo:@{NSLocalizedDescriptionKey: @"Public key must be 33 or 65 bytes"}];
        }
        return NO;
    }

    if (signature.length != 64) {
        if (error) {
            *error = [NSError errorWithDomain:Secp256k1ErrorDomain
                                         code:Secp256k1ErrorInvalidSignature
                                     userInfo:@{NSLocalizedDescriptionKey: @"Signature must be 64 bytes"}];
        }
        return NO;
    }

    if (hash.length != 32) {
        if (error) {
            *error = [NSError errorWithDomain:Secp256k1ErrorDomain
                                         code:Secp256k1ErrorVerificationFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Hash must be 32 bytes"}];
        }
        return NO;
    }

    Secp256k1PublicKey pubKey;
    Secp256k1Error normResult = secp256k1_wrapper_public_key_normalize(publicKey.bytes, publicKey.length, pubKey.data);
    if (normResult != Secp256k1ErrorNone) {
        if (error) {
            *error = [NSError errorWithDomain:Secp256k1ErrorDomain
                                         code:normResult
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to parse/normalize public key"}];
        }
        return NO;
    }

    Secp256k1Signature sig;
    memcpy(sig.data, signature.bytes, 64);

    Secp256k1Error result = secp256k1_wrapper_verify(&pubKey, hash.bytes, &sig);
    if (result != Secp256k1ErrorNone) {
        if (error) {
            *error = [NSError errorWithDomain:Secp256k1ErrorDomain
                                         code:result
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:secp256k1_error_string(result)]}];
        }
        return NO;
    }

    return YES;
}

- (nullable NSData *)normalizedPublicKey:(NSData *)publicKey error:(NSError **)error {
    if (publicKey.length != 33 && publicKey.length != 65) {
        if (error) {
            *error = [NSError errorWithDomain:Secp256k1ErrorDomain
                                         code:Secp256k1ErrorInvalidPublicKey
                                     userInfo:@{NSLocalizedDescriptionKey: @"Public key must be 33 or 65 bytes"}];
        }
        return nil;
    }

    uint8_t output[65];
    Secp256k1Error result = secp256k1_wrapper_public_key_normalize(publicKey.bytes,
                                                                    publicKey.length,
                                                                    output);
    if (result != Secp256k1ErrorNone) {
        if (error) {
            *error = [NSError errorWithDomain:Secp256k1ErrorDomain
                                         code:result
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:secp256k1_error_string(result)]}];
        }
        return nil;
    }

    return [NSData dataWithBytes:output length:sizeof(output)];
}

@end
