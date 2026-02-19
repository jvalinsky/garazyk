#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Actor signing key management contract used by PDSActorStore.
 *
 * Keys are secp256k1 private keys (32 bytes). Implementations choose
 * platform-appropriate storage (for example Keychain on macOS).
 */
@protocol PDSActorKeyManager <NSObject>

- (BOOL)generateSigningKeyWithError:(NSError **)error;
- (BOOL)importSigningKey:(NSData *)privateKey error:(NSError **)error;
- (nullable NSData *)signData:(NSData *)data error:(NSError **)error;
- (nullable NSData *)publicSigningKeyWithError:(NSError **)error;
- (nullable NSString *)didKeyStringWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
