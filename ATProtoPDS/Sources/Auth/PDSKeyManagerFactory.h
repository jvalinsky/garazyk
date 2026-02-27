/*!
 @file PDSKeyManagerFactory.h

 @abstract Factory for creating platform-appropriate key managers.

 @discussion
    Creates the appropriate PDSKeyManager implementation based on the
    current platform:
    - macOS/iOS: PDSAppleKeyManager (Security.framework)
    - Linux: PDSOpenSSLKeyManager (OpenSSL)

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "PDSKeyManagerProtocol.h"

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabase;

/*!
 @class PDSKeyManagerFactory

 @abstract Factory for creating platform-appropriate key managers.

 @discussion
    Provides a unified entry point for obtaining a key manager instance
    without requiring platform-specific code at call sites.

 @code
    id<PDSKeyManager> keyManager = [PDSKeyManagerFactory createKeyManagerWithDatabase:database];
    id<PDSKeyPair> keyPair = [keyManager generateKeyPairWithAlgorithm:@"ES256" keySize:256 error:&error];
 @endcode
 */
@interface PDSKeyManagerFactory : NSObject

/*!
 @method createKeyManagerWithDatabase:

 @abstract Creates a platform-appropriate key manager.

 @param database The database for key storage metadata.

 @return A PDSKeyManager implementation appropriate for the current platform.
         Returns PDSAppleKeyManager on macOS/iOS, PDSOpenSSLKeyManager on Linux.

 @discussion
    The database is used for storing key metadata and, on Linux, the actual
    key material. On macOS/iOS, keys are stored in the Keychain with only
    metadata in the database.
 */
+ (id<PDSKeyManager>)createKeyManagerWithDatabase:(PDSDatabase *)database;

@end

NS_ASSUME_NONNULL_END
