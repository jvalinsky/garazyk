#import <Foundation/Foundation.h>

@class Secp256k1KeyPair;

NS_ASSUME_NONNULL_BEGIN

extern NSString * const PLCRotationKeyManagerErrorDomain;

typedef NS_ENUM(NSInteger, PLCRotationKeyManagerError) {
    PLCRotationKeyManagerErrorKeyGenerationFailed = 1,
    PLCRotationKeyManagerErrorKeyStorageFailed = 2,
    PLCRotationKeyManagerErrorKeyNotFound = 3,
    PLCRotationKeyManagerErrorInvalidKey = 4,
};

@interface PLCRotationKeyManager : NSObject

@property (nonatomic, copy, readonly, nullable) NSString *keyStoragePath;
@property (nonatomic, strong, readonly, nullable) Secp256k1KeyPair *rotationKeyPair;
@property (nonatomic, copy, readonly, nullable) NSString *rotationKeyDidKey;

- (instancetype)initWithStoragePath:(nullable NSString *)path;

+ (instancetype)sharedManager;

- (BOOL)loadOrGenerateKeyWithError:(NSError **)error;

- (BOOL)signHash:(NSData *)hash result:(NSData * _Nullable * _Nullable)result error:(NSError **)error;

- (void)clearKey;

@end

NS_ASSUME_NONNULL_END
