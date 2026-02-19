//
//  PDSAppleActorKeyManager.m
//  ATProtoPDS
//
//  Created by Antigravity on 2026-02-19.
//

#import "PDSAppleActorKeyManager.h"
#import <Security/Security.h>
#import <CommonCrypto/CommonDigest.h>
#import "Auth/Secp256k1.h"

static NSString * const kSigningKeyService = @"com.atproto.pds.signing";
static NSString * const kSigningKeyAccountPrefix = @"signing-key-";
NSString * const PDSAppleActorKeyManagerErrorDomain = @"com.atproto.pds.actorkeymanager";

@interface PDSAppleActorKeyManager ()
@property (nonatomic, strong) NSData *memoryKeyData; // For fallback
@property (nonatomic, assign) BOOL useKeychain;
@end

@implementation PDSAppleActorKeyManager

- (instancetype)initWithDid:(NSString *)did {
    self = [super init];
    if (self) {
        _did = [did copy];
        _useKeychain = YES; // Default to YES, typically checked against config
        
        // Check for process-wide keychain unavailability (simulating ActorStore logic)
        // In a real refactor, this should be injected or configured.
    }
    return self;
}

#pragma mark - Helper Methods

- (NSString *)keychainAccount {
    return [kSigningKeyAccountPrefix stringByAppendingString:self.did];
}

- (NSDictionary *)keychainQuery {
    return @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kSigningKeyService,
        (__bridge id)kSecAttrAccount: [self keychainAccount],
        (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleAfterFirstUnlock
    };
}

#pragma mark - PDSKeyManager Protocol

- (nullable id<PDSKeyPair>)generateKeyPairWithAlgorithm:(NSString *)algorithm
                                                  keySize:(NSUInteger)keySize
                                                    error:(NSError **)error {
    // We strictly support secp256k1 (ES256K) for Actors right now
    if (![algorithm isEqualToString:@"ES256K"] && ![algorithm isEqualToString:@"secp256k1"]) {
         if (error) {
             *error = [NSError errorWithDomain:PDSAppleActorKeyManagerErrorDomain code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Unsupported algorithm for Actor keys"}];
         }
         return nil;
    }

    NSError *genError = nil;
    Secp256k1KeyPair *keyPair = [Secp256k1KeyPair generateKeyPair:&genError];
    if (!keyPair) {
        if (error) *error = genError;
        return nil;
    }
    
    // Store in Keychain
    if (![self storeKeyData:keyPair.privateKey error:error]) {
        return nil; // Error set by storeKeyData
    }
    
    // We return nil for the KeyPair object because PDSKeyPair protocol is complex 
    // and currently ActorStore doesn't use the returned object from generation, 
    // it just needs the key stored.
    // TODO: Return proper PDSKeyPair wrapper if needed by protocol consumers.
    return nil; 
}

- (nullable id<PDSKeyPair>)getKeyPairWithID:(NSString *)keyID error:(NSError **)error {
    // ActorStore usually has ONE active key. ID is ignored for now.
    NSData *keyData = [self loadKeyData:error];
    if (!keyData) return nil;
    
    // TODO: Return PDSKeyPair wrapper
    return nil;
}

- (nullable NSData *)signData:(NSData *)data error:(NSError **)error {
    // Load key
    NSData *keyData = [self loadKeyData:error];
    if (!keyData) return nil;
    
    // Hash the data (SHA-256)
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    if (!CC_SHA256(data.bytes, (CC_LONG)data.length, hash)) {
        if (error) {
             *error = [NSError errorWithDomain:PDSAppleActorKeyManagerErrorDomain code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Failed to compute SHA256 hash"}];
        }
        return nil;
    }
    NSData *hashData = [NSData dataWithBytes:hash length:CC_SHA256_DIGEST_LENGTH];

    // Sign hash using Secp256k1 wrapper
    return [[Secp256k1 shared] signHash:hashData withPrivateKey:keyData error:error];
}

- (nullable NSData *)exportPublicKeyAndReturnError:(NSError **)error {
      NSData *keyData = [self loadKeyData:error];
      if (!keyData) return nil;

      Secp256k1KeyPair *pair = [Secp256k1KeyPair keyPairWithPrivateKey:keyData error:error];
      if (!pair) return nil;
      
      return pair.compressedPublicKey;
}

#pragma mark - Internal Storage

- (BOOL)storeKeyData:(NSData *)keyData error:(NSError **)error {
    if (keyData.length != 32) {
        if (error) {
            *error = [NSError errorWithDomain:PDSAppleActorKeyManagerErrorDomain
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Signing key must be 32 bytes (secp256k1)"}];
        }
        return NO;
    }

    if (self.useKeychain) {
        NSMutableDictionary *query = [[self keychainQuery] mutableCopy];
        
        // Delete existing
        SecItemDelete((__bridge CFDictionaryRef)query);
        
        // Add new
        query[(__bridge id)kSecValueData] = keyData;
        
        OSStatus status = SecItemAdd((__bridge CFDictionaryRef)query, NULL);
        if (status != errSecSuccess) {
            if (error) {
                *error = [NSError errorWithDomain:NSOSStatusErrorDomain
                                             code:status
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to store key in Keychain"}];
            }
            return NO;
        }
        return YES;
    } else {
        self.memoryKeyData = [keyData copy];
        return YES;
    }
}

- (nullable NSData *)loadKeyData:(NSError **)error {
    if (self.useKeychain) {
        NSMutableDictionary *query = [[self keychainQuery] mutableCopy];
        query[(__bridge id)kSecReturnData] = @YES;
        
        CFTypeRef result = NULL;
        OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
        
        if (status == errSecItemNotFound) {
            if (error) {
                *error = [NSError errorWithDomain:PDSAppleActorKeyManagerErrorDomain
                                             code:status
                                         userInfo:@{NSLocalizedDescriptionKey: @"Key not found in Keychain"}];
            }
            return nil;
        }
        
        if (status != errSecSuccess) {
            if (error) {
                 *error = [NSError errorWithDomain:NSOSStatusErrorDomain
                                              code:status
                                          userInfo:@{NSLocalizedDescriptionKey: @"Keychain error"}];
            }
            return nil;
        }
        
        return CFBridgingRelease(result);
    } else {
        if (!self.memoryKeyData) {
            if (error) {
                *error = [NSError errorWithDomain:PDSAppleActorKeyManagerErrorDomain
                                             code:-1
                                         userInfo:@{NSLocalizedDescriptionKey: @"Key not found in memory"}];
            }
            return nil;
        }
        return self.memoryKeyData;
    }
}

- (BOOL)importKey:(NSData *)keyData error:(NSError **)error {
    return [self storeKeyData:keyData error:error];
}

@end
