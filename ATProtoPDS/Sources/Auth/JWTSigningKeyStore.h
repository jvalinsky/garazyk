/*!
 @file JWTSigningKeyStore.h

 @abstract Persistence for the PDS JWT signing key.

 @discussion The PDS mints JWTs using secp256k1 (ES256K). If the signing key is
 regenerated on each boot, all existing sessions immediately become invalid.
 This helper loads a stable server signing key from disk (data directory by
 default) or creates it on first run.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class Secp256k1KeyPair;

@interface JWTSigningKeyStore : NSObject

/*! Returns the path used to store the server JWT signing private key. */
+ (NSString *)privateKeyPathForDataDirectory:(NSString *)dataDirectory;

/*! Loads an existing server signing key, or creates and persists one. */
+ (nullable Secp256k1KeyPair *)loadOrCreateKeyPairForDataDirectory:(NSString *)dataDirectory
                                                             error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

