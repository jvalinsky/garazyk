#import "Auth/KeyRotationManager.h"
#import "Auth/KeyManager.h"

NSString * const KeyRotationManagerErrorDomain = @"com.atproto.pds.keyrotation";

@interface KeyRotationManager ()

@property (nonatomic, strong) KeyManager *keyStore;
@property (nonatomic, strong) dispatch_queue_t accessQueue;

@end

@implementation KeyRotationManager

- (instancetype)initWithKeyStore:(KeyManager *)keyStore {
    self = [super init];
    if (self) {
        _keyStore = keyStore;
        _accessQueue = dispatch_queue_create("com.atproto.pds.keyrotation", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (SecKeyRef _Nullable)currentSigningKey {
    __block SecKeyRef keyRef = NULL;
    
    dispatch_sync(self.accessQueue, ^{
        KeyPair *activeKeyPair = [self.keyStore getActiveKeyPair:nil];
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
        NSArray<KeyPair *> *allKeyPairs = [self.keyStore allKeyPairs:nil];
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
        KeyPair *newKeyPair = [self.keyStore generateKeyPairWithAlgorithm:@"ECDSA" keySize:256 error:&error];
        
        if (newKeyPair) {
            // Set the new key as active
            success = [self.keyStore setKeyPairActive:newKeyPair.keyID error:&error];
            
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

@end