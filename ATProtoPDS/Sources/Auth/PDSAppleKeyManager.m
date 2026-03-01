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
#import "App/PDSConfiguration.h"
#import "Database/PDSDatabase.h"
#import "Debug/PDSLogger.h"
#import "Compat/PDSTypes.h"
#import <CommonCrypto/CommonDigest.h>

NSString * const KeyManagerErrorDomain = @"com.atproto.pds.keymanager";

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

- (void)dealloc {
    if (_privateKey) CFRelease(_privateKey);
    if (_publicKey) CFRelease(_publicKey);
}

- (nullable NSDictionary *)publicKeyJWK {
    NSData *publicKeyData = [self exportPublicKeyData:self.publicKey];
    if (!publicKeyData) return nil;

    NSMutableDictionary *jwk = [NSMutableDictionary dictionary];
    jwk[@"kty"] = @"RSA";
    jwk[@"kid"] = self.keyID;
    jwk[@"alg"] = self.algorithm;
    jwk[@"use"] = @"sig";

    NSString *base64Key = [publicKeyData base64EncodedStringWithOptions:0];
    jwk[@"n"] = [base64Key stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    jwk[@"e"] = @"AQAB";

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

    NSString *base64 = [hashData base64EncodedStringWithOptions:0];
    return [base64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
}

- (nullable NSData *)exportPublicKeyData:(SecKeyRef)key {
    NSDictionary *options = @{
        (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeRSA,
        (__bridge id)kSecAttrKeyClass: (__bridge id)kSecAttrKeyClassPublic
    };

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
@end

@implementation PDSAppleKeyManager

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _serviceIdentifier = @"com.atproto.pds.keys";
        _signingAlgorithm = kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256;
        _keyPairs = [NSMutableDictionary dictionary];
        _accessQueue = dispatch_queue_create("com.atproto.pds.keymanager", DISPATCH_QUEUE_SERIAL);
        [self loadKeysFromDatabase];
    }
    return self;
}

- (instancetype)initWithServiceIdentifier:(NSString *)serviceIdentifier {
    self = [super init];
    if (self) {
        _serviceIdentifier = [serviceIdentifier copy];
        _signingAlgorithm = kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256;
        _keyPairs = [NSMutableDictionary dictionary];
        _accessQueue = dispatch_queue_create("com.atproto.pds.keymanager", DISPATCH_QUEUE_SERIAL);
        [self loadKeysFromDatabase];
    }
    return self;
}

- (instancetype)initWithDatabase:(PDSDatabase *)database serviceIdentifier:(NSString *)serviceIdentifier {
    self = [super init];
    if (self) {
        _database = database;
        _serviceIdentifier = [serviceIdentifier copy];
        _signingAlgorithm = kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256;
        _keyPairs = [NSMutableDictionary dictionary];
        _accessQueue = dispatch_queue_create("com.atproto.pds.keymanager", DISPATCH_QUEUE_SERIAL);
        [self loadKeysFromDatabase];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        _serviceIdentifier = [coder decodeObjectOfClass:[NSString class] forKey:@"serviceIdentifier"];
        _signingAlgorithm = kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256;
        _keyPairs = [NSMutableDictionary dictionary];
        _accessQueue = dispatch_queue_create("com.atproto.pds.keymanager", DISPATCH_QUEUE_SERIAL);
        _currentKeyID = [coder decodeObjectOfClass:[NSString class] forKey:@"currentKeyID"];
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

    CFTypeRef keyType = kSecAttrKeyTypeRSA;
    if ([algorithm isEqualToString:@"ES256"] || [algorithm isEqualToString:@"ECDSA"] || [algorithm isEqualToString:@"ECDSA-P256"]) {
        keyType = kSecAttrKeyTypeECSECPrimeRandom;
    }

    PDSConfiguration *config = [PDSConfiguration sharedConfiguration];
    BOOL useSE = config.useSecureEnclave;

    NSMutableDictionary *parameters = [NSMutableDictionary dictionaryWithDictionary:@{
        (__bridge id)kSecAttrKeyType: (__bridge id)keyType,
        (__bridge id)kSecAttrKeySizeInBits: @(keySize)
    }];

    if (useSE) {
        parameters[(__bridge id)kSecAttrTokenID] = (__bridge id)kSecAttrTokenIDSecureEnclave;
        parameters[(__bridge id)kSecAttrIsPermanent] = @YES;
        parameters[(__bridge id)kSecAttrLabel] = keyID;
        parameters[(__bridge id)kSecAttrApplicationTag] = [keyID dataUsingEncoding:NSUTF8StringEncoding];
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
        PDS_LOG_AUTH_WARN(@"Failed to save JWT signing key to database: %@", saveError);
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

    return [self generateKeyPairWithAlgorithm:@"RS256" keySize:2048 error:error];
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

    CFErrorRef cfError = NULL;
    NSData *signature = CFBridgingRelease(SecKeyCreateSignature(keyPair.privateKey,
                                                                 self.signingAlgorithm,
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
    header[@"alg"] = @"RS256";
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
    NSArray *results = [self.database executeQuery:@"SELECT key_id, algorithm, private_key_data, public_key_data, keychain_tag, is_active, created_at FROM jwt_signing_keys ORDER BY created_at DESC" error:&error];

    if (error) {
        PDS_LOG_AUTH_ERROR(@"Failed to load JWT signing keys from database: %@", error);
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

            if (keychainTag) {
                // Load Secure Enclave key from Keychain
                NSDictionary *query = @{
                    (__bridge id)kSecClass: (__bridge id)kSecClassKey,
                    (__bridge id)kSecAttrApplicationTag: [keychainTag dataUsingEncoding:NSUTF8StringEncoding],
                    (__bridge id)kSecReturnRef: @YES
                };
                OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef *)&privateKey);
                if (status != errSecSuccess) {
                    PDS_LOG_AUTH_ERROR(@"Failed to load Secure Enclave key from Keychain for tag: %@ (status: %d)", keychainTag, (int)status);
                }
            } else if (privateKeyData) {
                // Import legacy RSA/EC key from data
                NSDictionary *privateKeyAttrs = @{
                    (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeRSA, // Default to RSA, but SecKeyCreateWithData handles it
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
                    keyPair.isSecureEnclaveKey = (keychainTag != nil);
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

    // Export key data
    NSDictionary *privateKeyAttrs = @{
        (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeRSA,
        (__bridge id)kSecAttrKeyClass: (__bridge id)kSecAttrKeyClassPrivate
    };

    NSDictionary *publicKeyAttrs = @{
        (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeRSA,
        (__bridge id)kSecAttrKeyClass: (__bridge id)kSecAttrKeyClassPublic
    };

    CFErrorRef exportError = NULL;
    NSData *privateKeyData = nil;
    NSString *keychainTag = nil;

    if (keyPair.isSecureEnclaveKey) {
        keychainTag = keyPair.keyID;
        PDS_LOG_AUTH_INFO(@"Storing Secure Enclave key by reference: %@", keychainTag);
    } else {
        privateKeyData = CFBridgingRelease(SecKeyCopyExternalRepresentation(keyPair.privateKey, &exportError));
        if (exportError) {
            CFRelease(exportError);
            exportError = NULL;
        }
    }

    NSData *publicKeyData = CFBridgingRelease(SecKeyCopyExternalRepresentation(keyPair.publicKey, &exportError));
    if (exportError) {
        CFRelease(exportError);
    }

    if (!publicKeyData || (!privateKeyData && !keyPair.isSecureEnclaveKey)) {
        if (error) {
            *error = [NSError errorWithDomain:KeyManagerErrorDomain
                                         code:KeyManagerErrorExportFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to export key data"}];
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
    
    return [self verifySignature:signature forData:data withKey:keyPair.publicKey error:error];
}

@end
