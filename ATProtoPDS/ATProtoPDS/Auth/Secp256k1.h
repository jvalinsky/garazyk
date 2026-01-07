#import <Foundation/Foundation.h>
#import "secp256k1_wrapper_c.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString * const Secp256k1ErrorDomain;

@interface Secp256k1KeyPair : NSObject

@property (nonatomic, strong, readonly) NSData *privateKey;
@property (nonatomic, strong, readonly) NSData *publicKey;
@property (nonatomic, strong, readonly) NSData *compressedPublicKey;

+ (nullable instancetype)generateKeyPair:(NSError **)error;
+ (nullable instancetype)keyPairWithPrivateKey:(NSData *)privateKey error:(NSError **)error;

- (nullable NSData *)signHash:(NSData *)hash error:(NSError **)error;
- (BOOL)verifySignature:(NSData *)signature forHash:(NSData *)hash error:(NSError **)error;

@end

@interface Secp256k1 : NSObject

+ (instancetype)shared;

- (nullable Secp256k1KeyPair *)generateKeyPairWithError:(NSError **)error;
- (nullable Secp256k1KeyPair *)keyPairFromPrivateKey:(NSData *)privateKey error:(NSError **)error;
- (nullable NSData *)signHash:(NSData *)hash withPrivateKey:(NSData *)privateKey error:(NSError **)error;
- (BOOL)verifySignature:(NSData *)signature forHash:(NSData *)hash withPublicKey:(NSData *)publicKey error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
