// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSAppleKeyManager.m

 @abstract Apple Security.framework implementation of PDSKeyManager.

 @discussion This file implements key pair generation, storage, and retrieval
 using the iOS/macOS Security framework. Keys are persisted to the database
 and used for JWT signing and DPoP proof generation.

 @copyright Copyright (c) 2024 Jack Valinsky
 */

#import "Auth/PDSAppleKeyManager.h"
#import "Auth/JWT.h"
#import "Auth/Secp256k1.h"
#import "App/ATProtoServiceConfiguration.h"
#import "Database/PDSDatabase.h"
#import "Debug/GZLogger.h"
#import "Compat/PDSTypes.h"
#import <CommonCrypto/CommonDigest.h>

NSString * const KeyManagerErrorDomain = @"com.atproto.pds.keymanager";

static NSString *PDSBase64URLStringFromData(NSData *data) {
    NSString *base64 = [data base64EncodedStringWithOptions:0];
    NSString *base64url = [[base64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"]
        stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    return [base64url stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"="]];
}

@implementation PDSAppleKeyPair

+ (nullable instancetype)keyPairFromPrivateKey:(SecKeyRef)privateKey
                                      publicKey:(SecKeyRef)publicKey
                                        keyID:(NSString *)keyID
                                     algorithm:(NSString *)algorithm {
    if (!privateKey || !publicKey || !keyID) return nil;

    CFRetain(privateKey);
    CFRetain(publicKey);

    PDSAppleKeyPair *keyPair = [[PDSAppleKeyPair alloc] init];
    keyPair.keyID = keyID;
    keyPair.algorithm = algorithm;
    keyPair.privateKey = privateKey;
    keyPair.publicKey = publicKey;
    keyPair.createdAt = [NSDate date];
    keyPair.isActive = YES;

    return keyPair;
}

+ (nullable instancetype)keyPairWithSecp256k1PrivateKey:(NSData *)privateKeyData
                                              publicKey:(NSData *)publicKeyData
                                                 keyID:(NSString *)keyID {
    if (!privateKeyData || privateKeyData.length != 32 || !publicKeyData || !keyID) return nil;

    PDSAppleKeyPair *keyPair = [[PDSAppleKeyPair alloc] init];
    keyPair.keyID = keyID;
    keyPair.algorithm = @"ES256K";
    keyPair.privateKey = NULL;
    keyPair.publicKey = NULL;
    keyPair.secp256k1PrivateKeyData = [privateKeyData copy];
    keyPair.createdAt = [NSDate date];
    keyPair.isActive = YES;

    // Store the public key data for JWK export
    // We don't create SecKeyRef for secp256k1 keys since Apple Security doesn't support them

    return keyPair;
}

- (void)dealloc {
    if (_privateKey) CFRelease(_privateKey);
    if (_publicKey) CFRelease(_publicKey);
}

- (nullable NSDictionary *)publicKeyJWK {
    // For ES256K keys stored as raw secp256k1 data
    if ([self.algorithm isEqualToString:@"ES256K"] && self.secp256k1PrivateKeyData) {
        Secp256k1KeyPair *kp = [Secp256k1KeyPair keyPairWithPrivateKey:self.secp256k1PrivateKeyData error:nil];
        if (!kp) return nil;

        NSMutableDictionary *jwk = [NSMutableDictionary dictionary];
        jwk[@"kty"] = @"EC";
        jwk[@"crv"] = @"secp256k1";
        jwk[@"kid"] = self.keyID;
        jwk[@"alg"] = @"ES256K";
        jwk[@"use"] = @"sig";

        // Export uncompressed public key for x/y coordinates
        NSData *pubKeyData = kp.publicKey;  // Uncompressed point
        if (pubKeyData.length > 1 && ((const uint8_t *)pubKeyData.bytes)[0] == 0x04) {
            NSUInteger coordLen = (pubKeyData.length - 1) / 2;
            NSData *xData = [pubKeyData subdataWithRange:NSMakeRange(1, coordLen)];
            NSData *yData = [pubKeyData subdataWithRange:NSMakeRange(1 + coordLen, coordLen)];
            jwk[@"x"] = PDSBase64URLStringFromData(xData);
            jwk[@"y"] = PDSBase64URLStringFromData(yData);
        } else {
            jwk[@"x"] = PDSBase64URLStringFromData(pubKeyData);
        }

        return jwk;
    }

    NSData *publicKeyData = [self exportPublicKeyData:self.publicKey];
    if (!publicKeyData) return nil;

    NSMutableDictionary *jwk = [NSMutableDictionary dictionary];
    jwk[@"kid"] = self.keyID;
    jwk[@"alg"] = self.algorithm;
    jwk[@"use"] = @"sig";

    if ([self.algorithm hasPrefix:@"RS"]) {
        jwk[@"kty"] = @"RSA";
        jwk[@"n"] = PDSBase64URLStringFromData(publicKeyData);
        jwk[@"e"] = @"AQAB";
    } else {
        // EC keys (ES256, ES256K, etc.)
        jwk[@"kty"] = @"EC";
        jwk[@"crv"] = [self.algorithm isEqualToString:@"ES256K"] ? @"secp256k1" : @"P-256";
        // For EC keys, publicKeyData is the uncompressed point (0x04 || x || y)
        if (publicKeyData.length > 1 && ((const uint8_t *)publicKeyData.bytes)[0] == 0x04) {
            NSUInteger coordLen = (publicKeyData.length - 1) / 2;
            NSData *xData = [publicKeyData subdataWithRange:NSMakeRange(1, coordLen)];
            NSData *yData = [publicKeyData subdataWithRange:NSMakeRange(1 + coordLen, coordLen)];
            jwk[@"x"] = PDSBase64URLStringFromData(xData);
            jwk[@"y"] = PDSBase64URLStringFromData(yData);
        } else {
            // Compressed or raw format — export as-is
            jwk[@"x"] = PDSBase64URLStringFromData(publicKeyData);
        }
    }

    return jwk;
}

- (nullable NSString *)publicKeyThumbprint {
    NSDictionary *jwk = [self publicKeyJWK];
    if (!jwk) return nil;

    NSData *thumbprintData = [NSJSONSerialization dataWithJSONObject:jwk options:0 error:nil];
    if (!thumbprintData) return nil;

    NSData *hashData;
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(thumbprintData.bytes, (CC_LONG)thumbprintData.length, hash);
    hashData = [NSData dataWithBytes:hash length:CC_SHA256_DIGEST_LENGTH];

    return PDSBase64URLStringFromData(hashData);
}

- (nullable NSData *)exportPublicKeyData:(SecKeyRef)key {
    CFErrorRef error = NULL;
    NSData *keyData = CFBridgingRelease(SecKeyCopyExternalRepresentation(key, &error));
    if (error) {
        CFRelease(error);
        return nil;
    }

    return keyData;
}

@end

@interface PDSAppleKeyManager ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, PDSAppleKeyPair *> *keyPairs;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t accessQueue;
@property (nonatomic, assign) BOOL useKeychain;
@end

@implementation PDSAppleKeyManager

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _serviceIdentifier = @"com.atproto.pds.keys";
        _signingAlgorithm = kSecKeyAlgorithmECDSASignatureMessageX962SHA256;
        _keyPairs = [NSMutableDictionary dictionary];
        _accessQueue = dispatch_queue_create("com.atproto.pds.keymanager", DISPATCH_QUEUE_SERIAL);
#if defined(GNUSTEP)
        _useKeychain = NO;
#else
        _useKeychain = [ATProtoServiceConfiguration sharedConfiguration].useKeychain;
#endif
        [self loadKeysFromDatabase];
    }
    return self;
}

- (instancetype)initWithServiceIdentifier:(NSString *)serviceIdentifier {
    self = [super init];
    if (self) {
        _serviceIdentifier = [serviceIdentifier copy];
        _signingAlgorithm = kSecKeyAlgorithmECDSASignatureMessageX962SHA256;
        _keyPairs = [NSMutableDictionary dictionary];
        _accessQueue = dispatch_queue_create("com.atproto.pds.keymanager", DISPATCH_QUEUE_SERIAL);
#if defined(GNUSTEP)
        _useKeychain = NO;
#else
        _useKeychain = [ATProtoServiceConfiguration sharedConfiguration].useKeychain;
#endif
        [self loadKeysFromDatabase];
    }
    return self;
}

- (instancetype)initWithDatabase:(PDSDatabase *)database serviceIdentifier:(NSString *)serviceIdentifier {
    self = [super init];
    if (self) {
        _database = database;
        _serviceIdentifier = [serviceIdentifier copy];
        _signingAlgorithm = kSecKeyAlgorithmECDSASignatureMessageX962SHA256;
        _keyPairs = [NSMutableDictionary dictionary];
        _accessQueue = dispatch_queue_create("com.atproto.pds.keymanager", DISPATCH_QUEUE_SERIAL);
#if defined(GNUSTEP)
        _useKeychain = NO;
#else
        _useKeychain = [ATProtoServiceConfiguration sharedConfiguration].useKeychain;
#endif
        [self loadKeysFromDatabase];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        _serviceIdentifier = [coder decodeObjectOfClass:[NSString class] forKey:@"serviceIdentifier"];
        _signingAlgorithm = kSecKeyAlgorithmECDSASignatureMessageX962SHA256;
        _keyPairs = [NSMutableDictionary dictionary];
        _accessQueue = dispatch_queue_create("com.atproto.pds.keymanager", DISPATCH_QUEUE_SERIAL);
        _currentKeyID = [coder decodeObjectOfClass:[NSString class] forKey:@"currentKeyID"];
#if defined(GNUSTEP)
        _useKeychain = NO;
#else
        _useKeychain = [ATProtoServiceConfiguration sharedConfiguration].useKeychain;
#endif
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.serviceIdentifier forKey:@"serviceIdentifier"];
    [coder encodeObject:self.currentKeyID forKey:@"currentKeyID"];
}

- (nullable id<PDSKeyPair>)generateKeyPairWithAlgorithm:(NSString *)algorithm
                                          keySize:(NSUInteger)keySize
                                             error:(NSError **)error {
    NSString *keyID = [[NSUUID UUID] UUIDString];

    // ES256K uses secp256k1 which Apple Security doesn't support natively.
    // Generate using our secp256k1 library and store raw key bytes.
    if ([algorithm isEqualToString:@"ES256K"]) {
        NSError *genError = nil;
        Secp256k1KeyPair *secpKeyPair = [Secp256k1KeyPair generateKeyPair:&genError];
        if (!secpKeyPair) {
            if (error) {
                *error = genError ?: [NSError errorWithDomain:KeyManagerErrorDomain
                                                         code:KeyManagerErrorKeyGenerationFailed
                                                     userInfo:@{NSLocalizedDescriptionKey: @"ES256K key generation failed"}];
            }
            return nil;
        }

        PDSAppleKeyPair *keyPair = [PDSAppleKeyPair keyPairWithSecp256k1PrivateKey:secpKeyPair.privateKey
                                                                        publicKey:secpKeyPair.publicKey
                                                                           keyID:keyID];

        dispatch_sync(self.accessQueue, ^{
            self.keyPairs[keyID] = keyPair;
        });

        self.currentKeyID = keyID;

        // Save to database for persistence
        NSError *saveError = nil;
        if (![self saveKeyPairToDatabase:keyPair error:&saveError]) {
            GZ_LOG_AUTH_WARN(@"Failed to save ES256K JWT signing key to database: %@", saveError);
        }

        return keyPair;
    }

    CFTypeRef keyType = kSecAttrKeyTypeECSECPrimeRandom;  // Default to EC (AT Protocol convention)
    if ([algorithm isEqualToString:@"RS256"]) {
        keyType = kSecAttrKeyTypeRSA;
    } else if ([algorithm isEqualToString:@"ES256"] || [algorithm isEqualToString:@"ECDSA"] || [algorithm isEqualToString:@"ECDSA-P256"]) {
        keyType = kSecAttrKeyTypeECSECPrimeRandom;
    }

    ATProtoServiceConfiguration *config = [ATProtoServiceConfiguration sharedConfiguration];
    BOOL useSE = (self.useKeychain && config.useSecureEnclave);
    NSString *keychainTag = [self keychainTagForKeyID:keyID];

    NSMutableDictionary *parameters = [NSMutableDictionary dictionaryWithDictionary:@{
        (__bridge id)kSecAttrKeyType: (__bridge id)keyType,
        (__bridge id)kSecAttrKeySizeInBits: @(keySize)
    }];

    if (self.useKeychain) {
        parameters[(__bridge id)kSecAttrIsPermanent] = @YES;
        parameters[(__bridge id)kSecAttrLabel] = keychainTag;
        parameters[(__bridge id)kSecAttrApplicationTag] = [keychainTag dataUsingEncoding:NSUTF8StringEncoding];
    } else {
        parameters[(__bridge id)kSecAttrIsPermanent] = @NO;
    }

    if (useSE) {
        parameters[(__bridge id)kSecAttrTokenID] = (__bridge id)kSecAttrTokenIDSecureEnclave;
    }

    CFErrorRef cfError = NULL;
    SecKeyRef privateKey = SecKeyCreateRandomKey((__bridge CFDictionaryRef)parameters, &cfError);

    if (!privateKey) {
        if (error) {
            *error = cfError ? CFBridgingRelease(cfError) : [NSError errorWithDomain:KeyManagerErrorDomain code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Key generation failed"}];
        } else if (cfError) {
            CFRelease(cfError);
        }
        return nil;
    }
    // Release cfError even on success path if populated (defensive)
    if (cfError) CFRelease(cfError);

    CFErrorRef pubError = NULL;
    SecKeyRef publicKey = SecKeyCopyPublicKey(privateKey);

    if (pubError) {
        CFRelease(privateKey);
        if (error) {
            *error = CFBridgingRelease(pubError);
        }
        return nil;
    }

    PDSAppleKeyPair *keyPair = [PDSAppleKeyPair keyPairFromPrivateKey:privateKey
                                             publicKey:publicKey
                                                 keyID:keyID
                                              algorithm:algorithm];
    keyPair.isSecureEnclaveKey = useSE;
    CFRelease(privateKey);
    CFRelease(publicKey);

    dispatch_sync(self.accessQueue, ^{
        self.keyPairs[keyID] = keyPair;
    });

    self.currentKeyID = keyID;

    // Save to database for persistence
    NSError *saveError = nil;
    if (![self saveKeyPairToDatabase:keyPair error:&saveError]) {
        GZ_LOG_AUTH_WARN(@"Failed to save JWT signing key to database: %@", saveError);
    }

    return keyPair;
}

- (nullable PDSAppleKeyPair *)generatePDSAppleKeyPairWithAlgorithm:(NSString *)algorithm
                                                            keySize:(NSUInteger)keySize
                                                              error:(NSError **)error {
    id<PDSKeyPair>keyPair = [self generateKeyPairWithAlgorithm:algorithm keySize:keySize error:error];
    if (!keyPair || ![keyPair isKindOfClass:[PDSAppleKeyPair class]]) {
        return nil;
    }
    return (PDSAppleKeyPair *)keyPair;
}

- (nullable PDSAppleKeyPair *)getPDSAppleKeyPairWithID:(NSString *)keyID
                                                  error:(NSError **)error {
    id<PDSKeyPair>keyPair = [self getKeyPairWithID:keyID error:error];
    return [keyPair isKindOfClass:[PDSAppleKeyPair class]] ? (PDSAppleKeyPair *)keyPair : nil;
}

- (nullable PDSAppleKeyPair *)getActivePDSAppleKeyPair:(NSError **)error {
    id<PDSKeyPair>keyPair = [self getActiveKeyPair:error];
    return [keyPair isKindOfClass:[PDSAppleKeyPair class]] ? (PDSAppleKeyPair *)keyPair : nil;
}

- (NSArray<PDSAppleKeyPair *> *)allPDSAppleKeyPairs:(NSError **)error {
    NSArray<id<PDSKeyPair>> *all = [self allKeyPairs:error];
    if (!all) {
        return @[];
    }

    NSMutableArray<PDSAppleKeyPair *> *result = [NSMutableArray arrayWithCapacity:all.count];
    for (id<PDSKeyPair>keyPair in all) {
        if ([keyPair isKindOfClass:[PDSAppleKeyPair class]]) {
            [result addObject:(PDSAppleKeyPair *)keyPair];
        }
    }
    return [result copy];
}

- (BOOL)deletePDSAppleKeyPairWithID:(NSString *)keyID error:(NSError **)error {
    return [self deleteKeyPairWithID:keyID error:error];
}

- (BOOL)setPDSAppleKeyPairActive:(NSString *)keyID error:(NSError **)error {
    return [self setKeyPairActive:keyID error:error];
}

- (nullable id<PDSKeyPair>)getKeyPairWithID:(NSString *)keyID error:(NSError **)error {
    __block PDSAppleKeyPair *keyPair = nil;

    dispatch_sync(self.accessQueue, ^{
        keyPair = self.keyPairs[keyID];
    });

    if (!keyPair && error) {
        *error = [NSError errorWithDomain:KeyManagerErrorDomain
                                     code:KeyManagerErrorKeyNotFound
                                 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Key pair with ID %@ not found", keyID]}];
    }

    return keyPair;
}

- (nullable id<PDSKeyPair>)getActiveKeyPair:(NSError **)error {
    if (self.currentKeyID) {
        return [self getKeyPairWithID:self.currentKeyID error:error];
    }

    NSArray *keys = [self allKeyPairs:error];
    for (PDSAppleKeyPair *keyPair in keys) {
        if (keyPair.isActive) {
            return keyPair;
        }
    }

    return [self generateKeyPairWithAlgorithm:@"ES256K" keySize:256 error:error];
}

- (NSArray<id<PDSKeyPair>> *)allKeyPairs:(NSError **)error {
    __block NSArray *keyPairs = @[];

    dispatch_sync(self.accessQueue, ^{
        keyPairs = [self.keyPairs.allValues copy];
    });

    return keyPairs;
}

- (BOOL)deleteKeyPairWithID:(NSString *)keyID error:(NSError **)error {
    __block BOOL success = NO;

    dispatch_sync(self.accessQueue, ^{
        PDSAppleKeyPair *keyPair = self.keyPairs[keyID];
        if (keyPair) {
            [self.keyPairs removeObjectForKey:keyID];
            success = YES;
        }
    });

    if (!success && error) {
        *error = [NSError errorWithDomain:KeyManagerErrorDomain
                                     code:KeyManagerErrorKeyNotFound
                                 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Key pair with ID %@ not found", keyID]}];
    }

    return success;
}

- (BOOL)setKeyPairActive:(NSString *)keyID error:(NSError **)error {
    __block BOOL success = NO;

    dispatch_sync(self.accessQueue, ^{
        if (self.keyPairs[keyID]) {
            for (PDSAppleKeyPair *keyPair in self.keyPairs.allValues) {
                keyPair.isActive = NO;
            }
            self.keyPairs[keyID].isActive = YES;
            self.currentKeyID = keyID;
            success = YES;
        }
    });

    if (!success && error) {
        *error = [NSError errorWithDomain:KeyManagerErrorDomain
                                     code:KeyManagerErrorKeyNotFound
                                 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Key pair with ID %@ not found", keyID]}];
    }

    return success;
}

- (nullable NSData *)signData:(NSData *)data
                     withKeyID:(NSString *)keyID
                         error:(NSError **)error {
    PDSAppleKeyPair *keyPair = (PDSAppleKeyPair *)[self getKeyPairWithID:keyID error:error];
    if (!keyPair) return nil;

    // ES256K keys use secp256k1 directly (Apple Security doesn't support secp256k1)
    if ([keyPair.algorithm isEqualToString:@"ES256K"] && keyPair.secp256k1PrivateKeyData) {
        uint8_t hash[CC_SHA256_DIGEST_LENGTH];
        CC_SHA256(data.bytes, (CC_LONG)data.length, hash);
        NSData *hashData = [NSData dataWithBytes:hash length:CC_SHA256_DIGEST_LENGTH];
        return [[Secp256k1 shared] signHash:hashData withPrivateKey:keyPair.secp256k1PrivateKeyData error:error];
    }

    // Select the correct SecKeyAlgorithm based on the key pair's algorithm
    SecKeyAlgorithm alg = self.signingAlgorithm;
    if ([keyPair.algorithm isEqualToString:@"ES256"] || [keyPair.algorithm isEqualToString:@"ECDSA-P256"]) {
        alg = kSecKeyAlgorithmECDSASignatureMessageX962SHA256;
    } else if ([keyPair.algorithm isEqualToString:@"RS256"]) {
        alg = kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256;
    }

    CFErrorRef cfError = NULL;
    NSData *signature = CFBridgingRelease(SecKeyCreateSignature(keyPair.privateKey,
                                                                 alg,
                                                                 (__bridge CFDataRef)data,
                                                                 &cfError));

    if (cfError) {
        if (error) {
            *error = CFBridgingRelease(cfError);
        }
        return nil;
    }

    return signature;
}

- (nullable NSDictionary *)signPayload:(NSDictionary *)payload
                              withKeyID:(NSString *)keyID
                                  error:(NSError **)error {
    NSData *payloadData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:error];
    if (!payloadData) return nil;

    NSData *signatureData = [self signData:payloadData withKeyID:keyID error:error];
    if (!signatureData) return nil;

    NSMutableDictionary *header = [NSMutableDictionary dictionary];
    PDSAppleKeyPair *keyPair = (PDSAppleKeyPair *)[self getKeyPairWithID:keyID error:nil];
    header[@"alg"] = keyPair.algorithm ?: @"ES256K";
    header[@"typ"] = @"JWT";
    header[@"kid"] = keyID;

    NSData *headerData = [NSJSONSerialization dataWithJSONObject:header options:0 error:error];
    if (!headerData) return nil;

    NSString *headerEncoded = [JWT base64URLEncodeData:headerData error:error];
    if (!headerEncoded) return nil;

    NSString *payloadEncoded = [JWT base64URLEncodeData:payloadData error:error];
    if (!payloadEncoded) return nil;

    NSString *signatureEncoded = [JWT base64URLEncodeData:signatureData error:error];
    if (!signatureEncoded) return nil;

    return @{
        @"token": [NSString stringWithFormat:@"%@.%@.%@", headerEncoded, payloadEncoded, signatureEncoded]
    };
}

- (nullable NSString *)signString:(NSString *)string
                         withKeyID:(NSString *)keyID
                             error:(NSError **)error {
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    NSData *signature = [self signData:data withKeyID:keyID error:error];
    if (!signature) return nil;

    return [signature base64EncodedStringWithOptions:0];
}

- (BOOL)verifySignature:(NSData *)signature
               forData:(NSData *)data
               withKey:(SecKeyRef)publicKey
                  error:(NSError **)error {
    BOOL isValid = SecKeyVerifySignature(publicKey,
                                          self.signingAlgorithm,
                                          (__bridge CFDataRef)data,
                                          (__bridge CFDataRef)signature,
                                          NULL);

    if (!isValid && error) {
        *error = [NSError errorWithDomain:KeyManagerErrorDomain
                                     code:KeyManagerErrorSigningFailed
                                 userInfo:@{NSLocalizedDescriptionKey: @"Signature verification failed"}];
    }

    return isValid;
}

- (NSDictionary *)toJWKS {
    id<PDSKeyPair> activeKey = [self getActiveKeyPair:nil];
    if (activeKey) {
        return [activeKey publicKeyJWK] ?: @{};
    }
    return @{};
}

- (NSArray<NSDictionary *> *)toJWKSArray {
    NSMutableArray *jwks = [NSMutableArray array];
    NSArray<id<PDSKeyPair>> *keyPairs = [self allKeyPairs:nil];

    for (id<PDSKeyPair> keyPair in keyPairs) {
        NSDictionary *jwk = [keyPair publicKeyJWK];
        if (jwk) {
            [jwks addObject:jwk];
        }
    }

    return jwks;
}

#pragma mark - Database Persistence

- (void)loadKeysFromDatabase {
    if (!self.database) return;

    NSError *error = nil;
    NSArray *results = [self.database executeParameterizedQuery:@"SELECT key_id, algorithm, private_key_data, public_key_data, keychain_tag, is_active, created_at FROM jwt_signing_keys ORDER BY created_at DESC" params:@[] error:&error];

    if (error) {
        GZ_LOG_AUTH_ERROR(@"Failed to load JWT signing keys from database: %@", error);
        return;
    }

    dispatch_sync(self.accessQueue, ^{
        for (NSDictionary *row in results) {
            NSString *keyID = row[@"key_id"];
            NSString *algorithm = row[@"algorithm"];
            NSData *privateKeyData = [row[@"private_key_data"] isKindOfClass:[NSData class]] ? row[@"private_key_data"] : nil;
            NSData *publicKeyData = row[@"public_key_data"];
            NSString *keychainTag = [row[@"keychain_tag"] isKindOfClass:[NSString class]] ? row[@"keychain_tag"] : nil;
            NSNumber *isActive = row[@"is_active"];

            SecKeyRef privateKey = NULL;
            SecKeyRef publicKey = NULL;
            CFErrorRef importError = NULL;

            if (keychainTag && self.useKeychain) {
                // Load key from Keychain
                NSDictionary *query = @{
                    (__bridge id)kSecClass: (__bridge id)kSecClassKey,
                    (__bridge id)kSecAttrApplicationTag: [keychainTag dataUsingEncoding:NSUTF8StringEncoding],
                    (__bridge id)kSecAttrKeyClass: (__bridge id)kSecAttrKeyClassPrivate,
                    (__bridge id)kSecReturnRef: @YES
                };
                OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef *)&privateKey);
                if (status != errSecSuccess) {
                    GZ_LOG_AUTH_WARN(@"Failed to load private key from Keychain for tag: %@ (status: %d)", keychainTag, (int)status);
                }
            }
            
            if (!privateKey && privateKeyData) {
                // ES256K keys are stored as raw secp256k1 private key bytes (32 bytes)
                if ([algorithm isEqualToString:@"ES256K"] && privateKeyData.length == 32) {
                    PDSAppleKeyPair *keyPair = [PDSAppleKeyPair keyPairWithSecp256k1PrivateKey:privateKeyData
                                                                                     publicKey:publicKeyData
                                                                                        keyID:keyID];
                    if (keyPair) {
                        keyPair.isActive = [isActive boolValue];
                        self.keyPairs[keyID] = keyPair;
                        if (keyPair.isActive && !self.currentKeyID) {
                            self.currentKeyID = keyID;
                        }
                    }
                    continue;  // Skip SecKeyRef creation for ES256K keys
                }

                // Import legacy RSA/EC key from data
                GZ_LOG_AUTH_WARN(@"Loading legacy private key from database for key ID: %@. Migration recommended.", keyID);
                NSDictionary *privateKeyAttrs = @{
                    (__bridge id)kSecAttrKeyType: [algorithm hasPrefix:@"RS"] ? (__bridge id)kSecAttrKeyTypeRSA : (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
                    (__bridge id)kSecAttrKeyClass: (__bridge id)kSecAttrKeyClassPrivate
                };
                privateKey = SecKeyCreateWithData((__bridge CFDataRef)privateKeyData,
                                                  (__bridge CFDictionaryRef)privateKeyAttrs,
                                                  &importError);
                if (importError) {
                    CFRelease(importError);
                    importError = NULL;
                }
            }
            // Public key should always be present as data
            NSDictionary *publicKeyAttrs = @{
                (__bridge id)kSecAttrKeyType: [algorithm hasPrefix:@"RS"] ? (__bridge id)kSecAttrKeyTypeRSA : (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
                (__bridge id)kSecAttrKeyClass: (__bridge id)kSecAttrKeyClassPublic
            };

            publicKey = SecKeyCreateWithData((__bridge CFDataRef)publicKeyData,
                                             (__bridge CFDictionaryRef)publicKeyAttrs,
                                             &importError);
            if (importError) {
                CFRelease(importError);
                importError = NULL;
            }

            if (privateKey && publicKey) {
                PDSAppleKeyPair *keyPair = [PDSAppleKeyPair keyPairFromPrivateKey:privateKey
                                                         publicKey:publicKey
                                                           keyID:keyID
                                                        algorithm:algorithm];
                if (keyPair) {
                    keyPair.isActive = [isActive boolValue];
                    keyPair.isSecureEnclaveKey = (privateKeyData == nil && keychainTag != nil);
                    self.keyPairs[keyID] = keyPair;

                    // Set current key ID if this is active
                    if (keyPair.isActive && !self.currentKeyID) {
                        self.currentKeyID = keyID;
                    }
                }
            }

            if (privateKey) CFRelease(privateKey);
            if (publicKey) CFRelease(publicKey);
        }
    });
}

- (BOOL)saveKeyPairToDatabase:(PDSAppleKeyPair *)keyPair error:(NSError **)error {
    if (!self.database) return YES; // Not an error if no database

    NSData *privateKeyData = nil;
    NSData *publicKeyData = nil;
    NSString *keychainTag = nil;

    // ES256K keys store raw secp256k1 private key bytes directly
    if ([keyPair.algorithm isEqualToString:@"ES256K"] && keyPair.secp256k1PrivateKeyData) {
        privateKeyData = keyPair.secp256k1PrivateKeyData;
        // Get public key from the secp256k1 key pair
        Secp256k1KeyPair *kp = [Secp256k1KeyPair keyPairWithPrivateKey:keyPair.secp256k1PrivateKeyData error:nil];
        publicKeyData = kp.publicKey;  // Uncompressed public key
    } else {
        CFErrorRef exportError = NULL;

        if (self.useKeychain) {
            keychainTag = [self keychainTagForKeyID:keyPair.keyID];
            privateKeyData = nil;
        } else {
            if (keyPair.privateKey) {
                privateKeyData = CFBridgingRelease(SecKeyCopyExternalRepresentation(keyPair.privateKey, &exportError));
                if (exportError) {
                    if (error) {
                        *error = CFBridgingRelease(exportError);
                    } else {
                        CFRelease(exportError);
                    }
                    return NO;
                }
            }
        }

        if (keyPair.publicKey) {
            CFErrorRef pubExportError = NULL;
            publicKeyData = CFBridgingRelease(SecKeyCopyExternalRepresentation(keyPair.publicKey, &pubExportError));
            if (pubExportError) {
                if (error) {
                    *error = CFBridgingRelease(pubExportError);
                } else {
                    CFRelease(pubExportError);
                }
                return NO;
            }
        }
    }

    if (!publicKeyData || (self.useKeychain && !keychainTag && ![keyPair.algorithm isEqualToString:@"ES256K"]) || (!self.useKeychain && !privateKeyData)) {
        if (error) {
            *error = [NSError errorWithDomain:KeyManagerErrorDomain
                                         code:KeyManagerErrorExportFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to export key material for persistence"}];
        }
        return NO;
    }

    // Insert into database
    NSString *sql = @"INSERT OR REPLACE INTO jwt_signing_keys (key_id, algorithm, private_key_data, public_key_data, keychain_tag, is_active, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)";
    NSArray *params = @[
        keyPair.keyID,
        keyPair.algorithm,
        privateKeyData ?: [NSNull null],
        publicKeyData,
        keychainTag ?: [NSNull null],
        @(keyPair.isActive),
        [self iso8601StringFromDate:keyPair.createdAt]
    ];

    return [self.database executeParameterizedUpdate:sql params:params error:error];
}

- (NSString *)keychainTagForKeyID:(NSString *)keyID {
    NSString *service = self.serviceIdentifier.length > 0 ? self.serviceIdentifier : @"com.atproto.pds.keys";
    return [NSString stringWithFormat:@"%@.%@", service, keyID];
}

- (NSString *)iso8601StringFromDate:(NSDate *)date {
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSSZ"];
        [formatter setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
        [formatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
    });
    return [formatter stringFromDate:date];
}



- (BOOL)verifySignature:(NSData *)signature
                forData:(NSData *)data
              withKeyID:(NSString *)keyID
                  error:(NSError **)error {
    PDSAppleKeyPair *keyPair = [self getPDSAppleKeyPairWithID:keyID error:error];
    if (!keyPair) {
        return NO;
    }

    // ES256K verification using secp256k1 library
    if ([keyPair.algorithm isEqualToString:@"ES256K"] && keyPair.secp256k1PrivateKeyData) {
        Secp256k1KeyPair *kp = [Secp256k1KeyPair keyPairWithPrivateKey:keyPair.secp256k1PrivateKeyData error:nil];
        if (!kp) {
            if (error) {
                *error = [NSError errorWithDomain:KeyManagerErrorDomain
                                             code:KeyManagerErrorSigningFailed
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to reconstruct ES256K key pair for verification"}];
            }
            return NO;
        }
        uint8_t hash[CC_SHA256_DIGEST_LENGTH];
        CC_SHA256(data.bytes, (CC_LONG)data.length, hash);
        NSData *hashData = [NSData dataWithBytes:hash length:CC_SHA256_DIGEST_LENGTH];
        return [[Secp256k1 shared] verifySignature:signature forHash:hashData withPublicKey:kp.compressedPublicKey error:error];
    }

    return [self verifySignature:signature forData:data withKey:keyPair.publicKey error:error];
}

@end
