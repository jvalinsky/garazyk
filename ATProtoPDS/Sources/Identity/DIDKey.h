#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const DIDKeyErrorDomain;

typedef NS_ENUM(NSInteger, DIDKeyError) {
    DIDKeyErrorInvalidFormat = 1,
    DIDKeyErrorInvalidMultibase = 2,
    DIDKeyErrorUnsupportedKeyType = 3,
    DIDKeyErrorSigningFailed = 4,
    DIDKeyErrorVerificationFailed = 5
};

@interface DIDKey : NSObject <NSSecureCoding>

@property (nonatomic, copy, readonly) NSString *didKey;
@property (nonatomic, strong, readonly) NSData *publicKeyData;
@property (nonatomic, strong, readonly, nullable) NSData *privateKeyData;
@property (nonatomic, assign, readonly) BOOL isPublicKey;
@property (nonatomic, copy, readonly) NSString *fingerprint;

+ (nullable instancetype)parse:(NSString *)didKeyString error:(NSError **)error;

+ (instancetype)generateSecp256k1;

- (instancetype)initWithPublicKeyData:(NSData *)publicKeyData
                         didKeyString:(NSString *)didKeyString;

- (instancetype)initWithPublicKeyData:(NSData *)publicKeyData
                         privateKeyData:(NSData *)privateKeyData
                         didKeyString:(NSString *)didKeyString;

- (nullable NSData *)signData:(NSData *)data error:(NSError **)error;

- (BOOL)verifySignature:(NSData *)signature forData:(NSData *)data error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
