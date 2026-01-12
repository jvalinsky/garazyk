#import "Auth/KeyRotationManager.h"
#import "Auth/KeyManager.h"

NSString * const KeyRotationManagerErrorDomain = @"com.atproto.pds.keyrotation";

@interface KeyRotationManager ()

@property (nonatomic, strong) PDSDatabase *database;
@property (nonatomic, strong) KeyManager *keyManager;
@property (nonatomic, strong) NSTimer *rotationTimer;
#if defined(__linux__) || defined(__GNUstep__)
@property (nonatomic, assign) dispatch_queue_t accessQueue;
#else
@property (nonatomic, strong) dispatch_queue_t accessQueue;
#endif

@end

@implementation KeyRotationManager

- (instancetype)initWithKeyStore:(KeyManager *)keyStore {
    self = [super init];
    if (self) {
        _keyManager = keyStore;
        _accessQueue = dispatch_queue_create("com.atproto.pds.keyrotation", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (SecKeyRef _Nullable)currentSigningKey {
    __block SecKeyRef keyRef = NULL;
    
    dispatch_sync(self.accessQueue, ^{
        KeyPair *activeKeyPair = [self.keyManager getActiveKeyPair:nil];
        if (activeKeyPair) {
            keyRef = activeKeyPair.privateKey;
            CFRetain(keyRef);
        }
    });
    
    return keyRef;
}

- (NSArray *)allValidPublicKeys {
    __block NSMutableArray *validKeys = [NSMutableArray array];
    
    dispatch_sync(self.accessQueue, ^{
        NSArray<KeyPair *> *allKeyPairs = [self.keyManager allKeyPairs:nil];
        for (KeyPair *keyPair in allKeyPairs) {
            if (keyPair.isActive) {
                [validKeys addObject:(__bridge id)keyPair.publicKey];
            }
        }
    });
    
    return [validKeys copy];
}

- (BOOL)rotateKeys {
    __block BOOL success = NO;
    
    dispatch_sync(self.accessQueue, ^{
        // Generate a new key pair
        NSError *error = nil;
        KeyPair *newKeyPair = [self.keyManager generateKeyPairWithAlgorithm:@"ECDSA" keySize:256 error:&error];
        
        if (newKeyPair) {
            // Set the new key as active
            success = [self.keyManager setKeyPairActive:newKeyPair.keyID error:&error];
            
            if (success) {
                // Optionally, deactivate old keys after a grace period
                // For now, keep all keys active during transition
                NSLog(@"Key rotation completed successfully. New key ID: %@", newKeyPair.keyID);
            }
        } else {
            NSLog(@"Key rotation failed: %@", error);
        }
    });
    
    return success;
}

- (nullable NSData *)signData:(NSData *)data error:(NSError **)error {
    __block NSData *signature = nil;
    __block NSError *localError = nil;
    
    dispatch_sync(self.accessQueue, ^{
        KeyPair *active = [self.keyManager getActiveKeyPair:&localError];
        if (active) {
            signature = [self.keyManager signData:data withKeyID:active.keyID error:&localError];
        }
    });
    
    if (error) *error = localError;
    return signature;
}

- (BOOL)verifySignature:(NSData *)signature forData:(NSData *)data error:(NSError **)error {
    NSArray *publicKeys = [self allValidPublicKeys];
    for (id keyObj in publicKeys) {
        SecKeyRef publicKey = (__bridge SecKeyRef)keyObj;
        if ([self.keyManager verifySignature:signature forData:data withKey:publicKey error:nil]) {
            return YES;
        }
    }
    
    if (error) {
        *error = [NSError errorWithDomain:KeyRotationManagerErrorDomain
                                     code:KeyRotationManagerErrorKeyNotFound
                                 userInfo:@{NSLocalizedDescriptionKey: @"Signature verification failed with all active keys"}];
    }
    return NO;
}

@end