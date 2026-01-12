#import <Foundation/Foundation.h>
#import <Security/Security.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const KeyRotationManagerErrorDomain;

typedef NS_ENUM(NSInteger, KeyRotationManagerError) {
    KeyRotationManagerErrorKeyGenerationFailed = 1000,
    KeyRotationManagerErrorKeyNotFound,
    KeyRotationManagerErrorRotationFailed
};

@class KeyManager;

@interface KeyRotationManager : NSObject

- (instancetype)initWithKeyStore:(KeyManager *)keyStore;
- (SecKeyRef _Nullable)currentSigningKey;
- (NSArray *)allValidPublicKeys;
- (BOOL)rotateKeys;
- (nullable NSData *)signData:(NSData *)data error:(NSError **)error;
- (BOOL)verifySignature:(NSData *)signature forData:(NSData *)data error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END