//
//  PDSOpenSSLSessionKeyManager.m
//  ATProtoPDS
//
//  Created by Jack Valinsky on 2/18/26.
//  Copyright (c) 2026 Jack Valinsky. All rights reserved.
//

#import "PDSOpenSSLSessionKeyManager.h"
#import "Database/PDSDatabase.h"
#import "Core/NSDateFormatter+ATProto.h"
#import "Debug/PDSLogger.h"
#import "Compat/PDSTypes.h"
#import <openssl/rsa.h>
#import <openssl/pem.h>
#import <openssl/err.h>
#import <openssl/evp.h>
#import <openssl/bio.h>
#import <openssl/buffer.h>

// Error domain
NSString * const OpenSSLKeyManagerErrorDomain = @"com.atproto.pds.opensslsessionkeymanager";

@interface PDSOpenSSLKeyPair : NSObject <PDSKeyPair>
@property (nonatomic, copy) NSString *keyID;
@property (nonatomic, copy) NSString *algorithm;
@property (nonatomic, assign) RSA *rsaKey; // Owned by this object
@property (nonatomic, strong) NSDate *createdAt;
@property (nonatomic, assign) BOOL isActive;
@end

@implementation PDSOpenSSLKeyPair

- (void)dealloc {
    if (_rsaKey) {
        RSA_free(_rsaKey);
        _rsaKey = NULL;
    }
}

- (nullable NSDictionary *)publicKeyJWK {
    if (!self.rsaKey) return nil;

    // Extract n (modulus) and e (exponent)
    const BIGNUM *n = NULL;
    const BIGNUM *e = NULL;
    RSA_get0_key(self.rsaKey, &n, &e, NULL);

    if (!n || !e) return nil;

    NSData *nData = [self dataFromBIGNUM:n];
    NSData *eData = [self dataFromBIGNUM:e];

    NSString *nStr = [self base64UrlEncode:nData];
    NSString *eStr = [self base64UrlEncode:eData];

    return @{
        @"kty": @"RSA",
        @"kid": self.keyID,
        @"alg": self.algorithm,
        @"use": @"sig",
        @"n": nStr,
        @"e": eStr
    };
}

- (nullable NSString *)publicKeyThumbprint {
    NSDictionary *jwk = [self publicKeyJWK];
    if (!jwk) return nil;

    // Create canonical JSON for thumbprint (sorted keys)
    // For RSA, required members are e, kty, n
    NSDictionary *thumbprintJWK = @{
        @"e": jwk[@"e"],
        @"kty": jwk[@"kty"],
        @"n": jwk[@"n"]
    };

    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:thumbprintJWK options:NSJSONWritingSortedKeys error:nil];
    if (!jsonData) return nil;

    unsigned char hash[SHA256_DIGEST_LENGTH];
    SHA256(jsonData.bytes, jsonData.length, hash);

    NSData *hashData = [NSData dataWithBytes:hash length:SHA256_DIGEST_LENGTH];
    return [self base64UrlEncode:hashData];
}

#pragma mark - Helpers

- (NSData *)dataFromBIGNUM:(const BIGNUM *)bn {
    int len = BN_num_bytes(bn);
    unsigned char *buf = malloc(len);
    BN_bn2bin(bn, buf);
    NSData *data = [NSData dataWithBytes:buf length:len];
    free(buf);
    return data;
}

- (NSString *)base64UrlEncode:(NSData *)data {
    NSString *base64 = [data base64EncodedStringWithOptions:0];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"=" withString:@""];
    return base64;
}

@end

@interface PDSOpenSSLSessionKeyManager ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, PDSOpenSSLKeyPair *> *keyPairs;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t accessQueue;
@property (nonatomic, copy) NSString *currentKeyID;
@end

@implementation PDSOpenSSLSessionKeyManager

- (instancetype)initWithDatabase:(PDSDatabase *)database {
    self = [super init];
    if (self) {
        _database = database;
        _keyPairs = [NSMutableDictionary dictionary];
        _accessQueue = dispatch_queue_create("com.atproto.pds.opensslsessionkeymanager", DISPATCH_QUEUE_SERIAL);
        [self loadKeysFromDatabase];
    }
    return self;
}

- (nullable id<PDSKeyPair>)generateKeyPairWithAlgorithm:(NSString *)algorithm
                                               keySize:(NSUInteger)keySize
                                                 error:(NSError **)error {
    // Only support RS256 for now
    if (![algorithm isEqualToString:@"RS256"]) {
        if (error) {
            *error = [NSError errorWithDomain:OpenSSLKeyManagerErrorDomain
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unsupported algorithm (OpenSSL manager only supports RS256)"}];
        }
        return nil;
    }

    NSString *keyID = [[NSUUID UUID] UUIDString];
    RSA *rsa = RSA_new();
    BIGNUM *e = BN_new();
    BN_set_word(e, RSA_F4);

    if (RSA_generate_key_ex(rsa, (int)keySize, e, NULL) != 1) {
        if (error) {
            *error = [NSError errorWithDomain:OpenSSLKeyManagerErrorDomain
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to generate RSA key"}];
        }
        RSA_free(rsa);
        BN_free(e);
        return nil;
    }
    BN_free(e);

    PDSOpenSSLKeyPair *keyPair = [[PDSOpenSSLKeyPair alloc] init];
    keyPair.keyID = keyID;
    keyPair.algorithm = algorithm;
    keyPair.rsaKey = rsa;
    keyPair.createdAt = [NSDate date];
    keyPair.isActive = YES;

    dispatch_sync(self.accessQueue, ^{
        self.keyPairs[keyID] = keyPair;
        self.currentKeyID = keyID;
    });

    [self saveKeyPairToDatabase:keyPair error:nil];

    return keyPair;
}

- (nullable id<PDSKeyPair>)getKeyPairWithID:(NSString *)keyID error:(NSError **)error {
    __block PDSOpenSSLKeyPair *keyPair = nil;
    dispatch_sync(self.accessQueue, ^{
        keyPair = self.keyPairs[keyID];
    });
    return keyPair;
}

- (nullable id<PDSKeyPair>)getActiveKeyPair:(NSError **)error {
    __block PDSOpenSSLKeyPair *active = nil;
    dispatch_sync(self.accessQueue, ^{
        if (self.currentKeyID) {
            active = self.keyPairs[self.currentKeyID];
        } else {
             // Find any active
            for (PDSOpenSSLKeyPair *kp in self.keyPairs.allValues) {
                if (kp.isActive) {
                    active = kp;
                     self.currentKeyID = kp.keyID;
                    break;
                }
            }
        }
    });

    if (!active) {
        return [self generateKeyPairWithAlgorithm:@"RS256" keySize:2048 error:error];
    }
    return active;
}

- (NSArray<id<PDSKeyPair>> *)allKeyPairs:(NSError **)error {
    __block NSArray *all = nil;
    dispatch_sync(self.accessQueue, ^{
        all = [self.keyPairs.allValues copy];
    });
    return all;
}

- (BOOL)deleteKeyPairWithID:(NSString *)keyID error:(NSError **)error {
    dispatch_sync(self.accessQueue, ^{
        [self.keyPairs removeObjectForKey:keyID];
        if ([self.currentKeyID isEqualToString:keyID]) {
            self.currentKeyID = nil;
        }
    });
    // Also delete from DB? Protocol doesn't strictly imply, but PDSAppleKeyManager does not implement delete from DB in detail in snippet provided (it does remove from memory).
    // Assuming memory only for explicit delete unless we add SQL delete.
    return YES;
}

- (BOOL)setKeyPairActive:(NSString *)keyID error:(NSError **)error {
    __block BOOL found = NO;
    dispatch_sync(self.accessQueue, ^{
        PDSOpenSSLKeyPair *target = self.keyPairs[keyID];
        if (target) {
            for (PDSOpenSSLKeyPair *kp in self.keyPairs.allValues) {
                kp.isActive = NO;
            }
            target.isActive = YES;
            self.currentKeyID = keyID;
            found = YES;
        }
    });
    
    // We should probably update DB here to reflect active status, but sticking to memory for now as primary cache.
    // PDSAppleKeyManager updates isActive in DB on 'save', but update query logic is complex.
    // Ideally we re-save the key with new flag.
    if (found) {
        id<PDSKeyPair> kp = [self getKeyPairWithID:keyID error:nil];
        if (kp) [self saveKeyPairToDatabase:(PDSOpenSSLKeyPair*)kp error:nil];
    }
    
    return found;
}

- (nullable NSData *)signData:(NSData *)data
                     withKeyID:(NSString *)keyID
                         error:(NSError **)error {
    PDSOpenSSLKeyPair *keyPair = (PDSOpenSSLKeyPair *)[self getKeyPairWithID:keyID error:error];
    if (!keyPair || !keyPair.rsaKey) return nil;

    unsigned char hash[SHA256_DIGEST_LENGTH];
    SHA256(data.bytes, data.length, hash);

    unsigned char *sig = malloc(RSA_size(keyPair.rsaKey));
    unsigned int sigLen = 0;

    int result = RSA_sign(NID_sha256, hash, SHA256_DIGEST_LENGTH, sig, &sigLen, keyPair.rsaKey);

    if (result != 1) {
        free(sig);
        if (error) {
            *error = [NSError errorWithDomain:OpenSSLKeyManagerErrorDomain
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"RSA_sign failed"}];
        }
        return nil;
    }

    NSData *signature = [NSData dataWithBytes:sig length:sigLen];
    free(sig);
    return signature;
}

- (nullable NSDictionary *)signPayload:(NSDictionary *)payload
                              withKeyID:(NSString *)keyID
                                  error:(NSError **)error {
    // Basic JWT construction
    NSData *payloadData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:error];
    if (!payloadData) return nil;
    
    NSMutableDictionary *header = [NSMutableDictionary dictionary];
    header[@"alg"] = @"RS256";
    header[@"typ"] = @"JWT";
    header[@"kid"] = keyID;
    
    NSData *headerData = [NSJSONSerialization dataWithJSONObject:header options:0 error:error];
    if (!headerData) return nil;
    
    NSString *headerB64 = [self base64UrlEncode:headerData];
    NSString *payloadB64 = [self base64UrlEncode:payloadData];
    
    NSString *signingInput = [NSString stringWithFormat:@"%@.%@", headerB64, payloadB64];
    NSData *inputData = [signingInput dataUsingEncoding:NSUTF8StringEncoding];
    
    NSData *signature = [self signData:inputData withKeyID:keyID error:error];
    if (!signature) return nil;
    
    NSString *sigB64 = [self base64UrlEncode:signature];
    
    return @{@"token": [NSString stringWithFormat:@"%@.%@", signingInput, sigB64]};
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
              withKeyID:(NSString *)keyID
                  error:(NSError **)error {
    PDSOpenSSLKeyPair *keyPair = (PDSOpenSSLKeyPair *)[self getKeyPairWithID:keyID error:error];
    if (!keyPair || !keyPair.rsaKey) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:OpenSSLKeyManagerErrorDomain
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Key not found or invalid"}];
        }
        return NO;
    }

    // Hash the data first (SHA256)
    unsigned char hash[SHA256_DIGEST_LENGTH];
    SHA256(data.bytes, data.length, hash);

    // Verify signature
    // RSA_verify returns 1 on success.
    int result = RSA_verify(NID_sha256, hash, SHA256_DIGEST_LENGTH, (unsigned char *)signature.bytes, (unsigned int)signature.length, keyPair.rsaKey);

    if (result != 1) {
        if (error) {
            unsigned long err = ERR_get_error();
            char errBuf[256];
            ERR_error_string_n(err, errBuf, sizeof(errBuf));
            *error = [NSError errorWithDomain:OpenSSLKeyManagerErrorDomain
                                         code:err
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:errBuf]}];
        }
        return NO;
    }

    return YES;
}

- (NSDictionary *)toJWKS {
    id<PDSKeyPair> active = [self getActiveKeyPair:nil];
    return active ? ([active publicKeyJWK] ?: @{}) : @{};
}

- (NSArray<NSDictionary *> *)toJWKSArray {
    NSMutableArray *arr = [NSMutableArray array];
    NSArray *keys = [self allKeyPairs:nil];
    for (id<PDSKeyPair> k in keys) {
        NSDictionary *jwk = [k publicKeyJWK];
        if (jwk) [arr addObject:jwk];
    }
    return arr;
}

#pragma mark - Utils

- (NSString *)base64UrlEncode:(NSData *)data {
    NSString *base64 = [data base64EncodedStringWithOptions:0];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"=" withString:@""];
    return base64;
}

#pragma mark - Persistence

- (void)loadKeysFromDatabase {
    if (!self.database) return;

    NSError *error = nil;
    NSArray *results = [self.database executeQuery:@"SELECT key_id, algorithm, private_key_data, public_key_data, keychain_tag, is_active, created_at FROM jwt_signing_keys ORDER BY created_at DESC" error:&error];

    if (error) {
        PDS_LOG_AUTH_ERROR(@"Failed to load keys: %@", error);
        return;
    }

    for (NSDictionary *row in results) {
        NSString *keyID = row[@"key_id"];
        NSString *algorithm = row[@"algorithm"];
        NSData *privData = [row[@"private_key_data"] isKindOfClass:[NSData class]] ? row[@"private_key_data"] : nil;
        NSString *keychainTag = row[@"keychain_tag"];
        NSNumber *active = row[@"is_active"];
        NSString *createdAtStr = row[@"created_at"];
        
        if ([keychainTag isKindOfClass:[NSString class]] && keychainTag.length > 0) {
            PDS_LOG_AUTH_WARN(@"OpenSSL manager skipping hardware-backed key: %@", keychainTag);
            continue;
        }

        if (!privData) continue;

        // Deserialize OpenSSL RSA key
        const unsigned char *p = privData.bytes;
        RSA *rsa = d2i_RSAPrivateKey(NULL, &p, (long)privData.length);
        
        if (rsa) {
            PDSOpenSSLKeyPair *kp = [[PDSOpenSSLKeyPair alloc] init];
            kp.keyID = keyID;
            kp.algorithm = algorithm;
            kp.rsaKey = rsa;
            kp.isActive = [active boolValue];
            kp.createdAt = [self dateFromISO8601:createdAtStr];
            
            dispatch_sync(self.accessQueue, ^{
                self.keyPairs[keyID] = kp;
                if (kp.isActive && !self.currentKeyID) {
                    self.currentKeyID = keyID;
                }
            });
        }
    }
}

- (BOOL)saveKeyPairToDatabase:(PDSOpenSSLKeyPair *)keyPair error:(NSError **)error {
    if (!self.database) return YES;
    
    // Serialize RSA private key
    if (!keyPair.rsaKey) return NO;
    
    int len = i2d_RSAPrivateKey(keyPair.rsaKey, NULL);
    unsigned char *buf = malloc(len);
    unsigned char *p = buf;
    i2d_RSAPrivateKey(keyPair.rsaKey, &p);
    NSData *privData = [NSData dataWithBytes:buf length:len];
    free(buf);
    
    // Serialize public key
    int pubLen = i2d_RSAPublicKey(keyPair.rsaKey, NULL);
    unsigned char *pubBuf = malloc(pubLen);
    unsigned char *pubP = pubBuf;
    i2d_RSAPublicKey(keyPair.rsaKey, &pubP);
    NSData *pubData = [NSData dataWithBytes:pubBuf length:pubLen];
    free(pubBuf);
    
    NSString *sql = @"INSERT OR REPLACE INTO jwt_signing_keys (key_id, algorithm, private_key_data, public_key_data, keychain_tag, is_active, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)";
    
    NSArray *params = @[
        keyPair.keyID,
        keyPair.algorithm,
        privData,
        pubData,
        [NSNull null], // keychain_tag
        @(keyPair.isActive),
        [self iso8601StringFromDate:keyPair.createdAt ?: [NSDate date]]
    ];
    
    return [self.database executeParameterizedUpdate:sql params:params error:error];
}

- (NSString *)iso8601StringFromDate:(NSDate *)date {
    return [NSDateFormatter atproto_stringFromDate:date];
}

- (NSDate *)dateFromISO8601:(NSString *)string {
    return [NSDateFormatter atproto_dateFromString:string];
}

@end
