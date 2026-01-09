#import "Auth/KeyManager.h"
#import "Auth/JWT.h"
#import <CommonCrypto/CommonDigest.h>

NSString * const KeyManagerErrorDomain = @"com.atproto.pds.keymanager";

@implementation KeyPair

+ (nullable instancetype)keyPairFromPrivateKey:(SecKeyRef)privateKey
                                      publicKey:(SecKeyRef)publicKey
                                        keyID:(NSString *)keyID
                                     algorithm:(NSString *)algorithm {
    if (!privateKey || !publicKey || !keyID) return nil;

    CFRetain(privateKey);
    CFRetain(publicKey);

    KeyPair *keyPair = [[KeyPair alloc] init];
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
    if (error) return nil;

    return keyData;
}

@end

@interface KeyManager ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, KeyPair *> *keyPairs;
@property (nonatomic, strong) dispatch_queue_t accessQueue;
@end

@implementation KeyManager

- (instancetype)init {
    self = [super init];
    if (self) {
        _serviceIdentifier = @"com.atproto.pds.keys";
        _signingAlgorithm = kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256;
        _keyPairs = [NSMutableDictionary dictionary];
        _accessQueue = dispatch_queue_create("com.atproto.pds.keymanager", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (instancetype)initWithServiceIdentifier:(NSString *)serviceIdentifier {
    self = [self init];
    if (self) {
        _serviceIdentifier = serviceIdentifier;
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        _serviceIdentifier = [coder decodeObjectForKey:@"serviceIdentifier"];
        _signingAlgorithm = kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256;
        _keyPairs = [NSMutableDictionary dictionary];
        _accessQueue = dispatch_queue_create("com.atproto.pds.keymanager", DISPATCH_QUEUE_SERIAL);
        _currentKeyID = [coder decodeObjectForKey:@"currentKeyID"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.serviceIdentifier forKey:@"serviceIdentifier"];
    [coder encodeObject:self.currentKeyID forKey:@"currentKeyID"];
}

- (nullable KeyPair *)generateKeyPairWithAlgorithm:(NSString *)algorithm
                                          keySize:(NSUInteger)keySize
                                             error:(NSError **)error {
    NSString *keyID = [[NSUUID UUID] UUIDString];

    NSDictionary *parameters = @{
        (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeRSA,
        (__bridge id)kSecAttrKeySizeInBits: @(keySize),
        (__bridge id)kSecPrivateKeyAttrs: @{
            (__bridge id)kSecAttrIsPermanent: @NO,
            (__bridge id)kSecAttrApplicationTag: [keyID dataUsingEncoding:NSUTF8StringEncoding]
        }
    };

    CFErrorRef cfError = NULL;
    SecKeyRef privateKey = SecKeyCreateRandomKey((__bridge CFDictionaryRef)parameters, &cfError);

    if (cfError) {
        if (error) {
            *error = CFBridgingRelease(cfError);
        }
        return nil;
    }

    CFErrorRef pubError = NULL;
    SecKeyRef publicKey = SecKeyCopyPublicKey(privateKey);

    if (pubError) {
        CFRelease(privateKey);
        if (error) {
            *error = CFBridgingRelease(pubError);
        }
        return nil;
    }

    KeyPair *keyPair = [KeyPair keyPairFromPrivateKey:privateKey
                                             publicKey:publicKey
                                                keyID:keyID
                                             algorithm:algorithm];

    dispatch_sync(self.accessQueue, ^{
        self.keyPairs[keyID] = keyPair;
    });

    self.currentKeyID = keyID;

    return keyPair;
}

- (nullable KeyPair *)generateECDSAKeyPairWithCurve:(NSString *)curve
                                             error:(NSError **)error {
    NSString *keyID = [[NSUUID UUID] UUIDString];

    NSDictionary *parameters = @{
        (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
        (__bridge id)kSecAttrKeySizeInBits: @(256),
        (__bridge id)kSecPrivateKeyAttrs: @{
            (__bridge id)kSecAttrIsPermanent: @NO,
            (__bridge id)kSecAttrApplicationTag: [keyID dataUsingEncoding:NSUTF8StringEncoding]
        }
    };

    CFErrorRef cfError = NULL;
    SecKeyRef privateKey = SecKeyCreateRandomKey((__bridge CFDictionaryRef)parameters, &cfError);

    if (cfError) {
        if (error) {
            *error = CFBridgingRelease(cfError);
        }
        return nil;
    }

    CFErrorRef pubError = NULL;
    SecKeyRef publicKey = SecKeyCopyPublicKey(privateKey);

    if (pubError) {
        CFRelease(privateKey);
        if (error) {
            *error = CFBridgingRelease(pubError);
        }
        return nil;
    }

    KeyPair *keyPair = [KeyPair keyPairFromPrivateKey:privateKey
                                             publicKey:publicKey
                                                keyID:keyID
                                             algorithm:@"ES256"];

    dispatch_sync(self.accessQueue, ^{
        self.keyPairs[keyID] = keyPair;
    });

    self.currentKeyID = keyID;

    return keyPair;
}

- (nullable KeyPair *)getKeyPairWithID:(NSString *)keyID error:(NSError **)error {
    __block KeyPair *keyPair = nil;

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

- (nullable KeyPair *)getActiveKeyPair:(NSError **)error {
    if (self.currentKeyID) {
        return [self getKeyPairWithID:self.currentKeyID error:error];
    }

    NSArray *keys = [self allKeyPairs:error];
    for (KeyPair *keyPair in keys) {
        if (keyPair.isActive) {
            return keyPair;
        }
    }

    return [self generateKeyPairWithAlgorithm:@"RS256" keySize:2048 error:error];
}

- (NSArray<KeyPair *> *)allKeyPairs:(NSError **)error {
    __block NSArray *keyPairs = @[];

    dispatch_sync(self.accessQueue, ^{
        keyPairs = [self.keyPairs.allValues copy];
    });

    return keyPairs;
}

- (BOOL)deleteKeyPairWithID:(NSString *)keyID error:(NSError **)error {
    __block BOOL success = NO;

    dispatch_sync(self.accessQueue, ^{
        KeyPair *keyPair = self.keyPairs[keyID];
        if (keyPair) {
            if (keyPair.privateKey) CFRelease(keyPair.privateKey);
            if (keyPair.publicKey) CFRelease(keyPair.publicKey);
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
            for (KeyPair *keyPair in self.keyPairs.allValues) {
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
    KeyPair *keyPair = [self getKeyPairWithID:keyID error:error];
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
    KeyPair *activeKey = [self getActiveKeyPair:nil];
    if (activeKey) {
        return [activeKey publicKeyJWK] ?: @{};
    }
    return @{};
}

- (NSArray<NSDictionary *> *)toJWKSArray {
    NSMutableArray *jwks = [NSMutableArray array];
    NSArray *keyPairs = [self allKeyPairs:nil];

    for (KeyPair *keyPair in keyPairs) {
        NSDictionary *jwk = [keyPair publicKeyJWK];
        if (jwk) {
            [jwks addObject:jwk];
        }
    }

    return jwks;
}

@end

@implementation KeyRotationManager

- (instancetype)init {
    self = [super init];
    if (self) {
        _keyLifetime = 86400 * 30;
        _rotationGracePeriod = 86400 * 7;
        _maxActiveKeys = 2;
    }
    return self;
}

- (void)performScheduledRotation:(void (^)(NSString * _Nullable, NSError * _Nullable))completion {
}

- (BOOL)shouldRotateKeyWithID:(NSString *)keyID createdAt:(NSDate *)createdAt {
    NSTimeInterval age = [[NSDate date] timeIntervalSinceDate:createdAt];
    return age >= (self.keyLifetime - self.rotationGracePeriod);
}

@end
