// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSKeyManagerFactory.h

 @abstract Factory for creating platform-appropriate key managers.

 @discussion
    Creates the appropriate PDSKeyManager implementation based on the
    current platform:
    - macOS/iOS: PDSAppleKeyManager (Security.framework) when keychain is enabled
    - macOS/iOS (non-keychain): PDSOpenSSLSessionKeyManager when OpenSSL support is available, else PDSAppleKeyManager in non-keychain mode
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
/**
 * @abstract Declares the PDSKeyManagerFactory public API.
 */
@interface PDSKeyManagerFactory : NSObject

/*!
 @method createKeyManagerWithDatabase:

 @abstract Creates a platform-appropriate key manager.

 @param database The database for key storage metadata.

 @return A PDSKeyManager implementation appropriate for the current platform.
         Returns PDSAppleKeyManager on macOS/iOS when keychain is enabled.
         Returns PDSOpenSSLSessionKeyManager on Linux and on macOS/iOS when
         keychain is disabled and OpenSSL support is compiled in; otherwise
         returns PDSAppleKeyManager with keychain behavior controlled by config.

 @discussion
    The database is used for storing key metadata and, on Linux, the actual
    key material. On macOS/iOS, keys are stored in the Keychain with only
    metadata in the database.
 */
/**
 * @abstract Performs the createKeyManagerWithDatabase operation.
 */
+ (id<PDSKeyManager>)createKeyManagerWithDatabase:(PDSDatabase *)database;

@end

NS_ASSUME_NONNULL_END
