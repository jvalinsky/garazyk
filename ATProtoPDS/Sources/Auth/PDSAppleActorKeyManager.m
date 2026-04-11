//
//  PDSAppleActorKeyManager.m
//  ATProtoPDS
//

#import "PDSAppleActorKeyManager.h"

#import <CommonCrypto/CommonDigest.h>

#import "App/PDSConfiguration.h"
#import "Auth/Secp256k1.h"

#if !defined(GNUSTEP)
#import <Security/Security.h>
#endif

NSString * const PDSAppleActorKeyManagerErrorDomain = @"com.atproto.pds.actorkeymanager";

static NSString * const kSigningKeyService = @"com.atproto.pds.signing";
static NSString * const kSigningKeyAccountPrefix = @"signing-key-";

@interface PDSAppleActorKeyManager ()
@property (nonatomic, strong, nullable) NSData *memoryKeyData;
@property (nonatomic, assign) BOOL useKeychain;
@end

@implementation PDSAppleActorKeyManager

- (instancetype)initWithDid:(NSString *)did {
    self = [super init];
    if (self) {
        _did = [did copy];
#if defined(GNUSTEP)
        _useKeychain = NO;
#else
        _useKeychain = [PDSConfiguration sharedConfiguration].useKeychain;
#endif
    }
    return self;
}

- (BOOL)generateSigningKeyWithError:(NSError **)error {
    NSError *genError = nil;
    Secp256k1KeyPair *keyPair = [Secp256k1KeyPair generateKeyPair:&genError];
    if (!keyPair) {
        if (error) {
            *error = genError;
        }
        return NO;
    }
    return [self importSigningKey:keyPair.privateKey error:error];
}

- (BOOL)importSigningKey:(NSData *)privateKey error:(NSError **)error {
    if (privateKey.length != 32) {
        if (error) {
            *error = [NSError errorWithDomain:PDSAppleActorKeyManagerErrorDomain
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Signing key must be 32 bytes (secp256k1)"}];
        }
        return NO;
    }

    if (!self.useKeychain) {
        self.memoryKeyData = [privateKey copy];
        if ([self.delegate respondsToSelector:@selector(appleActorKeyManager:storeSigningKey:publicKey:error:)]) {
            Secp256k1KeyPair *kp = [Secp256k1KeyPair keyPairWithPrivateKey:privateKey error:nil];
            [self.delegate appleActorKeyManager:self storeSigningKey:privateKey publicKey:kp.compressedPublicKey error:nil];
        }
        return YES;
    }

#if defined(GNUSTEP)
    // GNUstep does not provide macOS Keychain APIs.
    self.memoryKeyData = [privateKey copy];
    return YES;
#else
    NSString *account = [self keychainAccount];

    NSDictionary *deleteQuery = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kSigningKeyService,
        (__bridge id)kSecAttrAccount: account
    };
    SecItemDelete((__bridge CFDictionaryRef)deleteQuery);

    NSMutableDictionary *addQuery = [NSMutableDictionary dictionaryWithDictionary:deleteQuery];
    addQuery[(__bridge id)kSecValueData] = privateKey;
    addQuery[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlock;

    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)addQuery, NULL);
    if (status == errSecSuccess) {
        self.memoryKeyData = nil;
        return YES;
    }

    if ([self shouldFallbackToMemoryForKeychainStatus:status]) {
        self.memoryKeyData = [privateKey copy];
        return YES;
    }

    if (error) {
        *error = [NSError errorWithDomain:NSOSStatusErrorDomain
                                     code:status
                                 userInfo:@{NSLocalizedDescriptionKey: @"Failed to store signing key in Keychain"}];
    }
    return NO;
#endif
}

- (nullable NSData *)signData:(NSData *)data error:(NSError **)error {
    NSData *privateKey = [self loadPrivateKeyWithError:error];
    if (!privateKey) {
        return nil;
    }

    uint8_t hash[CC_SHA256_DIGEST_LENGTH] = {0};
    if (!CC_SHA256(data.bytes, (CC_LONG)data.length, hash)) {
        if (error) {
            *error = [NSError errorWithDomain:PDSAppleActorKeyManagerErrorDomain
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to hash signing payload"}];
        }
        return nil;
    }

    NSData *hashData = [NSData dataWithBytes:hash length:CC_SHA256_DIGEST_LENGTH];
    return [[Secp256k1 shared] signHash:hashData withPrivateKey:privateKey error:error];
}

- (nullable NSData *)publicSigningKeyWithError:(NSError **)error {
    NSData *privateKey = [self loadPrivateKeyWithError:error];
    if (!privateKey) {
        return nil;
    }

    Secp256k1KeyPair *keyPair = [Secp256k1KeyPair keyPairWithPrivateKey:privateKey error:error];
    if (!keyPair) {
        return nil;
    }
    return keyPair.compressedPublicKey;
}

- (nullable NSString *)didKeyStringWithError:(NSError **)error {
    NSData *privateKey = [self loadPrivateKeyWithError:error];
    if (!privateKey) {
        return nil;
    }

    Secp256k1KeyPair *keyPair = [Secp256k1KeyPair keyPairWithPrivateKey:privateKey error:error];
    if (!keyPair) {
        return nil;
    }
    return keyPair.didKeyString;
}

- (nullable NSData *)exportPrivateKeyWithError:(NSError **)error {
    return [self loadPrivateKeyWithError:error];
}

- (nullable NSData *)loadPrivateKeyWithError:(NSError **)error {
    if (self.memoryKeyData.length == 32) {
        return self.memoryKeyData;
    }

    if (!self.useKeychain) {
        if (self.memoryKeyData.length == 32) {
            return self.memoryKeyData;
        }
        if ([self.delegate respondsToSelector:@selector(appleActorKeyManagerLoadSigningKey:error:)]) {
            self.memoryKeyData = [self.delegate appleActorKeyManagerLoadSigningKey:self error:nil];
            if (self.memoryKeyData.length == 32) {
                return self.memoryKeyData;
            }
        }
        if (error) {
            *error = [NSError errorWithDomain:PDSAppleActorKeyManagerErrorDomain
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Signing key not found"}];
        }
        return nil;
    }

#if defined(GNUSTEP)
    if (error) {
        *error = [NSError errorWithDomain:PDSAppleActorKeyManagerErrorDomain
                                     code:-1
                                 userInfo:@{NSLocalizedDescriptionKey: @"Keychain APIs are unavailable on GNUstep"}];
    }
    return nil;
#else
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kSigningKeyService,
        (__bridge id)kSecAttrAccount: [self keychainAccount],
        (__bridge id)kSecReturnData: @YES,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne
    };

    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status == errSecSuccess && result != NULL) {
        NSData *keyData = CFBridgingRelease(result);
        if (keyData.length == 32) {
            return keyData;
        }
        if (error) {
            *error = [NSError errorWithDomain:PDSAppleActorKeyManagerErrorDomain
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Stored signing key has invalid length"}];
        }
        return nil;
    }

    if ([self shouldFallbackToMemoryForKeychainStatus:status] && self.memoryKeyData.length == 32) {
        return self.memoryKeyData;
    }

    if (status == errSecItemNotFound) {
        if (error) {
            *error = [NSError errorWithDomain:PDSAppleActorKeyManagerErrorDomain
                                         code:status
                                     userInfo:@{NSLocalizedDescriptionKey: @"Signing key not found"}];
        }
        return nil;
    }

    if (error) {
        *error = [NSError errorWithDomain:NSOSStatusErrorDomain
                                     code:status
                                 userInfo:@{NSLocalizedDescriptionKey: @"Failed to load signing key from Keychain"}];
    }
    return nil;
#endif
}

- (NSString *)keychainAccount {
    return [kSigningKeyAccountPrefix stringByAppendingString:self.did];
}

#if !defined(GNUSTEP)
- (BOOL)shouldFallbackToMemoryForKeychainStatus:(OSStatus)status {
    return status == errSecNotAvailable ||
           status == errSecNoSuchKeychain ||
           status == errSecInteractionNotAllowed ||
           status == errSecParam;
}
#endif

@end
