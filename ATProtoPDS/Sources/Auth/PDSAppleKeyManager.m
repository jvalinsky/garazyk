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
#import "Auth/CryptoUtils.h"
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
    jwk[@"kid"] = self.keyID;
    jwk[@"use"] = @"sig";
    jwk[@"alg"] = self.algorithm;

    NSString *alg = self.algorithm ?: @"";
    if ([alg hasPrefix:@"RS"]) {
        // RSA: SecKeyCopyExternalRepresentation returns PKCS#1 DER (SEQUENCE { n INTEGER, e INTEGER }).
        // The full modulus bytes form the JWK "n" parameter; exponent is almost always 65537 = AQAB.
        jwk[@"kty"] = @"RSA";
        jwk[@"n"]   = [CryptoUtils base64URLEncode:publicKeyData];
        jwk[@"e"]   = @"AQAB";
    } else {
        // EC: SecKeyCopyExternalRepresentation returns an ANSI X9.63 uncompressed point:
        // 0x04 || X (32 bytes) || Y (32 bytes) = 65 bytes total.
        if (publicKeyData.length != 65 ||
            ((const uint8_t *)publicKeyData.bytes)[0] != 0x04) {
            return nil;
        }
        NSData *xData = [publicKeyData subdataWithRange:NSMakeRange(1,  32)];
        NSData *yData = [publicKeyData subdataWithRange:NSMakeRange(33, 32)];
        jwk[@"kty"] = @"EC";
        jwk[@"crv"] = [alg isEqualToString:@"ES256K"] ? @"secp256k1" : @"P-256";
        jwk[@"x"]   = [CryptoUtils base64URLEncode:xData];
        jwk[@"y"]   = [CryptoUtils base64URLEncode:yData];
    }

    return [jwk copy];
}

- (nullable NSString *)publicKeyThumbprint {
    // RFC 7638: hash only the required members in lexicographic key order.
    NSData *publicKeyData = [self exportPublicKeyData:self.publicKey];
    if (!publicKeyData) return nil;

    NSString *canonical = nil;
    NSString *alg = self.algorithm ?: @"";

    if ([alg hasPrefix:@"RS"]) {
        // Required members for RSA (lex order): e, kty, n
        NSString *nStr = [CryptoUtils base64URLEncode:publicKeyData];
        canonical = [NSString stringWithFormat:@"{\"e\":\"AQAB\",\"kty\":\"RSA\",\"n\":\"%@\"}",
                     nStr];
    } else {
        if (publicKeyData.length != 65 ||
            ((const uint8_t *)publicKeyData.bytes)[0] != 0x04) {
            return nil;
        }
        NSString *crv  = [alg isEqualToString:@"ES256K"] ? @"secp256k1" : @"P-256";
        NSString *xStr = [CryptoUtils base64URLEncode:[publicKeyData subdataWithRange:NSMakeRange(1,  32)]];
        NSString *yStr = [CryptoUtils base64URLEncode:[publicKeyData subdataWithRange:NSMakeRange(33, 32)]];
        // Required members for EC (lex order): crv, kty, x, y
        canonical = [NSString stringWithFormat:@"{\"crv\":\"%@\",\"kty\":\"EC\",\"x\":\"%@\",\"y\":\"%@\"}",
                     crv, xStr, yStr];
    }

    NSData *canonicalData = [canonical dataUsingEncoding:NSUTF8StringEncoding];
    NSData *hash = [CryptoUtils sha256:canonicalData];
    return [CryptoUtils base64URLEncode:hash];
}

- (nullable NSData *)exportPublicKeyData:(SecKeyRef)key {
    CFErrorRef cfError = NULL;
    NSData *keyData = CFBridgingRelease(SecKeyCopyExternalRepresentation(key, &cfError));
    if (cfError) {
        CFRelease(cfError);
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
        _signingAlgorithm = kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256;
        _keyPairs = [NSMutableDictionary dictionary];
        _accessQueue = dispatch_queue_create("com.atproto.pds.keymanager", DISPATCH_QUEUE_SERIAL);
#if defined(GNUSTEP)
        _useKeychain = NO;
#else
        _useKeychain = [PDSConfiguration sharedConfiguration].useKeychain;
#endif
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
#if defined(GNUSTEP)
        _useKeychain = NO;
#else
        _useKeychain = [PDSConfiguration sharedConfiguration].useKeychain;
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
        _signingAlgorithm = kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256;
        _keyPairs = [NSMutableDictionary dictionary];
        _accessQueue = dispatch_queue_create("com.atproto.pds.keymanager", DISPATCH_QUEUE_SERIAL);
#if defined(GNUSTEP)
        _useKeychain = NO;
#else
        _useKeychain = [PDSConfiguration sharedConfiguration].useKeychain;
#endif
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
#if defined(GNUSTEP)
        _useKeychain = NO;
#else
        _useKeychain = [PDSConfiguration sharedConfiguration].useKeychain;
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

    CFTypeRef keyType = kSecAttrKeyTypeRSA;
    if ([algorithm isEqualToString:@"ES256"] || [algorithm isEqualToString:@"ECDSA"] || [algorithm isEqualToString:@"ECDSA-P256"]) {
        keyType = kSecAttrKeyTypeECSECPrimeRandom;
    }

    PDSConfiguration *config = [PDSConfiguration sharedConfiguration];
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

    SecKeyRef publicKey = SecKeyCopyPublicKey(privateKey);
    if (!publicKey) {
        CFRelease(privateKey);
        if (error) {
            *error = [NSError errorWithDomain:KeyManagerErrorDomain
                                         code:KeyManagerErrorKeyGenerationFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to derive public key from private key"}];
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
        self.currentKeyID = keyID;
    });

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

    NSDictionary *headerDict = @{ @"alg": @"RS256", @"typ": @"JWT", @"kid": keyID };
    NSData *headerData = [NSJSONSerialization dataWithJSONObject:headerDict options:0 error:error];
    if (!headerData) return nil;

    NSString *headerB64  = [CryptoUtils base64URLEncode:headerData];
    NSString *payloadB64 = [CryptoUtils base64URLEncode:payloadData];
    // JWT signature covers base64url(header) || "." || base64url(payload)
    NSString *signingInput = [NSString stringWithFormat:@"%@.%@", headerB64, payloadB64];
    NSData *inputData = [signingInput dataUsingEncoding:NSUTF8StringEncoding];

    NSData *signatureData = [self signData:inputData withKeyID:keyID error:error];
    if (!signatureData) return nil;

    NSString *sigB64 = [CryptoUtils base64URLEncode:signatureData];
    return @{ @"token": [NSString stringWithFormat:@"%@.%@", signingInput, sigB64] };
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

            if (keychainTag && self.useKeychain) {
                // Load key from Keychain
                NSDictionary *query = @{
                    (__bridge id)kSecClass: (__bridge id)kSecClassKey,
                    (__bridge id)kSecAttrApplicationTag: [keychainTag dataUsingEncoding:NSUTF8StringEncoding],
                    (__bridge id)kSecReturnRef: @YES
                };
                OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef *)&privateKey);
                if (status != errSecSuccess) {
                    PDS_LOG_AUTH_WARN(@"Failed to load private key from Keychain for tag: %@ (status: %d)", keychainTag, (int)status);
                }
            }
            
            if (!privateKey && privateKeyData) {
                // Import legacy key from data; use the stored algorithm to determine key type.
                PDS_LOG_AUTH_WARN(@"Loading legacy private key from database for key ID: %@. Migration recommended.", keyID);
                CFTypeRef privateKeyType = [algorithm hasPrefix:@"RS"]
                    ? kSecAttrKeyTypeRSA
                    : kSecAttrKeyTypeECSECPrimeRandom;
                NSDictionary *privateKeyAttrs = @{
                    (__bridge id)kSecAttrKeyType:  (__bridge id)privateKeyType,
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

    CFErrorRef exportError = NULL;
    NSData *privateKeyData = nil;
    NSString *keychainTag = nil;

    if (self.useKeychain) {
        keychainTag = [self keychainTagForKeyID:keyPair.keyID];
        privateKeyData = nil;
    } else {
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

    NSData *publicKeyData = CFBridgingRelease(SecKeyCopyExternalRepresentation(keyPair.publicKey, &exportError));
    if (exportError) {
        if (error) {
            *error = CFBridgingRelease(exportError);
        } else {
            CFRelease(exportError);
        }
        return NO;
    }

    if (!publicKeyData || (self.useKeychain && !keychainTag) || (!self.useKeychain && !privateKeyData)) {
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
    
    return [self verifySignature:signature forData:data withKey:keyPair.publicKey error:error];
}

@end
